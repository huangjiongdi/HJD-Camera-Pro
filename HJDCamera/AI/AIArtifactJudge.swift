//
//  AIArtifactJudge.swift
//  HJD Camera Pro
//
//  通用伪影检测：锐化白边、重影、重复纹理、色彩漂移。
//

import Foundation
import CoreImage

final class AIArtifactJudge {

    static let shared = AIArtifactJudge()

    struct ArtifactReport {
        var whiteEdgeScore: Double       // 锐化白边
        var ghostingScore: Double        // 重影
        var repeatedTextureScore: Double // 重复纹理
        var colorDriftScore: Double      // 色彩漂移
        var overallScore: Double
    }

    private init() {}

    func evaluate(original: CIImage, processed: CIImage) -> ArtifactReport {
        let whiteEdge = detectWhiteEdges(processed)
        let ghosting = detectGhosting(original: original, processed: processed)
        let repeated = detectRepeatedTexture(processed)
        let colorDrift = detectColorDrift(original: original, processed: processed)
        let overall = (whiteEdge + ghosting + repeated + colorDrift) / 4.0
        return ArtifactReport(
            whiteEdgeScore: whiteEdge,
            ghostingScore: ghosting,
            repeatedTextureScore: repeated,
            colorDriftScore: colorDrift,
            overallScore: overall
        )
    }

    // MARK: - Detection

    private func detectWhiteEdges(_ image: CIImage) -> Double {
        // 检测边缘附近过亮像素
        let edge = edgeMagnitude(image)
        let brightEdge = edge.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.3,
            kCIInputSaturationKey: 0
        ])
        return grayscaleMean(brightEdge)
    }

    private func detectGhosting(original: CIImage, processed: CIImage) -> Double {
        // 重影：原图与处理图的差值图中出现规律性纹理
        let diff = processed.applyingFilter("CIDifferenceBlendMode", parameters: [
            kCIInputBackgroundImageKey: original
        ])
        return grayscaleMean(diff)
    }

    private func detectRepeatedTexture(_ image: CIImage) -> Double {
        // 检测高频纹理的周期性重复（简化：返回纹理能量）
        let lap = laplacianVariance(image)
        return min(1.0, lap * 5.0)
    }

    private func detectColorDrift(original: CIImage, processed: CIImage) -> Double {
        // 比较两图的平均色相偏移
        let origMean = colorMean(original)
        let procMean = colorMean(processed)
        let deltaR = abs(origMean.r - procMean.r)
        let deltaG = abs(origMean.g - procMean.g)
        let deltaB = abs(origMean.b - procMean.b)
        return min(1.0, Double((deltaR + deltaG + deltaB) / 3.0))
    }

    // MARK: - Metrics

    private func edgeMagnitude(_ image: CIImage) -> CIImage {
        let gx = CIVector(values: [-1,0,1, -2,0,2, -1,0,1], count: 9)
        let dx = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: gx])
        return dx
    }

    private func laplacianVariance(_ image: CIImage) -> Double {
        let kernel = CIVector(values: [0,1,0, 1,-4,1, 0,1,0], count: 9)
        guard let filtered = image.applyingFilter("CIConvolution3X3", parameters: [
            kCIInputWeightsKey: kernel
        ]) as CIImage? else { return 0 }
        return grayscaleMeanSquared(filtered)
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
        let count = w * h
        for i in 0..<count { sum += Double(ptr[i]) / 255.0 }
        return sum / Double(count)
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
        let count = w * h
        for i in 0..<count {
            let v = Double(ptr[i]) / 255.0
            sumSq += v * v
        }
        return sumSq / Double(count)
    }

    private func colorMean(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        let extent = image.extent
        let w = min(64, Int(extent.width))
        let h = min(64, Int(extent.height))
        guard w > 0, h > 0 else { return (0.5, 0.5, 0.5) }
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_32BGRA, nil, &buf)
        guard let pb = buf else { return (0.5, 0.5, 0.5) }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return (0.5, 0.5, 0.5) }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0
        let count = w * h
        for i in 0..<count {
            bSum += Double(ptr[i*4]) / 255.0
            gSum += Double(ptr[i*4+1]) / 255.0
            rSum += Double(ptr[i*4+2]) / 255.0
        }
        return (rSum / Double(count), gSum / Double(count), bSum / Double(count))
    }
}
