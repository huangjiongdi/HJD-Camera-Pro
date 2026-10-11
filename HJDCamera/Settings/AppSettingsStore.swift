import Foundation
import SwiftUI
import Combine

// MARK: - 设置存储（功能开关 + 偏好）

final class AppSettingsStore: ObservableObject {

    // 20 项差异化功能开关
    @Published var aiMomentEnabled = true
    @Published var multiCamFusionEnabled = true
    @Published var predictiveTrackingEnabled = true
    @Published var realityMapEnabled = true
    @Published var rawPlusEnabled = true
    @Published var depthStudioEnabled = true
    @Published var computationalShutterEnabled = true
    @Published var cameraCoachEnabled = true
    @Published var atmosphereRestoreEnabled = true
    @Published var videoDirectorEnabled = true
    @Published var oneShotMultiCropEnabled = false
    @Published var blindCaptureEnabled = false
    @Published var hapticLanguageEnabled = true
    @Published var flickerRadarEnabled = true
    @Published var colorMatchEnabled = false
    @Published var lensProfileEnabled = false
    @Published var capturePlaybackEnabled = false
    @Published var privacyShutterEnabled = true
    @Published var aiStoryEnabled = true
    @Published var cameraHealthCenterEnabled = true

    // 拍摄偏好
    @Published var saveOriginal = true
    @Published var saveAIResult = true
    @Published var autoSwitchLens = true
    @Published var lidarLensSwitch = true
    @Published var realtimeEnhance = false
    @Published var autoNight = true
    @Published var moonGuard = true
    @Published var hapticEnabled = true

    // 变焦显示
    @Published var zoomDisplay: ZoomDisplayMode = .multiplier

    // 水印
    @Published var watermarkEnabled = false
    @Published var watermarkBrand = "苹果"
    let watermarkBrands = ["OPPO", "一加", "vivo", "小米", "华为",
                           "苹果", "荣耀", "三星", "谷歌"]

    // EXIF 模式
    @Published var customEXIF = false

    // 视频偏好
    @Published var spatialAudio = false
    @Published var antiWindNoise = true
}
