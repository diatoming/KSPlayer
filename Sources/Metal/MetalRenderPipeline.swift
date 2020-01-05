//
//  MetalRenderPipeline.swift
//  KSPlayer-iOS
//
//  Created by wangjinbian on 2019/12/31.
//

import CoreVideo
import Foundation
import Metal
import simd
protocol MetalRenderPipeline {
    var device: MTLDevice { get }
    var library: MTLLibrary { get }
    var state: MTLRenderPipelineState { get }
    var descriptor: MTLRenderPipelineDescriptor { get }
    init(device: MTLDevice, library: MTLLibrary)
}

struct NV12MetalRenderPipeline: MetalRenderPipeline {
    let device: MTLDevice
    let library: MTLLibrary
    let state: MTLRenderPipelineState
    let descriptor: MTLRenderPipelineDescriptor
    init(device: MTLDevice, library: MTLLibrary) {
        self.device = device
        self.library = library
        descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.fragmentFunction = library.makeFunction(name: "displayNV12Texture")
        // swiftlint:disable force_try
        try! state = device.makeRenderPipelineState(descriptor: descriptor)
        // swftlint:enable force_try
    }
}

struct BGRAMetalRenderPipeline: MetalRenderPipeline {
    let device: MTLDevice
    let library: MTLLibrary
    let state: MTLRenderPipelineState
    let descriptor: MTLRenderPipelineDescriptor
    init(device: MTLDevice, library: MTLLibrary) {
        self.device = device
        self.library = library
        descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.fragmentFunction = library.makeFunction(name: "displayTexture")
        // swiftlint:disable force_try
        try! state = device.makeRenderPipelineState(descriptor: descriptor)
        // swftlint:enable force_try
    }
}

struct YUVMetalRenderPipeline: MetalRenderPipeline {
    let device: MTLDevice
    let library: MTLLibrary
    let state: MTLRenderPipelineState
    let descriptor: MTLRenderPipelineDescriptor
    init(device: MTLDevice, library: MTLLibrary) {
        self.device = device
        self.library = library
        descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.fragmentFunction = library.makeFunction(name: "displayYUVTexture")
        // swiftlint:disable force_try
        try! state = device.makeRenderPipelineState(descriptor: descriptor)
        // swftlint:enable force_try
    }
}

class MetalRenderPipelinePool {
    static let share = MetalRenderPipelinePool()
    let device: MTLDevice
    private let library: MTLLibrary
    private lazy var yuv = YUVMetalRenderPipeline(device: device, library: library)
    private lazy var nv12 = NV12MetalRenderPipeline(device: device, library: library)
    private lazy var bgra = BGRAMetalRenderPipeline(device: device, library: library)

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        var library: MTLLibrary!
        library = device.makeDefaultLibrary()
        if library == nil, let path = Bundle.main.path(forResource: "Metal", ofType: "bundle"), let bundle = Bundle(path: path) {
            if #available(iOS 10, OSX 10.12, *) {
                library = try? device.makeDefaultLibrary(bundle: bundle)
            }
            if library == nil, let libraryFile = bundle.path(forResource: "Shaders", ofType: "metal") {
                do {
                    let source = try String(contentsOfFile: libraryFile)
                    library = try device.makeLibrary(source: source, options: nil)
                } catch {}
            }
        }
        self.library = library
    }

    func pipeline(pixelBuffer: CVPixelBuffer) -> MetalRenderPipeline {
        switch pixelBuffer.planeCount {
        case 3:
            return yuv
        case 2:
            return nv12
        case 1:
            return bgra
        default:
            return bgra
        }
    }
}

protocol DisplayModel {
    var indexCount: UInt16 { get }
    var indexType: MTLIndexType { get }
    var primitiveType: MTLPrimitiveType { get }
    var indexBuffer: MTLBuffer { get }
    var vertexBuffer: MTLBuffer? { get }
    var matrixBuffer: MTLBuffer? { get }
    init()
}

extension DisplayModel {
    func set(encoder: MTLRenderCommandEncoder) {
//        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: Int(indexCount), indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
//        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

class PlaneDisplayModel: DisplayModel {
    let indexCount: UInt16
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangleStrip
    let indexBuffer: MTLBuffer
    let vertexBuffer: MTLBuffer?
    let matrixBuffer: MTLBuffer?
    required init() {
        let (indices, vertices) = PlaneDisplayModel.genSphere()
        let device = MetalRenderPipelinePool.share.device
        indexCount = UInt16(indices.count)
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indices.count, options: .storageModeShared)!
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.size * vertices.count, options: .storageModeShared)
        var matrix = matrix_identity_float4x4
        matrixBuffer = device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size, options: .storageModeShared)
    }

    private static func genSphere() -> ([UInt16], [Vertex]) {
        let vertices = [
            Vertex(-1.0, -1.0, 0.0, 1.0, 0.0, 1.0),
            Vertex(-1.0, 1.0, 0.0, 1.0, 0.0, 0.0),
            Vertex(1.0, -1.0, 0.0, 1.0, 1.0, 1.0),
            Vertex(1.0, 1.0, 0.0, 1.0, 1.0, 0.0),
        ]
        let indices: [UInt16] = [0, 1, 2,3]
        return (indices, vertices)
    }
}

