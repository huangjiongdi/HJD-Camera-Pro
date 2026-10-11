//
//  MacroSubjectDetector.swift
//  HJD Camera Pro
//
//  微距主体识别：基于 Vision 识别昆虫/花朵/叶片。
//

import Foundation
import CoreImage
import Vision

final class MacroSubjectDetector {

    static let shared = MacroSubjectDetector()

    enum SubjectType {
        case insect
        case flower
        case leaf
        case unknown
    }

    struct Detection {
        var type: SubjectType
        var boundingBox: CGRect
        var confidence: Double
    }

    private init() {}

    /// 检测微距主体。
    func detect(image: CIImage) -> Detection {
        // 使用 Vision 分类请求
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            if let results = request.results, let top = results.first {
                let identifier = top.identifier
                let conf = top.confidence
                let type: SubjectType
                if identifier.contains("insect") || identifier.contains("bug") || identifier.contains("butterfly") {
                    type = .insect
                } else if identifier.contains("flower") || identifier.contains("blossom") {
                    type = .flower
                } else if identifier.contains("leaf") || identifier.contains("plant") || identifier.contains("tree") {
                    type = .leaf
                } else {
                    type = .unknown
                }
                return Detection(type: type,
                                boundingBox: CGRect(x: 0, y: 0,
                                                   width: image.extent.width,
                                                   height: image.extent.height),
                                confidence: Double(conf))
            }
        } catch {
            // 分类模型不可用时回退到规则
        }

        // 规则回退：高细节 + 暖色 = 花；高细节 + 绿色 = 叶；运动模糊 = 昆虫
        let detail = laplacianVariance(image)
        let colorStats = colorStats(image)
        let type: SubjectType
        if colorStats.greenRatio > 0.5 {
            type = .leaf
        } else if colorStats.warmRatio > 0.4 {
            type = .flower
        } else if detail > 0.015 {
            type = .insect
        } else {
            type = .unknown
        }

        return Detection(type: type,
                        boundingBox: CGRect(x: 0, y: 0,
                                           width: image.extent.width,
                                           height: image.extent.height),
                        confidence: 0.5)
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

    private func colorStats(_ image: CIImage) -> (greenRatio: Double, warmRatio: Double) {
        let extent = image.extent
        let w = min(64, Int(extent.width))
        let h = min(64, Int(extent.height))
        guard w > 0, h > 0 else { return (0, 0) }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_32BGRA, nil, &buf)
        guard let pb = buf else { return (0, 0) }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return (0, 0) }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var green = 0, warm = 0
        let count = w * h
        for i in 0..<count {
            let r = Double(ptr[i*4+2]) / 255.0
            let g = Double(ptr[i*4+1]) / 255.0
            let b = Double(ptr[i*4]) / 255.0
            if g > r && g > b { green += 1 }
            if r > g && r > b && g > b { warm += 1 }
        }
        return (Double(green)/Double(count), Double(warm)/Double(count))
    }
}
