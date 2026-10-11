//
//  AppSettingsStore.swift
//  HJD Camera Pro
//
//  Centralized, UserDefaults-backed application settings. All settings are
//  @Published so SwiftUI views react to changes, and every change is persisted.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Supporting Enums (local to settings)

enum FocusMeteringMode: String, CaseIterable {
    case center = "中央重点"
    case spot = "点测光"
    case average = "平均测光"
    case facePriority = "人脸优先"
}

enum AEAFLockBehavior: String, CaseIterable {
    case holdUntilTap = "点击任意处解除"
    case sessionOnly = "仅本次拍摄"
    case manualOnly = "手动解除"
}

enum LensSwitchStrategy: String, CaseIterable {
    case automatic = "自动切换"
    case opticalOnly = "仅光学镜头"
    case preferTele = "优先长焦"
}

enum VideoStabilization: String, CaseIterable {
    case off = "关闭"
    case standard = "标准防抖"
    case cinematic = "电影防抖"
    case cinematicExtended = "扩展电影防抖"
}

enum AudioSource: String, CaseIterable {
    case microphone = "内置麦克风"
    case external = "外接麦克风"
    case wireless = "无线麦克风"
}

enum NightHandholdMode: String, CaseIterable {
    case handheld = "手持"
    case tripod = "三脚架"
}

enum SkinToneStyle: String, CaseIterable {
    case natural = "自然"
    case warm = "暖调"
    case fair = "白皙"
    case cinematic = "电影感"
}

enum BackgroundPolicy: String, CaseIterable {
    case suspend = "进入后台即暂停"
    case finishCurrent = "完成当前任务"
    case allowContinue = "允许继续处理"
}

enum WatermarkStyle: String, CaseIterable {
    case none = "无水印"
    case minimal = "简洁水印"
    case detailed = "参数水印"
}

// MARK: - Keys

private enum Keys {
    // Capture
    static let defaultMode = "settings.capture.defaultMode"
    static let defaultAspectRatio = "settings.capture.defaultAspectRatio"
    static let defaultFormat = "settings.capture.defaultFormat"
    static let photoResolution = "settings.capture.photoResolution"
    static let videoResolution = "settings.capture.videoResolution"
    static let videoFrameRate = "settings.capture.videoFrameRate"
    static let defaultLensZoom = "settings.capture.defaultLensZoom"
    static let burstCount = "settings.capture.burstCount"
    static let shutterPriority = "settings.capture.shutterPriority"
    static let focusMetering = "settings.capture.focusMetering"
    static let aeafLockBehavior = "settings.capture.aeafLockBehavior"
    static let lensSwitchStrategy = "settings.capture.lensSwitchStrategy"
    static let externalLensConfigured = "settings.capture.externalLensConfigured"
    static let gridEnabled = "settings.capture.gridEnabled"
    static let levelEnabled = "settings.capture.levelEnabled"
    static let focusPeaking = "settings.capture.focusPeaking"
    static let zebraStripes = "settings.capture.zebraStripes"
    static let histogramEnabled = "settings.capture.histogramEnabled"
    static let volumeKeyShutter = "settings.capture.volumeKeyShutter"
    static let touchShutter = "settings.capture.touchShutter"

    // AI quality
    static let livePreviewLevel = "settings.ai.livePreviewLevel"
    static let defaultUpscaleModel = "settings.ai.defaultUpscaleModel"
    static let defaultOutputScale = "settings.ai.defaultOutputScale"
    static let denoiseStrength = "settings.ai.denoiseStrength"
    static let detailEnhance = "settings.ai.detailEnhance"
    static let sharpen = "settings.ai.sharpen"
    static let multiFrameFusion = "settings.ai.multiFrameFusion"
    static let motionSubjectProtect = "settings.ai.motionSubjectProtect"
    static let highlightRecovery = "settings.ai.highlightRecovery"
    static let shadowRecovery = "settings.ai.shadowRecovery"
    static let backlightOptimize = "settings.ai.backlightOptimize"
    static let portraitRepair = "settings.ai.portraitRepair"
    static let skinTexture = "settings.ai.skinTexture"
    static let architectureTexture = "settings.ai.architectureTexture"
    static let textEnhance = "settings.ai.textEnhance"
    static let moireReduction = "settings.ai.moireReduction"
    static let reflectionRemoval = "settings.ai.reflectionRemoval"
    static let authenticityProtection = "settings.ai.authenticityProtection"
    static let lowConfidenceWarning = "settings.ai.lowConfidenceWarning"
    static let fallbackOnFailure = "settings.ai.fallbackOnFailure"
    static let keepOriginal = "settings.ai.keepOriginal"

    // Video
    static let videoCodec = "settings.video.codec"
    static let videoBitrate = "settings.video.bitrate"
    static let videoHDR = "settings.video.hdr"
    static let videoColorSpace = "settings.video.colorSpace"
    static let videoStabilization = "settings.video.stabilization"
    static let videoAILevel = "settings.video.aiLevel"
    static let audioSource = "settings.video.audioSource"
    static let windNoiseReduction = "settings.video.windNoiseReduction"
    static let lockExposureWhileRecording = "settings.video.lockExposure"
    static let estimateFileSize = "settings.video.estimateFileSize"
    static let thermalWarning = "settings.video.thermalWarning"
    static let lowStorageReminder = "settings.video.lowStorageReminder"
    static let interruptRecovery = "settings.video.interruptRecovery"

    // Night / Moon
    static let nightMultiFrame = "settings.night.multiFrame"
    static let nightHandholdMode = "settings.night.handholdMode"
    static let nightPortrait = "settings.night.portrait"
    static let nightMotionProtect = "settings.night.motionProtect"
    static let pointSourceControl = "settings.night.pointSourceControl"
    static let shadowColor = "settings.night.shadowColor"
    static let moonAutoDetect = "settings.moon.autoDetect"
    static let moonTracking = "settings.moon.tracking"
    static let moonExposureProtect = "settings.moon.exposureProtect"
    static let moonUpscaleStrength = "settings.moon.upscaleStrength"
    static let moonAuthenticity = "settings.moon.authenticity"
    static let moonAIReconstructionHint = "settings.moon.aiReconstructionHint"
    static let moonCaptureRecipe = "settings.moon.captureRecipe"
    static let extremeZoomStabilization = "settings.moon.extremeZoomStabilization"
    static let extremeZoomWarning = "settings.moon.extremeZoomWarning"

