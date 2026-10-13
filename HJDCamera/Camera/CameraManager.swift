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
    @Published var isSessionRunning = false
    /// The display zoom factor (what the UI shows: 0.5 / 1 / 2 / 5 / 10 / ... / 500).
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var zoomSource: ZoomSource = .optical
    @Published var usingFrontCamera = false

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

    /// On virtual multi-camera devices (triple / dual-wide) the hardware
    /// `videoZoomFactor` is normalized with the ULTRA-WIDE lens at factor 1.0,
    /// i.e. display 0.5× -> hardware 1.0, display 1× (main/wide) -> hardware 2.0,
    /// display 2×/3× (tele) -> hardware 4.0/6.0. Passing the display factor
    /// straight through is what previously made 0.5× and 1× both land on the
    /// ultra-wide and only 2× reach the main lens. This multiplier corrects that.
    private func virtualMultiplier(for device: AVCaptureDevice) -> CGFloat {
        let hasUltraWide = device.constituentDevices.contains {
            $0.deviceType == .builtInUltraWideCamera
        }
        guard hasUltraWide else { return 1.0 }
        // minAvailableVideoZoomFactor is 1.0 on a virtual triple/dual-wide;
        // display 0.5× maps to it.
        return max(device.minAvailableVideoZoomFactor / 0.5, 1.0)
    }

    /// Maps a display zoom factor (0.5 … 500) to the hardware
    /// `videoZoomFactor`, clamped to the device's real range.
    func hardwareZoomFactor(forDisplayZoom displayZoom: CGFloat) -> CGFloat {
        guard let device = currentDevice else { return 1.0 }
        let mult = virtualMultiplier(for: device)
        let minHW = device.minAvailableVideoZoomFactor
        let maxHW = device.maxAvailableVideoZoomFactor
        let hw = displayZoom * mult
        return min(max(hw, minHW), maxHW)
    }

    /// Largest display zoom the hardware alone can reach on the active device.
    var maxHardwareDisplayZoom: CGFloat {
        guard let device = currentDevice else { return 10 }
        return max(device.maxAvailableVideoZoomFactor / virtualMultiplier(for: device), 1.0)
    }

    /// Additional software crop factor used once the hardware zoom is maxed.
    /// Returned in DISPLAY space so the UI always reaches 500×.
    func digitalCropFactor(forDisplayZoom displayZoom: CGFloat) -> CGFloat {
        let maxDisplay = maxHardwareDisplayZoom
        return displayZoom > maxDisplay ? displayZoom / maxDisplay : 1.0
    }

    /// Digital crop factor for the most recently requested display zoom —
    /// used by the still pipeline to crop the captured photo at high zoom.
    private(set) var currentDigitalCrop: CGFloat = 1.0

    func zoomSource(forDisplayZoom displayZoom: CGFloat) -> ZoomSource {
        if displayZoom >= 100 { return .ai }
        if displayZoom > maxHardwareDisplayZoom { return .digital }
        guard let device = currentDevice else { return .optical }
        let mult = virtualMultiplier(for: device)
        let hw = displayZoom * mult
        let switches = DeviceCapabilityManager.shared.switchOverFactors
        // Up to the first hardware switch-over point is a single native lens.
        if hw <= (switches.first ?? 2.0) { return .optical }
        return .hybrid
    }

    /// Set the hardware videoZoomFactor while the device is already locked.
    private func applyZoomLocked(_ displayZoom: CGFloat) {
        guard let device = currentDevice else { return }
        let hw = hardwareZoomFactor(forDisplayZoom: displayZoom)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = hw
            device.unlockForConfiguration()
        } catch {
            health.recordStartupFailure(error)
        }
    }

    /// Set the display zoom factor. Hardware part is clamped to the device;
    /// any remaining factor is a preview-layer digital crop so the UI always
    /// reaches 500× instead of being stuck at the hardware maximum.
    func setZoomFactor(_ displayZoom: CGFloat) {
        let clamped = min(max(displayZoom, 0.5), 500.0)
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
            self.currentDigitalCrop = crop
            self.applyDigitalCrop(crop)
            DispatchQueue.main.async {
                self.currentZoomFactor = clamped
                self.zoomSource = self.zoomSource(forDisplayZoom: clamped)
                AppState.shared.setZoom(Double(clamped), source: self.zoomSource)
            }
        }
    }

    /// Smoothly ramp to a display zoom factor (used by animated UI transitions).
    /// Hardware zoom is ramped only within the hardware range; the all-digital
    /// zone (>hardware max) is applied directly since ramping cannot exceed it.
    func rampZoom(to displayZoom: CGFloat, rate: CGFloat = 5.0) {
        let clamped = min(max(displayZoom, 0.5), 500.0)
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            let hw = self.hardwareZoomFactor(forDisplayZoom: clamped)
            let crop = self.digitalCropFactor(forDisplayZoom: clamped)
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: hw, withRate: Float(rate))
                device.unlockForConfiguration()
            } catch {
                self.health.recordStartupFailure(error)
            }
            self.currentDigitalCrop = crop
            self.applyDigitalCrop(crop)
            DispatchQueue.main.async {
                self.currentZoomFactor = clamped
                self.zoomSource = self.zoomSource(forDisplayZoom: clamped)
                AppState.shared.setZoom(Double(clamped), source: self.zoomSource)
            }
        }
    }

    /// Scale the preview layer itself for the all-digital zone (>hardware max).
    /// Independent of capture so it can't exceed the device's hardware limit.
    private func applyDigitalCrop(_ scale: CGFloat) {
        let s = max(scale, 1.0)
        DispatchQueue.main.async {
            guard let layer = self.previewLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
            CATransaction.commit()
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        // RAW capture must use the dedicated raw initializer; `rawFileType` is
        // read-only on a normal photo settings object.
        let wantsRaw = AppState.shared.rawEnabled
            && photoOutput.availableRawPhotoPixelFormatTypes.first != nil

        let settings: AVCapturePhotoSettings
        if wantsRaw, let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            let raw = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            raw.flashMode = AppState.shared.flashMode
            raw.previewPhotoFormat = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            settings = raw
        } else {
            let normal = AVCapturePhotoSettings()
            normal.flashMode = AppState.shared.flashMode
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                normal.photoQualityPrioritization = .balanced
            }
            settings = normal
        }
        photoOutput.capturePhoto(with: settings, delegate: PhotoCapturePipeline.shared)
    }

    // MARK: - Recording

    func startRecording() {
        guard movieOutput.isRecording == false else { return }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // The session already runs on a video-capable `.high` preset; do NOT
            // reconfigure it here. Switching presets while a movie output is
            // attached (and restoring `.photo` on stop) was the crash.
            guard let connection = self.movieOutput.connection(with: .video) else { return }
            connection.videoRotationAngle = OrientationObserver.shared.videoRotationAngle
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
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

    /// No longer reconfigures the preset: the session stays on `.high` for the
    /// whole app lifetime so both photo and movie outputs coexist.
    func restorePhotoPreset() {
        // Intentionally empty — kept for call-site compatibility.
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
        // Keep the badge honest: the live engine is now actually receiving frames.
        DispatchQueue.main.async {
            AppState.shared.liveEnhanceFrameCount += 1
            AppState.shared.liveEnhanceLatency = result.latency
        }
    }
}
