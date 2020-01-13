//
//  MetalPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import CoreMedia
import MetalKit

final class MetalPlayView: MTKView {
    var display: DisplayEnum = .plane
    init() {
        let device = MetalRender.share.device
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
    #if targetEnvironment(simulator)
    override func touchesMoved(_ touches: Set<UITouch>, with: UIEvent?) {
        if display == .plane {
            super.touchesMoved(touches, with: with)
        } else {
            display.touchesMoved(touch: touches.first!)
        }
    }
    #endif
}

extension MetalPlayView: PixelRenderView {
    func set(pixelBuffer: CVPixelBuffer, time _: CMTime) {
        autoreleasepool {
            // Check if the pixel buffer exists
            if display == .plane {
                drawableSize = pixelBuffer.drawableSize
            } else {
                drawableSize = UIScreen.main.bounds.size
            }
            guard let renderPassDescriptor = currentRenderPassDescriptor,
                let commandBuffer = MetalRender.share.set(descriptor: renderPassDescriptor, pixelBuffer: pixelBuffer, display: display) else {
                return
            }
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
}
