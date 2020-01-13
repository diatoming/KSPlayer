//
//  VideoOutput.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import CoreImage
import QuartzCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
final class VideoOutput: NSObject, FrameOutput {
    private var currentRender: MEFrame?
    weak var renderSource: OutputRenderSourceDelegate?
    var renderView: PixelRenderView & UIView
    var isOutput = true
    private lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(target: self, selector: #selector(readBuffer(_:)))
        displayLink.add(to: .main, forMode: RunLoop.Mode.default)
        displayLink.isPaused = true
        return displayLink
    }()

    override init() {
        renderView = KSDefaultParameter.renderViewType.init()
    }

    func play() {
        displayLink.isPaused = false
    }

    func pause() {
        displayLink.isPaused = true
    }

    @objc private func readBuffer(_: CADisplayLink) {
        if let render = renderSource?.getOutputRender(type: .video, isDependent: true) {
            renderSource?.setVideo(time: render.cmtime)
            if isOutput {
                renderView.set(render: render)
            }
            currentRender = render
        }
    }

    func invalidate() {
        displayLink.invalidate()
    }

    deinit {
        invalidate()
    }

    func flush() {}

    func shutdown() {}

    public func thumbnailImageAtCurrentTime(handler: @escaping (UIImage?) -> Void) {
        if let frame = currentRender as? VideoVTBFrame, let pixelBuffer = frame.corePixelBuffer {
            DispatchQueue.global().async {
                let ciImage = CIImage(cvImageBuffer: pixelBuffer)
                let context = CIContext(options: nil)
                if let videoImage = context.createCGImage(ciImage, from: CGRect(origin: .zero, size: pixelBuffer.size)) {
                    handler(UIImage(cgImage: videoImage))
                } else {
                    handler(nil)
                }
            }
        }
        return handler(nil)
    }
}
