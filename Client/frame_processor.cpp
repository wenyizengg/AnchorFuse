// Copyright (C) 2026 Wenyi Chen

#include "frame_processor.h"

bool frame_processor::extract_features(
    const cv::Mat& image,
    vector<cv::KeyPoint>& keypoints,
    cv::Mat& descriptors
) {
    cv::Ptr<cv::ORB> orb = cv::ORB::create(
        1000,   // max number of features
        1.2,    // size factor between pyramid levels
        8,      // number of pyramid levels
        15,     // edge threshold
        0,      // first level
        2,      // WTA_K
        cv::ORB::HARRIS_SCORE,
        31,     // patch size
        20      // FAST threshold
    );

    const int keypoint_threshold = 300;

    orb->detectAndCompute(
        image,
        cv::noArray(),
        keypoints,
        descriptors
    );

    return keypoints.size() >= keypoint_threshold && !descriptors.empty();
}

vector<cv::DMatch> frame_processor::knn_match(
    const cv::Mat& descriptors1,
    const cv::Mat& descriptors2
) {
    if (descriptors1.empty() || descriptors2.empty()) {
        return {};
    }

    cv::BFMatcher matcher(cv::NORM_HAMMING, false);
    vector<vector<cv::DMatch>> knn_matches;
    matcher.knnMatch(descriptors1, descriptors2, knn_matches, 2);

    vector<cv::DMatch> good_matches;
    const float ratio_thresh = 0.8f;

    for (const auto& candidates : knn_matches) {
        if (candidates.size() < 2) {
            continue;
        }

        if (
            candidates[0].distance <
            ratio_thresh * candidates[1].distance
        ) {
            good_matches.push_back(candidates[0]);
        }
    }

    cout
        << "Original matches: " << knn_matches.size()
        << ", matches after Lowe filtering: " << good_matches.size()
        << endl;

    return good_matches;
}

bool frame_processor::sample_depth(
    const cv::Mat& depth_map,
    const cv::Mat& confidence_map,
    float image_x,
    float image_y,
    int image_width,
    int image_height,
    float& depth_metres
) {
    if (
        depth_map.empty() ||
        depth_map.type() != CV_32FC1 ||
        image_width <= 1 ||
        image_height <= 1
    ) {
        return false;
    }

    const float depth_x =
        image_x * static_cast<float>(depth_map.cols - 1) /
        static_cast<float>(image_width - 1);

    const float depth_y =
        image_y * static_cast<float>(depth_map.rows - 1) /
        static_cast<float>(image_height - 1);

    const int centre_x = static_cast<int>(std::lround(depth_x));
    const int centre_y = static_cast<int>(std::lround(depth_y));

    vector<float> candidates;
    candidates.reserve(9);

    const bool use_confidence =
        !confidence_map.empty() &&
        confidence_map.type() == CV_8UC1 &&
        confidence_map.cols == depth_map.cols &&
        confidence_map.rows == depth_map.rows;

    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            const int x = centre_x + dx;
            const int y = centre_y + dy;

            if (
                x < 0 || x >= depth_map.cols ||
                y < 0 || y >= depth_map.rows
            ) {
                continue;
            }

            // ARKit confidence values are low / medium / high. Reject low
            // confidence samples when a confidence map is available.
            if (use_confidence) {
                const uint8_t confidence = confidence_map.at<uint8_t>(y, x);
                if (confidence < 1) {
                    continue;
                }
            }

            const float depth = depth_map.at<float>(y, x);

            // Keep a broad physically sensible interval. LiDAR-quality
            // filtering is primarily provided by ARKit's confidence map.
            if (
                std::isfinite(depth) &&
                depth >= 0.15f &&
                depth <= 10.0f
            ) {
                candidates.push_back(depth);
            }
        }
    }

    if (candidates.empty()) {
        return false;
    }

    const size_t middle = candidates.size() / 2;
    std::nth_element(
        candidates.begin(),
        candidates.begin() + middle,
        candidates.end()
    );

    depth_metres = candidates[middle];
    return std::isfinite(depth_metres);
}

