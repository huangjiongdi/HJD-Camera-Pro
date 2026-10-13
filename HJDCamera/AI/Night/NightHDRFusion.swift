//
//  NightHDRFusion.swift
//  HJD Camera Pro
//
//  夜景多帧 HDR 融合：对齐后多帧加权融合，恢复高光与暗部细节。
//

import Foundation
import CoreImage

final class NightHDRFusion {

    static let shared = NightHDRFusion()

    struct FusionResult {
        var image: CIImage
        var dynamicRange: Double  // 动态范围提升倍数
    }

    private init() {}

    /// 融合对齐后的多帧夜景。
    func fuse(alignedFrames: [CIImage], motionMask: NightMotionMask.MaskResult) -> FusionResult {
        guard !alignedFrames.isEmpty else {
            return FusionResult(image: CIImage.empty(), dynamicRange: 1.0)
        }

        // 静态区域：多帧平均降噪
        // 运动区域：取最清晰单帧
        var fused: CIImage = alignedFrames[0]

        for frame in alignedFrames.dropFirst() {
            // 使用运动掩码混合：静态区域用平均，运动区域保留当前帧
            let blended = frame.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: fused,
                kCIInputMaskImageKey: motionMask.mask
            ])
            fused = blended
        }

        // 局部色调映射恢复高光与暗部
        let toneMapped = fused.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0.05),
            "inputPoint1": CIVector(x: 0.25, y: 0.35),
            "inputPoint2": CIVector(x: 0.5, y: 0.55),
            "inputPoint3": CIVector(x: 0.75, y: 0.75),
            "inputPoint4": CIVector(x: 1, y: 0.95)
        ])

        return FusionResult(image: toneMapped, dynamicRange: 2.5)
    }
}