class SphereDisplayModel: DisplayModel {
    let indexCount: UInt16
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangle
    let indexBuffer: MTLBuffer
    let vertexBuffer: MTLBuffer?
    let matrixBuffer: MTLBuffer?

    required init() {
        let (indices, vertices) = SphereDisplayModel.genSphere()
        let device = MetalRenderPipelinePool.share.device
        indexCount = UInt16(indices.count)
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indices.count, options: .storageModeShared)!
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.size * 6 * vertices.count, options: .storageModeShared)
        var matrix = matrix_identity_float4x4
        matrixBuffer = device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size, options: .storageModeShared)
    }

    private static func genSphere() -> ([UInt16], [[Float]]) {
        let slicesCount = UInt16(200)
        let parallelsCount = slicesCount / 2
        let indicesCount = Int(slicesCount) * Int(parallelsCount) * 6
        let verticesCount = (slicesCount + 1) * (parallelsCount + 1)
        var indices = [UInt16](repeating: 0, count: indicesCount)
        var vertices = [[Float]](repeating: [Float](), count: Int(verticesCount))
        var runCount = 0
        let radius = Float(1.0)
        let step = (2.0 * Float.pi) / Float(slicesCount)
        for i in 0 ... parallelsCount {
            for j in 0 ... slicesCount {
                var vertex = [Float](repeating: 0, count: 6)
                vertex[0] = radius * sinf(step * Float(i)) * cosf(step * Float(j))
                vertex[1] = radius * cosf(step * Float(i))
                vertex[2] = radius * sinf(step * Float(i)) * sinf(step * Float(j))
                vertex[3] = 1.0
                vertex[4] = Float(j) / Float(slicesCount)
                vertex[5] = Float(i) / Float(parallelsCount)
                vertices[Int(i * (slicesCount + 1) + j)] = vertex
                if i < parallelsCount, j < slicesCount {
                    indices[runCount] = i * (slicesCount + 1) + j
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + j)
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + (j + 1))
                    runCount += 1
                    indices[runCount] = UInt16(i * (slicesCount + 1) + j)
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + (j + 1))
                    runCount += 1
                    indices[runCount] = UInt16(i * (slicesCount + 1) + (j + 1))
                    runCount += 1
                }
            }
        }
        return (indices, vertices)
    }
}

extension CVPixelBuffer {
    var drawableSize: CGSize {
        // Check if the pixel buffer exists
        if let ratio = CVBufferGetAttachment(self, kCVImageBufferPixelAspectRatioKey, nil)?.takeUnretainedValue() as? NSDictionary,
            let horizontal = (ratio[kCVImageBufferPixelAspectRatioHorizontalSpacingKey] as? NSNumber)?.intValue,
            let vertical = (ratio[kCVImageBufferPixelAspectRatioVerticalSpacingKey] as? NSNumber)?.intValue,
            horizontal > 0, vertical > 0, horizontal != vertical {
            return CGSize(width: width, height: height * vertical / horizontal)
        } else {
            return size
        }
    }

    var width: Int {
        return CVPixelBufferGetWidth(self)
    }

    var height: Int {
        return CVPixelBufferGetHeight(self)
    }

    var size: CGSize {
        return CGSize(width: width, height: height)
    }

    var isPlanar: Bool {
        return CVPixelBufferIsPlanar(self)
    }

    var planeCount: Int {
        return CVPixelBufferGetPlaneCount(self)
    }

    var format: OSType {
        return CVPixelBufferGetPixelFormatType(self)
    }

    func widthOfPlane(at planeIndex: Int) -> Int {
        return CVPixelBufferGetWidthOfPlane(self, planeIndex)
    }

    func heightOfPlane(at planeIndex: Int) -> Int {
        return CVPixelBufferGetHeightOfPlane(self, planeIndex)
    }

    func baseAddressOfPlane(at planeIndex: Int) -> UnsafeMutableRawPointer? {
        return CVPixelBufferGetBaseAddressOfPlane(self, planeIndex)
    }
}

extension Vertex {
    // swiftlint:disable identifier_name
    init(_ v0: Float, _ v1: Float, _ v2: Float, _ v3: Float, _ v4: Float, _ v5: Float) {
        self.init(pos: simd_float4(v0, v1, v2, v3), uv: simd_float2(v4, v5))
    }

    // swiftlint:enable identifier_name
}