bool frame_processor::create_metric_landmarks(
    const cv::Mat& image,
    const cv::Mat& depth_map,
    const cv::Mat& confidence_map,
    const cv::Mat& intrinsics,
    vector<cv::Point3f>& metric_points,
    cv::Mat& metric_descriptors
) {
    metric_points.clear();
    metric_descriptors.release();

    if (
        image.empty() ||
        depth_map.empty() ||
        intrinsics.empty() ||
        intrinsics.rows != 3 ||
        intrinsics.cols != 3
    ) {
        return false;
    }

    vector<cv::KeyPoint> keypoints;
    cv::Mat descriptors;

    if (!extract_features(image, keypoints, descriptors)) {
        cout << "Keyframe rejected: fewer than 300 ORB keypoints." << endl;
        return false;
    }

    const double fx = intrinsics.at<double>(0, 0);
    const double fy = intrinsics.at<double>(1, 1);
    const double cx = intrinsics.at<double>(0, 2);
    const double cy = intrinsics.at<double>(1, 2);

    if (
        !std::isfinite(fx) ||
        !std::isfinite(fy) ||
        fx <= 1e-9 ||
        fy <= 1e-9
    ) {
        return false;
    }

    metric_points.reserve(keypoints.size());

    for (size_t i = 0; i < keypoints.size(); ++i) {
        float depth = 0.0f;

        if (!sample_depth(
            depth_map,
            confidence_map,
            keypoints[i].pt.x,
            keypoints[i].pt.y,
            image.cols,
            image.rows,
            depth
        )) {
            continue;
        }

        const float u = keypoints[i].pt.x;
        const float v = keypoints[i].pt.y;

        // Back project into the OpenCV camera coordinate system.
        const float x = static_cast<float>((u - cx) * depth / fx);
        const float y = static_cast<float>((v - cy) * depth / fy);
        const float z = depth;

        if (
            !std::isfinite(x) ||
            !std::isfinite(y) ||
            !std::isfinite(z)
        ) {
            continue;
        }

        metric_points.emplace_back(x, y, z);
        metric_descriptors.push_back(descriptors.row(static_cast<int>(i)));
    }

    const size_t minimum_metric_landmarks = 30;

    cout
        << "ORB keypoints: " << keypoints.size()
        << ", valid metric landmarks: " << metric_points.size()
        << endl;

    if (
        metric_points.size() < minimum_metric_landmarks ||
        metric_descriptors.rows != static_cast<int>(metric_points.size())
    ) {
        metric_points.clear();
        metric_descriptors.release();
        return false;
    }

    metric_descriptors = metric_descriptors.clone();
    return true;
}

