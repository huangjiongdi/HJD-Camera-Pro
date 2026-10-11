//
//  LunarSR.swift
//  HJD Camera Pro
//
//  月面专用超分：调用适配的 Real-ESRGAN / LunarSR 模型，放大月面细节。
//

import Foundation
import CoreImage

final class LunarSR {

    static let shared = LunarSR()

    struct SRResult {
        var image: CIImage
        var scale: Double
        var modelUsed: String
    }

    private init() {}

    /// 月面超分。
    func superResolve(image: CIImage, scale: Double = 2.0) -> SRResult {
        // 优先使用 LunarSR 专用模型
        if AIModelRegistry.shared.isModelAvailable("lunarsr") {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: "lunarsr", input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                return SRResult(image: result, scale: scale, modelUsed: "LunarSR")
            }
        }

        // 回退到通用超分模型
        if let model = AIModelRegistry.shared.defaultModel(for: .superResolution),
           AIModelRegistry.shared.isModelAvailable(model.id) {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: model.id, input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                return SRResult(image: result, scale: scale, modelUsed: model.name)
            }
        }

        // 最终回退：Lanczos 缩放
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let enhanced = scaled.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 2.0,
            kCIInputIntensityKey: 0.5
        ])
        return SRResult(image: enhanced, scale: scale, modelUsed: "Lanczos+UnsharpMask")
    }
}
