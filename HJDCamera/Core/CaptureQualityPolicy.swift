//
//  CaptureQualityPolicy.swift
//  HJD Camera Pro
//
//  Pre-shutter quality gate. Given live sensor/preview signals (focus contrast,
//  exposure, hand-shake estimate, subject motion, highlight clipping) it builds a
//  QualityAssessment and returns actionable advice. Three strategies trade speed
//  against perfection: .speed fires immediately, .balanced requires a minimum
//  bar, .quality waits until the shot is genuinely good (or times out).
//

import Foundation
import CoreGraphics

enum CaptureQualityStrategy: String, CaseIterable {
    case speed = "速度优先"
    case balanced = "均衡"
    case quality = "画质优先"
}

struct QualitySignals {
    var focusContrast: Double      // 0...1, higher = sharper focus
    var exposureLuma: Double       // 0...1, 0.18 = mid-tone target
    var highlightClipRatio: Double // 0...1, fraction of blown highlights
    var noiseLevel: Double         // 0...1
    var motionBlur: Double         // 0...1, hand shake / subject motion
}

struct CaptureAdvice {
    let message: String
    /// Whether the policy recommends waiting / retaking the shot.
    let shouldWait: Bool
    /// Whether to invoke a multi-frame / AI rescue pass before saving.
    let requestRescue: Bool
}

final class CaptureQualityPolicy {
    static let shared = CaptureQualityPolicy()

    private init() {}

    // MARK: - Assessment

    func assess(signals: QualitySignals) -> QualityAssessment {
        let sharpness = clamp(signals.focusContrast)
        let noise = clamp(signals.noiseLevel)
        // Distance of luma from the ideal 0.18 exposure -> higher score when closer.
        let exposure = clamp(1.0 - abs(signals.exposureLuma - 0.35) * 2.0)
        let motion = clamp(signals.motionBlur)
        let artifact = clamp(signals.highlightClipRatio)

        let weights: (sharpness: Double, noise: Double, exposure: Double, motion: Double, artifact: Double)
        = (0.30, 0.20, 0.20, 0.20, 0.10)
        let overall = sharpness * weights.sharpness
            + (1.0 - noise) * weights.noise
            + exposure * weights.exposure
            + (1.0 - motion) * weights.motion
            + (1.0 - artifact) * weights.artifact

        var warnings: [String] = []
        if sharpness < 0.35 { warnings.append("对焦模糊") }
        if exposure < 0.45 { warnings.append("曝光不足") }
        if signals.highlightClipRatio > 0.12 { warnings.append("高光溢出") }
        if noise > 0.6 { warnings.append("噪点偏高") }
        if motion > 0.5 { warnings.append("手抖/主体移动") }

        return QualityAssessment(
            sharpnessScore: sharpness,
            noiseScore: noise,
            exposureScore: exposure,
            motionBlurScore: motion,
            artifactScore: artifact,
            overallScore: clamp(overall),
            warnings: warnings,
            aiGeneratedAreas: 0.0
        )
    }

    // MARK: - Advice

    func advice(for assessment: QualityAssessment, strategy: CaptureQualityStrategy) -> CaptureAdvice {
        switch strategy {
        case .speed:
            // Never block; only ask for rescue on severe motion/noise.
            let rescue = assessment.motionBlurScore > 0.6 || assessment.noiseScore > 0.7
            return CaptureAdvice(
                message: assessment.warnings.first ?? "已拍摄",
                shouldWait: false,
                requestRescue: rescue
            )

        case .balanced:
            let shouldWait = assessment.overallScore < 0.45
            let rescue = assessment.noiseScore > 0.55 || assessment.motionBlurScore > 0.5
            let message: String
            if shouldWait, let first = assessment.warnings.first {
                message = "建议稳定后再拍：\(first)"
            } else {
                message = "可拍摄"
            }
            return CaptureAdvice(message: message, shouldWait: shouldWait, requestRescue: rescue)

        case .quality:
            let shouldWait = assessment.overallScore < 0.65
            let rescue = assessment.overallScore < 0.75
            let message: String
            if shouldWait {
                message = assessment.warnings.isEmpty
                    ? "等待最佳拍摄时机"
                    : "等待改善：\(assessment.warnings.joined(separator: "、"))"
            } else {
                message = "画质良好"
            }
            return CaptureAdvice(message: message, shouldWait: shouldWait, requestRescue: rescue)
        }
    }

    // MARK: - Helpers

    private func clamp(_ v: Double) -> Double {
        min(max(v, 0.0), 1.0)
    }
}
