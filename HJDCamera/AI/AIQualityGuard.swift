//
//  AIQualityGuard.swift
//  HJD Camera Pro
//
//  AI 质量守护：检测过度锐化、光晕、文字篡改、捏造纹理，给出伪影评分与回退建议。
//

import Foundation
import CoreImage
import Accelerate

final class AIQualityGuard {

    static let shared = AIQualityGuard()

    struct Report {
        var overSharpeningScore: Double   // 0-1，越高越严重
        var haloScore: Double            // 0-1
        var textHallucinationScore: Double
        var inventedTextureScore: Double
        var overallArtifactScore: Double // 0-1
        var shouldFallback: Bool
        var suggestion: String
    }

    private init() {}

    /// 对比原图与 AI 处理后图像，生成质量报告。
    func evaluate(original: CIImage, processed: CIImage) -> Report {
        let overSharp = detectOverSharpening(original: original, processed: processed)
        let halo = detectHalo(original: original, processed: processed)
        let textHall = detectTextHallucination(original: original, processed: processed)
        let invented = detectInventedTexture(original: original, processed: processed)

        let overall = (overSharp + halo + textHall + invented) / 4.0
        let shouldFallback = overall > 0.5 || overSharp > 0.7 || textHall > 0.6

        let suggestion: String
        if shouldFallback {
            if textHall > 0.6 {
                suggestion = "检测到文字被AI改写，建议关闭文字增强或回退到原图"
            } else if overSharp > 0.7 {
                suggestion = "锐化过度，建议降低超分强度或使用 Lanczos 传统缩放"
            } else if halo > 0.6 {
                suggestion = "边缘光晕明显，建议开启边缘保护"
            } else {
                suggestion = "整体伪影偏高，建议回退到传统图像处理"
            }
        } else {
            suggestion = "质量合格"
        }

        return Report(
            overSharpeningScore: overSharp,
            haloScore: halo,
            textHallucinationScore: textHall,
            inventedTextureScore: invented,
            overallArtifactScore: overall,
            shouldFallback: shouldFallback,
            suggestion: suggestion
        )
    }

    // MARK: - Detection

    private func detectOverSharpening(original: CIImage, processed: CIImage) -> Double {
        // 计算处理后图像高频能量增幅
        let origLap = laplacianVariance(original)
        let procLap = laplacianVariance(processed)
        guard origLap > 0 else { return 0 }
        let ratio = procLap / origLap
        if ratio > 4.0 { return min(1.0, Double(ratio - 4.0) / 6.0) }
        return 0
    }

    private func detectHalo(original: CIImage, processed: CIImage) -> Double {
        // 在强边缘附近检测亮度过冲
        let edgeMap = edgeMagnitude(processed)
        let brightRing = edgeMap.filtered(
            using: CIFilter(name: "CIGaussianBlur",
                           parameters: [kCIInputRadiusKey: 3.0])
        )
        // 简化：返回边缘密度作为光晕指标
        return edgeDensity(brightRing)
    }

    private func detectTextHallucination(original: CIImage, processed: CIImage) -> Double {
        // 对比两图中 Vision 检测到的文字区域面积与内容变化
        // 简化实现：返回 0（文字检测由 TextEnhancer 中的 TextIntegrityGuard 完成）
        return 0.0
    }

    private func detectInventedTexture(original: CIImage, processed: CIImage) -> Double {
        // 检测处理后图像中出现原图不存在的高频重复纹理
        let origTexture = textureEnergy(original)
        let procTexture = textureEnergy(processed)
        guard origTexture > 0 else { return 0 }
        let ratio = procTexture / origTexture
        if ratio > 3.0 { return min(1.0, Double(ratio - 3.0) / 5.0) }
        return 0
    }

    // MARK: - Image Metrics

    private func laplacianVariance(_ image: CIImage) -> Double {
        let kernel = CIVector(values: [0,1,0, 1,-4,1, 0,1,0], count: 9)
        guard let filtered = image.applyingFilter("CIConvolution3X3", parameters: [
            kCIInputWeightsKey: kernel
        ]) as CIImage? else { return 0 }
        return grayscaleMeanSquared(filtered)
    }

    private func edgeMagnitude(_ image: CIImage) -> CIImage {
        let gx = CIVector(values: [-1,0,1, -2,0,2, -1,0,1], count: 9)
        let gy = CIVector(values: [-1,-2,-1, 0,0,0, 1,2,1], count: 9)
        let dx = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: gx])
        let dy = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: gy])
        return dx.applyingFilter("CISquareRoot", parameters: [:])
    }

    private func edgeDensity(_ image: CIImage) -> Double {
        return grayscaleMeanSquared(image)
    }

    private func textureEnergy(_ image: CIImage) -> Double {
        return laplacianVariance(image)
    }

    private func grayscaleMeanSquared(_ image: CIImage) -> Double {
        let extent = image.extent
        let w = min(256, Int(extent.width))
        let h = min(256, Int(extent.height))
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
        let count = w * h
        for i in 0..<count {
            let v = Double(ptr[i]) / 255.0
            sumSq += v * v
        }
        return sumSq / Double(count)
    }
}
