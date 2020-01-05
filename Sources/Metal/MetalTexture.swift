//
//  MetalTexture.swift
//  Pods
//
//  Created by kintan on 2018/6/14.
//

import MetalKit
final class MetalTexture {
    private var textureCache: CVMetalTextureCache?
    public var commandQueue: MTLCommandQueue?
    private let device: MTLDevice
    init() {
        device = MetalRenderPipelinePool.share.device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        commandQueue = device.makeCommandQueue()
    }

    public func makeCommandBuffer() -> MTLCommandBuffer? {
        return commandQueue?.makeCommandBuffer()
    }

    public func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture]? {
        if pixelBuffer.isPlanar {
            var textures = [MTLTexture]()
            let formats: [MTLPixelFormat] = pixelBuffer.planeCount == 3 ? [.r8Unorm, .r8Unorm, .r8Unorm] : [.r8Unorm, .rg8Unorm]
            for index in 0 ..< pixelBuffer.planeCount {
                let width = pixelBuffer.widthOfPlane(at: index)
                let height = pixelBuffer.heightOfPlane(at: index)
                if let texture = texture(pixelBuffer: pixelBuffer, planeIndex: index, pixelFormat: formats[index], width: width, height: height) {
                    textures.append(texture)
                }
            }
            return textures
        } else {
            if let texture = texture(pixelBuffer: pixelBuffer, planeIndex: 0, pixelFormat: .bgra8Unorm, width: pixelBuffer.width, height: pixelBuffer.height) {
                return [texture]
            }
        }
        return nil
    }

    private func texture(pixelBuffer: CVPixelBuffer, planeIndex: Int, pixelFormat: MTLPixelFormat, width: Int, height: Int) -> MTLTexture? {
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &cvTextureOut)
        guard let cvTexture = cvTextureOut, let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        return inputTexture
    }

    func textures(pixelFormat: OSType, width: Int, height: Int, bytes: [UnsafeRawPointer], bytesPerRow: [Int]) -> [MTLTexture]? {
        var planeCount = 3
        var widths = Array(repeating: width, count: 3)
        var heights = Array(repeating: height, count: 3)
        var formats = Array(repeating: MTLPixelFormat.r8Unorm, count: 3)
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8Planar:
            widths[1] = width / 2
            widths[2] = width / 2
            heights[1] = height / 2
            heights[2] = height / 2
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            planeCount = 2
            widths[1] = width / 2
            heights[1] = height / 2
            formats[1] = .rg8Unorm
        case kCVPixelFormatType_32BGRA:
            planeCount = 1
            formats[0] = .bgra8Unorm
        default:
            return nil
        }
        var textures = [MTLTexture]()
        for i in 0 ..< planeCount {
            if let texture = texture(pixelFormat: formats[i], width: widths[i], height: heights[i], bytes: bytes[i], bytesPerRow: bytesPerRow[i]) {
                textures.append(texture)
            }
        }
        return textures
    }

    private func texture(pixelFormat: MTLPixelFormat, width: Int, height: Int, bytes: UnsafeRawPointer, bytesPerRow: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: bytesPerRow)
        return texture
    }
}
