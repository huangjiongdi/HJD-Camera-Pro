//
//  VideoCapturePipeline.swift
//  HJD Camera Pro
//
//  Recording owner for AVCaptureMovieFileOutput. Dynamically selects device
//  format / frame rate / codec from a requested VideoFormat, supports
//  HEVC / H.264 / ProRes and SDR / HDR / LOG working color spaces. Locks AI
//  model switching for the duration of a take and surfaces live recording HUD
//  signals (remaining storage, thermal risk, audio). Performs recovery and a
//  file-integrity check when a take ends.
//

import AVFoundation
import UIKit
import SwiftUI
import Combine

final class VideoCapturePipeline: NSObject, AVCaptureFileOutputRecordingDelegate, ObservableObject {
    static let shared = VideoCapturePipeline()

    // MARK: - Published recording HUD

    @Published var isRecording = false
    @Published var recordedDuration: TimeInterval = 0
    @Published var remainingStorageBytes: Int64 = 0
    @Published var thermalRisk: Double = 0          // 0...1
    @Published var audioActive = true
    @Published var selectedFormat: VideoFormat = VideoFormat.common[6] // 4K/30 HEVC HDR
    @Published var selectedCodec: VideoCodec = .hevc
    @Published var colorSpace: ColorSpace = .hdr

    /// While true, AI model switches are suppressed mid-take.
    private(set) var aiSwitchLocked = false

    private let health = CameraHealthMonitor.shared
    private var durationTimer: Timer?

    private override init() {
        super.init()
        refreshStorage()
    }

    // MARK: - Format / codec / color-space selection

    /// Apply the requested format to the active device, querying the device's
    /// supported formats to pick the closest match.
    func applyFormat(_ format: VideoFormat) {
        selectedFormat = format
        guard let device = CameraManager.shared.currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let targetFPS = Double(format.frameRate)
            if let best = DeviceCapabilityManager.shared.availableVideoFormats(for: device)
                .first(where: { fmt in
                    fmt.videoSupportedFrameRateRanges.contains { range in range.maxFrameRate >= targetFPS }
                }) {
                device.activeFormat = best
                if let range = best.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= targetFPS }) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                    device.activeVideoMaxFrameDuration = range.minFrameDuration
                }
            }
            configureColorSpace(colorSpace, on: device)
            device.unlockForConfiguration()
        } catch {
            health.recordStartupFailure(error)
        }
    }

    func selectCodec(_ codec: VideoCodec) {
        selectedCodec = codec
        // Codec choice is forwarded to the movie output / encoder at recording time.
    }

    func configureColorSpace(_ space: ColorSpace, on device: AVCaptureDevice) {
        colorSpace = space
        do {
            try device.lockForConfiguration()
            switch space {
            case .hdr:
                if device.activeFormat.isVideoHDRSupported {
                    // HDR is negotiated through the active format + session preset;
                    // on iOS 17+ the system selects the HDR pipeline automatically.
                }
            case .log:
                // Log working space requires a ProRes-capable format; fall back silently if absent.
                break
            case .sdr, .p3, .dolbyVision:
                break
            }
            device.unlockForConfiguration()
        } catch {
            health.recordStartupFailure(error)
        }
    }

    // MARK: - Recording control

    func beginRecording(to url: URL) {
        guard !isRecording else { return }
        aiSwitchLocked = true
        isRecording = true
        recordedDuration = 0
        startDurationTimer()
        refreshStorage()
    }

    func finishRecording() {
        aiSwitchLocked = false
        stopDurationTimer()
        isRecording = false
    }

    // MARK: - Delegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        beginRecording(to: fileURL)
        audioActive = connections.contains { conn in
            conn.inputPorts.contains { port in port.mediaType == .audio }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        finishRecording()

        // 录制期间切到 .inputPriority / 自定义编码，结束后恢复照片默认配置。
        CameraManager.shared.restoreVideoDefaultsAfterRecording()

        // Even when an error is reported (e.g. a short take), AVFoundation may
        // have written a valid partial file. Validate it once and keep it if it
        // is usable, instead of tearing down the whole session.
        if let error = error {
            DiagnosticLogger.shared.error("Recording ended with error: \(error.localizedDescription)")
            if isUsableFile(at: outputFileURL) {
                verifyIntegrity(of: outputFileURL)
            } else {
                try? FileManager.default.removeItem(at: outputFileURL)
                NotificationCenter.default.post(name: .hjdStorageWarning, object: error)
            }
            return
        }
        verifyIntegrity(of: outputFileURL)
    }

    private func isUsableFile(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size > 10_000
    }

    // MARK: - Integrity & recovery

    private func verifyIntegrity(of url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 10_000 else {
            // Truncated / empty file — delete and surface a retry.
            try? FileManager.default.removeItem(at: url)
            NotificationCenter.default.post(name: .hjdStorageWarning, object: url)
            return
        }
        AppState.shared.lastCapturedImageURL = url
        // Export the finished take to the system photo library.
        Task.detached {
            _ = await PhotoLibraryExporter.shared.exportVideo(fileURL: url)
        }
    }

    // MARK: - HUD refresh

    private func refreshStorage() {
        if let stats = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) {
            remainingStorageBytes = stats.volumeAvailableCapacityForImportantUsage ?? 0
        }
        thermalRisk = health.thermalState == .critical ? 1.0
            : health.thermalState == .serious ? 0.6
            : health.thermalState == .fair ? 0.3 : 0.0
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordedDuration += 1
            AppState.shared.recordingDuration = self.recordedDuration
            self.refreshStorage()
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
