//
//  GalleryAIProcessor.swift
//  HJD Camera Pro
//
//  相册 AI 超算引擎（Gallery AI Lab）——离线高画质处理。
//
//  真实调用 AIModelRunner（内嵌 Core ML 分块推理）：
//    · 超分类任务：Real-ESRGAN 路线 ×4 真实放大（为控制内存，送入模型的输入
//      限制在约 14MP，输出约 48–56MP），再用 Lanczos 高质量重采样到目标规格。
//    · 修复/降噪/人像：同尺寸模型（MPRNet / GFPGAN）。
//    · 48MP = 真实 AI 超分；50/100/260MP = 真实 AI 超分 + 高质量重采样，
//      超出模型直接产出的像素属于重采样/AI 重建，不等于传感器原生细节。
//
//  全程 async/await（不再用 DispatchSemaphore），失败回退原图，绝不丢片。
//

import UIKit
import CoreImage
import CoreGraphics

final class GalleryAIProcessor {
    static let shared = GalleryAIProcessor()

    /// 送入超分模型的最大输入像素（×4 后约 56MP，控制峰值内存）。
    private let srInputLimitPixels: CGFloat = 14_000_000

    private let ciContext: CIContext = {
        let ctx = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
        return ctx
    }()

    struct Output {
        let image: UIImage
        let modelID: String
        let warnings: [String]
        let pixelSize: CGSize
        let usedAI: Bool
    }

    private init() {}

    // MARK: - 主入口

    /// - Parameters:
    ///   - targetMP: 目标百万像素（48/50/100/260），与 scale 二选一。
    ///   - scale: 目标边长倍率（1/2/3/4）。
    func process(image: UIImage,
                 task: AITaskType,
                 targetMP: Double? = nil,
                 scale: Double? = nil,
                 progress: @escaping (Double) -> Void) async -> Output {
        progress(0.02)
        let base = normalized(image)
        guard let cg = base.cgImage else {
            return Output(image: base, modelID: "none",
                          warnings: ["无法读取图像数据"], pixelSize: base.size,
                          usedAI: false)
        }

        let srcSize = CGSize(width: cg.width, height: cg.height)
        let srcPixels = srcSize.width * srcSize.height
        let targetSize = resolveTargetSize(src: srcSize, targetMP: targetMP, scale: scale)

        // 路由到真实模型
        let route = AISceneRouter.route(task: task) ?? AISceneRouter.route(task: .superResolution)
        let (resolvedID, routeWarning) = AISceneRouter.resolveAvailable(route)
        let modelID = resolvedID ?? "none"
        let modelAvailable = resolvedID != nil
        var warnings: [String] = []
        if let w = routeWarning { warnings.append(w) }

        progress(0.1)
        var current = CIImage(cgImage: cg)
        var usedAI = false

        // 真实模型推理
        if modelAvailable, let resolvedID = resolvedID {
            do {
                if route.isSuperResolution {
                    // 限制送入模型的输入，避免大照片 ×4 画布爆内存。
                    if srcPixels > srInputLimitPixels {
                        let k = sqrt(srInputLimitPixels / srcPixels)
                        let capped = CGSize(width: (srcSize.width * k).rounded(),
                                            height: (srcSize.height * k).rounded())
                        current = try lanczos(current, to: capped)
                        warnings.append("原图较大，已先缩放至约 \(Int(capped.width * capped.height / 1_000_000))MP 再做 AI 超分。")
                    }
                    progress(0.2)
                    let sr = try await runModel(modelID: resolvedID, image: current, progress: progress)
                    current = sr
                    usedAI = true
                    progress(0.8)
                } else {
                    // 同尺寸修复 / 降噪 / 人像
                    progress(0.2)
                    let fixed = try await runModel(modelID: resolvedID, image: current, progress: progress)
                    current = fixed
                    usedAI = true
                    progress(0.75)
                }
            } catch {
                warnings.append("AI 模型处理失败，已回退：\(error.localizedDescription)")
                current = CIImage(cgImage: cg)
                usedAI = false
            }
        } else {
            warnings.append("无可用模型，仅做高画质重采样。")
        }

        // 缩放到精确目标尺寸
        let finalSize = targetSize
        if needsResize(current.extent.size, to: finalSize) {
            do {
                current = try lanczos(current, to: finalSize)
                if usedAI {
                    let mp = Int(finalSize.width * finalSize.height / 1_000_000)
                    if let t = targetMP, Double(mp) > 48 {
                        warnings.append("\(mp)MP 中约 48MP 来自真实 AI 超分，其余为高质量重采样。")
                    }
                }
            } catch {
                warnings.append("最终缩放出错：\(error.localizedDescription)")
                // 回退：直接用模型输出或原图
                if let fallback = render(current) {
                    return Output(image: fallback, modelID: modelID, warnings: warnings,
                                  pixelSize: current.extent.size, usedAI: usedAI)
                }
            }
        }

        // 渲染（大图失败则逐级降级）
        let candidates = [finalSize,
                          CGSize(width: finalSize.width * 0.7, height: finalSize.height * 0.7),
                          CGSize(width: finalSize.width * 0.45, height: finalSize.height * 0.45)]
        for (idx, size) in candidates.enumerated() {
            if idx > 0 {
                let small = try? lanczos(current, to: size)
                if let img = small.flatMap({ render($0, size: size) }) {
                    warnings.append("受内存限制，输出降为约 \(Int(size.width * size.height / 1_000_000))MP。")
                    progress(1.0)
                    return Output(image: img, modelID: modelID, warnings: warnings,
                                  pixelSize: size, usedAI: usedAI)
                }
            } else if let img = render(current, size: size) {
                progress(1.0)
                return Output(image: img, modelID: modelID, warnings: warnings,
                              pixelSize: size, usedAI: usedAI)
            }
        }

        // 最终兜底：原图
        progress(1.0)
        return Output(image: base, modelID: modelID,
                      warnings: warnings + ["处理失败，已保留原图。"],
                      pixelSize: srcSize, usedAI: false)
    }

