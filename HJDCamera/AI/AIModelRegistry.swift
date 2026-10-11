//
//  AIModelRegistry.swift
//  HJD Camera Pro
//
//  AI 模型注册表：集中管理所有 CoreML 超分/降噪/专用模型的元数据与默认选择。
//  模型文件缺失时优雅降级，返回 nil，不触发崩溃。
//

import Foundation
import CoreML
import Combine

/// AI 模型注册表（单例）。
final class AIModelRegistry: ObservableObject {

    static let shared = AIModelRegistry()

    // MARK: - Published State

    @Published private(set) var allModels: [AIModelInfo] = []
    @Published private(set) var loadedModelIDs: Set<String> = []
    @Published private(set) var lastLoadError: Error?

    /// 每个分类的默认模型 ID
    private var defaultModelIDs: [AIModelCategory: String] = [:]

    private let queue = DispatchQueue(label: "com.hjd.camera.modelRegistry", qos: .utility)

    private init() {
        registerBuiltInModels()
        loadBundledModels()
    }

    // MARK: - Built-in Registration

    /// 注册所有内建模型元数据（即使 .mlmodelc 不存在也注册元信息，用于降级判断）。
    private func registerBuiltInModels() {
        var list: [AIModelInfo] = []

        // ---- 10 个超分模型 ----
        list.append(AIModelInfo(
            id: "realesrgan_x4plus",
            name: "Real-ESRGAN x4plus",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 64_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 4.0,
            license: "BSD-3-Clause",
            source: "xinntao/Real-ESRGAN"
        ))
        list.append(AIModelInfo(
            id: "realesrnet_x4plus",
            name: "RealESRNet x4plus",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 62_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 4.0,
            license: "BSD-3-Clause",
            source: "xinntao/Real-ESRGAN"
        ))
        list.append(AIModelInfo(
            id: "realesrgan_general_x4v3",
            name: "Real-ESRGAN General x4v3",
            category: .superResolution,
            version: "3.0.0",
            fileSize: 66_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 4.0,
            license: "BSD-3-Clause",
            source: "xinntao/Real-ESRGAN"
        ))
        list.append(AIModelInfo(
            id: "realesrgan_anime",
            name: "Real-ESRGAN AnimeVideo",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 60_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 4.0,
            license: "BSD-3-Clause",
            source: "xinntao/Real-ESRGAN"
        ))
        list.append(AIModelInfo(
            id: "swinir_classical",
            name: "SwinIR Classical SR",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 90_000_000,
            inputResolution: CGSize(width: 128, height: 128),
            outputScale: 4.0,
            license: "MIT",
            source: "JingyunLiang/SwinIR"
        ))
        list.append(AIModelInfo(
            id: "swinir_realworld",
            name: "SwinIR Real-World SR",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 92_000_000,
            inputResolution: CGSize(width: 128, height: 128),
            outputScale: 4.0,
            license: "MIT",
            source: "JingyunLiang/SwinIR"
        ))
        list.append(AIModelInfo(
            id: "hat_superres",
            name: "HAT Super-Resolution",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 110_000_000,
            inputResolution: CGSize(width: 128, height: 128),
            outputScale: 4.0,
            license: "NTU S-Lab",
            source: "XPixelGroup/HAT"
        ))
        list.append(AIModelInfo(
            id: "edsr_baseline",
            name: "EDSR Baseline",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 40_000_000,
            inputResolution: CGSize(width: 64, height: 64),
            outputScale: 4.0,
            license: "BSD",
            source: "thstkdgus35/EDSR-PyTorch"
        ))
        list.append(AIModelInfo(
            id: "waifu2x",
            name: "waifu2x",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 30_000_000,
            inputResolution: CGSize(width: 128, height: 128),
            outputScale: 2.0,
            license: "MIT",
            source: "nagadomi/waifu2x"
        ))
        list.append(AIModelInfo(
            id: "fsrcnn",
            name: "FSRCNN",
            category: .superResolution,
            version: "1.0.0",
            fileSize: 2_500_000,
            inputResolution: CGSize(width: 64, height: 64),
            outputScale: 4.0,
            license: "MIT",
            source: "triged/FSRCNN"
        ))

        // ---- 专用模型 ----
        list.append(AIModelInfo(
            id: "mprnet_denoise",
            name: "MPRNet Denoise",
            category: .denoise,
            version: "1.0.0",
            fileSize: 22_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 1.0,
            license: "GPL-3.0",
            source: "swz34/MPRNet"
        ))
        list.append(AIModelInfo(
            id: "nafnet_denoise",
            name: "NAFNet Denoise",
            category: .denoise,
            version: "1.0.0",
            fileSize: 88_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 1.0,
            license: "Apache-2.0",
            source: "mwkim2014/NAFNet"
        ))
        list.append(AIModelInfo(
            id: "gfpgan_face",
            name: "GFPGAN Face Restore",
            category: .faceEnhance,
            version: "1.3.0",
            fileSize: 34_000_000,
            inputResolution: CGSize(width: 512, height: 512),
            outputScale: 1.0,
            license: "Apache-2.0",
            source: "TencentARC/GFPGAN"
        ))
        list.append(AIModelInfo(
            id: "depthpro",
            name: "DepthPro Monocular Depth",
            category: .depth,
            version: "1.0.0",
            fileSize: 360_000_000,
            inputResolution: CGSize(width: 512, height: 512),
            outputScale: 1.0,
            license: "Apple Public Source",
            source: "apple/ml-depth-pro"
        ))
        list.append(AIModelInfo(
            id: "lunarsr",
            name: "LunarSR Moon Surface",
            category: .lunar,
            version: "1.0.0",
            fileSize: 48_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 2.0,
            license: "Proprietary HJD",
            source: "HJD Internal"
        ))
        list.append(AIModelInfo(
            id: "macrodetail_sr",
            name: "MacroDetailSR",
            category: .macro,
            version: "1.0.0",
            fileSize: 45_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 2.0,
            license: "Proprietary HJD",
            source: "HJD Internal"
        ))
        list.append(AIModelInfo(
            id: "architecture_sr",
            name: "ArchitectureSR",
            category: .architecture,
            version: "1.0.0",
            fileSize: 52_000_000,
            inputResolution: CGSize(width: 256, height: 256),
            outputScale: 2.0,
            license: "Proprietary HJD",
            source: "HJD Internal"
        ))

        DispatchQueue.main.async {
            self.allModels = list
        }

        // 默认模型
        defaultModelIDs[.superResolution] = "realesrgan_x4plus"
        defaultModelIDs[.denoise] = "nafnet_denoise"
        defaultModelIDs[.faceEnhance] = "gfpgan_face"
        defaultModelIDs[.depth] = "depthpro"
        defaultModelIDs[.lunar] = "lunarsr"
        defaultModelIDs[.macro] = "macrodetail_sr"
        defaultModelIDs[.architecture] = "architecture_sr"
    }

