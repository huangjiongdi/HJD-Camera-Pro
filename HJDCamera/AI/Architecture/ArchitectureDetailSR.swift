//
//  ArchitectureDetailSR.swift
//  HJD Camera Pro
//
//  建筑纹理超分：增强砖墙、石材、窗框细节，保护直线边缘。
//

import Foundation
import CoreImage

final class ArchitectureDetailSR {

    static let shared = ArchitectureDetailSR()

    struct SRResult {
        var image: CIImage
        var scale: Double
        var modelUsed: String
    }

    private init() {}

    /// 建筑纹理超分。
    func superResolve(image: CIImage, scale: Double = 2.0) -> SRResult {
        // 先提取边缘图
        let edgeMap = ArchitectureEdgeNet.shared.extractEdges(image)

        // 优先使用 ArchitectureSR 专用模型
        if AIModelRegistry.shared.isModelAvailable("architecture_sr") {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: "architecture_sr", input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                // 边缘保护混合
                let protectedResult = ArchitectureEdgeNet.shared.protectEdges(
                    original: image, enhanced: result, edgeMap: edgeMap)
                return SRResult(image: protectedResult, scale: scale, modelUsed: "ArchitectureSR")
            }
        }

        // 回退到通用超分
        if let model = AIModelRegistry.shared.defaultModel(for: .superResolution),
           AIModelRegistry.shared.isModelAvailable(model.id) {
            var result: CIImage?
            let sema = DispatchSemaphore(value: 0)
            AIModelRunner.shared.run(model: model.id, input: image) { output in
                result = output
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            if let result = result {
                let protectedResult = ArchitectureEdgeNet.shared.protectEdges(
                    original: image, enhanced: result, edgeMap: edgeMap)
                return SRResult(image: protectedResult, scale: scale, modelUsed: model.name)
            }
        }

        // 最终回退
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let enhanced = scaled.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 2.0,
            kCIInputIntensityKey: 0.4
        ])
        return SRResult(image: enhanced, scale: scale, modelUsed: "Lanczos+UnsharpMask")
    }
}
