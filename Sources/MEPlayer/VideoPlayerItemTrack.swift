//
//  VideoPlayerItemTrack.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import CoreVideo
import ffmpeg
import Foundation

final class VideoPlayerItemTrack: FFPlayerItemTrack<VideoVTBFrame>, PixelFormat {
    var pixelFormatType: OSType = KSDefaultParameter.bufferPixelFormatType
    private var pool: CVPixelBufferPool?
    private var imgConvertCtx: OpaquePointer?
    private var dstFrame: UnsafeMutablePointer<AVFrame>?
    private lazy var width = codecpar.pointee.width
    private lazy var height = codecpar.pointee.height
    private lazy var aspectRatio = codecpar.pointee.aspectRatio
    override func open() -> Bool {
        guard super.open(), codecpar.pointee.format != AV_PIX_FMT_NONE.rawValue else {
            return false
        }
        let convert: Bool
        if pixelFormatType == kCVPixelFormatType_32BGRA {
            convert = codecpar.pointee.format != AV_PIX_FMT_BGRA.rawValue
        } else {
            convert = codecpar.pointee.format != AV_PIX_FMT_NV12.rawValue
            //                    && codecpar.pointee.format != AV_PIX_FMT_YUV420P.rawValue
        }
        if convert {
            let dstFormat = pixelFormatType == kCVPixelFormatType_32BGRA ? AV_PIX_FMT_BGRA : AV_PIX_FMT_NV12
            imgConvertCtx = sws_getContext(width, height, AVPixelFormat(rawValue: codecpar.pointee.format), width, height, dstFormat, SWS_BICUBIC, nil, nil, nil)
            dstFrame = av_frame_alloc()
            guard imgConvertCtx != nil, let dstFrame = dstFrame else {
                return false
            }
            dstFrame.pointee.width = width
            dstFrame.pointee.height = height
            dstFrame.pointee.format = dstFormat.rawValue
            av_image_alloc(&dstFrame.pointee.data.0, &dstFrame.pointee.linesize.0, width, height, AVPixelFormat(rawValue: dstFrame.pointee.format), 64)
            pool = create(bytesPerRowAlignment: dstFrame.pointee.linesize.0)
            if pool == nil {
                return false
            }
        }
        return true
    }

    override func fetchReuseFrame() throws -> VideoVTBFrame {
        let result = avcodec_receive_frame(codecContext, coreFrame)
        if result == 0, let coreFrame = coreFrame {
            let convertFrame = swsConvert(frame: coreFrame.pointee)
            if pool == nil || convertFrame.width != width || convertFrame.height != height {
                width = convertFrame.width
                height = convertFrame.height
                if let pool = pool {
                    CVPixelBufferPoolFlush(pool, CVPixelBufferPoolFlushFlags(rawValue: 0))
                }
                pool = create(bytesPerRowAlignment: convertFrame.linesize.0)
            }
            if let pool = pool {
                let frame = VideoVTBFrame()
                frame.timebase = timebase
                frame.corePixelBuffer = pool.getPixelBuffer(fromFrame: convertFrame)
                if let buffer = frame.corePixelBuffer, let aspectRatio = aspectRatio {
                    CVBufferSetAttachment(buffer, kCVImageBufferPixelAspectRatioKey, aspectRatio, .shouldPropagate)
                }
                frame.position = coreFrame.pointee.best_effort_timestamp
                if frame.position == Int64.min || frame.position < 0 {
                    frame.position = max(coreFrame.pointee.pkt_dts, 0)
                }
                frame.duration = coreFrame.pointee.pkt_duration
                frame.size = Int64(coreFrame.pointee.pkt_size)
                frame.timebase = timebase
                return frame
            }
        }
        throw result
    }

    override func shutdown() {
        super.shutdown()
        if let pool = pool {
            CVPixelBufferPoolFlush(pool, CVPixelBufferPoolFlushFlags(rawValue: 0))
        }
        pool = nil
        if let imgConvertCtx = imgConvertCtx {
            sws_freeContext(imgConvertCtx)
        }
        imgConvertCtx = nil
        av_frame_free(&dstFrame)
        dstFrame = nil
    }

    private func swsConvert(frame: AVFrame) -> AVFrame {
        guard let dstFrame = dstFrame, codecpar.pointee.format == frame.format else {
            return frame
        }
        let sourceData = Array(tuple: frame.data).map { UnsafePointer<UInt8>($0) }
        let result = sws_scale(imgConvertCtx, sourceData, Array(tuple: frame.linesize), 0, frame.height, &dstFrame.pointee.data.0, &dstFrame.pointee.linesize.0)
        if result > 0 {
            dstFrame.pointee.best_effort_timestamp = frame.best_effort_timestamp
            dstFrame.pointee.pkt_duration = frame.pkt_duration
            dstFrame.pointee.pkt_size = frame.pkt_size
            return dstFrame.pointee
        } else {
            return frame
        }
    }

    private func create(bytesPerRowAlignment: Int32) -> CVPixelBufferPool? {
        let sourcePixelBufferOptions: NSMutableDictionary = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferBytesPerRowAlignmentKey: bytesPerRowAlignment,
        ]
        return .create(sourcePixelBufferOptions: sourcePixelBufferOptions, bufferCount: outputRenderQueue.maxCount)
    }
}

extension AVCodecParameters {
    var aspectRatio: NSDictionary? {
        let den = sample_aspect_ratio.den
        let num = sample_aspect_ratio.num
        if den > 0, num > 0, den != num {
            return [kCVImageBufferPixelAspectRatioHorizontalSpacingKey: num,
                    kCVImageBufferPixelAspectRatioVerticalSpacingKey: den] as NSDictionary
        } else {
            return nil
        }
    }
}

