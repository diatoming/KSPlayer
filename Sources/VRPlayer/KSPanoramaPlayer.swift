//
//  PanoramaPlayer.swift
//  KSPlayer-0677b3ec
//
//  Created by kintan on 2018/7/11.
//
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
public class KSVRPlayer: KSMEPlayer {
    open override var renderViewType: (PixelRenderView & UIView).Type {
        if canUseMetal() {
            return PanoramaView.self
        } else {
            return OpenGLVRPlayView.self
        }
    }

    public override var pixelFormatType: OSType {
        if canUseMetal() {
            return kCVPixelFormatType_32BGRA
        } else {
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
    }
}
