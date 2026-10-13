//
//  AISceneRouter.swift
//  HJD Camera Pro
//
//  三套 AI 超算系统共用的"场景/任务 -> 真实模型"路由层。
//
//    · Live Vision AI：取景框实时识别（LiveVisionEngine，轻量，不跑重型模型）
//    · Capture AI：按下快门后的快速确定性增强（PhotoCapturePipeline，保证不丢片）
//    · Gallery AI Lab：相册离线高画质处理（GalleryAIProcessor，真实 Core ML 推理）
//
//  这里只路由到 24 个已内嵌、真实可加载的模型。对于没有对应权重的生成类
//  功能（擦除/扩图/换天等），返回 nil，由上层诚实提示，绝不伪造结果。
//

import Foundation

/// 一条 AI 路由：使用哪个真实模型，以及该模型是否为放大型超分（×4）。
struct AISceneRoute {
    /// AIModelRegistry 中的模型 ID 或别名（会再经 resolveModelID 解析）。
    let modelID: String
    /// 是否为超分放大模型（输出 4 倍边长）；false 表示同尺寸修复/降噪。
    let isSuperResolution: Bool
    /// 面向用户的路线名称。
    let displayName: String
    /// 这条路线的诚实说明（无专用模型时的回退提示）。
    let note: String
}

enum AISceneRouter {

    /// 按任务类型选择真实模型。
    static func route(task: AITaskType) -> AISceneRoute? {
        switch task {
        case .superResolution:
            return AISceneRoute(modelID: "sr_generic", isSuperResolution: true,
                                displayName: "通用超分 Real-ESRGAN", note: "")
        case .denoise:
            return AISceneRoute(modelID: "denoise", isSuperResolution: false,
                                displayName: "AI 降噪 MPRNet", note: "")
        case .nightRestore:
            return AISceneRoute(modelID: "night_denoise", isSuperResolution: false,
                                displayName: "夜景降噪 MPRNet", note: "")
        case .deblur:
            return AISceneRoute(modelID: "deblur_net", isSuperResolution: false,
                                displayName: "去模糊 MPRNet", note: "")
        case .portraitOptimize:
            return AISceneRoute(modelID: "gfpgan_face", isSuperResolution: false,
                                displayName: "人脸增强 GFPGAN", note: "")
        case .lunarEnhance:
            return AISceneRoute(modelID: "lunarsr", isSuperResolution: true,
                                displayName: "月面超分 Real-ESRGAN",
                                note: "月面专用模型仍在训练，当前用通用超分保守处理，不凭空生成环形山。")
        case .macroEnhance:
            return AISceneRoute(modelID: "macrodetail_sr", isSuperResolution: true,
                                displayName: "微距细节超分",
                                note: "微距专用模型仍在训练，当前用通用超分处理。")
        case .architectureEnhance:
            return AISceneRoute(modelID: "architecture_sr", isSuperResolution: true,
                                displayName: "建筑纹理超分",
                                note: "建筑专用模型仍在训练，当前用通用超分处理并保留规则线条。")
        case .textEnhance:
            return AISceneRoute(modelID: "sr_generic", isSuperResolution: true,
                                displayName: "文字超分",
                                note: "无独立文字模型，提升边缘清晰度但不会臆造文字内容。")
        case .oldPhotoRestore:
            return AISceneRoute(modelID: "sr_generic", isSuperResolution: true,
                                displayName: "老照片修复", note: "通用超分提升清晰度。")
        case .dereflection, .demoire:
            return AISceneRoute(modelID: "sr_generic", isSuperResolution: true,
                                displayName: "画质增强",
                                note: "去反光/摩尔纹专用模型未内嵌，当前以通用超分做保守处理。")
        // 生成类能力当前没有内嵌权重，诚实返回 nil。
        case .objectErase, .outpaint, .skyReplace, .lutApply, .batchProcess:
            return nil
        }
    }

    /// 按检测到的场景选择默认路线（相册导入后自动识别）。
    static func route(scene: SceneType) -> AISceneRoute {
        switch scene {
        case .night, .starry:
            return route(task: .nightRestore) ?? route(task: .denoise)!
        case .portrait:
            return route(task: .portraitOptimize)!
        case .lunar:
            return route(task: .lunarEnhance)!
        case .macro:
            return route(task: .macroEnhance)!
        case .architecture, .document:
            return route(task: .architectureEnhance)!
        default:
            return route(task: .superResolution)!
        }
    }

    /// 解析为真实可加载的模型 ID；若目标模型不可用则回退到可用通用模型。
    /// 返回的 id 为 nil 表示当前没有任何可加载模型（仅做重采样）。
    static func resolveAvailable(_ route: AISceneRoute) -> (id: String?, warning: String?) {
        let registry = AIModelRegistry.shared
        if let resolved = registry.resolveModelID(route.modelID) {
            return (resolved, route.note.isEmpty ? nil : route.note)
        }
        // 回退链：通用超分 → 任意可用模型
        if let fallback = registry.resolveModelID("sr_generic") {
            return (fallback, "首选模型不可用，已回退到通用模型 \(fallback)。")
        }
        if let any = registry.allModels.first(where: { registry.isModelAvailable($0.id) }) {
            return (any.id, "已回退到可用模型 \(any.id)。")
        }
        return (nil, "模型尚未加载，将仅做高画质重采样，不执行 AI 推理。")
    }
}
