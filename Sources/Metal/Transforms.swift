//
//  Transforms.swift
//  MetalSpectrograph
//
//  Created by David Conner on 9/9/15.
//  Copyright © 2015 Voxxel. All rights reserved.
//

import CoreMotion
import simd
// swiftlint:disable identifier_name
extension simd_float4x4 {
    // sx  0   0   0
    // 0   sy  0   0
    // 0   0   sz  0
    // 0   0   0   1

    init(scale x: Float, y: Float, z: Float) {
        self.init(diagonal: [x, y, z, 1.0])
    }

    // 1   0   0   tx
    // 0   1   0   ty
    // 0   0   1   tz
    // 0   0   0   1
    init(translate: SIMD3<Float>) {
        self.init([SIMD4<Float>(1, 0.0, 0.0, translate.x),
                   SIMD4<Float>(0.0, 1, 0.0, translate.y),
                   SIMD4<Float>(0.0, 0.0, 1, translate.z),
                   SIMD4<Float>(0.0, 0.0, 0, 1)])
    }

    init(rotationX radians: Float) {
        self.init(simd_quatf(angle: radians, axis: SIMD3<Float>(1, 0, 0)))
    }

    init(rotationY radians: Float) {
        self.init(simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0)))
    }

    init(rotationZ radians: Float) {
        self.init(simd_quatf(angle: radians, axis: SIMD3<Float>(0, 0, 1)))
    }

    public init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let E = -eye
        let N = normalize(center + E)
        let U = normalize(cross(up, N))
        let V = cross(N, U)
        self.init(rows: [[U.x, V.x, N.x, 0.0],
                         [U.y, V.y, N.y, 0.0],
                         [U.z, V.z, N.z, 0.0],
                         [dot(U, E), dot(V, E), dot(N, E), 1.0]])
    }

    public init(perspective fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let cotan = 1.0 / tanf(fovyRadians / 2.0)
        self.init([SIMD4<Float>(cotan / aspect, 0.0, 0.0, 0.0),
                   SIMD4<Float>(0.0, cotan, 0.0, 0.0),
                   SIMD4<Float>(0.0, 0.0, (farZ + nearZ) / (nearZ - farZ), -1),
                   SIMD4<Float>(0.0, 0.0, (2.0 * farZ * nearZ) / (nearZ - farZ), 0)])
    }

    public init(motion: CMDeviceMotion) {
        self.init(rotation: motion.attitude.rotationMatrix)
    }

    public init(rotation: CMRotationMatrix) {
        self.init([SIMD4<Float>(Float(rotation.m11), Float(rotation.m12), Float(rotation.m13), 0.0),
                   SIMD4<Float>(Float(rotation.m21), Float(rotation.m22), Float(rotation.m23), 0.0),
                   SIMD4<Float>(Float(rotation.m31), Float(rotation.m32), Float(rotation.m33), -1),
                   SIMD4<Float>(0, 0, 0, 1)])
    }

    func rotateX(radians: Float) -> simd_float4x4 {
        return self * simd_float4x4(rotationX: radians)
    }

    func rotateY(radians: Float) -> simd_float4x4 {
        return self * simd_float4x4(rotationY: radians)
    }

    func rotateZ(radians: Float) -> simd_float4x4 {
        return self * simd_float4x4(rotationZ: radians)
    }
}

extension Vertex {
    init(_ v0: Float, _ v1: Float, _ v2: Float, _ v3: Float, _ v4: Float, _ v5: Float) {
        self.init(pos: simd_float4(v0, v1, v2, v3), uv: simd_float2(v4, v5))
    }
}

// swiftlint:enable identifier_name
