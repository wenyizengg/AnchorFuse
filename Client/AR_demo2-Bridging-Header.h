
// Copyright (C) 2026 Wenyi Chen

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
#import <simd/simd.h>


@interface frame_processor_wrapper : NSObject

- (instancetype)init;

// Extract ORB features from a keyframe, retain only features with valid LiDAR depth data, back-project them to metric 3D points, and return:
// -  result[0] = packed Float32 xyz points (12 bytes per point)
// -  result[1] = packed ORB descriptors (32 bytes per point)
- (NSArray<NSData *> * _Nullable)extract_metric_landmarks:
        (UIImage *)image
        depth_map:(CVPixelBufferRef)depthMap
        confidence_map:(CVPixelBufferRef _Nullable)confidenceMap
        intrinsics:(simd_float3x3)intrinsics;

// Estimate ^C T_K from stored metric 3D landmarks and 2D ORB observations in the current frame. The returned transform is converted from OpenCV
// camera axes to ARKit camera axes and its translation is in metres.
- (simd_float4x4)localise_with_pnp:
        (NSData *)landmark_points
        landmark_descriptors:(NSData *)landmarkDescriptors
        current_image:(UIImage *)currentImage
        current_intrinsics:(simd_float3x3)currentIntrinsics
        localisation_identifier:(bool *)isLocalised
        NS_SWIFT_NAME(localiseWithPnP(_:landmarkDescriptors:currentImage:currentIntrinsics:localisationIdentifier:));
@end
