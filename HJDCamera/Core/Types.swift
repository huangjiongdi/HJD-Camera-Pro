//
//  Types.swift
//  HJD Camera Pro
//
//  Global shared types, enums, and protocols.
//

import Foundation
import CoreImage
import AVFoundation

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo = "拍照"
    case portrait = "人像"
    case video = "视频"
    case slowMotion = "慢动作"
    case night = "夜景"
    case superMoon = "超级月亮"
    case pro = "专业模式"
    case timeLapse = "延时摄影"
    case burst = "连拍"
    case multiExposure = "多重曝光"
    case starTrail = "星轨"
    case lightTrail = "光轨"
    case macro = "长焦微距"
    case panorama = "全景"

    var id: String { rawValue }

    var isVideoMode: Bool {
        self == .video || self == .slowMotion || self == .timeLapse
    }

    /// 多帧序列模式：星轨/光轨（取每像素最亮）/ 多重曝光（叠加）。
    var isTrailMode: Bool {
        self == .starTrail || self == .lightTrail || self == .multiExposure
    }

    var coreModes: [CaptureMode] {
        [.photo, .portrait, .video, .slowMotion, .night, .superMoon]
    }

    var moreModes: [CaptureMode] {
        [.pro, .macro, .timeLapse, .burst, .multiExposure, .starTrail, .lightTrail, .panorama]
    }
}

// MARK: - Zoom

enum ZoomSource: String {
    case optical = "光学"
    case hybrid = "混合"
    case digital = "数字"
    case ai = "AI增强"
}

struct ZoomLevel: Identifiable, Hashable {
    let id = UUID()
    let factor: Double
    let label: String
    let source: ZoomSource
    let isExtreme: Bool

    static let standard: [ZoomLevel] = [
        ZoomLevel(factor: 0.5, label: "0.5×", source: .optical, isExtreme: false),
        ZoomLevel(factor: 1.0, label: "1×", source: .optical, isExtreme: false),
        ZoomLevel(factor: 2.0, label: "2×", source: .optical, isExtreme: false),
        ZoomLevel(factor: 5.0, label: "5×", source: .hybrid, isExtreme: false),
        ZoomLevel(factor: 10.0, label: "10×", source: .hybrid, isExtreme: false),
    ]

    static let extreme: [ZoomLevel] = [
        ZoomLevel(factor: 25, label: "25×", source: .digital, isExtreme: true),
        ZoomLevel(factor: 50, label: "50×", source: .digital, isExtreme: true),
        ZoomLevel(factor: 100, label: "100×", source: .ai, isExtreme: true),
        ZoomLevel(factor: 200, label: "200×", source: .ai, isExtreme: true),
        ZoomLevel(factor: 400, label: "400×", source: .ai, isExtreme: true),
        ZoomLevel(factor: 500, label: "500×", source: .ai, isExtreme: true),
    ]

    static let all: [ZoomLevel] = standard + extreme
}

enum ZoomConfidence: String {
    case high = "可信度较高"
    case medium = "细节不足"
    case low = "实验性重建"
}

// MARK: - Photo Format

enum PhotoFormat: String, CaseIterable {
    case heif = "HEIF"
    case jpeg = "JPEG"
    case raw = "RAW"
    case rawPlus = "RAW+"
}

enum PhotoAspectRatio: String, CaseIterable {
    case ratio4_3 = "4:3"
    case ratio16_9 = "16:9"
    case ratio1_1 = "1:1"
    case ratio3_2 = "3:2"
}

// MARK: - Video

struct VideoFormat: Identifiable, Hashable {
    let id = UUID()
    let resolution: String
    let frameRate: Int
    let codec: String
    let isHDR: Bool
    let isProRes: Bool

