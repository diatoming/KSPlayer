//
//  MetalPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import CoreMedia
import MetalKit
import simd

final class MetalPlayView: MTKView {
    private var textureLoad: MetalTexture
    var displayModel: DisplayModel
    private lazy var samplerState: MTLSamplerState? = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.mipFilter = .nearest
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.rAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        return device?.makeSamplerState(descriptor: samplerDescriptor)
    }()

    private lazy var colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1.164, 1.164, 1.164)
        let secondColumn = SIMD3<Float>(0, 0.392, 2.017)
        let thirdColumn = SIMD3<Float>(1.596, 0.813, 0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device?.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorConversion601FullRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1.0, 1.0, 1.0)
        let secondColumn = SIMD3<Float>(0.0, -0.343, 1.765)
        let thirdColumn = SIMD3<Float>(1.4, -0.711, 0.0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device?.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1.164, 1.164, 1.164)
        let secondColumn = SIMD3<Float>(0.0, -0.213, 2.112)
        let thirdColumn = SIMD3<Float>(1.793, -0.533, 0.0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device?.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorConversion709FullRangeMatrixBuffer: MTLBuffer? = {
        let firstColumn = SIMD3<Float>(1, 1, 1)
        let secondColumn = SIMD3<Float>(0.0, -0.187, 1.856)
        let thirdColumn = SIMD3<Float>(1.570, -0.467, 0.0)
        var matrix = simd_float3x3(firstColumn, secondColumn, thirdColumn)
        let buffer = device?.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }()

    private lazy var colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(-(16.0 / 255.0), -0.5, -0.5)
        let buffer = device?.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private lazy var colorOffsetFullRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(0, -0.5, -0.5)
        let buffer = device?.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared)
        buffer?.label = "colorOffset"
        return buffer
    }()

    init() {
        let device = MetalRenderPipelinePool.share.device
        textureLoad = MetalTexture()
        displayModel = PlaneDisplayModel()
        super.init(frame: .zero, device: device)
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
//        delegate = self
        framebufferOnly = true
        autoResizeDrawable = false
        // Change drawing mode based on setNeedsDisplay().
        enableSetNeedsDisplay = true
    }

    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var drawableSize: CGSize {
        didSet {
            #if targetEnvironment(simulator)
            if #available(iOS 13.0, tvOS 13.0, *) {
                (layer as? CAMetalLayer)?.drawableSize = drawableSize
            }
            #else
            (layer as? CAMetalLayer)?.drawableSize = drawableSize
            #endif
        }
    }
}

extension MetalPlayView: PixelRenderView {
    func set(pixelBuffer: CVPixelBuffer, time _: CMTime) {
        autoreleasepool {
            // Check if the pixel buffer exists
            drawableSize = pixelBuffer.drawableSize
            guard let commandBuffer = textureLoad.makeCommandBuffer(),
                let renderPassDescriptor = currentRenderPassDescriptor,
                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
                let textures = textureLoad.texture(pixelBuffer: pixelBuffer) else {
                return
            }
            encoder.setRenderPipelineState(MetalRenderPipelinePool.share.pipeline(pixelBuffer: pixelBuffer).state)
            encoder.pushDebugGroup("RenderFrame")
            encoder.setFragmentSamplerState(samplerState, index: 0)
            for (index, texture) in textures.enumerated() {
                texture.label = "texture\(index)"
                encoder.setFragmentTexture(texture, index: index)
            }
            setFragmentBuffer(pixelBuffer: pixelBuffer, encoder: encoder)
            displayModel.set(encoder: encoder)
            encoder.popDebugGroup()
            encoder.endEncoding()
            if let drawable = currentDrawable {
                // 不能用commandBuffer.present(drawable)，不然界面不可见的时候，会卡顿，苹果太坑了
                commandBuffer.addScheduledHandler { _ in
                    drawable.present()
                }
            }
            commandBuffer.commit()
            draw()
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
