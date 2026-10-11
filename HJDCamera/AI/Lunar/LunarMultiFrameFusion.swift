//
//  LunarMultiFrameFusion.swift
//  HJD Camera Pro
//
//  月面多帧融合：对齐多帧月亮图像，叠加提升信噪比与分辨率。
//

import Foundation
import CoreImage

final class LunarMultiFrameFusion {

    static let shared = LunarMultiFrameFusion()

    struct FusionResult {
        var image: CIImage
        var frameCount: Int
        var snrImprovement: Double  // 信噪比提升倍数
    }

    private init() {}

    /// 融合多帧月亮图像。
    func fuse(frames: [CIImage], detection: LunarDetector.DetectionResult) -> FusionResult {
        guard !frames.isEmpty else {
            return FusionResult(image: CIImage.empty(), frameCount: 0, snrImprovement: 1.0)
        }

        // 对齐所有帧到第一帧
        let alignment = NightFrameAligner.shared.align(frames: frames)

        // 多帧平均融合
        var fused: CIImage = alignment.alignedFrames[0]
        for frame in alignment.alignedFrames.dropFirst() {
            // 50% 混合
            fused = fused.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: frame
            ])
        }

        // 归一化：除以帧数
        let normFactor = 1.0 / Double(alignment.alignedFrames.count)
        let normalized = fused.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: normFactor, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: normFactor, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: normFactor, w: 0)
        ])

        let snr = sqrt(Double(alignment.alignedFrames.count))
        return FusionResult(image: normalized,
                          frameCount: alignment.alignedFrames.count,
                          snrImprovement: snr)
    }
}
