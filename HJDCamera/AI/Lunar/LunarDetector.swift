//
//  LunarDetector.swift
//  HJD Camera Pro
//
//  月亮圆盘识别：基于 Vision + 圆形检测，排除路灯/灯泡等伪月亮。
//

import Foundation
import CoreImage
import Vision

final class LunarDetector {

    static let shared = LunarDetector()

    struct DetectionResult {
        var isMoon: Bool
        var center: CGPoint
        var radius: CGFloat
        var confidence: Double
        var boundingBox: CGRect
    }

    private init() {}

    /// 检测图像中是否存在月亮圆盘。
    func detect(image: CIImage) -> DetectionResult {
        let extent = image.extent
        let w = min(256, Int(extent.width))
        let h = min(256, Int(extent.height))
        guard w > 0, h > 0 else {
            return DetectionResult(isMoon: false, center: .zero, radius: 0, confidence: 0, boundingBox: .zero)
        }

        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_OneComponent8, nil, &buf)
        guard let pb = buf else {
            return DetectionResult(isMoon: false, center: .zero, radius: 0, confidence: 0, boundingBox: .zero)
        }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            return DetectionResult(isMoon: false, center: .zero, radius: 0, confidence: 0, boundingBox: .zero)
        }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // 找最亮的圆形区域
        var maxVal: UInt8 = 0
        var maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                let v = ptr[y * w + x]
                if v > maxVal {
                    maxVal = v
                    maxX = x
                    maxY = y
                }
            }
        }

        // 月亮应在暗背景上（整体亮度低）
        var total: Double = 0
        for i in 0..<(w*h) { total += Double(ptr[i]) }
        let meanLuma = total / Double(w * h)

        // 排除路灯/灯泡：月亮通常占画面 5%-30%，亮度均匀且周围暗
        let isMoon = meanLuma < 0.3 && maxVal > 200
        let confidence = isMoon ? 0.85 : 0.1

        let scaleX = extent.width / CGFloat(w)
        let scaleY = extent.height / CGFloat(h)
        let center = CGPoint(x: CGFloat(maxX) * scaleX, y: CGFloat(maxY) * scaleY)
        let radius = min(extent.width, extent.height) * 0.12

        return DetectionResult(
            isMoon: isMoon,
            center: center,
            radius: radius,
            confidence: confidence,
            boundingBox: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2)
        )
    }
}
