//
//  MacroFocusAssist.swift
//  HJD Camera Pro
//
//  微距对焦辅助：对焦峰值、局部锐度评估、焦点位置提示。
//

import Foundation
import CoreImage

final class MacroFocusAssist {

    static let shared = MacroFocusAssist()

    struct FocusResult {
        var focusScore: Double       // 0-1，越高越清晰
        var focusRegion: CGRect      // 最清晰区域
        var peakOverlay: CIImage     // 对焦峰值叠加图
    }

    private init() {}

    /// 评估图像对焦质量。
    func evaluate(image: CIImage) -> FocusResult {
        let extent = image.extent
        let gridSize: CGFloat = 64
        let cols = Int(extent.width / gridSize)
        let rows = Int(extent.height / gridSize)

        var bestScore: Double = 0
        var bestRect = CGRect(x: 0, y: 0, width: gridSize, height: gridSize)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * gridSize
                let y = CGFloat(row) * gridSize
                let rect = CGRect(x: x, y: y, width: gridSize, height: gridSize)
                let tile = image.cropped(to: rect)
                let score = laplacianVariance(tile)
                if score > bestScore {
                    bestScore = score
                    bestRect = rect
                }
            }
        }

        // 生成对焦峰值叠加图（边缘高亮）
        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3.0])
        let peak = edges.applyingFilter("CIGlassDistortion", parameters: [:])

        let normalizedScore = min(1.0, bestScore * 20.0)
        return FocusResult(
            focusScore: normalizedScore,
            focusRegion: bestRect,
            peakOverlay: peak
        )
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
        let w = min(64, Int(extent.width))
        let h = min(64, Int(extent.height))
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
