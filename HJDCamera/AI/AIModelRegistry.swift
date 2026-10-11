//
//  AIModelRegistry.swift
//  HJD Camera Pro
//
//  AI 模型注册表：集中管理所有 CoreML 模型的元数据、默认选择与可用性。
//  模型与 App 完全合并（编译后作为 .mlmodelc 内嵌在 bundle 根目录）。
//  元数据始终注册；isDownloaded 由运行时 bundle 实际是否存在该模型决定。
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
        // 静态元数据先就位（此时 isDownloaded 全部 false）。
        self.allModels = Self.catalog.map { $0.toInfo(available: false) }
        computeDefaults()
    }

    // MARK: - Static catalog

    /// 一行静态元数据，运行时再与 bundle 实际存在情况合并。
    private struct Meta {
        let id: String
        let name: String
        let category: AIModelCategory
        let version: String
        let fileSize: Int64
        let inputResolution: String
        let outputScale: String
        let license: String
        let source: String
        let recommendedDevice: String
        let preferredDefault: Bool
        let usedByModes: [CaptureMode]

        func toInfo(available: Bool) -> AIModelInfo {
            AIModelInfo(
                id: id,
                name: name,
                category: category,
                version: version,
                fileSize: fileSize,
                isDownloaded: available,
                inputResolution: inputResolution,
                outputScale: outputScale,
                inferenceTime: nil,
                peakMemory: nil,
                license: license,
                source: source,
                recommendedDevice: recommendedDevice,
                isDefault: false,
                canUninstall: false, // 与 App 完全合并，不可卸载
                usedByModes: usedByModes
            )
        }
    }

    /// 全部预期模型的静态元数据（22 个，全部要求内嵌）。
    private static let catalog: [Meta] = [
        // --- 通用超分 ---
        Meta(id: "realesrgan512", name: "Real-ESRGAN 512", category: .superResolution,
             version: "1.0", fileSize: 64_000_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "TheMurusTeam/coreml-upscaler-realesrgan512",
             recommendedDevice: "iPhone 15 及以上", preferredDefault: true,
             usedByModes: [.photo, .night, .superMoon, .macro, .panorama]),
        Meta(id: "RealESRGAN_x4", name: "Real-ESRGAN x4", category: .superResolution,
             version: "1.0", fileSize: 67_000_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "mlboydaisuke/Real-ESRGAN-x4-CoreML",
             recommendedDevice: "iPhone 15 及以上", preferredDefault: false,
             usedByModes: [.photo, .night, .superMoon, .macro]),
        Meta(id: "RealESRGAN-x4plus", name: "Real-ESRGAN x4plus", category: .superResolution,
             version: "1.0", fileSize: 31_000_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "VincentGOURBIN/RealESRGAN-CoreML",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: false,
             usedByModes: [.photo, .night, .superMoon]),
        Meta(id: "RealESRGAN-UltraSharp", name: "Real-ESRGAN UltraSharp", category: .superResolution,
             version: "1.0", fileSize: 31_000_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "VincentGOURBIN/RealESRGAN-CoreML",
             recommendedDevice: "iPhone 15 及以上", preferredDefault: false,
             usedByModes: [.photo, .night, .macro]),
        Meta(id: "RealESRGAN-x4v3", name: "Real-ESRGAN x4v3", category: .superResolution,
             version: "3.0", fileSize: 2_300_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "VincentGOURBIN/RealESRGAN-CoreML",
             recommendedDevice: "iPhone 13 及以上", preferredDefault: false,
             usedByModes: [.photo, .night]),
        Meta(id: "RealESRGAN-x4v3-denoise", name: "Real-ESRGAN x4v3 Denoise", category: .superResolution,
             version: "3.0", fileSize: 2_300_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "VincentGOURBIN/RealESRGAN-CoreML",
             recommendedDevice: "iPhone 13 及以上", preferredDefault: false,
             usedByModes: [.photo, .night]),

        // --- 动漫与插画 ---
        Meta(id: "realesrganAnime512", name: "Real-ESRGAN Anime 512", category: .anime,
             version: "1.0", fileSize: 17_000_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "TheMurusTeam/coreml-upscaler-realesrganAnime512",
             recommendedDevice: "iPhone 13 及以上", preferredDefault: true,
             usedByModes: [.photo]),
        Meta(id: "ESRGAN-MangaJPEGLQ", name: "ESRGAN Manga JPEG LQ", category: .anime,
             version: "1.0", fileSize: 9_300_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "VincentGOURBIN/RealESRGAN-CoreML",
             recommendedDevice: "iPhone 13 及以上", preferredDefault: false,
             usedByModes: [.photo]),

        // --- GAN 超分 ---
        Meta(id: "aesrgan", name: "AESRGAN", category: .superResolution,
             version: "1.0", fileSize: 62_100_000, inputResolution: "512×512",
             outputScale: "×4", license: "Apache-2.0",
             source: "TheMurusTeam/coreml-upscaler-aesrgan",
             recommendedDevice: "iPhone 15 及以上", preferredDefault: false,
             usedByModes: [.photo, .night]),
        Meta(id: "bsrgan", name: "BSRGAN", category: .superResolution,
             version: "1.0", fileSize: 62_000_000, inputResolution: "512×512",
             outputScale: "×4", license: "BSD-3-Clause",
             source: "TheMurusTeam/coreml-upscaler-bsrgan",
             recommendedDevice: "iPhone 15 及以上", preferredDefault: false,
             usedByModes: [.photo, .night]),

        // --- 夜景降噪 ---
        Meta(id: "MPRNetDenoising", name: "MPRNet Denoising", category: .nightDenoise,
             version: "1.0", fileSize: 115_000_000, inputResolution: "512×512",
             outputScale: "×1", license: "GPL-3.0",
             source: "TheMurusTeam/coreml-upscaler-MPRNetDenoising",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: true,
             usedByModes: [.photo, .night, .video]),

        // --- 人像 / 人脸 ---
        Meta(id: "gfpgan", name: "GFPGAN Face Restore", category: .portrait,
             version: "1.4", fileSize: 333_000_000, inputResolution: "512×512",
             outputScale: "×1", license: "Apache-2.0",
             source: "TheMurusTeam/coreml-upscaler-gfpgan",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: true,
             usedByModes: [.portrait, .photo]),

        // --- 深度（驱动人像/Depth Studio） ---
        Meta(id: "DepthPro", name: "DepthPro Monocular Depth", category: .portrait,
             version: "1.0", fileSize: 1_800_000_000, inputResolution: "1536×1536",
             outputScale: "×1", license: "Apple Sample Code",
             source: "coreml-projects/DepthPro-coreml",
             recommendedDevice: "iPhone 15 Pro 及以上", preferredDefault: false,
             usedByModes: [.portrait, .photo]),
        Meta(id: "DepthAnythingV3_small_504", name: "Depth Anything V3 Small", category: .portrait,
             version: "3.0", fileSize: 69_000_000, inputResolution: "504×504",
             outputScale: "×1", license: "Apache-2.0",
             source: "mlboydaisuke/Depth-Anything-3-Small-CoreML",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: true,
             usedByModes: [.portrait, .photo]),
        Meta(id: "DepthAnythingV3_base_504", name: "Depth Anything V3 Base", category: .portrait,
             version: "3.0", fileSize: 233_000_000, inputResolution: "504×504",
             outputScale: "×1", license: "Apache-2.0",
             source: "mlboydaisuke/Depth-Anything-3-Base-CoreML",
             recommendedDevice: "iPhone 15 Pro 及以上", preferredDefault: false,
             usedByModes: [.portrait, .photo]),
        Meta(id: "DepthAnythingV2SmallF16", name: "Depth Anything V2 Small", category: .portrait,
             version: "2.0", fileSize: 50_000_000, inputResolution: "512×512",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-depth-anything-v2-small",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: false,
             usedByModes: [.portrait, .photo]),
        Meta(id: "DepthAnythingSmallF16", name: "Depth Anything Small", category: .portrait,
             version: "1.0", fileSize: 50_000_000, inputResolution: "512×512",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-depth-anything-small",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: false,
             usedByModes: [.portrait, .photo]),

        // --- 语义分割（用于创意编辑 / 抠图 / 重打光） ---
        Meta(id: "DETRResnet50SemanticSegmentationF16", name: "DETR ResNet50 Segmentation",
             category: .creative, version: "1.0", fileSize: 85_000_000,
             inputResolution: "512×512", outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-detr-semantic-segmentation",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: true,
             usedByModes: [.portrait, .photo]),
        Meta(id: "MobileViT_DeepLabV3", name: "MobileViT DeepLabV3", category: .creative,
             version: "1.0", fileSize: 26_000_000, inputResolution: "513×513",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/deeplabv3-mobilevit-small",
             recommendedDevice: "iPhone 13 及以上", preferredDefault: false,
             usedByModes: [.portrait, .photo]),
        Meta(id: "SAM2_1TinyImageEncoderFLOAT16", name: "SAM2 Image Encoder", category: .creative,
             version: "2.1", fileSize: 67_000_000, inputResolution: "1024×1024",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-sam2.1-tiny",
             recommendedDevice: "iPhone 15 Pro 及以上", preferredDefault: false,
             usedByModes: [.photo]),
        Meta(id: "SAM2_1TinyMaskDecoderFLOAT16", name: "SAM2 Mask Decoder", category: .creative,
             version: "2.1", fileSize: 10_000_000, inputResolution: "256×256",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-sam2.1-tiny",
             recommendedDevice: "iPhone 15 Pro 及以上", preferredDefault: false,
             usedByModes: [.photo]),
        Meta(id: "SAM2_1TinyPromptEncoderFLOAT16", name: "SAM2 Prompt Encoder", category: .creative,
             version: "2.1", fileSize: 2_100_000, inputResolution: "512×512",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-sam2.1-tiny",
             recommendedDevice: "iPhone 15 Pro 及以上", preferredDefault: false,
             usedByModes: [.photo]),

        // --- 目标检测 / 场景分类（实时追踪 / 场景识别） ---
        Meta(id: "YOLOv3FP16", name: "YOLOv3 Object Detection", category: .livePreview,
             version: "3.0", fileSize: 124_000_000, inputResolution: "416×416",
             outputScale: "×1", license: "MIT",
             source: "apple/coreml-YOLOv3",
             recommendedDevice: "iPhone 14 及以上", preferredDefault: true,
             usedByModes: [.video, .photo]),
        Meta(id: "Resnet50FP16", name: "ResNet50 Classification", category: .livePreview,
             version: "1.0", fileSize: 51_000_000, inputResolution: "224×224",
             outputScale: "×1", license: "Apache-2.0",
             source: "apple/coreml-resnet-50",
             recommendedDevice: "iPhone 13 及以上", preferredDefault: false,
             usedByModes: [.photo])
    ]

    // MARK: - Bundle scan

    /// 扫描 App Bundle 根目录的 .mlmodelc，更新可用性。
    func loadBundledModels() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let present = Self.compiledModelNames()

            let infos = Self.catalog.map { meta -> AIModelInfo in
                var info = meta.toInfo(available: present.contains(meta.id))
                return info
            }

            let defaults = self.buildDefaults(present: present)

            DispatchQueue.main.async {
                self.allModels = infos.map { info in
                    var i = info
                    if let def = defaults[i.category], def == i.id {
                        i.isDefault = true
                    }
                    return i
                }
                self.loadedModelIDs = present
                self.defaultModelIDs = defaults
            }
        }
    }

    /// 根目录下所有 .mlmodelc 的 basename。
    private static func compiledModelNames() -> Set<String> {
        let urls = Bundle.main.urls(forResourcesWithExtension: "mlmodelc",
                                   subdirectory: nil) ?? []
        return Set(urls.map { $0.deletingPathExtension().lastPathComponent })
    }

    private func buildDefaults(present: Set<String>) -> [AIModelCategory: String] {
        var result: [AIModelCategory: String] = [:]
        for category in AIModelCategory.allCases {
            let metas = Self.catalog.filter { $0.category == category }
            // 优先：标记 preferredDefault 且实际存在
            if let pick = metas.first(where: { $0.preferredDefault && present.contains($0.id) }) {
                result[category] = pick.id
                continue
            }
            // 其次：任意实际存在
            if let pick = metas.first(where: { present.contains($0.id) }) {
                result[category] = pick.id
                continue
            }
            // 最后：首选元数据（即使缺失）
            if let pick = metas.first(where: { $0.preferredDefault }) {
                result[category] = pick.id
            }
        }
        return result
    }

    private func computeDefaults() {
        defaultModelIDs = buildDefaults(present: [])
    }

    // MARK: - Aliases (logical purpose -> bundled model)

    /// 逻辑别名（旧调用方使用的"用途名"）→ 实际模型 id。
    private static let aliases: [String: String] = [
        "gfpgan_face": "gfpgan",
        "face": "gfpgan",
        "portrait_face": "gfpgan",
        "architecture_sr": "realesrgan512",
        "macrodetail_sr": "realesrgan512",
        "lunarsr": "realesrgan512",
        "deblur_net": "MPRNetDenoising",
        "denoise": "MPRNetDenoising",
        "night_denoise": "MPRNetDenoising",
        "sr_generic": "realesrgan512"
    ]

    /// 把逻辑别名解析为实际可用的 bundled 模型 id；不存在则 nil。
    func resolveModelID(_ requested: String) -> String? {
        if loadedModelIDs.contains(requested) { return requested }
        if let alias = Self.aliases[requested], loadedModelIDs.contains(alias) {
            return alias
        }
        // 兜底：按用途分类找默认
        if let category = categoryHint(for: requested),
           let def = defaultModelIDs[category], loadedModelIDs.contains(def) {
            return def
        }
        return nil
    }

    private func categoryHint(for logical: String) -> AIModelCategory? {
        let lower = logical.lowercased()
        if lower.contains("face") || lower.contains("portrait") { return .portrait }
        if lower.contains("denoise") || lower.contains("deblur") { return .nightDenoise }
        if lower.contains("anime") || lower.contains("manga") { return .anime }
        if lower.contains("lunar") || lower.contains("macro") || lower.contains("architecture") {
            return .superResolution
        }
        return nil
    }

    // MARK: - Query

    /// 便捷别名：视图中常用 `.models`。
    var models: [AIModelInfo] { allModels }

    /// 按 id 获取模型元信息。
    func model(for id: String) -> AIModelInfo? {
        allModels.first { $0.id == id }
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
        allModels = allModels.map { info in
            var i = info
            i.isDefault = (i.category == category) ? i.id == modelID : i.isDefault
            return i
        }
    }

    /// 某分类下所有模型。
    func allModels(in category: AIModelCategory) -> [AIModelInfo] {
        allModels.filter { $0.category == category }
    }

    /// 模型文件是否实际可用。
    func isModelAvailable(_ id: String) -> Bool {
        loadedModelIDs.contains(id)
    }
}
