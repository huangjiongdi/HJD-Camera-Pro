//
//  HJDReconstructionPolicy.swift
//  HJD Camera Pro
//
//  变焦分级 × 真实模型选择 × 输出像素上限 的统一策略（第四轮）。
//
//  三条铁律（与用户需求一一对应）：
//    1. 真变焦优先：0.5×–硬件长焦范围内走真实镜头/虚拟三摄；超过硬件能力的
//       部分明确标记为数字裁切 / AI 重建，绝不伪称光学变焦。
//    2. 50×–99.9× 默认最高 100MP；100×–500× 默认最高 50MP。像素上限只约束
//       输出尺寸，不代表传感器真的采集到了那么多细节。
//    3. 所有 AI 开关都必须连到真实推理：模型未内嵌/输入不匹配/推理失败时，
//       明确提示并回退原片，绝不用普通锐化或插值冒充 AI 超算。
//
//  模型诚实性说明（重要）：
//    · PiperSR（ModelPiper，2× 轻量实时超分）并未内嵌进本 App，因此实时
//      路线的 realtimeSRModelID 为 nil；实时预览只使用 Vision（人脸/人体/动物/
//      文字）+ YOLOv3FP16 检测 + LiveDetailEngine 的轻量 CoreImage 增强，
//      不谎称跑了 PiperSR 超分。
//    · RealESRGAN_x2plus 未内嵌。照片超分一律使用真实已内嵌的 Real-ESRGAN
//      家族：分块稳妥的 realesrgan512 与高质量 RealESRGAN-x4plus（均为 ×4）。
//    · 高倍(50+)与超高倍(100+)使用不同的真实模型档位：高倍优先 x4plus
//      （质量优先），超高倍回退 realesrgan512（分块更稳、内存可控，配 50MP 上限）。
//

import CoreGraphics
import Foundation

// MARK: - 变焦分级

enum HJDZoomTier: String, CaseIterable {
    /// 0.5×–1.99×：原生光学/主摄传感器区间
    case native
    /// 2×–4.99×：主摄 2× 传感器裁切与混合区间
    case lowZoom
    /// 5×–49.99×：潜望长焦 + 混合/数字
    case mediumZoom
    /// 50×–99.9×：高倍数字裁切 + AI 重建，输出上限 100MP
    case highZoom
    /// 100×–500×：超高倍数字裁切 + AI 重建，输出上限 50MP
    case ultraZoom

    var displayName: String {
        switch self {
        case .native:      return "原生光学"
        case .lowZoom:     return "低倍混合"
        case .mediumZoom:  return "长焦 / 数字"
        case .highZoom:    return "高倍 AI 重建"
        case .ultraZoom:   return "超高倍 AI 重建"
        }
    }

    /// 该档是否强制要求 AI 重建（否则不允许标称已达到该倍率的成片细节）。
    var aiReconstructionRequired: Bool {
        self == .highZoom || self == .ultraZoom
    }
}

// MARK: - 真实模型标识（与 24 个内嵌 .mlmodelc 对齐）

/// 仅引用真实已内嵌的模型资源；未内嵌的实时模型一律留空并诚实说明。
enum HJDRealModel {
    /// 照片超分（分块稳妥，内存可控）：AIModelRegistry 中的 realesrgan512。
    static let photoSRTiled = "realesrgan512"
    /// 照片超分（高质量 ×4，真实内嵌）：RealESRGAN-x4plus。
    static let photoSRHighQuality = "RealESRGAN-x4plus"

    /// 实时轻量超分模型。PiperSR 未内嵌，因此为 nil；
    /// 实时路线只做 Vision/YOLO 检测 + LiveDetailEngine 轻量增强。
    static let realtimeSR: String? = nil
    static let realtimeSRUnavailableNote =
        "PiperSR 实时超分模型未内嵌，实时画面仅做 Vision/YOLO 识别与轻量增强，不执行逐帧超分。"
}

// MARK: - 单档配置