    // MARK: - Bundle Loading

    /// 扫描 App Bundle，加载所有 .mlmodelc（编译后 CoreML 模型）。
    func loadBundledModels() {
        queue.async { [weak self] in
            guard let self = self else { return }
            var loaded: Set<String> = []
            let bundle = Bundle.main

            // 枚举 bundle 中所有 .mlmodelc
            guard let resourcePaths = pathsOfModels(in: bundle) else {
                DispatchQueue.main.async {
                    self.loadedModelIDs = []
                }
                return
            }

            for path in resourcePaths {
                let name = (path as NSString).deletingPathExtension
                // 尝试编译/加载以验证模型可用
                do {
                    let compiledURL: URL
                    if path.hasSuffix(".mlmodelc") {
                        compiledURL = URL(fileURLWithPath: path)
                    } else {
                        compiledURL = try MLModel.compileModel(at: URL(fileURLWithPath: path))
                    }
                    _ = try MLModel(contentsOf: compiledURL)
                    loaded.insert(name)
                } catch {
                    // 单个模型加载失败不影响其他模型
                    continue
                }
            }

            DispatchQueue.main.async {
                self.loadedModelIDs = loaded
            }
        }
    }

    private func pathsOfModels(in bundle: Bundle) -> [String]? {
        var result: [String] = []
        // 顶层
        if let top = bundle.paths(forResourcesOfType: "mlmodelc", inDirectory: nil) as? [String] {
            result.append(contentsOf: top)
        }
        // 递归子目录
        if let subBundlePaths = bundle.paths(forResourcesOfType: "mlmodelc", inDirectory: "Models") as? [String] {
            result.append(contentsOf: subBundlePaths)
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Query

    /// 按 id 获取模型元信息。
    func model(for id: String) -> AIModelInfo? {
        return allModels.first(where: { $0.id == id })
    }

    /// 某分类下的默认模型。
    func defaultModel(for category: AIModelCategory) -> AIModelInfo? {
        guard let id = defaultModelIDs[category] else { return nil }
        return model(for: id)
    }

    /// 设置某分类的默认模型。
    func setDefault(_ modelID: String, for category: AIModelCategory) {
        guard model(for: modelID) != nil else { return }
        defaultModelIDs[category] = modelID
    }

    /// 某分类下所有模型。
    func allModels(in category: AIModelCategory) -> [AIModelInfo] {
        return allModels.filter { $0.category == category }
    }

    /// 模型文件是否实际可用。
    func isModelAvailable(_ id: String) -> Bool {
        return loadedModelIDs.contains(id)
    }
}
