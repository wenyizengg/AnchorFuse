//
//  Copyright (C) 2026 Wenyi Chen


//  Anchor_information.swift
//  AR_demo2
//
//  Created by Wenyi on 17/03/2025.
//
//  LiDAR / PnP version.
//

import Foundation
import simd

final class Anchor_information {

    var anchor_id: UUID
    var model_id: Int32

    var lat: Double
    var lon: Double
    var alt: Double

    var yaw: Double
    var pitch: Double
    var roll: Double

    // Per-keyframe anchor pose expressed in that keyframe camera frame.
    // anchorRelativeTransforms[i] = ^K T_A
    
    // With a PnP estimate ^C T_K and the current ARKit camera pose ^S2 T_C:
    //  ^S2 T_A = ^S2 T_C * ^C T_K * ^K T_A
    
    // This representation is independent of the original AR session frame.
    var anchorRelativeTransforms: [simd_float4x4]

    // Packed metric 3D landmarks for each keyframe.
    // Each landmark is three consecutive Float(32) values (x, y, z) in metres,
    // expressed in the OpenCV keyframe-camera coordinate system:
    // +x right, +y down, +z forward.
    // landmarkPoints[i].count == landmarkCount * 12 bytes.
    var landmarkPoints: [Data]

    // ORB descriptors are 1:1 corresponding with landmarkPoints.
    // ORB uses 32 bytes per descriptor.
    // landmarkDescriptors[i].count == landmarkCount * 32 bytes.
    var landmarkDescriptors: [Data]

    // 0: not anchored
    // 1: GPS based preview anchored
    // 2: anchored using visual localisation
    var status: AtomicAnchorStatus

    init(
        anchor_id: UUID,
        model_id: Int32,
        lat: Double,
        lon: Double,
        alt: Double,
        yaw: Double,
        pitch: Double,
        roll: Double,
        anchorRelativeTransforms: [simd_float4x4],
        landmarkPoints: [Data],
        landmarkDescriptors: [Data]
    ) {
        self.anchor_id = anchor_id
        self.model_id = model_id

        self.lat = lat
        self.lon = lon
        self.alt = alt

        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll

        self.anchorRelativeTransforms = anchorRelativeTransforms
        self.landmarkPoints = landmarkPoints
        self.landmarkDescriptors = landmarkDescriptors

        self.status = AtomicAnchorStatus(0)
    }

    /*
     Binary layout:

     visual payload size: Int32

     anchor_id: UUID, 16 bytes
     model_id: Int32

     lat: Double
     lon: Double
     alt: Double

     yaw: Double
     pitch: Double
     roll: Double

     visual payload:

         keyframe count: UInt8

         repeated for every keyframe:

             ^K T_A: simd_float4x4
                 16 Float32 values = 64 bytes
                 column-major

             landmark count: UInt32

             landmark points:
                 landmark count × 3 Float32
                 packed x, y, z

             ORB descriptors:
                 landmark count × 32 UInt8

     Integer and floating-point fields are sent in the native little-endian
     representation used by the iOS client. The server uses this layout exactly.
     */

    func binarise() -> Data {

        let keyframeCount = anchorRelativeTransforms.count

        guard keyframeCount > 0 else {
            print("Cannot binarise anchor: no visual keyframes.")
            return Data()
        }

        guard keyframeCount <= Int(UInt8.max) else {
            print("Cannot binarise anchor: more than 255 keyframes.")
            return Data()
        }

        guard landmarkPoints.count == keyframeCount,
              landmarkDescriptors.count == keyframeCount else {
            print("Cannot binarise anchor: visual keyframe arrays differ in count.")
            return Data()
        }

        for index in 0..<keyframeCount {
            let points = landmarkPoints[index]
            let descriptors = landmarkDescriptors[index]

            guard points.count % 12 == 0 else {
                print("Cannot binarise keyframe \(index): malformed 3D point data.")
                return Data()
            }

            let landmarkCount = points.count / 12

            guard landmarkCount > 0,
                  landmarkCount <= Int(UInt32.max) else {
                print("Cannot binarise keyframe \(index): invalid landmark count.")
                return Data()
            }

            guard descriptors.count == landmarkCount * 32 else {
                print(
                    "Cannot binarise keyframe \(index): descriptor count does not " +
                    "match metric landmarks."
                )
                return Data()
            }
        }

        var result = Data()

        // MARK: anchor metadata

        withUnsafeBytes(of: anchor_id.uuid) {
            result.append(contentsOf: $0)
        }

        append(model_id, to: &result)

        append(lat, to: &result)
        append(lon, to: &result)
        append(alt, to: &result)

        append(yaw, to: &result)
        append(pitch, to: &result)
        append(roll, to: &result)

        // Everything after this point is counted as the visual payload.
        let metadataSize = result.count

        append(UInt8(keyframeCount), to: &result)

        // MARK: keyframes related data

        for index in 0..<keyframeCount {
            result.append(
                simd4x4ToBinary(
                    matrix: anchorRelativeTransforms[index]
                )
            )

            let pointData = landmarkPoints[index]
            let descriptorData = landmarkDescriptors[index]
            let landmarkCount = UInt32(pointData.count / 12)

            append(landmarkCount, to: &result)
            result.append(pointData)
            result.append(descriptorData)
        }

        let visualPayloadByteCount = result.count - metadataSize

        guard visualPayloadByteCount <= Int(Int32.max) else {
            print("Cannot binarise anchor: visual payload is too large.")
            return Data()
        }

        let visualPayloadSize = Int32(visualPayloadByteCount)

        var finalData = Data()
        append(visualPayloadSize, to: &finalData)
        finalData.append(result)

        print(
            "Visual PnP payload size: \(visualPayloadSize) bytes; " +
            "keyframes: \(keyframeCount)."
        )

        return finalData
    }

    // MARK: - Binary helpers

    private func append<T>(
        _ value: T,
        to data: inout Data
    ) {
        var mutableValue = value

        withUnsafeBytes(of: &mutableValue) {
            data.append(contentsOf: $0)
        }
    }

    // Serializes a 4×4 matrix in column-major order.
    private func simd4x4ToBinary(
        matrix: simd_float4x4
    ) -> Data {
        var data = Data()

        let columns = [
            matrix.columns.0,
            matrix.columns.1,
            matrix.columns.2,
            matrix.columns.3
        ]

        for column in columns {
            append(column.x, to: &data)
            append(column.y, to: &data)
            append(column.z, to: &data)
            append(column.w, to: &data)
        }

        return data
    }
}
