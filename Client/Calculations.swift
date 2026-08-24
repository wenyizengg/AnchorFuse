//
// Copyright (C) 2026 Wenyi Chen

//  Calculations.swift
//  AR_demo2
//
//  Created by Wenyi on 17/03/2025.
//

import Foundation
import simd

extension simd_float4 {
    var xyz: simd_float3 {
        return simd_float3(x, y, z)
    }
}

extension Float{
    var degreesToRadians: Float { return self * .pi/180 }
    var radiansToDegrees: Float { return self * 180 / .pi }
}

extension Double {
    
    var degreesToRadians: Double { return self * .pi / 180 }
    var radiansToDegrees: Double { return self * 180 / .pi }
    
    func toBytes() -> [UInt8] {
        var value = self
        return withUnsafeBytes(of: &value) { Array($0) }
    }

}

// MARK: Notice!! Math functions like cos() and sin() are expecting radian!

func Distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let R = 6371000.0
    let dLat = (lat2 - lat1).degreesToRadians
    let dLon = (lon2 - lon1).degreesToRadians

    let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1.degreesToRadians) * cos(lat2.degreesToRadians) *
            sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c
}


func bearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    
    let deltaLon = (lon2 - lon1).degreesToRadians

    if lat1 == lat2 {
        return deltaLon > 0 ? 90.0 : 270.0
    }

    let y = sin(deltaLon) * cos(lat2.degreesToRadians)
    let x = cos(lat1.degreesToRadians) * sin(lat2.degreesToRadians) -
            sin(lat1.degreesToRadians) * cos(lat2.degreesToRadians) * cos(deltaLon)
    return atan2(y, x).radiansToDegrees
}





func threeDimensionalPosition(
    lat1: Double, lon1: Double, alt1: Double,
    lat2: Double, lon2: Double, alt2: Double
) -> simd_float3 {
    let horizontalDistance = Distance(
        lat1: lat1,
        lon1: lon1,
        lat2: lat2,
        lon2: lon2
    )

    let bearingAngle = bearing(
        lat1: lat1,
        lon1: lon1,
        lat2: lat2,
        lon2: lon2
    ).degreesToRadians

    // True north coordinates: +x east, +y up, +z north.
    // DO NOT special case equal latitudes: doing so loses the east/west sign.
    let x = Float(horizontalDistance * sin(bearingAngle))
    let y = Float(alt2 - alt1)
    let z = Float(horizontalDistance * cos(bearingAngle))

    return simd_float3(x, y, z)
}

func make_translation_matrix(translation_vector: simd_float4) -> simd_float4x4{
    
   
    
    return simd_float4x4([
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        translation_vector
    ])
    
    
    
}


func make_rotation_matrix (rotation_angle: Float, axis: simd_float3, inputIsRadian: Bool) -> simd_float4x4 {
    
    var quaternion: simd_quatf
    
    if (inputIsRadian){
        quaternion = simd_quaternion(rotation_angle, axis)
    } else {
        quaternion = simd_quaternion(rotation_angle.degreesToRadians, axis)
        
    }
    
    
    return simd_float4x4(quaternion)
}

// tested
func heading_adjustment_matrix(current_heading_degree:Float, target_heading_degree:Float) -> simd_float4x4 {
    
    let basic_matrix = simd_float4x4([
        [1,0,0,0],
        [0,1,0,0],
        [0,0,1,0],
        [0,0,0,1]
    ])
    
    guard current_heading_degree != target_heading_degree else {return basic_matrix}
    
    var rotation_degree:Float = 0.0

    
    if (current_heading_degree > target_heading_degree){
        rotation_degree = current_heading_degree - target_heading_degree
        // quaternion always use left rotation (counterclockwise)
    } else {
        rotation_degree = 360 - (target_heading_degree - current_heading_degree)
    }
    
    print("Heading adjustment -- Current:\(current_heading_degree), target:\(target_heading_degree), rotation degrees:\(rotation_degree)")
    
    return make_rotation_matrix(rotation_angle: rotation_degree, axis: [0,1,0], inputIsRadian: false)

}

// tested
func pitch_adjustment_matrix(currentPitchRadian:Float, targetPitchRadian:Float) -> simd_float4x4{
    
    let basic_matrix = simd_float4x4([
        [1,0,0,0],
        [0,1,0,0],
        [0,0,1,0],
        [0,0,0,1]
    ])
    
    guard currentPitchRadian != targetPitchRadian else {return basic_matrix}
    
    var rotation_radian:Float
    
    if (currentPitchRadian > targetPitchRadian){
        rotation_radian = -(currentPitchRadian - targetPitchRadian)
    } else {
        rotation_radian = targetPitchRadian - currentPitchRadian
    }
    
    return make_rotation_matrix(rotation_angle: rotation_radian, axis: [1,0,0], inputIsRadian: true)
    
}

// tested
func roll_adjustment_matrix(currentRollRadian:Float, targetRollRadian:Float) -> simd_float4x4{
    
    let basic_matrix = simd_float4x4([
        [1,0,0,0],
        [0,1,0,0],
        [0,0,1,0],
        [0,0,0,1]
    ])
    
    guard currentRollRadian != targetRollRadian else {return basic_matrix}
    
    var rotation_radian: Float
    
    if (currentRollRadian > targetRollRadian){
        rotation_radian = -(currentRollRadian - targetRollRadian)
    } else {
        rotation_radian = targetRollRadian - currentRollRadian
    }
    print("Roll adjustment -- Current:\(currentRollRadian.radiansToDegrees), target:\(targetRollRadian.radiansToDegrees), rotation degrees:\(rotation_radian.radiansToDegrees)")
    
    
    return make_rotation_matrix(rotation_angle: rotation_radian, axis: [0,0,1], inputIsRadian: true)
    
    
    
}




