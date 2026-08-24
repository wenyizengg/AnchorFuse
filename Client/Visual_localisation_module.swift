//
// Copyright (C) 2026 Wenyi Chen

//  Visual_localisation_module.swift
//  AR_demo2
//
//  LiDAR / PnP revision.
//

import Foundation
import RealityKit
import ARKit
import simd


class Visual_localisation_module {

    weak var coordinator: Coordinator?

    // ^K T_A for every manually captured keyframe.
    // This transform is independent of the original AR session frame.
    var anchorRelativeTransforms = [simd_float4x4]()

    // Packed metric xyz landmarks for each keyframe.
    // Three Float32 values per point, expressed in the OpenCV keyframe frame.
    var landmarkPoints = [Data]()

    // Packed ORB descriptors corresponding 1:1 with landmarkPoints.
    var landmarkDescriptors = [Data]()

    let frame_processor = frame_processor_wrapper()

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Save-side keyframe capture

    func capture(anchor: ARAnchor) -> Bool {

        guard let coordinator,
              let arView = coordinator.arView,
              let frame = arView.session.currentFrame else {
            print("Failed capturing frame: AR frame unavailable.")
            return false
        }

        guard let processor = frame_processor else {
            print("Frame processor is unavailable.")
            return false
        }

        guard #available(iOS 14.0, *) else {
            print("LiDAR scene depth requires iOS 14 or later.")
            return false
        }

        // Prefer temporally smoothed LiDAR depth when ARKit provides it.
        // sceneDepth remains a valid fallback on a LiDAR capable device.
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            print(
                "Keyframe rejected: LiDAR scene depth is unavailable. " +
                "This revision does not use monocular/GPS scale recovery."
            )
            return false
        }

        guard let image = createRawImage(from: frame) else {
            print("Failed creating keyframe image.")
            return false
        }

        guard let buffers = processor.extract_metric_landmarks(
            image,
            depth_map: depthData.depthMap,
            confidence_map: depthData.confidenceMap,
            intrinsics: frame.camera.intrinsics
        ), buffers.count == 2 else {
            print(
                "Keyframe rejected: insufficient ORB features with " +
                "reliable metric depth."
            )
            return false
        }

        let points = buffers[0] as Data
        let descriptors = buffers[1] as Data

        guard points.count % 12 == 0 else {
            print("Keyframe rejected: malformed metric landmark buffer.")
            return false
        }

        let landmarkCount = points.count / 12

        guard landmarkCount >= 30,
              descriptors.count == landmarkCount * 32 else {
            print(
                "Keyframe rejected: invalid metric landmark/descriptor pair."
            )
            return false
        }

        let keyframePose = frame.camera.transform
        let anchorPose = anchor.transform

        // ARKit poses are ^S T_frame. Store the anchor directly in the
        // keyframe camera coordinate system:
        //
        //     ^K T_A = inverse(^S T_K) * ^S T_A
        //
        // Later, after PnP gives ^C T_K in metres:
        //
        //     ^S2 T_A = ^S2 T_C * ^C T_K * ^K T_A
        let anchorRelativeToKeyframe =
            simd_inverse(keyframePose) * anchorPose

        guard isFiniteTransform(anchorRelativeToKeyframe) else {
            print("Keyframe rejected: invalid keyframe-to-anchor transform.")
            return false
        }

        // Append only after every component has passed validation, keeping the
        // three per-keyframe arrays index-aligned.
        anchorRelativeTransforms.append(anchorRelativeToKeyframe)
        landmarkPoints.append(points)
        landmarkDescriptors.append(descriptors)

        print(
            "Captured metric keyframe with \(landmarkCount) LiDAR-backed " +
            "ORB landmarks."
        )

        return true
    }

    // MARK: - Restore-side visual localisation

    func find_overlap(
        anchor_info: Anchor_information
    ) -> (
        Transform: simd_float4x4,
        is_overlap: Bool
    ) {

        guard let coordinator,
              let arView = coordinator.arView,
              let frame = arView.session.currentFrame else {
            return (matrix_identity_float4x4, false)
        }

        guard let processor = frame_processor else {
            print("Frame processor is unavailable.")
            return (matrix_identity_float4x4, false)
        }

        let keyframeCount = anchor_info.anchorRelativeTransforms.count

        guard keyframeCount > 0,
              anchor_info.landmarkPoints.count == keyframeCount,
              anchor_info.landmarkDescriptors.count == keyframeCount else {
            print("Anchor contains incomplete PnP visual data.")
            return (matrix_identity_float4x4, false)
        }

        guard let currentImage = createRawImage(from: frame) else {
            print("Failed creating current camera image.")
            return (matrix_identity_float4x4, false)
        }

        for index in 0..<keyframeCount {

            let points = anchor_info.landmarkPoints[index]
            let descriptors = anchor_info.landmarkDescriptors[index]

            guard points.count % 12 == 0,
                  descriptors.count == (points.count / 12) * 32 else {
                print("Malformed PnP data for keyframe \(index).")
                continue
            }

            var localised = false

            // PnP uses:
            //
            //     stored metric 3D points in K
            //                  <->
            //     current 2D ORB observations in C
            //
            // and returns ^C T_K. Unlike the old essential-matrix result,
            // its translation is already metric because the object points are
            // measured in metres from LiDAR depth.
            let currentFromKeyframe = processor.localiseWithPnP(
                points,
                landmarkDescriptors: descriptors,
                currentImage: currentImage,
                currentIntrinsics: frame.camera.intrinsics,
                localisationIdentifier: &localised
            )

            guard localised,
                  isFiniteTransform(currentFromKeyframe) else {
                continue
            }

            print("PnP visual localisation succeeded for keyframe \(index).")

            let currentCameraPose = frame.camera.transform

            // ^S2 T_K = ^S2 T_C * ^C T_K
            let keyframePoseInCurrentSession =
                currentCameraPose * currentFromKeyframe

            // ^S2 T_A = ^S2 T_K * ^K T_A
            let anchorPoseInCurrentSession =
                keyframePoseInCurrentSession *
                anchor_info.anchorRelativeTransforms[index]

            guard isFiniteTransform(anchorPoseInCurrentSession) else {
                print("PnP produced an invalid anchor transform.")
                continue
            }

            return (
                anchorPoseInCurrentSession,
                true
            )
        }

        return (matrix_identity_float4x4, false)
    }

    func cleanup() {
        anchorRelativeTransforms.removeAll()
        landmarkPoints.removeAll()
        landmarkDescriptors.removeAll()
    }

    // MARK: - Helpers

    private func createRawImage(
        from frame: ARFrame
    ) -> UIImage? {

        let ciImage = CIImage(
            cvPixelBuffer: frame.capturedImage
        )

        let context = CIContext()

        guard let cgImage = context.createCGImage(
            ciImage,
            from: ciImage.extent
        ) else {
            return nil
        }

        // Keep native sensor pixel coordinates. ARKit's camera intrinsics and
        // scene-depth map are aligned to this captured-image coordinate system.
        return UIImage(
            cgImage: cgImage,
            scale: 1.0,
            orientation: .up
        )
    }

    private func isFiniteTransform(
        _ transform: simd_float4x4
    ) -> Bool {
        let columns = [
            transform.columns.0,
            transform.columns.1,
            transform.columns.2,
            transform.columns.3
        ]

        for column in columns {
            if !column.x.isFinite ||
               !column.y.isFinite ||
               !column.z.isFinite ||
               !column.w.isFinite {
                return false
            }
        }

        return true
    }
}
