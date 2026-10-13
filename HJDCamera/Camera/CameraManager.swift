//
//  CameraManager.swift
//  HJD Camera Pro
//
//  Central capture session owner. Owns the AVCaptureSession, the virtual
//  triple-camera device, and the photo / movie / video-data outputs. Performs
//  display-zoom -> hardware videoZoomFactor mapping (including the special
//  0.5x ultra-wide case) and keeps capture connections rotated with the device.
//

import AVFoundation
import UIKit
import SwiftUI
import Combine
import CoreGraphics
import CoreImage

final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    // MARK: - Published state

    let session = AVCaptureSession()
    @Published var currentDevice: AVCaptureDevice?
    @Published var photoOutput = AVCapturePhotoOutput()
    @Published var movieOutput = AVCaptureMovieFileOutput()
    @Published var videoDataOutput = AVCaptureVideoDataOutput()
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    /// 数字裁切倍率（>硬件上限后），由 SwiftUI 层 scaleEffect 驱动，确保 100×
    /// 以上的数字变焦在每帧重布局下都不会被重置（直接改 previewLayer.transform
    /// 会被 SwiftUI 布局冲掉，真机表现为最高卡在 100×）。
    @Published var digitalCropScale: CGFloat = 1.0
    @Published var isSessionRunning = false
    /// The display zoom factor (what the UI shows: 0.5 / 1 / 2 / 5 / 10 / ... / 500).
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var zoomSource: ZoomSource = .optical
    @Published var usingFrontCamera = false
    /// HUD 上显示的当前实际镜头（超广角 / 主摄 / 主摄 2× / 潜望长焦 / 数字）。
    @Published var activeLensLabel: String = "主摄"
    @Published var activeFocalText: String = "24mm"

    // MARK: - Private

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private let sessionQueue = DispatchQueue(label: "com.hjd.camera.session", qos: .userInitiated)
    // Live AI frames run on a dedicated queue so heavy per-frame Core Image work
    // never blocks lens switching / session reconfiguration on sessionQueue.
    private let videoDataQueue = DispatchQueue(label: "com.hjd.camera.videodata", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    private let health = CameraHealthMonitor.shared

    private override init() {
        super.init()
        observeOrientation()
    }

    // MARK: - Session lifecycle

    func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isConfigured else {
                if !self.session.isRunning { self.startSession() }
                return
            }
            self.session.beginConfiguration()
            // Use a steady, video-capable preset for the whole session.
            // `.photo` is stills-only and incompatible with AVCaptureMovieFileOutput
            // (which crashed the app when a take ended and the preset was switched);
            // AVCapturePhotoOutput still captures full-resolution stills under `.high`.
            self.session.sessionPreset = .high

            self.attachDeviceInput(self.usingFrontCamera
                                    ? DeviceCapabilityManager.shared.frontCamera
                                    : DeviceCapabilityManager.shared.virtualDevice)

            // Photo output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            // Movie output
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }

            // Video data output (used for live AI preview / analysis)
            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataQueue)
            }

            self.session.commitConfiguration()
            self.isConfigured = true
            self.applyCurrentOrientation()
            // Open on the MAIN lens (display 1x), not the ultra-wide. On a
            // virtual triple camera hardware factor 1.0 is the ultra-wide, so
            // the correct 1x wide lens must be selected explicitly.
            self.applyZoomLocked(self.currentZoomFactor)
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            do {
                try self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                    self.health.clearStartupError()
                }
            } catch {
                self.health.recordStartupFailure(error)
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    // MARK: - Device switching

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.usingFrontCamera.toggle()
            self.session.beginConfiguration()
            if let existing = self.videoDeviceInput {
                self.session.removeInput(existing)
            }
            let device = self.usingFrontCamera
                ? DeviceCapabilityManager.shared.frontCamera
                : DeviceCapabilityManager.shared.virtualDevice
            self.attachDeviceInput(device)
            self.session.commitConfiguration()
            self.applyCurrentOrientation()
            // Reset to 1x and explicitly select the new camera's default lens.
            self.applyDigitalCrop(1.0)
            self.currentDigitalCrop = 1.0
            self.applyZoomLocked(1.0)
            DispatchQueue.main.async {
                self.currentZoomFactor = 1.0
                self.zoomSource = .optical
                AppState.shared.setZoom(1.0, source: .optical)
            }
        }
    }

    private func attachDeviceInput(_ device: AVCaptureDevice?) {
        guard let device = device else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return }
            session.addInput(input)
            videoDeviceInput = input
            currentDevice = device
        } catch {
            health.recordStartupFailure(error)
        }
    }

    // MARK: - Zoom mapping (display -> hardware)

    /// 当前设备的镜头档案（16 Pro Max 校准）。所有倍率坐标都从设备真实的
    /// virtualDeviceSwitchOverVideoZoomFactors 推导，不硬编码 ×2。
    var lensProfile: DeviceLensProfile {
        guard let device = currentDevice else {
            return DeviceLensProfile(displayToHardware: 1, switchOverHardware: [],
                                     isVirtual: false, maxHardwareDisplayZoom: 10,
                                     isBack: !usingFrontCamera)
        }
        return DeviceLensProfile.profile(for: device, isBack: !usingFrontCamera)
    }

    /// Maps a display zoom factor (0.5 … 500) to the hardware
    /// `videoZoomFactor`, clamped to the device's real range.
    func hardwareZoomFactor(forDisplayZoom displayZoom: CGFloat) -> CGFloat {
        guard let device = currentDevice else { return 1.0 }
        return lensProfile.hardwareZoom(forDisplay: displayZoom, on: device)
    }

    /// Largest display zoom the hardware alone can reach on the active device.
    var maxHardwareDisplayZoom: CGFloat {
        lensProfile.maxHardwareDisplayZoom
    }

    /// Additional software crop factor used once the hardware zoom is maxed.
    /// Returned in DISPLAY space so the UI always reaches 500×.
    func digitalCropFactor(forDisplayZoom displayZoom: CGFloat) -> CGFloat {
        lensProfile.digitalCrop(forDisplay: displayZoom)
    }

    /// Digital crop factor for the most recently requested display zoom —
    /// used by the still pipeline to crop the captured photo at high zoom.
    private(set) var currentDigitalCrop: CGFloat = 1.0

    func zoomSource(forDisplayZoom displayZoom: CGFloat) -> ZoomSource {
        if displayZoom >= 100 { return .ai }
        if displayZoom > maxHardwareDisplayZoom { return .digital }
        // 镜头切换点之前都是真实光学镜头；主摄 2× 传感器裁切与跨焦段之间标混合。
        switch lensProfile.activeLens(forDisplay: displayZoom) {
        case .wideCrop2x, .telephoto: return .hybrid
        default: return .optical
        }
    }

    /// Set the hardware videoZoomFactor while the device is already locked.
    private func applyZoomLocked(_ displayZoom: CGFloat) {
        guard let device = currentDevice else { return }
        let hw = hardwareZoomFactor(forDisplayZoom: displayZoom)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = hw
            device.unlockForConfiguration()
            publishLensState(displayZoom)
        } catch {
            health.recordStartupFailure(error)
        }
    }

    // MARK: - Smooth non-linear fly-zoom (CADisplayLink driven)

    /// 逐帧丝滑变焦驱动。每一帧同时插值「显示倍率 → 硬件 videoZoomFactor +
    /// 预览数字裁切 transform + 倍率数字」，因此跨越超广角/主摄/长焦虚拟镜头
    /// 切换点以及硬件上限（进入 50×–500× 数字裁切区）时都不会跳变，
    /// 500×↔0.5× 全程超级丝滑。
    private var zoomDisplayLink: CADisplayLink?
    private var flyStartZoom: CGFloat = 1.0
    private var flyTargetZoom: CGFloat = 1.0
    private var flyStartTime: CFTimeInterval = 0
    private var flyDuration: CFTimeInterval = 0.55

    /// Set the display zoom factor immediately (follows the finger during a
    /// drag). Hardware part is clamped to the device; any remaining factor is a
    /// preview-layer digital crop so the UI always reaches 500×.
    func setZoomFactor(_ displayZoom: CGFloat) {
        stopFlyDriver()
        pushZoomFrame(min(max(displayZoom, 0.5), 500.0))
    }

    /// Smoothly fly to a display zoom factor. Used by zoom-button taps and
    /// slider release so ANY change (including 500×↔0.5×) is super smooth.
    /// `rate` is kept for source compatibility; it maps to a duration.
    func rampZoom(to displayZoom: CGFloat, rate: CGFloat = 5.0) {
        let duration = min(max(CGFloat(1.35 / max(rate, 0.1)), 0.28), 0.7)
        flyZoom(to: displayZoom, duration: duration)
    }

    /// Eased, frame-by-frame fly across the FULL 0.5×–500× range.
    func flyZoom(to displayZoom: CGFloat, duration: CGFloat = 0.55) {
        let target = min(max(displayZoom, 0.5), 500.0)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Cancel any hardware ramp so the display link owns every frame.
            self.stopHardwareRamp()
            self.flyStartZoom = self.currentZoomFactor
            self.flyTargetZoom = target
            self.flyDuration = CFTimeInterval(max(0.08, duration))
            self.flyStartTime = CACurrentMediaTime()
            if self.zoomDisplayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(self.flyTick(_:)))
                link.add(to: .main, forMode: .common)
                self.zoomDisplayLink = link
            }
        }
    }

    @objc private func flyTick(_ link: CADisplayLink) {
        let elapsed = link.timestamp - flyStartTime
        var t = flyDuration > 0 ? CGFloat(elapsed / flyDuration) : 1.0
        t = min(max(t, 0), 1)
        // easeInOutCubic：起步/收尾轻柔，中间连贯，保证“超级丝滑”。
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let z = flyStartZoom + (flyTargetZoom - flyStartZoom) * e
        pushZoomFrame(z)
        if t >= 1.0 {
            pushZoomFrame(flyTargetZoom)
            stopFlyDriver()
        }
    }

    private func stopFlyDriver() {
        let invalidate = { [weak self] in
            self?.zoomDisplayLink?.invalidate()
            self?.zoomDisplayLink = nil
        }
        Thread.isMainThread ? invalidate() : DispatchQueue.main.async(execute: invalidate)
    }

    private func stopHardwareRamp() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
        }
    }

    /// Apply a single display-zoom frame: hardware factor + preview digital crop
    /// + published state. Safe to call every frame (per-frame videoZoomFactor
    /// is Apple's documented custom-zoom technique and crosses virtual lens
    /// switch-over points smoothly).
    private func pushZoomFrame(_ clamped: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            let hw = self.hardwareZoomFactor(forDisplayZoom: clamped)
            let crop = self.digitalCropFactor(forDisplayZoom: clamped)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = hw
                device.unlockForConfiguration()
            } catch {
                self.health.recordStartupFailure(error)
            }
            // 成片裁切与所见帧严格一致：每帧同步当前数字裁切倍率。
            self.currentDigitalCrop = crop
            self.applyDigitalCrop(crop)
            DispatchQueue.main.async {
                self.currentZoomFactor = clamped
                let src = self.zoomSource(forDisplayZoom: clamped)
                self.zoomSource = src
                self.publishLensState(clamped)
                AppState.shared.setZoom(Double(clamped), source: src)
            }
        }
    }

    /// 刷新当前实际镜头名/焦距，供 HUD 显示，确保 0.5/1/2/5 走对镜头。
    /// 无论从哪个队列调用都切回主线程更新 @Published。
    private func publishLensState(_ display: CGFloat) {
        let profile = lensProfile
        let lens = profile.activeLens(forDisplay: display)
        let focal = profile.focalLengthText(forDisplay: display)
        let apply = {
            self.activeLensLabel = lens.shortName
            self.activeFocalText = focal
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    /// 数字裁切区（>硬件上限）的预览放大倍率。
    ///
    /// 不再直接修改 AVCaptureVideoPreviewLayer 的 transform：该层由 SwiftUI
    /// 每帧（currentZoomFactor 发布）重新布局，任何 transform 都会被布局冲掉，
    /// 真机表现为画面在硬件上限（约 100× 显示倍率）以上不再放大。
    /// 改为发布 digitalCropScale，由 CameraPreviewContainer 的 .scaleEffect
    /// 在 SwiftUI 层放大——scaleEffect 不参与布局，永远不会被重置。
    private func applyDigitalCrop(_ scale: CGFloat) {
        let s = max(scale, 1.0)
        if Thread.isMainThread {
            digitalCropScale = s
        } else {
            DispatchQueue.main.async {
                self.digitalCropScale = s
            }
        }
    }

    // MARK: - Capture

    func capturePhoto(tap: Int = 0) {
        // 拍照与逐帧变焦共用 sessionQueue，避免与 lockForConfiguration 竞争；
        // 也保证 AVCapturePhotoSettings 的校验在固定队列上完成。
        sessionQueue.async { [weak self] in
            guard let self = self else {
                ShutterTrace.mark(tap, "capturePhoto 已取消：CameraManager 已释放")
                return
            }

            let output = self.photoOutput
            let deviceDesc = self.currentDevice?.deviceType.rawValue ?? "nil"
            let supportedFlash = Set(output.supportedFlashModes)
            let rawFormats = output.availableRawPhotoPixelFormatTypes
            let photoFormats = output.availablePhotoPixelFormatTypes
            ShutterTrace.mark(
                tap, "进入 capturePhoto",
                extra: "设备=\(deviceDesc) 会话运行=\(self.session.isRunning) 已配置=\(self.isConfigured) photoOutput已挂载=\(self.session.outputs.contains(output)) 连接=\(output.connection(with: .video) != nil) 支持闪光=\(supportedFlash.map { $0.rawValue }) 照片格式数=\(photoFormats.count) RAW格式数=\(rawFormats.count) maxQuality=\(output.maxPhotoQualityPrioritization.rawValue)"
            )

            guard self.session.isRunning,
                  self.session.outputs.contains(output),
                  let connection = output.connection(with: .video) else {
                ShutterTrace.mark(tap, "中止：会话未运行/输出未挂载/无连接")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .hjdStorageWarning,
                                                    object: "相机尚未就绪，请稍后再试")
                }
                return
            }

            // 闪光灯必须是当前会话配置真实支持的模式。否则 capturePhoto
            // 会立即抛 NSInvalidArgumentException（虚拟三摄/前置/某些视频配置
            // 下 supportedFlashModes 可能为空或只有 .off），真机表现为一点快门
            // 就闪退。
            let wantedFlash = AppState.shared.flashMode
            let flash: AVCaptureDevice.FlashMode = supportedFlash.contains(wantedFlash)
                ? wantedFlash : .off
            if flash != wantedFlash {
                ShutterTrace.mark(tap, "闪光灯回退", extra: "想要=\(wantedFlash.rawValue) 实际=\(flash.rawValue)")
            }

            // RAW capture must use the dedicated raw initializer; `rawFileType` is
            // read-only on a normal photo settings object.
            let settings: AVCapturePhotoSettings
            if AppState.shared.rawEnabled,
               let rawFormat = rawFormats.first {
                let raw = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
                raw.flashMode = flash
                // 不设置 previewPhotoFormat——我们成片读取的是完整 fileDataRepresentation，
                // 不需要内嵌预览图；该字典在不同设备上的像素格式约束可能触发异常。
                settings = raw
            } else {
                let normal = AVCapturePhotoSettings()
                normal.flashMode = flash
                // 质量优先级不能超过当前设备/配置允许的最大值。
                if AVCapturePhotoOutput.QualityPrioritization.balanced.rawValue
                    <= output.maxPhotoQualityPrioritization.rawValue {
                    normal.photoQualityPrioritization = .balanced
                } else {
                    normal.photoQualityPrioritization = .speed
                }
                settings = normal
            }
            ShutterTrace.mark(tap, "拍照参数就绪",
                              extra: "RAW=\(settings.rawFileType != nil) 闪光=\(settings.flashMode.rawValue) 质量=\(settings.photoQualityPrioritization.rawValue)")

            if connection.isVideoRotationAngleSupported(OrientationObserver.shared.videoRotationAngle) {
                connection.videoRotationAngle = OrientationObserver.shared.videoRotationAngle
            }

            ShutterTrace.mark(tap, "即将调用 AVCapturePhotoOutput.capturePhoto")
            output.capturePhoto(with: settings, delegate: PhotoCapturePipeline.shared)
            ShutterTrace.mark(tap, "capturePhoto 已提交（未立即异常）")
        }
    }

    // MARK: - Recording

    /// 录制前是否把 session 切到了 .inputPriority（恢复照片预设时用）。
    private var videoPresetOverridden = false

    func startRecording() {
        guard movieOutput.isRecording == false else { return }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let connection = self.movieOutput.connection(with: .video) else { return }
            // 真实应用设置里的分辨率/帧率/编码/HDR/Log/防抖（失败只回退、不崩）。
            self.applyVideoSettings(connection: connection)
            connection.videoRotationAngle = OrientationObserver.shared.videoRotationAngle
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: VideoCapturePipeline.shared)
            DispatchQueue.main.async { AppState.shared.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
            DispatchQueue.main.async { AppState.shared.isRecording = false }
        }
    }

    // MARK: - 录制参数真实应用（参考 Varlens：ProRes / HDR / 防抖 / 码率）

    private func applyVideoSettings(connection: AVCaptureConnection) {
        let s = AppSettingsStore.shared
        guard let device = currentDevice else {
            DiagnosticLogger.shared.log("录制参数：无设备，跳过", category: .camera)
            return
        }

        let wantsProRes = s.videoCodec != .h264 && s.videoCodec != .hevc
        let wantsLog = s.videoColorSpace == .log
        let wantsHDR = s.videoHDR && !wantsLog
        let targetFPS = s.videoFrameRate

        // 1) 选择 activeFormat（必须在 .inputPriority 下才能手选格式）。
        let targetWidth = Self.targetWidth(for: s.videoResolution)
        let picked: AVCaptureDevice.Format? = device.formats
            .filter { fmt in
                let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                return Int(dims.width) == targetWidth
            }
            .sorted { a, b in
                let aMax = a.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
                let bMax = b.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
                return aMax > bMax
            }
            .first { fmt in
                let fpsOK = fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(targetFPS) }
                let hdrOK = !wantsHDR || fmt.isVideoHDRSupported
                let logOK = !wantsLog || Self.formatSupportsAppleLog(fmt)
                return fpsOK && hdrOK && logOK
            }

        if let fmt = picked {
            session.beginConfiguration()
            session.sessionPreset = .inputPriority
            do {
                try device.lockForConfiguration()
                device.activeFormat = fmt
                let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                if #available(iOS 17.1, *) {
                    if wantsLog && Self.formatSupportsAppleLog(fmt) {
                        device.activeColorSpace = .appleLog
                        device.isGlobalToneMappingEnabled = false
                    } else if s.videoColorSpace == .p3 {
                        device.activeColorSpace = .P3_D65
                    } else if wantsHDR && fmt.isVideoHDRSupported {
                        // HLG 由输出设置协商；全局色调映射关闭以保留 HDR 高光。
                        device.isGlobalToneMappingEnabled = false
                    }
                } else if wantsHDR && fmt.isVideoHDRSupported {
                    device.isGlobalToneMappingEnabled = false
                }
                device.unlockForConfiguration()
            } catch {
                DiagnosticLogger.shared.log("录制格式设置失败: \(error.localizedDescription)", category: .camera)
            }
            session.commitConfiguration()
            videoPresetOverridden = true
            DiagnosticLogger.shared.log(
                "录制格式: \(s.videoResolution)/\(targetFPS) HDR=\(wantsHDR) LOG=\(wantsLog) ProRes=\(wantsProRes)",
                category: .camera)
        } else {
            DiagnosticLogger.shared.log(
                "录制格式不匹配，沿用 .high 默认: \(s.videoResolution)/\(targetFPS)",
                category: .camera)
        }

        // 2) 编码 + 色彩（setOutputSettings 必须在未录制时调用）。
        var outputSettings: [String: Any] = [:]
        var resolvedCodec: AVVideoCodecType = s.videoCodec == .h264 ? .h264 : .hevc
        let available = movieOutput.availableVideoCodecTypes
        if wantsProRes {
            let wanted: AVVideoCodecType
            switch s.videoCodec {
            case .proRes422: wanted = .proRes422
            case .proRes422HQ: wanted = .proRes422HQ
            case .proRes422LT: wanted = .proRes422LT
            case .proResProxy: wanted = .proRes422Proxy
            default: wanted = .proRes422
            }
            if available.contains(wanted) {
                resolvedCodec = wanted
            } else if let proRes = available.first(where: { $0.rawValue.contains("ProRes") }) {
                // 内部存储 ProRes 通常只支持 1080p30：自动选可用的 ProRes 变体。
                resolvedCodec = proRes
                DiagnosticLogger.shared.log("ProRes 回退到 \(proRes.rawValue)", category: .camera)
            } else {
                resolvedCodec = .hevc
                DiagnosticLogger.shared.log("ProRes 不可用，回退 HEVC", category: .camera)
            }
        } else {
            let wanted: AVVideoCodecType = s.videoCodec == .h264 ? .h264 : .hevc
            if available.contains(wanted) { resolvedCodec = wanted }
        }
        outputSettings[AVVideoCodecKey] = resolvedCodec

        // HLG HDR：仅 HEVC 且当前格式支持时协商。
        if wantsHDR, resolvedCodec == .hevc,
           device.activeFormat.isVideoHDRSupported {
            outputSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG
            ]
        }
        movieOutput.setOutputSettings(outputSettings, for: connection)

        // 3) 防抖（按设置；AVCaptureConnection 没有逐档位查询 API，
        // 若硬件不支持所设档位，系统会自动降到最接近的可用档位）。
        if connection.isVideoStabilizationSupported {
            switch s.videoStabilization {
            case .off:
                connection.preferredVideoStabilizationMode = .off
            case .standard:
                connection.preferredVideoStabilizationMode = .standard
            case .cinematic:
                connection.preferredVideoStabilizationMode = .cinematic
            case .cinematicExtended:
                connection.preferredVideoStabilizationMode = .cinematicExtended
            }
        }
    }

    /// 录制结束后恢复照片用默认配置（.high，全局色调映射打开）。
    private func restoreVideoDefaults() {
        guard videoPresetOverridden else { return }
        if let connection = movieOutput.connection(with: .video) {
            movieOutput.setOutputSettings([:], for: connection)
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = currentDevice {
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = .invalid
                device.activeVideoMaxFrameDuration = .invalid
                if #available(iOS 17.1, *) {
                    device.isGlobalToneMappingEnabled = true
                }
                device.unlockForConfiguration()
            } catch { }
        }
        session.commitConfiguration()
        videoPresetOverridden = false
    }

    private static func targetWidth(for resolution: String) -> Int {
        switch resolution {
        case "8K": return 7680
        case "4K": return 3840
        case "1080p": return 1920
        case "720p": return 1280
        case "480p": return 640
        default: return 3840
        }
    }

    private static func formatSupportsAppleLog(_ fmt: AVCaptureDevice.Format) -> Bool {
        if #available(iOS 17.1, *) {
            return fmt.supportedColorSpaces.contains(.appleLog)
        }
        return false
    }

    /// 录制结束后在 sessionQueue 上恢复照片默认配置。
    func restoreVideoDefaultsAfterRecording() {
        sessionQueue.async { [weak self] in
            self?.restoreVideoDefaults()
        }
    }

    // MARK: - Orientation

    private func observeOrientation() {
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in self?.applyCurrentOrientation() }
            .store(in: &cancellables)
    }

    private func applyCurrentOrientation() {
        let angle = OrientationObserver.shared.videoRotationAngle
        for output in [photoOutput, movieOutput] {
            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        previewLayer?.connection.map {
            if $0.isVideoRotationAngleSupported(angle) { $0.videoRotationAngle = angle }
        }
    }
}

