//
//  RepetitiveTextureGuard.swift
//  HJD Camera Pro
//
//  重复纹理保护：防止窗户、砖缝、瓦片等被 AI 错误重复生成。
//

import Foundation
import CoreImage

final class RepetitiveTextureGuard {

    static let shared = RepetitiveTextureGuard()

    struct GuardResult {
        var protectedImage: CIImage
        var repetitionScore: Double  // 0-1，越高越可能错误重复
        var pass: Bool
    }

    private init() {}

    /// 检测并保护重复纹理区域。
    func check(original: CIImage, processed: CIImage) -> GuardResult {
        // 比较原图与处理图的自相关，检测异常重复
        let origRepetition = measureRepetition(original)
        let procRepetition = measureRepetition(processed)

        // 如果处理后重复度异常升高，可能是 AI 错误复制
        let delta = procRepetition - origRepetition
        let repetitionScore = max(0, delta)
        let pass = repetitionScore < 0.3

        // 不通过时混合原图
        let output = pass ? processed : processed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: original,
            kCIInputMaskImageKey: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: processed.extent)
        ])

        return GuardResult(
            protectedImage: output,
            repetitionScore: repetitionScore,
            pass: pass
        )
    }

    private func measureRepetition(_ image: CIImage) -> Double {
        // 简化：用高频能量近似重复纹理强度
        let lap = laplacianVariance(image)
        return min(1.0, lap * 10.0)
    }

    private func laplacianVariance(_ image: CIImage) -> Double {
        let kernel = CIVector(values: [0,1,0, 1,-4,1, 0,1,0], count: 9)
        guard let filtered = image.applyingFilter("CIConvolution3X3", parameters: [
            kCIInputWeightsKey: kernel
        ]) as CIImage? else { return 0 }
        return grayscaleMeanSquared(filtered)
    }

    private func grayscaleMeanSquared(_ image: CIImage) -> Double {
        let extent = image.extent
        let w = min(128, Int(extent.width))
        let h = min(128, Int(extent.height))
        guard w > 0, h > 0 else { return 0 }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_OneComponent8, nil, &buf)
        guard let pb = buf else { return 0 }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0 }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sumSq: Double = 0
        for i in 0..<(w*h) {
            let v = Double(ptr[i]) / 255.0
            sumSq += v * v
        }
        return sumSq / Double(w * h)
    }
}