func from_device_to_anchor_true_north (
    
    deviceLat: Double,
    deviceLon: Double,
    deviceAlt: Double,
    anchorLat: Double,
    anchorLon: Double,
    anchorAlt: Double,
    anchorHeadingDegrees:Float,
    anchorPitchRadian: Float,
    anchorRollRadian: Float,
    deviceTrueHeading:Float,
    devicePitchRadian:Float,
    deviceRollRadian:Float
    
) -> simd_float4x4 {
    
    let relativeXYZ = threeDimensionalPosition(lat1: deviceLat, lon1: deviceLon, alt1: deviceAlt, lat2: anchorLat, lon2: anchorLon, alt2: anchorAlt)
    
    print( "relative xyz: \(relativeXYZ)")
    
    let XYZVector = simd_float4([relativeXYZ.x, relativeXYZ.y, relativeXYZ.z, 1])
    
    let translationMatrix = make_translation_matrix(translation_vector: XYZVector)
    
    let headingAdjustmentMatrix = heading_adjustment_matrix(current_heading_degree: deviceTrueHeading, target_heading_degree: anchorHeadingDegrees) 
    
    let pitchAdjustmentMatrix = pitch_adjustment_matrix(currentPitchRadian: devicePitchRadian, targetPitchRadian: anchorPitchRadian) // tested

    let rollAdjustmentMatrix = roll_adjustment_matrix(currentRollRadian: deviceRollRadian, targetRollRadian: anchorRollRadian) // tested
    
    
    let rotation_matrix = pitchAdjustmentMatrix * headingAdjustmentMatrix * rollAdjustmentMatrix
    
    return translationMatrix * rotation_matrix

}


func rotationPart(_ transform: simd_float4x4) -> simd_float3x3 {
    simd_float3x3(columns: (
        transform.columns.0.xyz,
        transform.columns.1.xyz,
        transform.columns.2.xyz
    ))
}

func makeTransform(
    rotation: simd_float3x3,
    translation: simd_float3
) -> simd_float4x4 {
    var transform = matrix_identity_float4x4
    transform.columns.0 = simd_float4(
        rotation.columns.0.x,
        rotation.columns.0.y,
        rotation.columns.0.z,
        0
    )
    transform.columns.1 = simd_float4(
        rotation.columns.1.x,
        rotation.columns.1.y,
        rotation.columns.1.z,
        0
    )
    transform.columns.2 = simd_float4(
        rotation.columns.2.x,
        rotation.columns.2.y,
        rotation.columns.2.z,
        0
    )
    transform.columns.3 = simd_float4(
        translation.x,
        translation.y,
        translation.z,
        1
    )
    return transform
}

func normaliseDegrees(_ angle: Double) -> Double {
    let result = angle.truncatingRemainder(dividingBy: 360)
    return result >= 0 ? result : result + 360
}

func compassHeadingDegrees(forwardTrueNorth: simd_float3) -> Double {
    // True-north coordinates: +x east and +z north.
    let horizontal = simd_float2(forwardTrueNorth.x, forwardTrueNorth.z)
    guard simd_length_squared(horizontal) > 1e-8 else { return 0 }

    return normaliseDegrees(
        Double(atan2f(horizontal.x, horizontal.y).radiansToDegrees)
    )
}

func absoluteOrientationTrueNorth(
    headingDegrees: Float,
    pitchRadian: Float,
    rollRadian: Float
) -> simd_float3x3 {

    /*
     "headingDegrees" describes the compass direction of the
     anchor's local -Z forward axis.

     A Y axis rotation of heading + 180 is required because
     an identity ARKit transform points local -Z toward true north
     heading 180 when true north is +Z. Always remember this!!!!!
     */
    let heading = make_rotation_matrix(
        rotation_angle: headingDegrees + 180.0,
        axis: [0, 1, 0],
        inputIsRadian: false
    )

    let pitch = pitch_adjustment_matrix(
        currentPitchRadian: 0,
        targetPitchRadian: pitchRadian
    )

    let roll = roll_adjustment_matrix(
        currentRollRadian: 0,
        targetRollRadian: rollRadian
    )

    return rotationPart(
        pitch * heading * roll
    )
}


func calculate_origin_absolute_heading(cameraHeadingDegree:Double, cameraTransform: simd_float4x4) -> Double{
    
    var thetaDegree = extract_heading_rotation_degree(transform: cameraTransform)
    
    thetaDegree = fmodf(thetaDegree + 180, 360)
    // in ARKit Z axis direction is the opposite, e.g., camera is always facing -Z direction
    // so Z axis should be rotated in realife: the origin always headin the opposite as the camera
    
    // Calculate the absolute yaw and normalise to 0-360
    let h_Origin = (cameraHeadingDegree - Double(thetaDegree)).truncatingRemainder(dividingBy: 360)
    
    //print("\n\n origin heading:\(h_Origin), camera heading degree:\(cameraHeadingDegree)")
    
    return h_Origin >= 0 ? h_Origin : h_Origin + 360

}


func extract_heading_rotation_degree(transform: simd_float4x4) -> Float {
  
    let forward = transform.columns.2.xyz
    let projection = simd_normalize(simd_float2(forward.x, forward.z))
    let headingRadian = atan2f(projection.x, projection.y)
    
   
    return headingRadian.radiansToDegrees
}



