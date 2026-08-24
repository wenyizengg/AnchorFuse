//
// Copyright (C) 2026 Wenyi Chen

//  frame_processor_wrapper.mm
//  AR_demo2
//
//  LiDAR / PnP revision.
//

#import "frame_processor.h"
#import "AR_demo2-Bridging-Header.h"


@interface frame_processor_wrapper () {
    frame_processor *frameProcessor;
}
@end


static cv::Mat simd3x3_to_cv(const simd_float3x3& matrix) {
    cv::Mat result(3, 3, CV_64F);

    // simd matrices are column-major.
    for (int col = 0; col < 3; ++col) {
        for (int row = 0; row < 3; ++row) {
            result.at<double>(row, col) =
                static_cast<double>(matrix.columns[col][row]);
        }
    }

    return result;
}


static cv::Mat UIImageToMat(UIImage *image) {
    if (image == nil || image.CGImage == nil) {
        return cv::Mat();
    }

    CGImageRef cgImage = image.CGImage;
    const size_t cols = CGImageGetWidth(cgImage);
    const size_t rows = CGImageGetHeight(cgImage);

    if (cols == 0 || rows == 0) {
        return cv::Mat();
    }

    cv::Mat bgra(
        static_cast<int>(rows),
        static_cast<int>(cols),
        CV_8UC4
    );

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    CGContextRef contextRef = CGBitmapContextCreate(
        bgra.data,
        cols,
        rows,
        8,
        bgra.step[0],
        colorSpace,
        kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault
    );

    CGColorSpaceRelease(colorSpace);

    if (contextRef == nil) {
        return cv::Mat();
    }

    CGContextDrawImage(
        contextRef,
        CGRectMake(0, 0, cols, rows),
        cgImage
    );

    CGContextRelease(contextRef);

    cv::Mat gray;
    cv::cvtColor(bgra, gray, cv::COLOR_BGRA2GRAY);
    return gray;
}


static simd_float4x4 mat_to_simd(const cv::Mat& matrix) {
    simd_float4x4 result = matrix_identity_float4x4;

    if (
        matrix.rows != 4 ||
        matrix.cols != 4 ||
        matrix.empty()
    ) {
        std::cout << "Invalid input transform." << std::endl;
        return result;
    }

    for (int col = 0; col < 4; ++col) {
        for (int row = 0; row < 4; ++row) {
            float value = 0.0f;

            if (matrix.type() == CV_32FC1) {
                value = matrix.at<float>(row, col);
            } else if (matrix.type() == CV_64FC1) {
                value = static_cast<float>(
                    matrix.at<double>(row, col)
                );
            } else {
                std::cout << "Unsupported matrix type." << std::endl;
                return matrix_identity_float4x4;
            }

            result.columns[col][row] = value;
        }
    }

    return result;
}


static NSData *packed_points_to_data(
    const vector<cv::Point3f>& points
) {
    NSMutableData *data = [NSMutableData dataWithCapacity:points.size() * 12];

    for (const auto& point : points) {
        const float xyz[3] = {point.x, point.y, point.z};
        [data appendBytes:xyz length:sizeof(xyz)];
    }

    return [data copy];
}


static bool data_to_packed_points(
    NSData *data,
    vector<cv::Point3f>& points
) {
    points.clear();

    if (data == nil || data.length == 0 || data.length % 12 != 0) {
        return false;
    }

    const NSUInteger count = data.length / 12;
    const uint8_t *bytes = static_cast<const uint8_t *>(data.bytes);

    points.reserve(count);

    for (NSUInteger i = 0; i < count; ++i) {
        float xyz[3];
        memcpy(xyz, bytes + i * 12, sizeof(xyz));

        if (
            !std::isfinite(xyz[0]) ||
            !std::isfinite(xyz[1]) ||
            !std::isfinite(xyz[2])
        ) {
            return false;
        }

        points.emplace_back(xyz[0], xyz[1], xyz[2]);
    }

    return true;
}


@implementation frame_processor_wrapper

- (instancetype)init {
    self = [super init];

    if (self) {
        frameProcessor = new frame_processor();
    }

    return self;
}