    // Portrait / Macro
    static let skinToneStyle = "settings.portrait.skinToneStyle"
    static let portraitSkinTexture = "settings.portrait.skinTexture"
    static let bokehStrength = "settings.portrait.bokehStrength"
    static let apertureSimulation = "settings.portrait.apertureSimulation"
    static let eyeDetail = "settings.portrait.eyeDetail"
    static let hairEdge = "settings.portrait.hairEdge"
    static let backlightCompensation = "settings.portrait.backlightCompensation"
    static let macroAutoDetect = "settings.macro.autoDetect"
    static let macroFocusAssist = "settings.macro.focusAssist"
    static let macroStabilization = "settings.macro.stabilization"
    static let focusStacking = "settings.macro.focusStacking"
    static let macroMultiFrame = "settings.macro.multiFrame"
    static let insectDetail = "settings.macro.insectDetail"
    static let macroAuthenticity = "settings.macro.authenticity"

    // Architecture / Zoom
    static let archTexture = "settings.arch.texture"
    static let windowFrameLines = "settings.arch.windowFrameLines"
    static let archMoire = "settings.arch.moire"
    static let repeatTexture = "settings.arch.repeatTexture"
    static let windowPaneAuthenticity = "settings.arch.windowPaneAuthenticity"
    static let zoomCurveSensitivity = "settings.arch.zoomCurveSensitivity"
    static let dualSpeedZoom = "settings.arch.dualSpeedZoom"
    static let zoomSnapping = "settings.arch.zoomSnapping"
    static let lensSwitchTransition = "settings.arch.lensSwitchTransition"
    static let targetLock = "settings.arch.targetLock"
    static let highZoomAIStrength = "settings.arch.highZoomAIStrength"

    // Color / LUT
    static let lutManagement = "settings.lut.management"
    static let cubeImport = "settings.lut.cubeImport"
    static let lutStrength = "settings.lut.strength"
    static let colorPreset = "settings.lut.colorPreset"
    static let whiteBalanceTint = "settings.lut.whiteBalanceTint"
    static let highlightCompression = "settings.lut.highlightCompression"
    static let shadowTint = "settings.lut.shadowTint"
    static let skinProtection = "settings.lut.skinProtection"
    static let logRestore = "settings.lut.logRestore"
    static let hdrConversion = "settings.lut.hdrConversion"
    static let useP3 = "settings.lut.useP3"
    static let exportColorSpace = "settings.lut.exportColorSpace"

    // Storage
    static let saveOriginal = "settings.storage.saveOriginal"
    static let saveRAW = "settings.storage.saveRAW"
    static let saveAIProcessed = "settings.storage.saveAIProcessed"
    static let keepBeforeAfter = "settings.storage.keepBeforeAfter"
    static let thumbnailProxy = "settings.storage.thumbnailProxy"
    static let exportToLibrary = "settings.storage.exportToLibrary"
    static let preserveMetadata = "settings.storage.preserveMetadata"
    static let watermarkStyle = "settings.storage.watermarkStyle"
    static let defaultFormat = "settings.storage.defaultFormat"
    static let maxUpscalePixels = "settings.storage.maxUpscalePixels"
    static let storageWarningThreshold = "settings.storage.warningThreshold"
    static let cacheCleanupOnExit = "settings.storage.cacheCleanupOnExit"
    static let keepModelCache = "settings.storage.keepModelCache"
    static let tempFileCleanup = "settings.storage.tempFileCleanup"
    static let failedTaskCleanup = "settings.storage.failedTaskCleanup"
    static let keepExportHistory = "settings.storage.keepExportHistory"

    // Performance
    static let perfLivePreviewLevel = "settings.perf.livePreviewLevel"
    static let lowPowerDegrade = "settings.perf.lowPowerDegrade"
    static let thermalDegrade = "settings.perf.thermalDegrade"
    static let memoryPressureProtection = "settings.perf.memoryPressureProtection"
    static let aiTaskConcurrency = "settings.perf.aiTaskConcurrency"
    static let backgroundPolicy = "settings.perf.backgroundPolicy"
    static let preloadModels = "settings.perf.preloadModels"
    static let launchSpeedPriority = "settings.perf.launchSpeedPriority"
    static let batteryWarning = "settings.perf.batteryWarning"
    static let compatibilityReport = "settings.perf.compatibilityReport"
    static let runModelBenchmark = "settings.perf.runModelBenchmark"
    static let stressTestOnLaunch = "settings.perf.stressTestOnLaunch"
    static let diagnosticLogging = "settings.perf.diagnosticLogging"

    // Haptic
    static let hapticPreset = "settings.haptic.preset"
    static let hapticShutter = "settings.haptic.shutter"
    static let hapticFocus = "settings.haptic.focus"
    static let hapticMoonLock = "settings.haptic.moonLock"
    static let hapticZoomNode = "settings.haptic.zoomNode"
    static let hapticAIComplete = "settings.haptic.aiComplete"
    static let hapticExportComplete = "settings.haptic.exportComplete"
    static let hapticError = "settings.haptic.error"
}

// MARK: - Store

