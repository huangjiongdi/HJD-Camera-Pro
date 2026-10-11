//
//  TextEnhancer.swift
//  HJD Camera Pro
//
//  文字增强：Vision 文字检测 + 边缘增强，TextIntegrityGuard 防止 AI 猜写文字。
//

import Foundation
import CoreImage
import Vision

final class TextEnhancer {

    static let shared = TextEnhancer()

    struct TextResult {
        var image: CIImage
        var textRegions: [CGRect]
        var integrityPreserved: Bool
    }

    private init() {}

    /// 增强图像中的文字区域。
    func enhance(image: CIImage) -> TextResult {
        // 检测文字区域
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = true
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        var regions: [CGRect] = []

        do {
            try handler.perform([request])
            regions = request.results?.map { $0.boundingBox } ?? []
        } catch {
            // Vision 不可用时返回原图
        }

        guard !regions.isEmpty else {
            return TextResult(image: image, textRegions: [], integrityPreserved: true)
        }

        // 对文字区域做边缘增强
        var enhanced = image
        for region in regions {
            let textTile = image.cropped(to: region)
            let sharpened = textTile.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 1.0,
                kCIInputIntensityKey: 0.6
            ])
            enhanced = enhanced.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: enhanced,
                kCIInputMaskImageKey: sharpened
            ])
        }

        // 完整性检查：确保文字内容未被篡改
        let integrity = TextIntegrityGuard.shared.check(original: image, enhanced: enhanced)

        return TextResult(
            image: integrity.passed ? enhanced : image,
            textRegions: regions,
            integrityPreserved: integrity.passed
        )
    }
}

// MARK: - Text Integrity Guard

final class TextIntegrityGuard {

    static let shared = TextIntegrityGuard()

    struct IntegrityReport {
        var passed: Bool
        var hallucinationScore: Double
    }

    private init() {}

    /// 检测增强后是否出现原图不存在的文字。
    func check(original: CIImage, enhanced: CIImage) -> IntegrityReport {
        // 比较两图中 Vision 检测到的文字区域数量
        let origCount = detectTextCount(original)
        let procCount = detectTextCount(enhanced)

        // 如果处理后文字区域显著增多，可能是 AI 猜写
        let ratio = origCount > 0 ? Double(procCount) / Double(origCount) : 1.0
        let hallucination = ratio > 1.5 ? min(1.0, (ratio - 1.5) / 2.0) : 0

        return IntegrityReport(
            passed: hallucination < 0.3,
            hallucinationScore: hallucination
        )
    }

    private func detectTextCount(_ image: CIImage) -> Int {
        let request = VNDetectTextRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results?.count ?? 0
        } catch {
            return 0
        }
    }
}
