//
//  NightNoiseEstimator.swift
//  HJD Camera Pro
//
//  夜景噪声估计：亮度噪声、色彩噪声、固定图样噪声。
//

import Foundation
import CoreImage

final class NightNoiseEstimator {

    static let shared = NightNoiseEstimator()

    struct NoiseProfile {
        var lumaNoise: Double      // 亮度噪声强度 0-1
        var chromaNoise: Double    // 色彩噪声强度 0-1
        var fixedPattern: Double    // 固定图样噪声（热噪点）0-1
        var recommendedISO: Double  // 估计的等效 ISO
    }

    private init() {}

    /// 估计夜景图像的噪声剖面。
    func estimate(image: CIImage) -> NoiseProfile {
        let lumaNoise = estimateLumaNoise(image)
        let chromaNoise = estimateChromaNoise(image)
        let fixedPattern = estimateFixedPattern(image)
        let iso = lumaNoise * 3200.0 + chromaNoise * 800.0
        return NoiseProfile(
            lumaNoise: lumaNoise,
            chromaNoise: chromaNoise,
            fixedPattern: fixedPattern,
            recommendedISO: iso
        )
    }

    private func estimateLumaNoise(_ image: CIImage) -> Double {
        // 在平坦区域计算局部标准差
        let blur = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
        let diff = image.applyingFilter("CIDifferenceBlendMode", parameters: [
            kCIInputBackgroundImageKey: blur
        ])
        return grayscaleMean(diff)
    }

    private func estimateChromaNoise(_ image: CIImage) -> Double {
        let colorControls = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 2.0
        ])
        let luma = estimateLumaNoise(colorControls)
        return min(1.0, luma * 0.8)
    }

    private func estimateFixedPattern(_ image: CIImage) -> Double {
        // 固定图样噪声：多帧平均后仍残留的亮像素
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
        var hotPixels = 0
        for i in 0..<(w*h) where ptr[i] > 240 { hotPixels += 1 }
        return min(1.0, Double(hotPixels) / Double(w * h) * 10.0)
    }

    private func grayscaleMean(_ image: CIImage) -> Double {
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
        var sum: Double = 0
        for i in 0..<(w*h) { sum += Double(ptr[i]) / 255.0 }
        return sum / Double(w * h)
    }
}
