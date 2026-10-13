//
//  DeblurNet.swift
//  HJD Camera Pro
//
//  去运动模糊：检测模糊核并反卷积恢复清晰图像。
//

import Foundation
import CoreImage

final class DeblurNet {

    static let shared = DeblurNet()

    struct DeblurResult {
        var image: CIImage
        var blurEstimated: Double  // 估计的模糊程度 0-1
        var method: String
    }

    private init() {}

    /// 去除运动模糊。
    func deblur(image: CIImage) -> DeblurResult {
        // 估计模糊程度
        let blurScore = estimateBlur(image)

        guard blurScore > 0.1 else {
            return DeblurResult(image: image, blurEstimated: 0, method: "NoDeblur")
        }

        // 尝试 CoreML 去模糊模型
        if AIModelRegistry.shared.isModelAvailable("deblur_net") {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: "deblur_net", input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                return DeblurResult(image: result, blurEstimated: blurScore, method: "CoreML")
            }
        }

        // 回退：反锐化蒙版
        let sharpened = image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 3.0,
            kCIInputIntensityKey: min(1.0, blurScore * 2.0)
        ])

        return DeblurResult(image: sharpened, blurEstimated: blurScore, method: "UnsharpMask")
    }

    private func estimateBlur(_ image: CIImage) -> Double {
        // 拉普拉斯方差越低，模糊越严重
        let lap = laplacianVariance(image)
        // 归一化：0-0.02 映射到 0-1
        return min(1.0, 1.0 - lap / 0.02)
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
