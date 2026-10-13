//
//  FocusStackingEngine.swift
//  HJD Camera Pro
//
//  焦点包围景深合成：从不同对焦距离的帧中提取清晰区域，合成全景深图像。
//

import Foundation
import CoreImage

final class FocusStackingEngine {

    static let shared = FocusStackingEngine()

    struct StackResult {
        var image: CIImage
        var depthLayers: Int
    }

    private init() {}

    /// 焦点堆叠合成。
    /// - Parameter frames: 不同对焦距离的图像（同一构图）
    func stack(frames: [CIImage]) -> StackResult {
        guard frames.count > 1 else {
            return StackResult(image: frames.first ?? CIImage.empty(), depthLayers: frames.count)
        }

        // 对齐所有帧
        let alignment = NightFrameAligner.shared.align(frames: frames)
        let aligned = alignment.alignedFrames

        // 分块计算每帧在每个区域的清晰度，选择最清晰的像素
        let extent = aligned[0].extent
        let tileSize: CGFloat = 64
        let cols = Int(ceil(extent.width / tileSize))
        let rows = Int(ceil(extent.height / tileSize))

        var output: CIImage = aligned[0]

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * tileSize
                let y = CGFloat(row) * tileSize
                let w = min(tileSize, extent.width - x)
                let h = min(tileSize, extent.height - y)
                let rect = CGRect(x: x, y: y, width: w, height: h)

                // 找该区域最清晰的帧
                var bestFrame = aligned[0]
                var bestScore: Double = -1

                for frame in aligned {
                    let tile = frame.cropped(to: rect)
                    let score = laplacianVariance(tile)
                    if score > bestScore {
                        bestScore = score
                        bestFrame = frame
                    }
                }

                // 将最清晰的区域贴回输出
                let bestTile = bestFrame.cropped(to: rect)
                output = output.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: output,
                    kCIInputMaskImageKey: bestTile
                ])
            }
        }

        return StackResult(image: output, depthLayers: aligned.count)
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