    static let common: [VideoFormat] = [
        VideoFormat(resolution: "480p", frameRate: 30, codec: "H.264", isHDR: false, isProRes: false),
        VideoFormat(resolution: "720p", frameRate: 30, codec: "HEVC", isHDR: false, isProRes: false),
        VideoFormat(resolution: "1080p", frameRate: 30, codec: "HEVC", isHDR: false, isProRes: false),
        VideoFormat(resolution: "1080p", frameRate: 60, codec: "HEVC", isHDR: false, isProRes: false),
        VideoFormat(resolution: "4K", frameRate: 24, codec: "HEVC", isHDR: true, isProRes: false),
        VideoFormat(resolution: "4K", frameRate: 30, codec: "HEVC", isHDR: true, isProRes: false),
        VideoFormat(resolution: "4K", frameRate: 60, codec: "HEVC", isHDR: true, isProRes: false),
        VideoFormat(resolution: "4K", frameRate: 120, codec: "HEVC", isHDR: false, isProRes: false),
        VideoFormat(resolution: "4K", frameRate: 240, codec: "HEVC", isHDR: false, isProRes: false),
        VideoFormat(resolution: "8K", frameRate: 30, codec: "HEVC", isHDR: true, isProRes: false),
        VideoFormat(resolution: "8K", frameRate: 60, codec: "HEVC", isHDR: true, isProRes: false),
    ]
}

enum VideoCodec: String {
    case h264 = "H.264"
    case hevc = "HEVC"
    case proRes422 = "ProRes 422"
    case proRes422HQ = "ProRes 422 HQ"
    case proRes422LT = "ProRes 422 LT"
    case proResProxy = "ProRes Proxy"
}

enum ColorSpace: String {
    case sdr = "SDR"
    case hdr = "HDR"
    case dolbyVision = "Dolby Vision"
    case p3 = "P3"
    case log = "LOG"
}

// MARK: - Pro Controls

enum ExposureMode: String, CaseIterable, Hashable {
    case auto = "Auto"
    case program = "P"
    case shutterPriority = "S"
    case aperturePriority = "A"
    case manual = "M"
}

/// 极影式 Pro 轮盘可调参数。
enum ProWheelParam: String, CaseIterable, Identifiable {
    case focus = "对焦"
    case iso = "ISO"
    case shutter = "快门"
    case ev = "EV"
    case wb = "白平衡"
    var id: String { rawValue }
}

struct ProCaptureSettings {
    var iso: Double
    var shutterSpeed: Double
    var evCompensation: Double
    var whiteBalance: Int
    var colorTemperature: Int
    var manualFocusDistance: Double
    var sharpness: Double
    var aiIntensity: Double
    var outputScale: Double
}

// MARK: - AI

enum AIModelCategory: String, CaseIterable {
    case superResolution = "通用超分"
    case anime = "动漫与插画"
    case nightDenoise = "夜景降噪"
    case multiFrame = "多帧融合"
    case livePreview = "实时预览"
    case portrait = "人像"
    case hdr = "逆光HDR"
    case lunar = "超级月亮"
    case macro = "长焦微距"
    case architecture = "建筑纹理"
    case text = "文字与文档"
    case landscape = "风景与自然纹理"
    case creative = "创意编辑"
    case quality = "质量检测与真实性保护"
}

struct AIModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let category: AIModelCategory
    let version: String
    let fileSize: Int64
    let isDownloaded: Bool
    let inputResolution: String
    let outputScale: String
    let inferenceTime: Double?
    let peakMemory: Int64?
    let license: String
    let source: String
    let recommendedDevice: String
    var isDefault: Bool
    let canUninstall: Bool
    let usedByModes: [CaptureMode]
}

enum AIProcessingState {
    case idle
    case queued
    case processing(progress: Double)
    case completed
    case failed(error: String)
    case cancelled
}

struct AIProcessingTask: Identifiable {
    let id = UUID()
    let type: AITaskType
    let inputImageURL: URL
    var outputImageURL: URL?
    var state: AIProcessingState
    var progress: Double
    var modelName: String
    var createdAt: Date
    var estimatedRemaining: TimeInterval?
    var errorMessage: String?
}

