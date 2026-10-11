//
//  LiveTemporalFusion.swift
//  HJD Camera Pro
//
//  轻量时域融合：利用前后帧信息提升实时预览画质。
//

import Foundation
import CoreImage

final class LiveTemporalFusion {

    static let shared = LiveTemporalFusion()

    private var previousFrame: CIImage?
    private var fusionStrength: Double = 0.3

    private init() {}

    /// 时域融合当前帧与前一帧。
    func fuse(current: CIImage) -> CIImage {
        guard let prev = previousFrame else {
            previousFrame = current
            return current
        }

        // 检测帧间位移（简化：全局混合）
        let fused = current.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: prev
        ])

        // 归一化
        let normalized = fused.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.7, y: 0.3, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.7, z: 0.3, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.7, w: 0)
        ])

        previousFrame = current
        return normalized
    }

    /// 重置时域状态。
    func reset() {
        previousFrame = nil
    }

    /// 设置融合强度。
    func setStrength(_ strength: Double) {
        fusionStrength = max(0, min(1, strength))
    }
}
