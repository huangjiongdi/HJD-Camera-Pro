//
//  SkyReplacer.swift
//  HJD Camera Pro
//
//  天空替换：识别天空区域，替换为用户选择的天空素材。
//

import Foundation
import CoreImage

final class SkyReplacer {

    static let shared = SkyReplacer()

    struct ReplaceResult {
        var image: CIImage
        var skyMask: CIImage
        var skyDetected: Bool
    }

    private init() {}

    /// 检测天空区域并替换。
    func replace(image: CIImage, with skyImage: CIImage? = nil) -> ReplaceResult {
        let extent = image.extent

        // 天空特征：上方区域、高亮度、蓝色或暖色
        let topHalf = image.cropped(to: CGRect(x: 0, y: extent.height/2,
                                              width: extent.width,
                                              height: extent.height/2))
        let meanLuma = grayscaleMean(topHalf)
        let skyDetected = meanLuma > 0.4

        guard skyDetected else {
            let emptyMask = CIImage(color: .black).cropped(to: extent)
            return ReplaceResult(image: image, skyMask: emptyMask, skyDetected: false)
        }

        // 创建天空掩码（上方区域渐变为天空）
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: extent.height),
            "inputPoint1": CIVector(x: extent.midX, y: extent.height * 0.4),
            "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0)
        ])
        let skyMask = gradient?.outputImage?.cropped(to: extent) ?? CIImage(color: .white).cropped(to: extent)

        // 混合天空
        let sky = skyImage ?? CIImage(color: CIColor(red: 0.4, green: 0.6, blue: 0.9)).cropped(to: extent)
        let blended = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: sky,
            kCIInputMaskImageKey: skyMask
        ])

        return ReplaceResult(image: blended, skyMask: skyMask, skyDetected: true)
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