struct HJDZoomModelProfile {
    let tier: HJDZoomTier
    let minimumZoom: CGFloat
    let maximumZoom: CGFloat
    /// 实时超分模型资源 id；nil 表示当前没有可用的实时超分模型（诚实回退）。
    let realtimeSRModelID: String?
    /// 拍照后超分模型资源 id（真实内嵌，运行时再经 AIModelRegistry 校验）。
    let photoModelID: String
    /// 该档输出像素上限（MP）。
    let maxOutputMegapixels: Int
    /// 该档默认输出像素（MP）。
    let defaultOutputMegapixels: Int
    /// 是否要求 AI 重建。
    let aiReconstructionRequired: Bool
}

// MARK: - 策略

enum HJDReconstructionPolicy {
    static let minimumZoom: CGFloat = 0.5
    static let maximumZoom: CGFloat = 500.0
    /// 输出像素下限（任何档位都不低于 12MP）。
    static let floorOutputMegapixels = 12

    static let profiles: [HJDZoomModelProfile] = [
        HJDZoomModelProfile(
            tier: .native, minimumZoom: 0.5, maximumZoom: 1.99,
            realtimeSRModelID: HJDRealModel.realtimeSR,
            photoModelID: HJDRealModel.photoSRTiled,
            maxOutputMegapixels: 48, defaultOutputMegapixels: 48,
            aiReconstructionRequired: false),
        HJDZoomModelProfile(
            tier: .lowZoom, minimumZoom: 2.0, maximumZoom: 4.99,
            realtimeSRModelID: HJDRealModel.realtimeSR,
            photoModelID: HJDRealModel.photoSRTiled,
            maxOutputMegapixels: 48, defaultOutputMegapixels: 48,
            aiReconstructionRequired: false),
        HJDZoomModelProfile(
            tier: .mediumZoom, minimumZoom: 5.0, maximumZoom: 49.99,
            realtimeSRModelID: HJDRealModel.realtimeSR,
            photoModelID: HJDRealModel.photoSRTiled,
            maxOutputMegapixels: 48, defaultOutputMegapixels: 48,
            aiReconstructionRequired: false),
        HJDZoomModelProfile(
            tier: .highZoom, minimumZoom: 50.0, maximumZoom: 99.99,
            realtimeSRModelID: HJDRealModel.realtimeSR,
            // 高倍优先高质量 ×4 模型；运行时若不可用会被 resolvePhotoModel 回退。
            photoModelID: HJDRealModel.photoSRHighQuality,
            maxOutputMegapixels: 100, defaultOutputMegapixels: 100,
            aiReconstructionRequired: true),
        HJDZoomModelProfile(
            tier: .ultraZoom, minimumZoom: 100.0, maximumZoom: 500.0,
            realtimeSRModelID: HJDRealModel.realtimeSR,
            // 超高倍配 50MP 上限，选分块更稳的模型，保证任务能跑完不爆内存。
            photoModelID: HJDRealModel.photoSRTiled,
            maxOutputMegapixels: 50, defaultOutputMegapixels: 50,
            aiReconstructionRequired: true)
    ]

    static func profile(for zoom: CGFloat) -> HJDZoomModelProfile {
        let z = min(max(zoom, minimumZoom), maximumZoom)
        return profiles.first { z >= $0.minimumZoom && z <= $0.maximumZoom }
            ?? profiles[0]
    }

    static func tier(for zoom: CGFloat) -> HJDZoomTier { profile(for: zoom).tier }

    // MARK: - 输出像素钳制（带原因）

    /// 把用户请求的输出 MP 按当前倍率档位自动钳制，并返回是否被钳制及原因。
    /// - 50×–99.9×：最高 100MP；100×–500×：最高 50MP。
    static func clampOutputMegapixels(requested: Int, zoom: CGFloat)
        -> (megapixels: Int, clamped: Bool, reason: String?) {
        let p = profile(for: zoom)
        let lower = min(floorOutputMegapixels, p.maxOutputMegapixels)
        let clampedValue = min(max(requested, lower), p.maxOutputMegapixels)
        if clampedValue != requested {
            let reason = "当前倍率 \(zoomLabel(zoom)) 属于「\(p.tier.displayName)」档，输出上限为 \(p.maxOutputMegapixels)MP，已自动调整（像素上限只约束输出尺寸，不代表传感器原生细节）。"
            return (clampedValue, true, reason)
        }
        return (clampedValue, false, nil)
    }

