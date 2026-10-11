//
//  LunarDetailRecovery.swift
//  HJD Camera Pro
//
//  月面细节恢复：受约束增强，不凭空捏造环形山与坑纹。
//

import Foundation
import CoreImage

final class LunarDetailRecovery {

    static let shared = LunarDetailRecovery()

    struct RecoveryResult {
        var image: CIImage
        var recoveredDetail: Double  // 恢复的细节量 0-1
        var constrained: Bool       // 是否受约束（不捏造）
    }

    private init() {}

    /// 恢复月面细节，严格受约束。
    func recover(image: CIImage, original: CIImage) -> RecoveryResult {
        // 只增强原图中已存在的高频细节，不创造新结构
        let origLap = laplacianVariance(original)
        let procLap = laplacianVariance(image)

        // 计算原图高频能量作为约束上限
        let detailRatio = procLap > 0 ? origLap / procLap : 0
        let constrainedGain = min(1.0, detailRatio * 1.5)

        // 非锐化蒙版，强度受限
        let recovered = image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.5,
            kCIInputIntensityKey: 0.3 * constrainedGain
        ])

        // 混合：保留 30% 原图，防止过度处理
        let blended = recovered.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: original,
            kCIInputMaskImageKey: CIImage(color: CIColor(red: 0.7, green: 0.7, blue: 0.7))
                .cropped(to: image.extent)
        ])

        return RecoveryResult(
            image: blended,
            recoveredDetail: constrainedGain,
            constrained: true
        )
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
