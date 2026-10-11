//
//  ArchitectureDetector.swift
//  HJD Camera Pro
//
//  建筑主体识别：检测窗框、屋檐、直线结构，识别建筑场景。
//

import Foundation
import CoreImage
import Vision

final class ArchitectureDetector {

    static let shared = ArchitectureDetector()

    struct Detection {
        var isArchitecture: Bool
        var lineCount: Int
        var boundingBox: CGRect
        var confidence: Double
    }

    private init() {}

    /// 检测建筑场景。
    func detect(image: CIImage) -> Detection {
        // 直线检测
        let request = VNDetectLinesRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        var lineCount = 0
        do {
            try handler.perform([request])
            lineCount = request.results?.count ?? 0
        } catch {
            // Vision 不可用时用简化方法
            lineCount = estimateLineCount(image)
        }

        let isArch = lineCount > 5
        let confidence = min(1.0, Double(lineCount) / 15.0)

        return Detection(
            isArchitecture: isArch,
            lineCount: lineCount,
            boundingBox: CGRect(x: 0, y: 0,
                               width: image.extent.width,
                               height: image.extent.height),
            confidence: confidence
        )
    }

    private func estimateLineCount(_ image: CIImage) -> Int {
        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 2.0])
        let mean = grayscaleMean(edges)
        return mean > 0.1 ? 8 : 0
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
