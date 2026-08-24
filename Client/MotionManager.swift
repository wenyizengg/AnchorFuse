//
// Copyright (C) 2026 Wenyi Chen

//  MotionManager.swift
//  AR_demo2
//
//  Created by Wenyi on 17/03/2025.
//

import Foundation
import CoreMotion

class MotionManager {
    
    private let motionManager = CMMotionManager()
    var onMotionUpdate: ((CMDeviceMotion) -> Void)? // recursively call when updating

    init() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device does not support DeviceMotion.")
            return
        }

        motionManager.deviceMotionUpdateInterval = 0.2 // 0.2s
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            if let motion = motion {
                self?.onMotionUpdate?(motion) // notify the update
            }
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates() // stop updating
    }
}