- (NSArray<NSData *> *)extract_metric_landmarks:
        (UIImage *)image
        depth_map:(CVPixelBufferRef)depthMap
        confidence_map:(CVPixelBufferRef)confidenceMap
        intrinsics:(simd_float3x3)intrinsics {

    if (image == nil || depthMap == nil) {
        return nil;
    }

    const OSType depthFormat = CVPixelBufferGetPixelFormatType(depthMap);

    if (depthFormat != kCVPixelFormatType_DepthFloat32) {
        std::cout << "Unsupported ARKit depth pixel format." << std::endl;
        return nil;
    }

    const CVReturn depthLockResult = CVPixelBufferLockBaseAddress(
        depthMap,
        kCVPixelBufferLock_ReadOnly
    );

    if (depthLockResult != kCVReturnSuccess) {
        std::cout << "Failed locking ARKit depth buffer." << std::endl;
        return nil;
    }

    bool confidenceLocked = false;

    if (confidenceMap != nil) {
        const OSType confidenceFormat =
            CVPixelBufferGetPixelFormatType(confidenceMap);

        if (confidenceFormat == kCVPixelFormatType_OneComponent8) {
            const CVReturn confidenceLockResult =
                CVPixelBufferLockBaseAddress(
                    confidenceMap,
                    kCVPixelBufferLock_ReadOnly
                );

            confidenceLocked =
                confidenceLockResult == kCVReturnSuccess;
        }
    }

    cv::Mat imageMat = UIImageToMat(image);

    const size_t depthWidth = CVPixelBufferGetWidth(depthMap);
    const size_t depthHeight = CVPixelBufferGetHeight(depthMap);
    const size_t depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap);
    void *depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap);

    cv::Mat depthMat;

    if (
        depthBaseAddress != nullptr &&
        depthWidth > 0 &&
        depthHeight > 0
    ) {
        depthMat = cv::Mat(
            static_cast<int>(depthHeight),
            static_cast<int>(depthWidth),
            CV_32FC1,
            depthBaseAddress,
            depthBytesPerRow
        );
    }

    cv::Mat confidenceMat;

    if (confidenceMap != nil) {
        const size_t confidenceWidth = CVPixelBufferGetWidth(confidenceMap);
        const size_t confidenceHeight = CVPixelBufferGetHeight(confidenceMap);
        const size_t confidenceBytesPerRow =
            CVPixelBufferGetBytesPerRow(confidenceMap);
        void *confidenceBaseAddress =
            CVPixelBufferGetBaseAddress(confidenceMap);

        if (
            confidenceBaseAddress != nullptr &&
            confidenceWidth == depthWidth &&
            confidenceHeight == depthHeight
        ) {
            confidenceMat = cv::Mat(
                static_cast<int>(confidenceHeight),
                static_cast<int>(confidenceWidth),
                CV_8UC1,
                confidenceBaseAddress,
                confidenceBytesPerRow
            );
        }
    }

    const cv::Mat K = simd3x3_to_cv(intrinsics);

    vector<cv::Point3f> points;
    cv::Mat descriptors;

    const bool succeeded = frameProcessor->create_metric_landmarks(
        imageMat,
        depthMat,
        confidenceMat,
        K,
        points,
        descriptors
    );

    if (confidenceLocked) {
        CVPixelBufferUnlockBaseAddress(
            confidenceMap,
            kCVPixelBufferLock_ReadOnly
        );
    }

    CVPixelBufferUnlockBaseAddress(
        depthMap,
        kCVPixelBufferLock_ReadOnly
    );

    if (
        !succeeded ||
        points.empty() ||
        descriptors.empty() ||
        descriptors.rows != static_cast<int>(points.size()) ||
        descriptors.cols != 32 ||
        descriptors.type() != CV_8UC1
    ) {
        return nil;
    }

    NSData *pointsData = packed_points_to_data(points);

    const size_t descriptorByteCount =
        descriptors.total() * descriptors.elemSize();

    NSData *descriptorData = [NSData
        dataWithBytes:descriptors.data
        length:descriptorByteCount
    ];

    return @[pointsData, descriptorData];
}


- (simd_float4x4)localise_with_pnp:
        (NSData *)landmark_points
        landmark_descriptors:(NSData *)landmarkDescriptors
        current_image:(UIImage *)currentImage
        current_intrinsics:(simd_float3x3)currentIntrinsics
        localisation_identifier:(bool *)isLocalised {

    if (isLocalised == nullptr) {
        return matrix_identity_float4x4;
    }

    *isLocalised = false;

    vector<cv::Point3f> points;

    if (!data_to_packed_points(landmark_points, points)) {
        std::cout << "Invalid packed landmark points." << std::endl;
        return matrix_identity_float4x4;
    }

    if (
        landmarkDescriptors == nil ||
        landmarkDescriptors.length != points.size() * 32
    ) {
        std::cout << "Invalid packed landmark descriptors." << std::endl;
        return matrix_identity_float4x4;
    }

    cv::Mat descriptors(
        static_cast<int>(points.size()),
        32,
        CV_8UC1,
        const_cast<void *>(landmarkDescriptors.bytes)
    );

    descriptors = descriptors.clone();

    cv::Mat imageMat = UIImageToMat(currentImage);
    cv::Mat K = simd3x3_to_cv(currentIntrinsics);

    cv::Mat transform = frameProcessor->localise_with_pnp(
        points,
        descriptors,
        imageMat,
        K,
        *isLocalised
    );

    return mat_to_simd(transform);
}


- (void)dealloc {
    delete frameProcessor;
    frameProcessor = nullptr;
}

@end