    // MARK: - 目标尺寸

    private func resolveTargetSize(src: CGSize, targetMP: Double?, scale: Double?) -> CGSize {
        if let mp = targetMP {
            let aspect = src.width / src.height
            let pixels = CGFloat(mp * 1_000_000)
            let w = sqrt(pixels * aspect)
            return CGSize(width: w.rounded(), height: (w / aspect).rounded())
        }
        if let s = scale {
            return CGSize(width: (src.width * s).rounded(), height: (src.height * s).rounded())
        }
        return src
    }

    private func needsResize(_ a: CGSize, to b: CGSize) -> Bool {
        abs(a.width - b.width) > 2 || abs(a.height - b.height) > 2
    }

    // MARK: - Core ML 调用（continuation 封装，不阻塞）

    private func runModel(modelID: String,
                          image: CIImage,
                          progress: @escaping (Double) -> Void) async throws -> CIImage {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // 报告一次推理开始（分块内部不再逐块回传，避免刷屏）
                progress(0.35)
                AIModelRunner.shared.run(model: modelID, input: image) { out in
                    if let out = out {
                        cont.resume(returning: out)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "HJD.GalleryAI", code: 500,
                            userInfo: [NSLocalizedDescriptionKey: "模型 \(modelID) 未返回结果"]))
                    }
                }
            }
        }
    }

    // MARK: - Lanczos 重采样

    private func lanczos(_ image: CIImage, to size: CGSize) throws -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            throw NSError(domain: "HJD.GalleryAI", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "无效图像尺寸"])
        }
        let scale = size.width / extent.width
        let filter = CIFilter(name: "CILanczosScaleTransform")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let out = filter.outputImage else {
            throw NSError(domain: "HJD.GalleryAI", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Lanczos 处理失败"])
        }
        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func render(_ image: CIImage, size: CGSize? = nil) -> UIImage? {
        let rect = size.map { CGRect(origin: .zero, size: $0) } ?? image.extent
        guard let cg = ciContext.createCGImage(image, from: rect) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 方向归一化

    private func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
