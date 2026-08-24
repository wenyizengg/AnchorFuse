//
// Copyright (C) 2026 Wenyi Chen

//  GPS_preview_module.swift
//  AR_demo2
//
//  Created by Wenyi.
//

import Foundation
import RealityKit
import SwiftUI
import ARKit
import CoreLocation
import CoreMotion
import Network
import simd

class GPS_preview_module{
    
    weak var coordinator:Coordinator?
    // Shared GPS accuracy threshold for both horizontal and vertical accuracy.
    let gps_accuracy_threshold = 7.0
    
    // A threshold specifically for vertical accuracy during restoration
    let vertical_accuracy_threshold_restoration = 2.5
    
    // If Core Location's vertical accuracy is poor when an anchor is saved, store this sentinel instead of an unreliable altitude. During restoration, the sentinel causes the GPS preview to use a fixed camera-relative height.
    private let unavailableAltitudeSentinel = -9999.0
    private let previewHeightBelowCamera = 1.7
    
    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }
    
    func If_GPS_accuracy_accpetable() -> Bool {
        // used when trying to place GPS anchor preview
        
        guard let coordin = self.coordinator else {return false}
        
        guard (!coordin.currentLocation.isNil()) else {return false}
        
        // GPS preview uses only latitude/longitude, so only horizontal
        // accuracy is relevant. A smaller value means higher accuracy.
        let horizontalAccuracy = coordin.currentLocation.getHorizontalAccuracy()
        return horizontalAccuracy >= 0
            && horizontalAccuracy <= self.gps_accuracy_threshold
        
        
        
       
    }
    
    func on_save()->(anchorLat:Double, anchorLon:Double, anchorAlt:Double, anchorYaw:Double, valid:Bool){

        let defaultReturn = (0.0, 0.0, 0.0, 0.0, false)

        guard let coordin = self.coordinator,
              let anchor = coordin.anchor_to_be_saved,
              let arView = coordin.arView,
              let currentFrame = arView.session.currentFrame,
              !coordin.currentLocation.isNil(),
              !coordin.currentTrueHeading.isNil() else {
            return defaultReturn
        }

        let anchorPoseSession = anchor.transform
        let devicePoseSession = currentFrame.camera.transform
        let deviceTrueHeading = coordin.currentTrueHeading.getHeadigDegree()

        let originTrueNorthHeading = calculate_origin_absolute_heading(
            cameraHeadingDegree: deviceTrueHeading,
            cameraTransform: devicePoseSession
        )

        // C_N<-S: converts a vector represented in the AR session basis
        // into the true-north basis (+x east, +y up, +z north).
        let sessionToTrueNorth = rotationPart(
            heading_adjustment_matrix(
                current_heading_degree: Float(originTrueNorthHeading),
                target_heading_degree: 0
            )
        )

        // GPS needs a displacement vector, not the translation column of T_D->A. The latter equals p_A - R_DA p_D when rotation is present.
        let devicePositionSession = devicePoseSession.columns.3.xyz
        let anchorPositionSession = anchorPoseSession.columns.3.xyz
        let deviceToAnchorSession = anchorPositionSession - devicePositionSession
        let deviceToAnchorTrueNorth = sessionToTrueNorth * deviceToAnchorSession

        let deviceCoordinates = coordin.currentLocation.getLocation()
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude
            * cos(deviceCoordinates.lat.degreesToRadians)

        let anchorLat = deviceCoordinates.lat
            + Double(deviceToAnchorTrueNorth.z) / metersPerDegreeLatitude
        let anchorLon = deviceCoordinates.lon
            + Double(deviceToAnchorTrueNorth.x) / metersPerDegreeLongitude
        // Use Core Location altitude only when its estimated vertical
        // accuracy is acceptable. Otherwise store a sentinel so restoration
        // can fall back to a fixed camera-relative preview height.
        let verticalAccuracy = coordin.currentLocation.getVerticalAccuracy()
        let anchorAlt: Double

        if verticalAccuracy >= 0
            && verticalAccuracy <= gps_accuracy_threshold {

            anchorAlt = deviceCoordinates.alt
                + Double(deviceToAnchorTrueNorth.y)
        } else {
            anchorAlt = unavailableAltitudeSentinel
        }

        // RealityKit/ARKit forward is -Z. Convert that direction into the
        // true-north basis and read compass heading from east/north components.
        let anchorForwardSession = -anchorPoseSession.columns.2.xyz
        let anchorForwardTrueNorth = sessionToTrueNorth * anchorForwardSession
        let anchorTrueHeading = compassHeadingDegrees(
            forwardTrueNorth: anchorForwardTrueNorth
        )

        print(
            "\nanchor true heading: \(anchorTrueHeading), "
            + "origin true heading: \(originTrueNorthHeading), "
            + "device true heading: \(deviceTrueHeading)"
        )

        return (anchorLat, anchorLon, anchorAlt, anchorTrueHeading, true)
    }

    func on_place(anchor:Anchor_information) -> (Transform:simd_float4x4, valid:Bool){

        guard let coordin = self.coordinator,
              let arView = coordin.arView,
              let currentFrame = arView.session.currentFrame,
              !coordin.currentLocation.isNil(),
              !coordin.currentTrueHeading.isNil() else {
            return (matrix_identity_float4x4, false)
        }

        guard self.If_GPS_accuracy_accpetable() else {
            print("GPS accuracy unacceptable.")
            return (matrix_identity_float4x4, false)
        }

        let devicePoseSession = currentFrame.camera.transform
        let deviceTrueHeading = coordin.currentTrueHeading.getHeadigDegree()
        let deviceLocation = coordin.currentLocation.getLocation()

        let originTrueNorthHeading = calculate_origin_absolute_heading(
            cameraHeadingDegree: deviceTrueHeading,
            cameraTransform: devicePoseSession
        )

        // C_S<-N: converts true-north vectors/orientations into the AR session.
        let trueNorthToSession = rotationPart(
            heading_adjustment_matrix(
                current_heading_degree: 0,
                target_heading_degree: Float(originTrueNorthHeading)
            )
        )

        // A stored altitude is useful only if the current device altitude is
        // also reliable. If the anchor contains the sentinel, or the current
        // vertical accuracy is poor, place the preview 1.7 m below the camera.
        let currentVerticalAccuracy = coordin.currentLocation.getVerticalAccuracy()
        let canUseStoredAltitude =
            anchor.alt != unavailableAltitudeSentinel
            && currentVerticalAccuracy >= 0
            && currentVerticalAccuracy <= vertical_accuracy_threshold_restoration

        let effectiveAnchorAltitude: Double
        if canUseStoredAltitude {
            effectiveAnchorAltitude = anchor.alt
        } else {
            effectiveAnchorAltitude = deviceLocation.alt - previewHeightBelowCamera
        }

        let deviceToAnchorTrueNorth = threeDimensionalPosition(
            lat1: deviceLocation.lat,
            lon1: deviceLocation.lon,
            alt1: deviceLocation.alt,
            lat2: anchor.lat,
            lon2: anchor.lon,
            alt2: effectiveAnchorAltitude
        )

        // Position is reconstructed directly in the session frame.
        let devicePositionSession = devicePoseSession.columns.3.xyz
        let anchorPositionSession = devicePositionSession
            + trueNorthToSession * deviceToAnchorTrueNorth

        // ================ Debug =====================
        print("""
        ========== GPS PREVIEW ==========
        Device session position:
        x: \(devicePositionSession.x)
        y: \(devicePositionSession.y)
        z: \(devicePositionSession.z)

        Device GPS:
        lat: \(deviceLocation.lat)
        lon: \(deviceLocation.lon)
        alt: \(deviceLocation.alt)

        Anchor GPS:
        lat: \(anchor.lat)
        lon: \(anchor.lon)
        stored alt: \(anchor.alt)
        effective alt: \(effectiveAnchorAltitude)

        Device -> Anchor true north:
        x: \(deviceToAnchorTrueNorth.x)
        y: \(deviceToAnchorTrueNorth.y)
        z: \(deviceToAnchorTrueNorth.z)

        Final GPS preview position:
        x: \(anchorPositionSession.x)
        y: \(anchorPositionSession.y)
        z: \(anchorPositionSession.z)

        Distance from camera:
        \(simd_distance(devicePositionSession, anchorPositionSession)) m
        =================================
        """)
        
        // ===============================
        
        
        
        // Build the anchor's absolute orientation in true-north coordinates,
        // then express that orientation in the AR session coordinates.
        let anchorRotationTrueNorth = absoluteOrientationTrueNorth(
            headingDegrees: Float(anchor.yaw),
//            pitchRadian: Float(anchor.pitch.degreesToRadians),
//            rollRadian: Float(anchor.roll.degreesToRadians)
            pitchRadian: 0,
            rollRadian: 0,
            // always align with the gravity
        )

        let anchorRotationSession = trueNorthToSession
            * anchorRotationTrueNorth

        // This is T_O->A directly under the active-displacement convention.
        let originToAnchorSession = makeTransform(
            rotation: anchorRotationSession,
            translation: anchorPositionSession
        )

        // Only derive T_D->A if another part of the program needs it:
        // let deviceToAnchorSession = originToAnchorSession
        //     * simd_inverse(devicePoseSession)
        // and deviceToAnchorSession * devicePoseSession == originToAnchorSession.

        return (originToAnchorSession, true)
    }
    
}