extension AVPixelFormat {
    var format: OSType {
        switch self {
        case AV_PIX_FMT_MONOBLACK: return kCVPixelFormatType_1Monochrome
        case AV_PIX_FMT_RGB555BE: return kCVPixelFormatType_16BE555
        case AV_PIX_FMT_RGB555LE: return kCVPixelFormatType_16LE555
        case AV_PIX_FMT_RGB565BE: return kCVPixelFormatType_16BE565
        case AV_PIX_FMT_RGB565LE: return kCVPixelFormatType_16LE565
        case AV_PIX_FMT_RGB24: return kCVPixelFormatType_24RGB
        case AV_PIX_FMT_BGR24: return kCVPixelFormatType_24BGR
        case AV_PIX_FMT_0RGB: return kCVPixelFormatType_32ARGB
        case AV_PIX_FMT_BGR0: return kCVPixelFormatType_32BGRA
        case AV_PIX_FMT_0BGR: return kCVPixelFormatType_32ABGR
        case AV_PIX_FMT_RGB0: return kCVPixelFormatType_32RGBA
        case AV_PIX_FMT_BGR48BE: return kCVPixelFormatType_48RGB
        case AV_PIX_FMT_UYVY422: return kCVPixelFormatType_422YpCbCr8
        case AV_PIX_FMT_YUVA444P: return kCVPixelFormatType_4444YpCbCrA8R
        case AV_PIX_FMT_YUVA444P16LE: return kCVPixelFormatType_4444AYpCbCr16
        case AV_PIX_FMT_YUV444P: return kCVPixelFormatType_444YpCbCr8
//        case AV_PIX_FMT_YUV422P16: return kCVPixelFormatType_422YpCbCr16
//        case AV_PIX_FMT_YUV422P10: return kCVPixelFormatType_422YpCbCr10
//        case AV_PIX_FMT_YUV444P10: return kCVPixelFormatType_444YpCbCr10
        case AV_PIX_FMT_YUV420P: return kCVPixelFormatType_420YpCbCr8Planar
        case AV_PIX_FMT_NV12: return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case AV_PIX_FMT_YUYV422: return kCVPixelFormatType_422YpCbCr8_yuvs
        case AV_PIX_FMT_GRAY8: return kCVPixelFormatType_OneComponent8
        default:
            return 0
        }
    }
}

extension CVPixelBufferPool {
    static func create(sourcePixelBufferOptions: NSMutableDictionary, bufferCount: Int = 24) -> CVPixelBufferPool? {
        var outputPool: CVPixelBufferPool?
        sourcePixelBufferOptions[kCVPixelBufferIOSurfacePropertiesKey] = NSDictionary()
        let pixelBufferPoolOptions: NSDictionary = [kCVPixelBufferPoolMinimumBufferCountKey: bufferCount]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, pixelBufferPoolOptions, sourcePixelBufferOptions, &outputPool)
        return outputPool
    }

    func getPixelBuffer(fromFrame frame: AVFrame) -> CVPixelBuffer? {
        var pbuf: CVPixelBuffer?
        let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self, &pbuf)
        //    let dic = [kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        //               kCVPixelBufferBytesPerRowAlignmentKey: frame.linesize.0] as NSDictionary
        //    let ret = CVPixelBufferCreate(kCFAllocatorDefault, Int(frame.width), Int(frame.height), KSDefaultParameter.bufferPixelFormatType, dic, &pbuf)
        if let pbuf = pbuf, ret == kCVReturnSuccess {
            CVPixelBufferLockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
            var base = pbuf.baseAddressOfPlane(at: 0)
            base?.copyMemory(from: frame.data.0!, byteCount: Int(frame.linesize.0 * frame.height))
            if pbuf.isPlanar {
                base = pbuf.baseAddressOfPlane(at: 1)
                if frame.format == AV_PIX_FMT_NV12.rawValue {
                    base?.copyMemory(from: frame.data.1!, byteCount: Int(frame.linesize.1 * frame.height / 2))
                } else if frame.format == AV_PIX_FMT_YUV420P.rawValue {
                    let dstPlaneSize = Int(frame.linesize.1 * frame.height / 2)
                    for index in 0 ..< dstPlaneSize {
                        base?.storeBytes(of: frame.data.1![index], toByteOffset: 2 * index, as: UInt8.self)
                        base?.storeBytes(of: frame.data.2![index], toByteOffset: 2 * index + 1, as: UInt8.self)
                    }
                } else if frame.format == AV_PIX_FMT_YUV444P.rawValue {
                    let width = Int(frame.linesize.1 / 2)
                    let height = Int(frame.height / 2)
                    for i in 0 ..< height {
                        for j in 0 ..< width {
                            let index = i * width * 2 + 2 * j
                            let index1 = 2 * i * width * 2 + 2 * j
                            let index2 = index1 + 1
                            let index3 = index1 + width * 2
                            let index4 = index3 + 1
                            var data1 = UInt16(frame.data.1![index1])
                            var data2 = UInt16(frame.data.1![index2])
                            var data3 = UInt16(frame.data.1![index3])
                            var data4 = UInt16(frame.data.1![index4])
                            base?.storeBytes(of: UInt8((data1 + data2 + data3 + data4) / 4), toByteOffset: index, as: UInt8.self)
                            data1 = UInt16(frame.data.2![index1])
                            data2 = UInt16(frame.data.2![index2])
                            data3 = UInt16(frame.data.2![index3])
                            data4 = UInt16(frame.data.2![index4])
                            base?.storeBytes(of: UInt8((data1 + data2 + data3 + data4) / 4), toByteOffset: index + 1, as: UInt8.self)
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
        }
        return pbuf
    }
}
