//
//  MotionSensor.swift
//  KSPlayer-iOS
//
//  Created by wangjinbian on 2020/1/13.
//

import CoreMotion
import Foundation
final class MotionSensor {
    static let shared = MotionSensor()
    private let manager = CMMotionManager()
    func ready() -> Bool {
        if manager.isDeviceMotionAvailable {
            return manager.isDeviceMotionActive
        }
        return false
    }

    func start() {
        if manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive {
            manager.deviceMotionUpdateInterval = 1 / 60
            manager.startDeviceMotionUpdates()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func matrix() -> simd_float4x4? {
        return manager.matrix()
    }
}

extension CMMotionManager {
    public func matrix() -> simd_float4x4? {
        guard let motion = deviceMotion else {
            return nil
        }
        return simd_float4x4(motion: motion)
    }
}