cv::Mat frame_processor::localise_with_pnp(
    const vector<cv::Point3f>& metric_points,
    const cv::Mat& metric_descriptors,
    const cv::Mat& current_image,
    const cv::Mat& current_intrinsics,
    bool& is_localised
) {
    is_localised = false;
    const cv::Mat empty_result = cv::Mat::eye(4, 4, CV_64F);

    if (
        metric_points.size() < 6 ||
        metric_descriptors.empty() ||
        metric_descriptors.rows != static_cast<int>(metric_points.size()) ||
        metric_descriptors.cols != 32 ||
        metric_descriptors.type() != CV_8UC1 ||
        current_image.empty() ||
        current_intrinsics.empty() ||
        current_intrinsics.rows != 3 ||
        current_intrinsics.cols != 3
    ) {
        return empty_result;
    }

    vector<cv::KeyPoint> current_keypoints;
    cv::Mat current_descriptors;

    if (!extract_features(
        current_image,
        current_keypoints,
        current_descriptors
    )) {
        return empty_result;
    }

    vector<cv::DMatch> good_matches = knn_match(
        metric_descriptors,
        current_descriptors
    );

    // Several stored landmarks can occasionally choose the same current-image feature. PnP requires a meaningful 1:1 correspondence set, so keep only the lowest distance match for each current keypoint.
    std::sort(
        good_matches.begin(),
        good_matches.end(),
        [](const cv::DMatch& lhs, const cv::DMatch& rhs) {
            return lhs.distance < rhs.distance;
        }
    );

    vector<bool> current_keypoint_used(current_keypoints.size(), false);
    vector<cv::Point3f> object_points;
    vector<cv::Point2f> image_points;

    object_points.reserve(good_matches.size());
    image_points.reserve(good_matches.size());

    for (const auto& match : good_matches) {
        if (
            match.queryIdx < 0 ||
            match.queryIdx >= static_cast<int>(metric_points.size()) ||
            match.trainIdx < 0 ||
            match.trainIdx >= static_cast<int>(current_keypoints.size()) ||
            current_keypoint_used[match.trainIdx]
        ) {
            continue;
        }

        current_keypoint_used[match.trainIdx] = true;
        object_points.push_back(metric_points[match.queryIdx]);
        image_points.push_back(current_keypoints[match.trainIdx].pt);
    }

    if (object_points.size() < 8) {
        cout << "PnP rejected: fewer than 8 3D-2D correspondences." << endl;
        return empty_result;
    }

    cv::Mat rvec;
    cv::Mat tvec;
    cv::Mat inliers;

    bool solved = false;

    try {
        solved = cv::solvePnPRansac(
            object_points,
            image_points,
            current_intrinsics,
            cv::noArray(),
            rvec,
            tvec,
            false,
            500,
            4.0,
            0.99,
            inliers,
            cv::SOLVEPNP_EPNP
        );
    } catch (const cv::Exception& exception) {
        cerr << "solvePnPRansac failed: " << exception.what() << endl;
        return empty_result;
    }

    const int minimum_pnp_inliers = 10;

    if (
        !solved ||
        rvec.empty() ||
        tvec.empty() ||
        inliers.rows < minimum_pnp_inliers
    ) {
        cout
            << "PnP rejected: "
            << (inliers.empty() ? 0 : inliers.rows)
            << " RANSAC inliers."
            << endl;
        return empty_result;
    }

    // Refine the RANSAC result using only the inlier correspondences.
    vector<cv::Point3f> inlier_object_points;
    vector<cv::Point2f> inlier_image_points;

    inlier_object_points.reserve(inliers.rows);
    inlier_image_points.reserve(inliers.rows);

    for (int row = 0; row < inliers.rows; ++row) {
        const int index = inliers.at<int>(row, 0);

        if (
            index < 0 ||
            index >= static_cast<int>(object_points.size())
        ) {
            continue;
        }

        inlier_object_points.push_back(object_points[index]);
        inlier_image_points.push_back(image_points[index]);
    }

    if (inlier_object_points.size() >= 6) {
        try {
            cv::solvePnPRefineLM(
                inlier_object_points,
                inlier_image_points,
                current_intrinsics,
                cv::noArray(),
                rvec,
                tvec
            );
        } catch (const cv::Exception& exception) {
            // Keep the valid RANSAC estimate if nonlinear refinement fails.
            cerr << "solvePnPRefineLM failed: "
                 << exception.what() << endl;
        }
    }

    if (
        cv::checkRange(rvec) == false ||
        cv::checkRange(tvec) == false
    ) {
        return empty_result;
    }

    cv::Mat R;
    cv::Rodrigues(rvec, R);

    cv::Mat transform_cv = create_complete_transform(R, tvec);

    // OpenCV camera axes: +x right, +y down, +z forward.
    // ARKit camera axes:  +x right, +y up,   -z forward.
    //
    // PnP returns ^C_cv T_K_cv. Change basis on both camera frames to obtain
    // ^C_arkit T_K_arkit while preserving the metric translation.
    const cv::Mat cv_to_arkit = (
        cv::Mat_<double>(4, 4) <<
         1.0,  0.0,  0.0, 0.0,
         0.0, -1.0,  0.0, 0.0,
         0.0,  0.0, -1.0, 0.0,
         0.0,  0.0,  0.0, 1.0
    );

    cv::Mat transform_arkit =
        cv_to_arkit * transform_cv * cv_to_arkit;

    cout
        << "PnP accepted with " << inlier_object_points.size()
        << " inliers; translation norm = "
        << cv::norm(tvec) << " m."
        << endl;

    is_localised = true;
    return transform_arkit;
}

cv::Mat frame_processor::create_complete_transform(
    const cv::Mat& R,
    const cv::Mat& t
) {
    cv::Mat transform = cv::Mat::eye(4, 4, CV_64F);

    if (R.empty() || R.rows != 3 || R.cols != 3) {
        return transform;
    }

    cv::Mat rotation64;
    R.convertTo(rotation64, CV_64F);
    rotation64.copyTo(transform(cv::Rect(0, 0, 3, 3)));

    for (int i = 0; i < 3; ++i) {
        if (t.type() == CV_64FC1) {
            transform.at<double>(i, 3) = t.at<double>(i);
        } else if (t.type() == CV_32FC1) {
            transform.at<double>(i, 3) =
                static_cast<double>(t.at<float>(i));
        } else {
            return cv::Mat::eye(4, 4, CV_64F);
        }
    }

    return transform;
}