final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    private let defaults = UserDefaults.standard

    private init() {
        loadAll()
    }

    // MARK: - Capture Settings

    @Published var defaultMode: CaptureMode = .photo {
        didSet { defaults.set(defaultMode.rawValue, forKey: Keys.defaultMode) }
    }
    @Published var defaultAspectRatio: PhotoAspectRatio = .ratio4_3 {
        didSet { defaults.set(defaultAspectRatio.rawValue, forKey: Keys.defaultAspectRatio) }
    }
    @Published var defaultFormat: PhotoFormat = .heif {
        didSet { defaults.set(defaultFormat.rawValue, forKey: Keys.defaultFormat) }
    }
    @Published var photoResolution: String = "48MP" {
        didSet { defaults.set(photoResolution, forKey: Keys.photoResolution) }
    }
    @Published var videoResolution: String = "4K" {
        didSet { defaults.set(videoResolution, forKey: Keys.videoResolution) }
    }
    @Published var videoFrameRate: Int = 30 {
        didSet { defaults.set(videoFrameRate, forKey: Keys.videoFrameRate) }
    }
    @Published var defaultLensZoom: Double = 1.0 {
        didSet { defaults.set(defaultLensZoom, forKey: Keys.defaultLensZoom) }
    }
    @Published var burstCount: Int = 10 {
        didSet { defaults.set(burstCount, forKey: Keys.burstCount) }
    }
    @Published var shutterPriority: ExposureMode = .auto {
        didSet { defaults.set(shutterPriority.rawValue, forKey: Keys.shutterPriority) }
    }
    @Published var focusMetering: FocusMeteringMode = .center {
        didSet { defaults.set(focusMetering.rawValue, forKey: Keys.focusMetering) }
    }
    @Published var aeafLockBehavior: AEAFLockBehavior = .holdUntilTap {
        didSet { defaults.set(aeafLockBehavior.rawValue, forKey: Keys.aeafLockBehavior) }
    }
    @Published var lensSwitchStrategy: LensSwitchStrategy = .automatic {
        didSet { defaults.set(lensSwitchStrategy.rawValue, forKey: Keys.lensSwitchStrategy) }
    }
    @Published var externalLensConfigured: Bool = false {
        didSet { defaults.set(externalLensConfigured, forKey: Keys.externalLensConfigured) }
    }
    @Published var gridEnabled: Bool = false {
        didSet { defaults.set(gridEnabled, forKey: Keys.gridEnabled) }
    }
    @Published var levelEnabled: Bool = false {
        didSet { defaults.set(levelEnabled, forKey: Keys.levelEnabled) }
    }
    @Published var focusPeaking: Bool = false {
        didSet { defaults.set(focusPeaking, forKey: Keys.focusPeaking) }
    }
    @Published var zebraStripes: Bool = false {
        didSet { defaults.set(zebraStripes, forKey: Keys.zebraStripes) }
    }
    @Published var histogramEnabled: Bool = false {
        didSet { defaults.set(histogramEnabled, forKey: Keys.histogramEnabled) }
    }
    @Published var volumeKeyShutter: Bool = false {
        didSet { defaults.set(volumeKeyShutter, forKey: Keys.volumeKeyShutter) }
    }
    @Published var touchShutter: Bool = true {
        didSet { defaults.set(touchShutter, forKey: Keys.touchShutter) }
    }

    // MARK: - AI Quality Settings

    @Published var livePreviewLevel: LivePreviewLevel = .balanced {
        didSet { defaults.set(livePreviewLevel.rawValue, forKey: Keys.livePreviewLevel) }
    }
    @Published var defaultUpscaleModel: String = "通用超分 v2" {
        didSet { defaults.set(defaultUpscaleModel, forKey: Keys.defaultUpscaleModel) }
    }
    @Published var defaultOutputScale: Double = 2.0 {
        didSet { defaults.set(defaultOutputScale, forKey: Keys.defaultOutputScale) }
    }
    @Published var denoiseStrength: Double = 0.5 {
        didSet { defaults.set(denoiseStrength, forKey: Keys.denoiseStrength) }
    }
    @Published var detailEnhance: Double = 0.5 {
        didSet { defaults.set(detailEnhance, forKey: Keys.detailEnhance) }
    }
    @Published var sharpen: Double = 0.4 {
        didSet { defaults.set(sharpen, forKey: Keys.sharpen) }
    }
    @Published var multiFrameFusion: Bool = true {
        didSet { defaults.set(multiFrameFusion, forKey: Keys.multiFrameFusion) }
    }
    @Published var motionSubjectProtect: Bool = true {
        didSet { defaults.set(motionSubjectProtect, forKey: Keys.motionSubjectProtect) }
    }
    @Published var highlightRecovery: Double = 0.4 {
        didSet { defaults.set(highlightRecovery, forKey: Keys.highlightRecovery) }
    }
    @Published var shadowRecovery: Double = 0.4 {
        didSet { defaults.set(shadowRecovery, forKey: Keys.shadowRecovery) }
    }
    @Published var backlightOptimize: Bool = true {
        didSet { defaults.set(backlightOptimize, forKey: Keys.backlightOptimize) }
    }
    @Published var portraitRepair: Bool = true {
        didSet { defaults.set(portraitRepair, forKey: Keys.portraitRepair) }
    }
    @Published var skinTexture: Double = 0.5 {
        didSet { defaults.set(skinTexture, forKey: Keys.skinTexture) }
    }
    @Published var architectureTexture: Double = 0.6 {
        didSet { defaults.set(architectureTexture, forKey: Keys.architectureTexture) }
    }
    @Published var textEnhance: Double = 0.5 {
        didSet { defaults.set(textEnhance, forKey: Keys.textEnhance) }
    }
    @Published var moireReduction: Double = 0.5 {
        didSet { defaults.set(moireReduction, forKey: Keys.moireReduction) }
    }
    @Published var reflectionRemoval: Double = 0.5 {
        didSet { defaults.set(reflectionRemoval, forKey: Keys.reflectionRemoval) }
    }
    @Published var authenticityProtection: Double = 0.8 {
        didSet { defaults.set(authenticityProtection, forKey: Keys.authenticityProtection) }
    }
    @Published var lowConfidenceWarning: Bool = true {
        didSet { defaults.set(lowConfidenceWarning, forKey: Keys.lowConfidenceWarning) }
    }
    @Published var fallbackOnFailure: Bool = true {
        didSet { defaults.set(fallbackOnFailure, forKey: Keys.fallbackOnFailure) }
    }
    @Published var keepOriginal: Bool = true {
        didSet { defaults.set(keepOriginal, forKey: Keys.keepOriginal) }
    }

    // MARK: - Video Settings

    @Published var videoCodec: VideoCodec = .hevc {
        didSet { defaults.set(videoCodec.rawValue, forKey: Keys.videoCodec) }
    }
    @Published var videoBitrate: Int = 20_000_000 {
        didSet { defaults.set(videoBitrate, forKey: Keys.videoBitrate) }
    }
    @Published var videoHDR: Bool = true {
        didSet { defaults.set(videoHDR, forKey: Keys.videoHDR) }
    }
    @Published var videoColorSpace: ColorSpace = .p3 {
        didSet { defaults.set(videoColorSpace.rawValue, forKey: Keys.videoColorSpace) }
    }
    @Published var videoStabilization: VideoStabilization = .standard {
        didSet { defaults.set(videoStabilization.rawValue, forKey: Keys.videoStabilization) }
    }
    @Published var videoAILevel: LivePreviewLevel = .smooth {
        didSet { defaults.set(videoAILevel.rawValue, forKey: Keys.videoAILevel) }
    }
    @Published var audioSource: AudioSource = .microphone {
        didSet { defaults.set(audioSource.rawValue, forKey: Keys.audioSource) }
    }
    @Published var windNoiseReduction: Bool = true {
        didSet { defaults.set(windNoiseReduction, forKey: Keys.windNoiseReduction) }
    }
    @Published var lockExposureWhileRecording: Bool = false {
        didSet { defaults.set(lockExposureWhileRecording, forKey: Keys.lockExposureWhileRecording) }
    }
    @Published var estimateFileSize: Bool = true {
        didSet { defaults.set(estimateFileSize, forKey: Keys.estimateFileSize) }
    }
    @Published var thermalWarning: Bool = true {
        didSet { defaults.set(thermalWarning, forKey: Keys.thermalWarning) }
    }
    @Published var lowStorageReminder: Bool = true {
        didSet { defaults.set(lowStorageReminder, forKey: Keys.lowStorageReminder) }
    }
    @Published var interruptRecovery: Bool = true {
        didSet { defaults.set(interruptRecovery, forKey: Keys.interruptRecovery) }
    }

    // MARK: - Night & Super Moon Settings

    @Published var nightMultiFrame: Bool = true {
        didSet { defaults.set(nightMultiFrame, forKey: Keys.nightMultiFrame) }
    }
    @Published var nightHandholdMode: NightHandholdMode = .handheld {
        didSet { defaults.set(nightHandholdMode.rawValue, forKey: Keys.nightHandholdMode) }
    }
    @Published var nightPortrait: Bool = true {
        didSet { defaults.set(nightPortrait, forKey: Keys.nightPortrait) }
    }
    @Published var nightMotionProtect: Bool = true {
        didSet { defaults.set(nightMotionProtect, forKey: Keys.nightMotionProtect) }
    }
    @Published var pointSourceControl: Bool = true {
        didSet { defaults.set(pointSourceControl, forKey: Keys.pointSourceControl) }
    }
    @Published var shadowColor: Double = 0.4 {
        didSet { defaults.set(shadowColor, forKey: Keys.shadowColor) }
    }
    @Published var moonAutoDetect: Bool = true {
        didSet { defaults.set(moonAutoDetect, forKey: Keys.moonAutoDetect) }
    }
    @Published var moonTracking: Bool = true {
        didSet { defaults.set(moonTracking, forKey: Keys.moonTracking) }
    }
    @Published var moonExposureProtect: Double = 0.5 {
        didSet { defaults.set(moonExposureProtect, forKey: Keys.moonExposureProtect) }
    }
    @Published var moonUpscaleStrength: Double = 0.6 {
        didSet { defaults.set(moonUpscaleStrength, forKey: Keys.moonUpscaleStrength) }
    }
    @Published var moonAuthenticity: Double = 0.8 {
        didSet { defaults.set(moonAuthenticity, forKey: Keys.moonAuthenticity) }
    }
    @Published var moonAIReconstructionHint: Bool = true {
        didSet { defaults.set(moonAIReconstructionHint, forKey: Keys.moonAIReconstructionHint) }
    }
    @Published var moonCaptureRecipe: String = "标准月面" {
        didSet { defaults.set(moonCaptureRecipe, forKey: Keys.moonCaptureRecipe) }
    }
    @Published var extremeZoomStabilization: Bool = true {
        didSet { defaults.set(extremeZoomStabilization, forKey: Keys.extremeZoomStabilization) }
    }
    @Published var extremeZoomWarning: Bool = true {
        didSet { defaults.set(extremeZoomWarning, forKey: Keys.extremeZoomWarning) }
    }

    // MARK: - Portrait & Macro Settings

    @Published var skinToneStyle: SkinToneStyle = .natural {
        didSet { defaults.set(skinToneStyle.rawValue, forKey: Keys.skinToneStyle) }
    }
    @Published var portraitSkinTexture: Double = 0.5 {
        didSet { defaults.set(portraitSkinTexture, forKey: Keys.portraitSkinTexture) }
    }
    @Published var bokehStrength: Double = 0.6 {
        didSet { defaults.set(bokehStrength, forKey: Keys.bokehStrength) }
    }
    @Published var apertureSimulation: Double = 2.8 {
        didSet { defaults.set(apertureSimulation, forKey: Keys.apertureSimulation) }
    }
    @Published var eyeDetail: Bool = true {
        didSet { defaults.set(eyeDetail, forKey: Keys.eyeDetail) }
    }
    @Published var hairEdge: Bool = true {
        didSet { defaults.set(hairEdge, forKey: Keys.hairEdge) }
    }
    @Published var backlightCompensation: Bool = true {
        didSet { defaults.set(backlightCompensation, forKey: Keys.backlightCompensation) }
    }
    @Published var macroAutoDetect: Bool = true {
        didSet { defaults.set(macroAutoDetect, forKey: Keys.macroAutoDetect) }
    }
    @Published var macroFocusAssist: Bool = true {
        didSet { defaults.set(macroFocusAssist, forKey: Keys.macroFocusAssist) }
    }
    @Published var macroStabilization: Bool = true {
        didSet { defaults.set(macroStabilization, forKey: Keys.macroStabilization) }
    }
    @Published var focusStacking: Bool = false {
        didSet { defaults.set(focusStacking, forKey: Keys.focusStacking) }
    }
    @Published var macroMultiFrame: Bool = true {
        didSet { defaults.set(macroMultiFrame, forKey: Keys.macroMultiFrame) }
    }
    @Published var insectDetail: Bool = false {
        didSet { defaults.set(insectDetail, forKey: Keys.insectDetail) }
    }
    @Published var macroAuthenticity: Double = 0.8 {
        didSet { defaults.set(macroAuthenticity, forKey: Keys.macroAuthenticity) }
    }

    // MARK: - Architecture & Zoom Settings

    @Published var archTexture: Double = 0.6 {
        didSet { defaults.set(archTexture, forKey: Keys.archTexture) }
    }
    @Published var windowFrameLines: Bool = true {
        didSet { defaults.set(windowFrameLines, forKey: Keys.windowFrameLines) }
    }
    @Published var archMoire: Double = 0.5 {
        didSet { defaults.set(archMoire, forKey: Keys.archMoire) }
    }
    @Published var repeatTexture: Double = 0.5 {
        didSet { defaults.set(repeatTexture, forKey: Keys.repeatTexture) }
    }
    @Published var windowPaneAuthenticity: Double = 0.8 {
        didSet { defaults.set(windowPaneAuthenticity, forKey: Keys.windowPaneAuthenticity) }
    }
    @Published var zoomCurveSensitivity: Double = 0.5 {
        didSet { defaults.set(zoomCurveSensitivity, forKey: Keys.zoomCurveSensitivity) }
    }
    @Published var dualSpeedZoom: Bool = true {
        didSet { defaults.set(dualSpeedZoom, forKey: Keys.dualSpeedZoom) }
    }
    @Published var zoomSnapping: Bool = true {
        didSet { defaults.set(zoomSnapping, forKey: Keys.zoomSnapping) }
    }
    @Published var lensSwitchTransition: Double = 0.3 {
        didSet { defaults.set(lensSwitchTransition, forKey: Keys.lensSwitchTransition) }
    }
    @Published var targetLock: Bool = false {
        didSet { defaults.set(targetLock, forKey: Keys.targetLock) }
    }
    @Published var highZoomAIStrength: Double = 0.7 {
        didSet { defaults.set(highZoomAIStrength, forKey: Keys.highZoomAIStrength) }
    }

    // MARK: - Color / LUT Settings

    @Published var lutManagement: Bool = true {
        didSet { defaults.set(lutManagement, forKey: Keys.lutManagement) }
    }
    @Published var cubeImport: Bool = true {
        didSet { defaults.set(cubeImport, forKey: Keys.cubeImport) }
    }
    @Published var lutStrength: Double = 0.5 {
        didSet { defaults.set(lutStrength, forKey: Keys.lutStrength) }
    }
    @Published var colorPreset: String = "标准" {
        didSet { defaults.set(colorPreset, forKey: Keys.colorPreset) }
    }
    @Published var whiteBalanceTint: Int = 5500 {
        didSet { defaults.set(whiteBalanceTint, forKey: Keys.whiteBalanceTint) }
    }
    @Published var highlightCompression: Double = 0.3 {
        didSet { defaults.set(highlightCompression, forKey: Keys.highlightCompression) }
    }
    @Published var shadowTint: Double = 0.3 {
        didSet { defaults.set(shadowTint, forKey: Keys.shadowTint) }
    }
    @Published var skinProtection: Double = 0.6 {
        didSet { defaults.set(skinProtection, forKey: Keys.skinProtection) }
    }
    @Published var logRestore: Bool = false {
        didSet { defaults.set(logRestore, forKey: Keys.logRestore) }
    }
    @Published var hdrConversion: Bool = true {
        didSet { defaults.set(hdrConversion, forKey: Keys.hdrConversion) }
    }
    @Published var useP3: Bool = true {
        didSet { defaults.set(useP3, forKey: Keys.useP3) }
    }
    @Published var exportColorSpace: ColorSpace = .p3 {
        didSet { defaults.set(exportColorSpace.rawValue, forKey: Keys.exportColorSpace) }
    }

    // MARK: - Storage Settings

    @Published var saveOriginal: Bool = true {
        didSet { defaults.set(saveOriginal, forKey: Keys.saveOriginal) }
    }
    @Published var saveRAW: Bool = false {
        didSet { defaults.set(saveRAW, forKey: Keys.saveRAW) }
    }
    @Published var saveAIProcessed: Bool = true {
        didSet { defaults.set(saveAIProcessed, forKey: Keys.saveAIProcessed) }
    }
    @Published var keepBeforeAfter: Bool = false {
        didSet { defaults.set(keepBeforeAfter, forKey: Keys.keepBeforeAfter) }
    }
    @Published var thumbnailProxy: Bool = true {
        didSet { defaults.set(thumbnailProxy, forKey: Keys.thumbnailProxy) }
    }
    @Published var exportToLibrary: Bool = true {
        didSet { defaults.set(exportToLibrary, forKey: Keys.exportToLibrary) }
    }
    @Published var preserveMetadata: Bool = true {
        didSet { defaults.set(preserveMetadata, forKey: Keys.preserveMetadata) }
    }
    @Published var watermarkStyle: WatermarkStyle = .none {
        didSet { defaults.set(watermarkStyle.rawValue, forKey: Keys.watermarkStyle) }
    }
    @Published var defaultStorageFormat: PhotoFormat = .heif {
        didSet { defaults.set(defaultStorageFormat.rawValue, forKey: Keys.defaultFormat) }
    }
    @Published var maxUpscalePixels: Int = 120_000_000 {
        didSet { defaults.set(maxUpscalePixels, forKey: Keys.maxUpscalePixels) }
    }
    @Published var storageWarningThreshold: Int64 = 1_000_000_000 {
        didSet { defaults.set(storageWarningThreshold, forKey: Keys.storageWarningThreshold) }
    }
    @Published var cacheCleanupOnExit: Bool = true {
        didSet { defaults.set(cacheCleanupOnExit, forKey: Keys.cacheCleanupOnExit) }
    }
    @Published var keepModelCache: Bool = true {
        didSet { defaults.set(keepModelCache, forKey: Keys.keepModelCache) }
    }
    @Published var tempFileCleanup: Bool = true {
        didSet { defaults.set(tempFileCleanup, forKey: Keys.tempFileCleanup) }
    }
    @Published var failedTaskCleanup: Bool = true {
        didSet { defaults.set(failedTaskCleanup, forKey: Keys.failedTaskCleanup) }
    }
    @Published var keepExportHistory: Bool = true {
        didSet { defaults.set(keepExportHistory, forKey: Keys.keepExportHistory) }
    }

    // MARK: - Performance Settings

    @Published var perfLivePreviewLevel: LivePreviewLevel = .balanced {
        didSet { defaults.set(perfLivePreviewLevel.rawValue, forKey: Keys.perfLivePreviewLevel) }
    }
    @Published var lowPowerDegrade: Bool = true {
        didSet { defaults.set(lowPowerDegrade, forKey: Keys.lowPowerDegrade) }
    }
    @Published var thermalDegrade: Bool = true {
        didSet { defaults.set(thermalDegrade, forKey: Keys.thermalDegrade) }
    }
    @Published var memoryPressureProtection: Bool = true {
        didSet { defaults.set(memoryPressureProtection, forKey: Keys.memoryPressureProtection) }
    }
    @Published var aiTaskConcurrency: Int = 2 {
        didSet { defaults.set(aiTaskConcurrency, forKey: Keys.aiTaskConcurrency) }
    }
    @Published var backgroundPolicy: BackgroundPolicy = .finishCurrent {
        didSet { defaults.set(backgroundPolicy.rawValue, forKey: Keys.backgroundPolicy) }
    }
    @Published var preloadModels: Bool = true {
        didSet { defaults.set(preloadModels, forKey: Keys.preloadModels) }
    }
    @Published var launchSpeedPriority: Bool = false {
        didSet { defaults.set(launchSpeedPriority, forKey: Keys.launchSpeedPriority) }
    }
    @Published var batteryWarning: Bool = true {
        didSet { defaults.set(batteryWarning, forKey: Keys.batteryWarning) }
    }
    @Published var compatibilityReport: Bool = true {
        didSet { defaults.set(compatibilityReport, forKey: Keys.compatibilityReport) }
    }
    @Published var runModelBenchmark: Bool = false {
        didSet { defaults.set(runModelBenchmark, forKey: Keys.runModelBenchmark) }
    }
    @Published var stressTestOnLaunch: Bool = false {
        didSet { defaults.set(stressTestOnLaunch, forKey: Keys.stressTestOnLaunch) }
    }
    @Published var diagnosticLogging: Bool = true {
        didSet { defaults.set(diagnosticLogging, forKey: Keys.diagnosticLogging) }
    }

    // MARK: - Haptic Settings

    @Published var hapticPreset: HapticPreset = .camera {
        didSet { defaults.set(hapticPreset.rawValue, forKey: Keys.hapticPreset) }
    }
    @Published var hapticShutter: Bool = true {
        didSet { defaults.set(hapticShutter, forKey: Keys.hapticShutter) }
    }
    @Published var hapticFocus: Bool = true {
        didSet { defaults.set(hapticFocus, forKey: Keys.hapticFocus) }
    }
    @Published var hapticMoonLock: Bool = true {
        didSet { defaults.set(hapticMoonLock, forKey: Keys.hapticMoonLock) }
    }
    @Published var hapticZoomNode: Bool = true {
        didSet { defaults.set(hapticZoomNode, forKey: Keys.hapticZoomNode) }
    }
    @Published var hapticAIComplete: Bool = true {
        didSet { defaults.set(hapticAIComplete, forKey: Keys.hapticAIComplete) }
    }
    @Published var hapticExportComplete: Bool = true {
        didSet { defaults.set(hapticExportComplete, forKey: Keys.hapticExportComplete) }
    }
    @Published var hapticError: Bool = true {
        didSet { defaults.set(hapticError, forKey: Keys.hapticError) }
    }

    // MARK: - Loading

    private func loadAll() {
        defaultMode = CaptureMode(rawValue: defaults.string(forKey: Keys.defaultMode) ?? "") ?? .photo
        defaultAspectRatio = PhotoAspectRatio(rawValue: defaults.string(forKey: Keys.defaultAspectRatio) ?? "") ?? .ratio4_3
        defaultFormat = PhotoFormat(rawValue: defaults.string(forKey: Keys.defaultFormat) ?? "") ?? .heif
        photoResolution = defaults.string(forKey: Keys.photoResolution) ?? "48MP"
        videoResolution = defaults.string(forKey: Keys.videoResolution) ?? "4K"
        videoFrameRate = defaults.integer(forKey: Keys.videoFrameRate, fallback: 30)
        defaultLensZoom = defaults.double(forKey: Keys.defaultLensZoom, fallback: 1.0)
        burstCount = defaults.integer(forKey: Keys.burstCount, fallback: 10)
        shutterPriority = ExposureMode(rawValue: defaults.string(forKey: Keys.shutterPriority) ?? "") ?? .auto
        focusMetering = FocusMeteringMode(rawValue: defaults.string(forKey: Keys.focusMetering) ?? "") ?? .center
        aeafLockBehavior = AEAFLockBehavior(rawValue: defaults.string(forKey: Keys.aeafLockBehavior) ?? "") ?? .holdUntilTap
        lensSwitchStrategy = LensSwitchStrategy(rawValue: defaults.string(forKey: Keys.lensSwitchStrategy) ?? "") ?? .automatic
        externalLensConfigured = defaults.bool(forKey: Keys.externalLensConfigured)
        gridEnabled = defaults.bool(forKey: Keys.gridEnabled)
        levelEnabled = defaults.bool(forKey: Keys.levelEnabled)
        focusPeaking = defaults.bool(forKey: Keys.focusPeaking)
        zebraStripes = defaults.bool(forKey: Keys.zebraStripes)
        histogramEnabled = defaults.bool(forKey: Keys.histogramEnabled)
        volumeKeyShutter = defaults.bool(forKey: Keys.volumeKeyShutter)
        touchShutter = defaults.bool(forKey: Keys.touchShutter, fallback: true)

        livePreviewLevel = LivePreviewLevel(rawValue: defaults.string(forKey: Keys.livePreviewLevel) ?? "") ?? .balanced
        defaultUpscaleModel = defaults.string(forKey: Keys.defaultUpscaleModel) ?? "通用超分 v2"
        defaultOutputScale = defaults.double(forKey: Keys.defaultOutputScale, fallback: 2.0)
        denoiseStrength = defaults.double(forKey: Keys.denoiseStrength, fallback: 0.5)
        detailEnhance = defaults.double(forKey: Keys.detailEnhance, fallback: 0.5)
        sharpen = defaults.double(forKey: Keys.sharpen, fallback: 0.4)
        multiFrameFusion = defaults.bool(forKey: Keys.multiFrameFusion, fallback: true)
        motionSubjectProtect = defaults.bool(forKey: Keys.motionSubjectProtect, fallback: true)
        highlightRecovery = defaults.double(forKey: Keys.highlightRecovery, fallback: 0.4)
        shadowRecovery = defaults.double(forKey: Keys.shadowRecovery, fallback: 0.4)
        backlightOptimize = defaults.bool(forKey: Keys.backlightOptimize, fallback: true)
        portraitRepair = defaults.bool(forKey: Keys.portraitRepair, fallback: true)
        skinTexture = defaults.double(forKey: Keys.skinTexture, fallback: 0.5)
        architectureTexture = defaults.double(forKey: Keys.architectureTexture, fallback: 0.6)
        textEnhance = defaults.double(forKey: Keys.textEnhance, fallback: 0.5)
        moireReduction = defaults.double(forKey: Keys.moireReduction, fallback: 0.5)
        reflectionRemoval = defaults.double(forKey: Keys.reflectionRemoval, fallback: 0.5)
        authenticityProtection = defaults.double(forKey: Keys.authenticityProtection, fallback: 0.8)
        lowConfidenceWarning = defaults.bool(forKey: Keys.lowConfidenceWarning, fallback: true)
        fallbackOnFailure = defaults.bool(forKey: Keys.fallbackOnFailure, fallback: true)
        keepOriginal = defaults.bool(forKey: Keys.keepOriginal, fallback: true)

        videoCodec = VideoCodec(rawValue: defaults.string(forKey: Keys.videoCodec) ?? "") ?? .hevc
        videoBitrate = defaults.integer(forKey: Keys.videoBitrate, fallback: 20_000_000)
        videoHDR = defaults.bool(forKey: Keys.videoHDR, fallback: true)
        videoColorSpace = ColorSpace(rawValue: defaults.string(forKey: Keys.videoColorSpace) ?? "") ?? .p3
        videoStabilization = VideoStabilization(rawValue: defaults.string(forKey: Keys.videoStabilization) ?? "") ?? .standard
        videoAILevel = LivePreviewLevel(rawValue: defaults.string(forKey: Keys.videoAILevel) ?? "") ?? .smooth
        audioSource = AudioSource(rawValue: defaults.string(forKey: Keys.audioSource) ?? "") ?? .microphone
        windNoiseReduction = defaults.bool(forKey: Keys.windNoiseReduction, fallback: true)
        lockExposureWhileRecording = defaults.bool(forKey: Keys.lockExposureWhileRecording)
        estimateFileSize = defaults.bool(forKey: Keys.estimateFileSize, fallback: true)
        thermalWarning = defaults.bool(forKey: Keys.thermalWarning, fallback: true)
        lowStorageReminder = defaults.bool(forKey: Keys.lowStorageReminder, fallback: true)
        interruptRecovery = defaults.bool(forKey: Keys.interruptRecovery, fallback: true)

        nightMultiFrame = defaults.bool(forKey: Keys.nightMultiFrame, fallback: true)
        nightHandholdMode = NightHandholdMode(rawValue: defaults.string(forKey: Keys.nightHandholdMode) ?? "") ?? .handheld
        nightPortrait = defaults.bool(forKey: Keys.nightPortrait, fallback: true)
        nightMotionProtect = defaults.bool(forKey: Keys.nightMotionProtect, fallback: true)
        pointSourceControl = defaults.bool(forKey: Keys.pointSourceControl, fallback: true)
        shadowColor = defaults.double(forKey: Keys.shadowColor, fallback: 0.4)
        moonAutoDetect = defaults.bool(forKey: Keys.moonAutoDetect, fallback: true)
        moonTracking = defaults.bool(forKey: Keys.moonTracking, fallback: true)
        moonExposureProtect = defaults.double(forKey: Keys.moonExposureProtect, fallback: 0.5)
        moonUpscaleStrength = defaults.double(forKey: Keys.moonUpscaleStrength, fallback: 0.6)
        moonAuthenticity = defaults.double(forKey: Keys.moonAuthenticity, fallback: 0.8)
        moonAIReconstructionHint = defaults.bool(forKey: Keys.moonAIReconstructionHint, fallback: true)
        moonCaptureRecipe = defaults.string(forKey: Keys.moonCaptureRecipe) ?? "标准月面"
        extremeZoomStabilization = defaults.bool(forKey: Keys.extremeZoomStabilization, fallback: true)
        extremeZoomWarning = defaults.bool(forKey: Keys.extremeZoomWarning, fallback: true)

        skinToneStyle = SkinToneStyle(rawValue: defaults.string(forKey: Keys.skinToneStyle) ?? "") ?? .natural
        portraitSkinTexture = defaults.double(forKey: Keys.portraitSkinTexture, fallback: 0.5)
        bokehStrength = defaults.double(forKey: Keys.bokehStrength, fallback: 0.6)
        apertureSimulation = defaults.double(forKey: Keys.apertureSimulation, fallback: 2.8)
        eyeDetail = defaults.bool(forKey: Keys.eyeDetail, fallback: true)
        hairEdge = defaults.bool(forKey: Keys.hairEdge, fallback: true)
        backlightCompensation = defaults.bool(forKey: Keys.backlightCompensation, fallback: true)
        macroAutoDetect = defaults.bool(forKey: Keys.macroAutoDetect, fallback: true)
        macroFocusAssist = defaults.bool(forKey: Keys.macroFocusAssist, fallback: true)
        macroStabilization = defaults.bool(forKey: Keys.macroStabilization, fallback: true)
        focusStacking = defaults.bool(forKey: Keys.focusStacking)
        macroMultiFrame = defaults.bool(forKey: Keys.macroMultiFrame, fallback: true)
        insectDetail = defaults.bool(forKey: Keys.insectDetail)
        macroAuthenticity = defaults.double(forKey: Keys.macroAuthenticity, fallback: 0.8)

        archTexture = defaults.double(forKey: Keys.archTexture, fallback: 0.6)
        windowFrameLines = defaults.bool(forKey: Keys.windowFrameLines, fallback: true)
        archMoire = defaults.double(forKey: Keys.archMoire, fallback: 0.5)
        repeatTexture = defaults.double(forKey: Keys.repeatTexture, fallback: 0.5)
        windowPaneAuthenticity = defaults.double(forKey: Keys.windowPaneAuthenticity, fallback: 0.8)
        zoomCurveSensitivity = defaults.double(forKey: Keys.zoomCurveSensitivity, fallback: 0.5)
        dualSpeedZoom = defaults.bool(forKey: Keys.dualSpeedZoom, fallback: true)
        zoomSnapping = defaults.bool(forKey: Keys.zoomSnapping, fallback: true)
        lensSwitchTransition = defaults.double(forKey: Keys.lensSwitchTransition, fallback: 0.3)
        targetLock = defaults.bool(forKey: Keys.targetLock)
        highZoomAIStrength = defaults.double(forKey: Keys.highZoomAIStrength, fallback: 0.7)

        lutManagement = defaults.bool(forKey: Keys.lutManagement, fallback: true)
        cubeImport = defaults.bool(forKey: Keys.cubeImport, fallback: true)
        lutStrength = defaults.double(forKey: Keys.lutStrength, fallback: 0.5)
        colorPreset = defaults.string(forKey: Keys.colorPreset) ?? "标准"
        whiteBalanceTint = defaults.integer(forKey: Keys.whiteBalanceTint, fallback: 5500)
        highlightCompression = defaults.double(forKey: Keys.highlightCompression, fallback: 0.3)
        shadowTint = defaults.double(forKey: Keys.shadowTint, fallback: 0.3)
        skinProtection = defaults.double(forKey: Keys.skinProtection, fallback: 0.6)
        logRestore = defaults.bool(forKey: Keys.logRestore)
        hdrConversion = defaults.bool(forKey: Keys.hdrConversion, fallback: true)
        useP3 = defaults.bool(forKey: Keys.useP3, fallback: true)
        exportColorSpace = ColorSpace(rawValue: defaults.string(forKey: Keys.exportColorSpace) ?? "") ?? .p3

        saveOriginal = defaults.bool(forKey: Keys.saveOriginal, fallback: true)
        saveRAW = defaults.bool(forKey: Keys.saveRAW)
        saveAIProcessed = defaults.bool(forKey: Keys.saveAIProcessed, fallback: true)
        keepBeforeAfter = defaults.bool(forKey: Keys.keepBeforeAfter)
        thumbnailProxy = defaults.bool(forKey: Keys.thumbnailProxy, fallback: true)
        exportToLibrary = defaults.bool(forKey: Keys.exportToLibrary, fallback: true)
        preserveMetadata = defaults.bool(forKey: Keys.preserveMetadata, fallback: true)
        watermarkStyle = WatermarkStyle(rawValue: defaults.string(forKey: Keys.watermarkStyle) ?? "") ?? .none
        defaultStorageFormat = PhotoFormat(rawValue: defaults.string(forKey: Keys.defaultFormat) ?? "") ?? .heif
        maxUpscalePixels = defaults.integer(forKey: Keys.maxUpscalePixels, fallback: 120_000_000)
        storageWarningThreshold = defaults.object(forKey: Keys.storageWarningThreshold) as? Int64 ?? 1_000_000_000
        cacheCleanupOnExit = defaults.bool(forKey: Keys.cacheCleanupOnExit, fallback: true)
        keepModelCache = defaults.bool(forKey: Keys.keepModelCache, fallback: true)
        tempFileCleanup = defaults.bool(forKey: Keys.tempFileCleanup, fallback: true)
        failedTaskCleanup = defaults.bool(forKey: Keys.failedTaskCleanup, fallback: true)
        keepExportHistory = defaults.bool(forKey: Keys.keepExportHistory, fallback: true)

        perfLivePreviewLevel = LivePreviewLevel(rawValue: defaults.string(forKey: Keys.perfLivePreviewLevel) ?? "") ?? .balanced
        lowPowerDegrade = defaults.bool(forKey: Keys.lowPowerDegrade, fallback: true)
        thermalDegrade = defaults.bool(forKey: Keys.thermalDegrade, fallback: true)
        memoryPressureProtection = defaults.bool(forKey: Keys.memoryPressureProtection, fallback: true)
        aiTaskConcurrency = defaults.integer(forKey: Keys.aiTaskConcurrency, fallback: 2)
        backgroundPolicy = BackgroundPolicy(rawValue: defaults.string(forKey: Keys.backgroundPolicy) ?? "") ?? .finishCurrent
        preloadModels = defaults.bool(forKey: Keys.preloadModels, fallback: true)
        launchSpeedPriority = defaults.bool(forKey: Keys.launchSpeedPriority)
        batteryWarning = defaults.bool(forKey: Keys.batteryWarning, fallback: true)
        compatibilityReport = defaults.bool(forKey: Keys.compatibilityReport, fallback: true)
        runModelBenchmark = defaults.bool(forKey: Keys.runModelBenchmark)
        stressTestOnLaunch = defaults.bool(forKey: Keys.stressTestOnLaunch)
        diagnosticLogging = defaults.bool(forKey: Keys.diagnosticLogging, fallback: true)

        hapticPreset = HapticPreset(rawValue: defaults.string(forKey: Keys.hapticPreset) ?? "") ?? .camera
        hapticShutter = defaults.bool(forKey: Keys.hapticShutter, fallback: true)
        hapticFocus = defaults.bool(forKey: Keys.hapticFocus, fallback: true)
        hapticMoonLock = defaults.bool(forKey: Keys.hapticMoonLock, fallback: true)
        hapticZoomNode = defaults.bool(forKey: Keys.hapticZoomNode, fallback: true)
        hapticAIComplete = defaults.bool(forKey: Keys.hapticAIComplete, fallback: true)
        hapticExportComplete = defaults.bool(forKey: Keys.hapticExportComplete, fallback: true)
        hapticError = defaults.bool(forKey: Keys.hapticError, fallback: true)
    }

    // MARK: - Reset / Diagnostics

    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.hjdcamera.app"
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        // Re-read (now defaults) into published properties.
        loadAll()
        NotificationCenter.default.post(name: .hjdSettingsChanged, object: nil)
    }

    func exportDiagnostics() -> [String: Any] {
        return [
            "defaultMode": defaultMode.rawValue,
            "defaultFormat": defaultFormat.rawValue,
            "videoResolution": videoResolution,
            "videoFrameRate": videoFrameRate,
            "livePreviewLevel": livePreviewLevel.rawValue,
            "denoiseStrength": denoiseStrength,
            "authenticityProtection": authenticityProtection,
            "hapticPreset": hapticPreset.rawValue,
            "storageWarningThreshold": storageWarningThreshold,
            "aiTaskConcurrency": aiTaskConcurrency,
            "keepOriginal": keepOriginal,
            "diagnosticLogging": diagnosticLogging,
        ]
    }
}

// MARK: - UserDefaults helpers

private extension UserDefaults {
    func bool(forKey key: String, fallback: Bool) -> Bool {
        guard object(forKey: key) != nil else { return fallback }
        return bool(forKey: key)
    }

    func integer(forKey key: String, fallback: Int) -> Int {
        guard object(forKey: key) != nil else { return fallback }
        return integer(forKey: key)
    }

    func double(forKey key: String, fallback: Double) -> Double {
        guard object(forKey: key) != nil else { return fallback }
        return double(forKey: key)
    }
}
