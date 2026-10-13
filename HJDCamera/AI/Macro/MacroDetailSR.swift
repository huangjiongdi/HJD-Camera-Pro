//
//  MacroDetailSR.swift
//  HJD Camera Pro
//
//  微距细节超分：增强翅膀纹理、复眼结构等，受约束不凭空捏造。
//

import Foundation
import CoreImage

final class MacroDetailSR {

    static let shared = MacroDetailSR()

    struct SRResult {
        var image: CIImage
        var scale: Double
        var modelUsed: String
    }

    private init() {}

    /// 微距细节超分。
    func superResolve(image: CIImage, scale: Double = 2.0) -> SRResult {
        // 优先使用 MacroDetailSR 专用模型
        if AIModelRegistry.shared.isModelAvailable("macrodetail_sr") {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: "macrodetail_sr", input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                return SRResult(image: result, scale: scale, modelUsed: "MacroDetailSR")
            }
        }

        // 回退到通用超分
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

        // 最终回退
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let enhanced = scaled.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.5,
            kCIInputIntensityKey: 0.5
        ])
        return SRResult(image: enhanced, scale: scale, modelUsed: "Lanczos+UnsharpMask")
    }
}