// MARK: - Live AI preview frames

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    private static var lastLiveRun: TimeInterval = 0

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let level = AppState.shared.aiPreviewLevel
        guard level != .off else { return }
        // Throttle: run the live engine at ~12 fps to avoid heating/latency.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - Self.lastLiveRun > 0.08 else { return }
        Self.lastLiveRun = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let result = LiveDetailEngine.shared.enhance(image: ciImage, level: level)

        // Live Vision AI：实时识别主体/场景（人脸/人体/动物/文字/YOLO/场景分类）。
        // 识别在低分辨率帧上进行，轮询高耗时请求，避免发热拖慢预览。
        let isFront = self.usingFrontCamera
        let vision = LiveVisionEngine.shared.analyze(
            pixelBuffer: pixelBuffer,
            orientation: isFront ? .leftMirrored : .right,
            level: level
        )

        // Keep the badge honest: the live engine is now actually receiving frames.
        DispatchQueue.main.async {
            let app = AppState.shared
            app.liveEnhanceFrameCount += 1
            app.liveEnhanceLatency = result.latency
            app.liveVisionActive = true
            app.liveVisionLatency = vision.latency
            app.liveSubjects = vision.subjects
            if !vision.sceneLabel.isEmpty { app.liveSceneLabel = vision.sceneLabel }
        }
    }
}
