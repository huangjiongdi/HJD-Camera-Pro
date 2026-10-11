//
//  LunarExposureController.swift
//  HJD Camera Pro
//
//  月面曝光控制：避免月亮过曝成白盘，保留月海与环形山细节。
//

import Foundation
import CoreImage

final class LunarExposureController {

    static let shared = LunarExposureController()

    struct ExposureResult {
        var adjustedImage: CIImage
        var exposureCompensation: Double  // EV 补偿值
        var highlightRecovery: Double
    }

    private init() {}

    /// 调整月亮区域曝光。
    func adjust(image: CIImage, detection: LunarDetector.DetectionResult) -> ExposureResult {
        // 月亮核心区域容易过曝，需要降低曝光
        let meanBrightness = grayscaleMean(image)

        // 如果月亮区域过曝，降低曝光
        var compensation: Double = 0
        if meanBrightness > 0.7 {
            compensation = -1.5
        } else if meanBrightness > 0.5 {
            compensation = -0.5
        }

        let adjusted = image.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: compensation
        ])

        // 高光恢复
        let recovered = adjusted.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 0.3, y: 0.3),
            "inputPoint2": CIVector(x: 0.6, y: 0.55),
            "inputPoint3": CIVector(x: 0.85, y: 0.75),
            "inputPoint4": CIVector(x: 1, y: 0.85)
        ])

        return ExposureResult(
            adjustedImage: recovered,
            exposureCompensation: compensation,
            highlightRecovery: meanBrightness > 0.7 ? 0.8 : 0.3
        )
    }

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
}
