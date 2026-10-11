//
//  NightMotionMask.swift
//  HJD Camera Pro
//
//  运动区域分割：区分静态背景与运动物体，避免多帧融合产生拖影。
//

import Foundation
import CoreImage

final class NightMotionMask {

    static let shared = NightMotionMask()

    struct MaskResult {
        var mask: CIImage       // 白色=静态区域，黑色=运动区域
        var motionRatio: Double  // 运动区域占比 0-1
    }

    private init() {}

    /// 基于多帧差异生成运动掩码。
    func compute(alignedFrames: [CIImage]) -> MaskResult {
        guard let ref = alignedFrames.first else {
            let fullMask = CIImage(color: CIColor.white)
            return MaskResult(mask: fullMask, motionRatio: 0)
        }
        guard alignedFrames.count > 1 else {
            let fullMask = CIImage(color: CIColor.white).cropped(to: ref.extent)
            return MaskResult(mask: fullMask, motionRatio: 0)
        }

        // 累积差异图
        var accumulatedDiff: CIImage = ref
        var diffCount = 0
        for frame in alignedFrames.dropFirst() {
            let diff = frame.applyingFilter("CIDifferenceBlendMode", parameters: [
                kCIInputBackgroundImageKey: ref
            ])
            accumulatedDiff = accumulatedDiff.applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: diff
            ])
            diffCount += 1
        }

        // 阈值化得到掩码
        let threshold = accumulatedDiff.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: -0.15,
            kCIInputContrastKey: 2.0
        ])
        let mask = threshold.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3.0])

        let motionRatio = grayscaleMean(mask)
        return MaskResult(mask: mask, motionRatio: motionRatio)
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
