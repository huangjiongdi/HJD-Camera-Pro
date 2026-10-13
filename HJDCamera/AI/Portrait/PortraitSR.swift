//
//  PortraitSR.swift
//  HJD Camera Pro
//
//  人脸与头发超分：调用 GFPGAN 模型修复面部细节。
//

import Foundation
import CoreImage

final class PortraitSR {

    static let shared = PortraitSR()

    struct SRResult {
        var image: CIImage
        var modelUsed: String
    }

    private init() {}

    /// 人脸超分修复。
    func superResolveFace(image: CIImage) -> SRResult {
        // 优先使用 GFPGAN
        if AIModelRegistry.shared.isModelAvailable("gfpgan_face") {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: "gfpgan_face", input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                return SRResult(image: result, modelUsed: "GFPGAN")
            }
        }

        // 回退：传统锐化
        let enhanced = image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.5,
            kCIInputIntensityKey: 0.3
        ])
        return SRResult(image: enhanced, modelUsed: "UnsharpMask")
    }
}