enum AITaskType: String {
    case superResolution = "超清增强"
    case nightRestore = "夜景修复"
    case portraitOptimize = "人像优化"
    case lunarEnhance = "超级月亮增强"
    case macroEnhance = "长焦微距增强"
    case architectureEnhance = "建筑纹理增强"
    case deblur = "去模糊"
    case dereflection = "去反光"
    case demoire = "去摩尔纹"
    case textEnhance = "文字增强"
    case objectErase = "擦除物体"
    case outpaint = "智能扩图"
    case skyReplace = "天空替换"
    case lutApply = "LUT色彩"
    case batchProcess = "批量处理"
    case denoise = "AI降噪"
    case oldPhotoRestore = "老照片修复"
}

enum AIQualityLevel: String {
    case natural = "自然"
    case balanced = "均衡"
    case strong = "强增强"
}

enum LivePreviewLevel: String {
    case off = "关闭"
    case smooth = "流畅"
    case balanced = "均衡"
    case highDetail = "高细节预览"
}

// MARK: - Lunar

enum LunarQualityMode: String {
    case realSurface = "真实月面"
    case detailEnhanced = "细节增强"
    case experimental = "实验性高细节"
}

struct LunarProcessingResult {
    var image: CIImage
    var confidence: Double
    var qualityScore: Double
    var frameCount: Int
    var modelUsed: String
}

// MARK: - Macro

enum MacroMode: String {
    case fast = "快速微距"
    case detail = "细节微距"
}

// MARK: - Night

enum NightPreset: String {
    case natural = "自然夜景"
    case clean = "纯净夜景"
    case detail = "夜景细节"
    case portrait = "夜景人像"
}

// MARK: - Haptic

enum HapticPreset: String, CaseIterable {
    case natural = "自然"
    case camera = "相机"
    case pro = "专业"
    case cinematic = "电影感"
}

struct HapticSettings {
    var preset: HapticPreset
    var shutterEnabled: Bool
    var focusEnabled: Bool
    var lunarLockEnabled: Bool
    var zoomNodeEnabled: Bool
    var aiCompleteEnabled: Bool
    var exportCompleteEnabled: Bool
    var errorEnabled: Bool
}

// MARK: - Storage

struct StorageBudget {
    var modelCacheSize: Int64
    var tempFilesSize: Int64
    var rawPhotosSize: Int64
    var processedPhotosSize: Int64
    var videoProxySize: Int64
    var totalAvailable: Int64
}

// MARK: - Capture Recipe

struct CaptureRecipe: Identifiable, Codable {
    let id: UUID
    var name: String
    var mode: String
    var lens: String
    var zoomFactor: Double
    var iso: Double
    var shutterSpeed: Double
    var ev: Double
    var whiteBalance: Int
    var modelName: String
    var lutName: String
    var aiIntensity: Double
    var createdAt: Date
}

// MARK: - Quality Guard

struct QualityAssessment {
    var sharpnessScore: Double
    var noiseScore: Double
    var exposureScore: Double
    var motionBlurScore: Double
    var artifactScore: Double
    var overallScore: Double
    var warnings: [String]
    var aiGeneratedAreas: Double
}

// MARK: - Scene Detection

enum SceneType: String {
    case normal = "普通"
    case night = "夜景"
    case portrait = "人像"
    case lunar = "月亮"
    case macro = "微距"
    case architecture = "建筑"
    case backlight = "逆光"
    case landscape = "风景"
    case document = "文档"
    case sports = "运动"
    case fireworks = "烟花"
    case stage = "舞台"
    case sunset = "日落"
    case starry = "星空"
}

// MARK: - Notification Names

extension Notification.Name {
    static let hjdCaptureCompleted = Notification.Name("HJDCaptureCompleted")
    static let hjdAIProcessingStarted = Notification.Name("HJDAIProcessingStarted")
    static let hjdAIProcessingCompleted = Notification.Name("HJDAIProcessingCompleted")
    static let hjdSettingsChanged = Notification.Name("HJDSettingsChanged")
    static let hjdThermalWarning = Notification.Name("HJDThermalWarning")
    static let hjdMemoryWarning = Notification.Name("HJDMemoryWarning")
    static let hjdStorageWarning = Notification.Name("HJDStorageWarning")
}
