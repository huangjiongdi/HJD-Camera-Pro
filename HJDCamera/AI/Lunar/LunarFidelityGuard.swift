//
//  LunarFidelityGuard.swift
//  HJD Camera Pro
//
//  月面真实性保护：检测虚构坑纹，确保 AI 增强不捏造不存在的环形山。
//

import Foundation
import CoreImage

final class LunarFidelityGuard {

    static let shared = LunarFidelityGuard()

    struct FidelityReport {
        var hallucinationScore: Double  // 0-1，越高越可能捏造
        var pass: Bool
        var suggestion: String
    }

    private init() {}

    /// 对比原图与处理后图像，检测是否存在虚构细节。
    func check(original: CIImage, processed: CIImage) -> FidelityReport {
        let origDetail = laplacianVariance(original)
        let procDetail = laplacianVariance(processed)

        // 如果处理后细节远超原图，可能是捏造
        let ratio = origDetail > 0 ? procDetail / origDetail : 1.0
        let hallucinationScore: Double
        if ratio > 4.0 {
            hallucinationScore = min(1.0, (ratio - 4.0) / 6.0)
        } else {
            hallucinationScore = 0
        }

        let pass = hallucinationScore < 0.5
        let suggestion = pass ? "月面细节真实可信" : "检测到可能的虚构坑纹，建议降低超分强度"

        return FidelityReport(
            hallucinationScore: hallucinationScore,
            pass: pass,
            suggestion: suggestion
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
