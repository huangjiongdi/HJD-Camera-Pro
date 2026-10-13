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
    private let sessionQueue = DispatchQueue(label: "com.hjd.camera.session", qos: .userInitiated)
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
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

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
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            }

            self.session.commitConfiguration()
            self.applyCurrentOrientation()
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
            DispatchQueue.main.async { self.currentZoomFactor = 1.0 }
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

    /// Maps a display zoom factor to the hardware `videoZoomFactor`.
    ///
    /// - 0.5x ultra-wide maps to the device minimum (which is 1.0 when the
    ///   virtual device's range starts at 1.0).
    /// - 1x maps to hardware 1.0.
    /// - 2x / 5x / 10x fall through to the virtual device's own lens switching
    ///   (driven by `virtualDeviceSwitchOverVideoZoomFactors`), so we pass the
    ///   display factor straight through up to the hardware maximum.
    /// - Beyond the hardware maximum, hardware is clamped to `maxAvailableVideoZoomFactor`
    ///   and the remainder is realised by cropping + AI enhancement in the
    ///   pipeline (never by exceeding the hardware zoom limit).
    func hardwareZoomFactor(forDisplayZoom displayZoom: CGFloat) -> CGFloat {
        guard let device = currentDevice else { return 1.0 }
        let minHW = device.minAvailableVideoZoomFactor
        let maxHW = device.maxAvailableVideoZoomFactor

        var hw: CGFloat
        if displayZoom <= 0.5 {
            hw = minHW                       // ultra wide -> hardware minimum
        } else if displayZoom <= 1.0 {
            hw = 1.0                          // 1x = hardware 1.0
        } else {
            hw = displayZoom                  // 2x/5x/10x follow switch-over points
        }
        return min(max(hw, minHW), maxHW)
    }

    func zoomSource(forDisplayZoom displayZoom: CGFloat) -> ZoomSource {
        let maxHW = currentDevice?.maxAvailableVideoZoomFactor ?? 10
        if displayZoom > maxHW {
            return displayZoom >= 100 ? .ai : .digital
        }
        let switches = DeviceCapabilityManager.shared.switchOverFactors
        if displayZoom <= (switches.first ?? 2.0) { return .optical }
        return .hybrid
    }

    /// Set the display zoom factor. Applies the hardware mapping and clamps the
    /// hardware value to the device's allowed range.
    func setZoomFactor(_ displayZoom: CGFloat) {
        let clamped = min(max(displayZoom, 0.5), 500.0)
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let hw = hardwareZoomFactor(forDisplayZoom: clamped)
            device.videoZoomFactor = hw
            device.unlockForConfiguration()
            currentZoomFactor = clamped
            zoomSource = zoomSource(forDisplayZoom: clamped)
            AppState.shared.setZoom(Double(clamped), source: zoomSource)
        } catch {
            health.recordStartupFailure(error)
        }
    }

    /// Smoothly ramp to a display zoom factor (used by animated UI transitions).
    func rampZoom(to displayZoom: CGFloat, rate: CGFloat = 5.0) {
        let clamped = min(max(displayZoom, 0.5), 500.0)
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let hw = hardwareZoomFactor(forDisplayZoom: clamped)
            device.ramp(toVideoZoomFactor: hw, withRate: Float(rate))
            device.unlockForConfiguration()
            currentZoomFactor = clamped
            zoomSource = zoomSource(forDisplayZoom: clamped)
        } catch {
            health.recordStartupFailure(error)
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
        guard let connection = movieOutput.connection(with: .video) else { return }
        connection.videoRotationAngle = OrientationObserver.shared.videoRotationAngle
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        movieOutput.startRecording(to: url, recordingDelegate: VideoCapturePipeline.shared)
        AppState.shared.isRecording = true
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        AppState.shared.isRecording = false
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
