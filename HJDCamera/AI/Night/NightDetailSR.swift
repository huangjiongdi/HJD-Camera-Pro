//
//  NightDetailSR.swift
//  HJD Camera Pro
//
//  夜景专用超分：在降噪后的夜景图上恢复细节，避免放大噪声。
//

import Foundation
import CoreImage

final class NightDetailSR {

    static let shared = NightDetailSR()

    struct SRResult {
        var image: CIImage
        var scale: Double
        var method: String
    }

    private init() {}

    /// 夜景超分。
    func superResolve(image: CIImage, scale: Double = 2.0) -> SRResult {
        // 尝试使用夜景专用超分模型
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
                return SRResult(image: result, scale: scale, method: "CoreML(\(model.id))")
            }
        }

        // 回退：Lanczos 缩放 + 边缘增强
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let enhanced = scaled.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.5,
            kCIInputIntensityKey: 0.4
        ])
        return SRResult(image: enhanced, scale: scale, method: "Lanczos+UnsharpMask")
    }
}
