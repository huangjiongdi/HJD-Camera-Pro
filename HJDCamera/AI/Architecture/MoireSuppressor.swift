//
//  MoireSuppressor.swift
//  HJD Camera Pro
//
//  摩尔纹抑制：检测并消除建筑纹理中的干涉条纹。
//

import Foundation
import CoreImage

final class MoireSuppressor {

    static let shared = MoireSuppressor()

    struct SuppressResult {
        var image: CIImage
        var moireDetected: Bool
        var strength: Double  // 抑制强度 0-1
    }

    private init() {}

    /// 检测并抑制摩尔纹。
    func suppress(image: CIImage) -> SuppressResult {
        // 摩尔纹特征：高频周期性条纹
        let detail = laplacianVariance(image)
        let moireDetected = detail > 0.015

        guard moireDetected else {
            return SuppressResult(image: image, moireDetected: false, strength: 0)
        }

        // 频域低通滤波（用高斯模糊近似）
        let radius = 3.0 + detail * 50.0
        let smoothed = image.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: radius
        ])

        // 恢复边缘细节
        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 2.0])
        let blended = smoothed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: smoothed,
            kCIInputMaskImageKey: edges
        ])

        return SuppressResult(image: blended, moireDetected: true, strength: min(1.0, detail * 20.0))
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
