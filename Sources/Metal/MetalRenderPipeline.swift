//
//  MetalRenderPipeline.swift
//  KSPlayer-iOS
//
//  Created by wangjinbian on 2019/12/31.
//

import CoreVideo
import Foundation
import Metal

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