    // MARK: - 模型可用性（真实校验，不伪造）

    /// 解析当前档位真实可加载的照片超分模型 id；
    /// 首选不可用时回退到 realesrgan512；都不可用返回 nil（仅做重采样）。
    static func resolvePhotoModel(for zoom: CGFloat) -> (id: String?, warning: String?) {
        let p = profile(for: zoom)
        let registry = AIModelRegistry.shared
        if let id = registry.resolveModelID(p.photoModelID) {
            return (id, nil)
        }
        if p.photoModelID != HJDRealModel.photoSRTiled,
           let fallback = registry.resolveModelID(HJDRealModel.photoSRTiled) {
            return (fallback, "首选模型 \(p.photoModelID) 不可用，已回退到分块超分 \(fallback)。")
        }
        if let any = registry.allModels.first(where: { registry.isModelAvailable($0.id) }) {
            return (any.id, "当前档位无专用超分模型，已回退到可用模型 \(any.id)。")
        }
        return (nil, "超分模型尚未加载，将仅做高画质重采样，不执行 AI 推理。")
    }

    /// 实时超分是否真实可用（PiperSR 未内嵌时恒为 false，并给出说明）。
    static func realtimeSuperResolutionAvailable() -> (available: Bool, note: String?) {
        guard let id = HJDRealModel.realtimeSR,
              AIModelRegistry.shared.resolveModelID(id) != nil else {
            return (false, HJDRealModel.realtimeSRUnavailableNote)
        }
        return (true, nil)
    }

    static func zoomLabel(_ zoom: CGFloat) -> String {
        zoom == 0.5 ? "0.5×" : "\(Int(zoom.rounded()))×"
    }
}

// MARK: - 5 秒实况配置（1080p30 / 4K30 真实；8K60 仅实验性离线 AI 导出）

enum HJDLiveResolution: String, CaseIterable, Identifiable {
    case p1080 = "1080p"
    case p4K = "4K"
    /// 实验性：先拍设备真实支持的源视频，再离线逐帧超分重编码，不是原生 8K60。
    case p8KAI = "8K AI 导出（实验性）"
    var id: String { rawValue }

    /// 是否需要先录制真实源视频再离线 AI 超分（手机不原生支持 8K60）。
    var requiresOfflineAIExport: Bool { self == .p8KAI }
}

struct HJDLiveSettings {
    var resolution: HJDLiveResolution = .p4K
    var fps: Int = 30
    var durationSeconds: Int = 5
    var realtimeEnhancement = false
    var aiUpscaleExport = false

    enum LiveError: LocalizedError {
        case durationMustBeFive
        case realtimeFPSMustBe30
        case eightKNeedsOfflineAI
        var errorDescription: String? {
            switch self {
            case .durationMustBeFive:
                return "实况时长当前固定为 5 秒。"
            case .realtimeFPSMustBe30:
                return "1080p / 4K 实况当前仅配置 30fps。"
            case .eightKNeedsOfflineAI:
                return "iPhone 16 Pro Max 不支持原生 8K60；需开启离线 AI 超分导出，先录制真实源视频再处理。"
            }
        }
    }

    func validate() throws {
        guard durationSeconds == 5 else { throw LiveError.durationMustBeFive }
        switch resolution {
        case .p1080, .p4K:
            guard fps == 30 else { throw LiveError.realtimeFPSMustBe30 }
        case .p8KAI:
            guard fps == 60 && aiUpscaleExport else { throw LiveError.eightKNeedsOfflineAI }
        }
    }
}
