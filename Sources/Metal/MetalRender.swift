//
//  MetalRenderer.swift
//  KSPlayer-iOS
//
//  Created by wangjinbian on 2020/1/11.
//
import Foundation
import Metal
import simd
class MetalRender {
    static let share = MetalRender()
    let device: MTLDevice
    private let library: MTLLibrary
    private lazy var yuv = YUVMetalRenderPipeline(device: device, library: library)
    private lazy var nv12 = NV12MetalRenderPipeline(device: device, library: library)
    private lazy var bgra = BGRAMetalRenderPipeline(device: device, library: library)
    private lazy var samplerState: MTLSamplerState? = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.mipFilter = .nearest
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.rAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        return device.makeSamplerState(descriptor: samplerDescriptor)
    }()

    private lazy var colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1.164, 1.164, 1.164)
        let secondColumn = SIMD3<Float>(0, 0.392, 2.017)
        let thirdColumn = SIMD3<Float>(1.596, 0.813, 0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorConversion601FullRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1.0, 1.0, 1.0)
        let secondColumn = SIMD3<Float>(0.0, -0.343, 1.765)
        let thirdColumn = SIMD3<Float>(1.4, -0.711, 0.0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1.164, 1.164, 1.164)
        let secondColumn = SIMD3<Float>(0.0, -0.213, 2.112)
        let thirdColumn = SIMD3<Float>(1.793, -0.533, 0.0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorConversion709FullRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1, 1, 1)
        let secondColumn = SIMD3<Float>(0.0, -0.187, 1.856)
        let thirdColumn = SIMD3<Float>(1.570, -0.467, 0.0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(-(16.0 / 255.0), -0.5, -0.5)
        let buffer = device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private lazy var colorOffsetFullRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(0, -0.5, -0.5)
        let buffer = device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared)
        buffer?.label = "colorOffset"
        return buffer
    }()

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

    func set(descriptor: MTLRenderPassDescriptor, pixelBuffer: CVPixelBuffer, display: DisplayEnum = .plane) -> MTLCommandBuffer? {
        guard let commandBuffer = MetalTexture.share.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
            let textures = MetalTexture.share.texture(pixelBuffer: pixelBuffer) else {
            return nil
        }
        encoder.pushDebugGroup("RenderFrame")
        encoder.setFragmentSamplerState(samplerState, index: 0)
        for (index, texture) in textures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setRenderPipelineState(pipeline(pixelBuffer: pixelBuffer).state)
        setFragmentBuffer(pixelBuffer: pixelBuffer, encoder: encoder)
        display.set(encoder: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
        return commandBuffer
    }

    private func pipeline(pixelBuffer: CVPixelBuffer) -> MetalRenderPipeline {
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

    private func setFragmentBuffer(pixelBuffer: CVPixelBuffer, encoder: MTLRenderCommandEncoder) {
        let pixelFormatType = pixelBuffer.format
        if pixelFormatType != kCVPixelFormatType_32BGRA {
            var buffer = colorConversion601FullRangeMatrixBuffer
            let colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue() as? NSString ?? kCVImageBufferYCbCrMatrix_ITU_R_709_2
            if colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4 {
                if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                    buffer = colorConversion601FullRangeMatrixBuffer
                } else if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
                    // WHY
                    buffer = colorConversion601FullRangeMatrixBuffer
                    //                     buffer = colorConversion601VideoRangeMatrixBuffer
                }
            } else if colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_709_2 {
                if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                    buffer = colorConversion709FullRangeMatrixBuffer
                } else if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
                    buffer = colorConversion709VideoRangeMatrixBuffer
                }
            }
            encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            let colorOffset = pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? colorOffsetFullRangeMatrixBuffer : colorOffsetVideoRangeMatrixBuffer
            encoder.setFragmentBuffer(colorOffset, offset: 0, index: 1)
        }
    }
}
