//
//  LiveDetailEngine.swift
//  HJD Camera Pro
//
//  HJD Live Detail Engine 核心：实时预览细节增强引擎。
//

import Foundation
import CoreImage

final class LiveDetailEngine {

    static let shared = LiveDetailEngine()

    struct LiveResult {
        var image: CIImage
        var enhancementLevel: Double  // 0-1
        var latency: TimeInterval
    }

    private init() {}

    /// 实时增强单帧预览。
    func enhance(image: CIImage, level: LivePreviewLevel = .balanced) -> LiveResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let intensity: Double
        switch level {
        case .off: intensity = 0
        case .smooth: intensity = 0.2
        case .balanced: intensity = 0.4
        case .highDetail: intensity = 0.7
        }

        guard intensity > 0 else {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LiveResult(image: image, enhancementLevel: 0, latency: elapsed)
        }

        // 轻量边缘增强
        let enhanced = image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.0,
            kCIInputIntensityKey: intensity
        ])

        // 局部对比度
        let contrast = enhanced.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.0 + intensity * 0.2,
            kCIInputSaturationKey: 1.0 + intensity * 0.1
        ])

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        return LiveResult(image: contrast, enhancementLevel: intensity, latency: elapsed)
    }
}
