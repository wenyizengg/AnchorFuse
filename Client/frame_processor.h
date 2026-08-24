// Copyright (C) 2026 Wenyi Chen

#ifndef FRAME_PROCESSOR_H
#define FRAME_PROCESSOR_H

#include <opencv2/core.hpp>
#include <opencv2/opencv.hpp>
#include <iostream>
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstdint>

using namespace std;

class frame_processor {

public:

    bool extract_features(
        const cv::Mat& image,
        vector<cv::KeyPoint>& keypoints,
        cv::Mat& descriptors
    );

    vector<cv::DMatch> knn_match(
        const cv::Mat& descriptors1,
        const cv::Mat& descriptors2
    );

    // Convert ORB keypoints with valid scene depth into metric 3D landmarks in the OpenCV keyframe-camera coordinate system.
    bool create_metric_landmarks(
        const cv::Mat& image,
        const cv::Mat& depth_map,
        const cv::Mat& confidence_map,
        const cv::Mat& intrinsics,
        vector<cv::Point3f>& metric_points,
        cv::Mat& metric_descriptors
    );

    // Estimate ^C T_K from metric keyframe 3D points and current-frame 2D feature observations. Translation is returned in metres.
    cv::Mat localise_with_pnp(
        const vector<cv::Point3f>& metric_points,
        const cv::Mat& metric_descriptors,
        const cv::Mat& current_image,
        const cv::Mat& current_intrinsics,
        bool& is_localised
    );

    cv::Mat create_complete_transform(
        const cv::Mat& R,
        const cv::Mat& t
    );

private:

    bool sample_depth(
        const cv::Mat& depth_map,
        const cv::Mat& confidence_map,
        float image_x,
        float image_y,
        int image_width,
        int image_height,
        float& depth_metres
    );
};

#endif
