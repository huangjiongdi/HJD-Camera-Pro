//
//  SceneDetector.swift
//  HJD Camera Pro
//
//  场景识别：基于 Vision 框架与规则引擎，识别夜景/人像/月亮/微距/建筑等场景，
//  并根据场景路由到对应 AI 模型管线。
//

import Foundation
import CoreImage
import Vision

final class SceneDetector {

    static let shared = SceneDetector()

    struct SceneResult {
        let primary: SceneType
        let confidence: Double
        let alternatives: [(SceneType, Double)]
    }

    private init() {}

    /// 检测图像场景。
    func detect(sceneIn image: CIImage) -> SceneResult {
        var scores: [SceneType: Double] = [:]

        // 规则 1：亮度判断夜景
        let meanLuma = grayscaleMean(image)
        if meanLuma < 0.25 {
            scores[.night] = (scores[.night] ?? 0) + 0.7
        }

        // 规则 2：人脸检测 -> 人像
        if detectFaces(in: image) > 0 {
            scores[.portrait] = (scores[.portrait] ?? 0) + 0.8
        }

        // 规则 3：圆形高亮物体 -> 月亮
        if detectMoonDisk(in: image) {
            scores[.lunar] = (scores[.lunar] ?? 0) + 0.9
        }

        // 规则 4：高细节近景 -> 微距
        let detail = laplacianVariance(image)
        if detail > 0.02 && meanLuma > 0.3 {
            scores[.macro] = (scores[.macro] ?? 0) + 0.5
        }

        // 规则 5：直线密集 -> 建筑
        if detectVerticalLines(in: image) > 5 {
            scores[.architecture] = (scores[.architecture] ?? 0) + 0.6
        }

        // 规则 6：强逆光检测
        if detectBacklight(in: image) {
            scores[.backlight] = (scores[.backlight] ?? 0) + 0.7
        }

        // 规则 7：文档检测（矩形+文字）
        if detectDocument(in: image) {
            scores[.document] = (scores[.document] ?? 0) + 0.7
        }

        // 规则 8：日落（暖色高占比）
        if detectWarmSky(in: image) {
            scores[.sunset] = (scores[.sunset] ?? 0) + 0.6
        }

        // 默认风景
        if scores.isEmpty {
            scores[.landscape] = 0.5
        }

        let sorted = scores.sorted { $0.value > $1.value }
        let primary = sorted.first?.key ?? .landscape
        let confidence = sorted.first?.value ?? 0.5
        let alternatives = Array(sorted.dropFirst().map { ($0.key, $0.value) })
        return SceneResult(primary: primary,
                          confidence: confidence,
                          alternatives: alternatives)
    }

    /// 根据场景返回推荐的默认模型分类。
    func recommendedModelCategory(for scene: SceneType) -> AIModelCategory {
        switch scene {
        case .normal: return .superResolution
        case .night: return .nightDenoise
        case .portrait: return .portrait
        case .lunar: return .lunar
        case .macro: return .macro
        case .architecture: return .architecture
        case .backlight: return .hdr
        case .landscape: return .superResolution
        case .document: return .text
        case .sports, .fireworks, .stage: return .superResolution
        case .sunset: return .superResolution
        case .starry: return .superResolution
        }
    }

    // MARK: - Vision Helpers

    private func detectFaces(in image: CIImage) -> Int {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results?.count ?? 0
        } catch {
            return 0
        }
    }

    private func detectMoonDisk(in image: CIImage) -> Bool {
        // 简化：在亮度高的小区域检测圆形
        let extent = image.extent
        let w = min(256, Int(extent.width))
        let h = min(256, Int(extent.height))
        guard w > 0, h > 0 else { return false }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_OneComponent8, nil, &buf)
        guard let pb = buf else { return false }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var brightCount = 0
        for i in 0..<(w * h) where ptr[i] > 230 { brightCount += 1 }
        let ratio = Double(brightCount) / Double(w * h)
        // 月亮占比约 1%-15%
        return ratio > 0.01 && ratio < 0.15
    }

    private func detectVerticalLines(in image: CIImage) -> Int {
        let edge = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 2.0])
        let mean = grayscaleMean(edge)
        return mean > 0.1 ? 6 : 0
    }

    private func detectBacklight(in image: CIImage) -> Bool {
        let extent = image.extent
        let w = min(128, Int(extent.width))
        let h = min(128, Int(extent.height))
        guard w > 0, h > 0 else { return false }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_OneComponent8, nil, &buf)
        guard let pb = buf else { return false }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var topBright = 0, bottomDark = 0
        let rowBytes = w
        for row in 0..<(h/2) {
            for col in 0..<w {
                if ptr[row * rowBytes + col] > 200 { topBright += 1 }
            }
        }
        for row in (h/2)..<h {
            for col in 0..<w {
                if ptr[row * rowBytes + col] < 60 { bottomDark += 1 }
            }
        }
        let topRatio = Double(topBright) / Double((h/2) * w)
        let bottomRatio = Double(bottomDark) / Double((h/2) * w)
        return topRatio > 0.3 && bottomRatio > 0.3
    }

    private func detectDocument(in image: CIImage) -> Bool {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            return (request.results?.count ?? 0) > 3
        } catch {
            return false
        }
    }

    private func detectWarmSky(in image: CIImage) -> Bool {
        let extent = image.extent
        let w = min(64, Int(extent.width))
        let h = min(64, Int(extent.height))
        guard w > 0, h > 0 else { return false }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_32BGRA, nil, &buf)
        guard let pb = buf else { return false }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var warmCount = 0
        for i in 0..<(w*h) {
            let r = Double(ptr[i*4+2]) / 255.0
            let g = Double(ptr[i*4+1]) / 255.0
            let b = Double(ptr[i*4]) / 255.0
            if r > 0.6 && r > b + 0.2 && g > b { warmCount += 1 }
        }
        return Double(warmCount) / Double(w * h) > 0.3
    }

    // MARK: - Metrics

    private func grayscaleMean(_ image: CIImage) -> Double {
        let extent = image.extent
        let w = min(128, Int(extent.width))
        let h = min(128, Int(extent.height))
        guard w > 0, h > 0 else { return 0.5 }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_OneComponent8, nil, &buf)
        guard let pb = buf else { return 0.5 }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0.5 }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum: Double = 0
        for i in 0..<(w*h) { sum += Double(ptr[i]) / 255.0 }
        return sum / Double(w * h)
    }

    private func laplacianVariance(_ image: CIImage) -> Double {
        let kernel = CIVector(values: [0,1,0, 1,-4,1, 0,1,0], count: 9)
        guard let filtered = image.applyingFilter("CIConvolution3X3", parameters: [
            kCIInputWeightsKey: kernel
        ]) as CIImage? else { return 0 }
        return grayscaleMeanSquared(filtered)
    }

    private func grayscaleMeanSquared(_ image: CIImage) -> Double {
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
        var sumSq: Double = 0
        for i in 0..<(w*h) {
            let v = Double(ptr[i]) / 255.0
            sumSq += v * v
        }
        return sumSq / Double(w * h)
    }
}
