//
//  AIConfidenceMap.swift
//  HJD Camera Pro
//
//  超分细节可信度地图：标记真实采集区域 vs AI 推测区域，低置信度区域降低增强强度。
//

import Foundation
import CoreImage

final class AIConfidenceMap {

    static let shared = AIConfidenceMap()

    /// 置信度级别
    enum ConfidenceLevel: Float {
        case high = 1.0      // 真实采集细节，可完全增强
        case medium = 0.6    // 部分可信，适度增强
        case low = 0.3      // AI推测区域，降低增强强度
    }

    /// 置信度地图：与输出图像同尺寸，每个像素表示该区域的可信度。
    struct Map {
        let ciImage: CIImage   // 灰度图，越亮置信度越高
        let size: CGSize
    }

    private init() {}

    /// 基于输入图像生成可信度地图。
    /// 高置信度区域：原图已有足够细节；
    /// 低置信度区域：原图模糊/过曝/欠曝，需要 AI 推测。
    func generate(from input: CIImage, tileSize: CGFloat = 64) -> Map {
        let extent = input.extent
        let cols = Int(ceil(extent.width / tileSize))
        let rows = Int(ceil(extent.height / tileSize))

        // 生成灰度置信度图
        var pixels: [Float] = Array(repeating: 0.5, count: cols * rows)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * tileSize
                let y = CGFloat(row) * tileSize
                let w = min(tileSize, extent.width - x)
                let h = min(tileSize, extent.height - y)
                let crop = input.cropped(to: CGRect(x: x, y: y, width: w, height: h))
                let confidence = tileConfidence(crop)
                pixels[row * cols + col] = confidence
            }
        }

        // 转为 CIImage
        let ciImage = grayscaleCIImage(from: pixels, width: cols, height: rows)
        let size = CGSize(width: extent.width, height: extent.height)
        return Map(ciImage: ciImage, size: size)
    }

    /// 根据置信度地图调整增强强度：低置信度区域使用较低的混合系数。
    func blend(original: CIImage,
               enhanced: CIImage,
               confidenceMap: Map) -> CIImage {
        // 将置信度图缩放到 enhanced 尺寸作为蒙版
        let scaleX = enhanced.extent.width / confidenceMap.size.width
        let scaleY = enhanced.extent.height / confidenceMap.size.height
        let mask = confidenceMap.ciImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 用蒙版混合：mask 越白，enhanced 占比越高
        let blendFilter = enhanced.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: original,
            kCIInputMaskImageKey: mask
        ])
        return blendFilter
    }

    // MARK: - Tile Confidence

    private func tileConfidence(_ tile: CIImage) -> Float {
        // 综合亮度、对比度、细节能量
        let meanBrightness = grayscaleMean(tile)
        let detailEnergy = laplacianVariance(tile)

        // 过曝或欠曝区域置信度低
        let brightnessPenalty: Float
        if meanBrightness > 0.9 || meanBrightness < 0.1 {
            brightnessPenalty = 0.3
        } else {
            brightnessPenalty = 1.0
        }

        // 细节丰富区域置信度高
        let detailScore = min(1.0, Float(detailEnergy) * 10.0)

        return min(1.0, brightnessPenalty * (0.4 + 0.6 * detailScore))
    }

    // MARK: - Helpers

    private func grayscaleMean(_ image: CIImage) -> Float {
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
        var sum: Float = 0
        let count = w * h
        for i in 0..<count { sum += Float(ptr[i]) / 255.0 }
        return sum / Float(count)
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
        let count = w * h
        for i in 0..<count {
            let v = Double(ptr[i]) / 255.0
            sumSq += v * v
        }
        return sumSq / Double(count)
    }

    private func grayscaleCIImage(from pixels: [Float], width: Int, height: Int) -> CIImage {
        var normalized = pixels.map { UInt8(max(0, min(255, $0 * 255))) }
        let data = Data(bytes: &normalized, count: width * height)
        return CIImage(bitmapData: data,
                       bytesPerRow: width,
                       size: CGSize(width: width, height: height),
                       format: .L8,
                       colorSpace: CGColorSpaceCreateDeviceGray())
    }
}
