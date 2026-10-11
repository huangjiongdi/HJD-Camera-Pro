//
//  PortraitRelighting.swift
//  HJD Camera Pro
//
//  面部光照调节：优化面部曝光，平衡高光与阴影。
//

import Foundation
import CoreImage

final class PortraitRelighting {

    static let shared = PortraitRelighting()

    struct RelightResult {
        var image: CIImage
        var exposureAdjusted: Double
    }

    private init() {}

    /// 调节面部光照。
    func relight(image: CIImage, segmentation: PortraitSegmentation.SegmentationResult) -> RelightResult {
        // 检测面部平均亮度
        let faceRegion = image.cropped(to: segmentation.boundingBox)
        let meanLuma = grayscaleMean(faceRegion)

        // 目标亮度 0.5
        let adjustment = 0.5 - meanLuma
        let adjusted = image.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: adjustment * 2.0
        ])

        // 局部色调映射
        let toneMapped = adjusted.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0.02),
            "inputPoint1": CIVector(x: 0.3, y: 0.35),
            "inputPoint2": CIVector(x: 0.6, y: 0.6),
            "inputPoint3": CIVector(x: 0.85, y: 0.82),
            "inputPoint4": CIVector(x: 1, y: 0.95)
        ])

        return RelightResult(image: toneMapped, exposureAdjusted: adjustment)
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
