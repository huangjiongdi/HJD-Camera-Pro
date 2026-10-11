//
//  LunarConfidenceMap.swift
//  HJD Camera Pro
//
//  月面可信度地图：标记真实采集区域 vs AI 推测区域，低置信度区域降低增强。
//

import Foundation
import CoreImage

final class LunarConfidenceMap {

    static let shared = LunarConfidenceMap()

    struct LunarMap {
        var confidenceImage: CIImage  // 灰度图，越亮越可信
        var size: CGSize
    }

    private init() {}

    /// 基于月面图像生成可信度地图。
    func generate(from image: CIImage, moonDetection: LunarDetector.DetectionResult) -> LunarMap {
        let extent = image.extent
        // 月面中心区域可信度高，边缘与暗区可信度低
        let center = moonDetection.center
        let radius = moonDetection.radius

        // 创建径向渐变掩码
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: center.x, y: center.y),
            "inputRadius0": radius * 0.3,
            "inputRadius1": radius * 1.5,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: 0.3, green: 0.3, blue: 0.3)
        ])
        let mask = gradient?.outputImage?.cropped(to: extent) ?? CIImage(color: .white).cropped(to: extent)

        return LunarMap(confidenceImage: mask, size: extent.size)
    }

    /// 根据可信度地图调整增强强度。
    func blend(original: CIImage, enhanced: CIImage, map: LunarMap) -> CIImage {
        return enhanced.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: original,
            kCIInputMaskImageKey: map.confidenceImage
        ])
    }
}
