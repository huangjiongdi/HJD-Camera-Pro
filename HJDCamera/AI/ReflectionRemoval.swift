//
//  ReflectionRemoval.swift
//  HJD Camera Pro
//
//  玻璃反光去除：检测并消除玻璃表面的反射影像。
//

import Foundation
import CoreImage

final class ReflectionRemoval {

    static let shared = ReflectionRemoval()

    struct RemovalResult {
        var image: CIImage
        var reflectionDetected: Bool
        var strength: Double
    }

    private init() {}

    /// 检测并去除玻璃反光。
    func remove(image: CIImage) -> RemovalResult {
        // 反光特征：高亮度、低饱和度的不规则光斑
        let brightRegions = image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,
            kCIInputSaturationKey: 0.5
        ])

        // 检测反光强度
        let meanBrightness = grayscaleMean(brightRegions)
        let reflectionDetected = meanBrightness > 0.6

        guard reflectionDetected else {
            return RemovalResult(image: image, reflectionDetected: false, strength: 0)
        }

        // 降低高光区域亮度
        let toneMapped = image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 0.5, y: 0.5),
            "inputPoint2": CIVector(x: 0.8, y: 0.65),
            "inputPoint3": CIVector(x: 0.95, y: 0.75),
            "inputPoint4": CIVector(x: 1, y: 0.8)
        ])

        // 局部对比度恢复
        let recovered = toneMapped.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.5,
            kCIInputIntensityKey: 0.3
        ])

        return RemovalResult(
            image: recovered,
            reflectionDetected: true,
            strength: min(1.0, (meanBrightness - 0.6) / 0.4)
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
