//
//  ArchitectureEdgeNet.swift
//  HJD Camera Pro
//
//  建筑边缘保护：识别窗框、屋檐、直线结构，超分时保护边缘不模糊。
//

import Foundation
import CoreImage

final class ArchitectureEdgeNet {

    static let shared = ArchitectureEdgeNet()

    struct EdgeMap {
        var edgeImage: CIImage   // 灰度图，白色=边缘
        var edgeDensity: Double
    }

    private init() {}

    /// 提取建筑边缘图。
    func extractEdges(image: CIImage) -> EdgeMap {
        // 使用 Sobel 算子
        let gx = CIVector(values: [-1,0,1, -2,0,2, -1,0,1], count: 9)
        let gy = CIVector(values: [-1,-2,-1, 0,0,0, 1,2,1], count: 9)
        let dx = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: gx])
        let dy = image.applyingFilter("CIConvolution3X3", parameters: [kCIInputWeightsKey: gy])
        let edges = dx.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: dy
        ])

        // 增强直线边缘
        let enhanced = edges.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.0,
            kCIInputIntensityKey: 0.5
        ])

        let density = grayscaleMean(enhanced)
        return EdgeMap(edgeImage: enhanced, edgeDensity: density)
    }

    /// 用边缘图保护超分结果：边缘区域保持锐利。
    func protectEdges(original: CIImage, enhanced: CIImage, edgeMap: EdgeMap) -> CIImage {
        // 在边缘区域混合原图（保持直线锐利），非边缘区域使用增强图
        let blended = enhanced.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: original,
            kCIInputMaskImageKey: edgeMap.edgeImage
        ])
        return blended
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
        for i in 0..<(w*h) { sum += Double(ptr[i]) / 255.0 }
        return sum / Double(w * h)
    }
}
