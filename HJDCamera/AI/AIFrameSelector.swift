//
//  AIFrameSelector.swift
//  HJD Camera Pro
//
//  多帧清晰帧选择：基于拉普拉斯方差评分、运动模糊检测、参考帧选择。
//

import Foundation
import CoreImage

final class AIFrameSelector {

    static let shared = AIFrameSelector()

    struct FrameScore {
        let index: Int
        let sharpness: Double    // 拉普拉斯方差
        let motionBlur: Double   // 0-1
        let combinedScore: Double
    }

    private init() {}

    /// 从多帧中选出最佳 N 帧。
    func selectBestFrames(_ frames: [CIImage], topK: Int) -> [CIImage] {
        guard !frames.isEmpty else { return [] }
        let scores = frames.enumerated().map { idx, frame in
            scoreFrame(frame, index: idx)
        }
        let sorted = scores.sorted { $0.combinedScore > $1.combinedScore }
        let top = Array(sorted.prefix(min(topK, sorted.count)))
        return top.compactMap { frames[safe: $0.index] }
    }

    /// 选择参考帧（最清晰的一帧）。
    func selectReferenceFrame(_ frames: [CIImage]) -> CIImage? {
        return selectBestFrames(frames, topK: 1).first
    }

    /// 单帧评分。
    func scoreFrame(_ frame: CIImage, index: Int) -> FrameScore {
        let sharpness = laplacianVariance(frame)
        let motionBlur = detectMotionBlur(frame)
        let combined = sharpness * (1.0 - motionBlur)
        return FrameScore(index: index,
                          sharpness: sharpness,
                          motionBlur: motionBlur,
                          combinedScore: combined)
    }

    // MARK: - Metrics

    private func laplacianVariance(_ image: CIImage) -> Double {
        let kernel = CIVector(values: [0,1,0, 1,-4,1, 0,1,0], count: 9)
        guard let filtered = image.applyingFilter("CIConvolution3X3", parameters: [
            kCIInputWeightsKey: kernel
        ]) as CIImage? else { return 0 }
        return grayscaleMeanSquared(filtered)
    }

    private func detectMotionBlur(_ image: CIImage) -> Double {
        let hKernel = CIVector(values: [-1,0,1, -2,0,2, -1,0,1], count: 9)
        let vKernel = CIVector(values: [-1,-2,-1, 0,0,0, 1,2,1], count: 9)
        let hEdge = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: hKernel])
        let vEdge = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: vKernel])
        let hEnergy = grayscaleMeanSquared(hEdge)
        let vEnergy = grayscaleMeanSquared(vEdge)
        let total = hEnergy + vEnergy
        guard total > 0.001 else { return 0.8 }
        let ratio = abs(hEnergy - vEnergy) / total
        return min(1.0, ratio * 2.0)
    }

    private func grayscaleMeanSquared(_ image: CIImage) -> Double {
        let extent = image.extent
        let w = min(256, Int(extent.width))
        let h = min(256, Int(extent.height))
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
