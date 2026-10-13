//
//  SlowMotionController.swift
//  HJD Camera Pro
//
//  Configures and reports slow-motion capture. Queries the device's real
//  supported frame rates from AVCaptureDevice.Format.videoSupportedFrameRateRanges
//  (never fabricates a higher rate via interpolation). Targets 4K/240fps when
//  available and otherwise surfaces the actual maximum combination. Also models
//  the speed-curve / keyframe editor applied on export.
//

import AVFoundation
import UIKit
import SwiftUI
import Combine

/// A single keyframe in the slow-mo speed curve.
struct SpeedKeyframe: Identifiable, Equatable {
    let id = UUID()
    var time: TimeInterval   // seconds into the clip
    var speed: Double        // playback speed multiplier (0.25 = quarter speed)
}

final class SlowMotionController: ObservableObject {
    static let shared = SlowMotionController()

    /// The flagship spec we advertise when the hardware supports it.
    let targetSpec = VideoFormat(resolution: "4K", frameRate: 240, codec: "HEVC",
                                 isHDR: false, isProRes: false)

    /// The best actually-available combination on this device.
    @Published private(set) var availableSpec: VideoFormat

    /// True only when the device truly captures native 4K/240 (no interpolation).
    @Published private(set) var canCaptureNative4K240 = false

    /// Speed curve keyframes authored by the user.
    @Published var keyframes: [SpeedKeyframe] = []

    private let device = CameraManager.shared.currentDevice

    private init() {
        availableSpec = SlowMotionController.resolveBestSpec(for: CameraManager.shared.currentDevice)
        canCaptureNative4K240 = availableSpec.resolution == "4K" && availableSpec.frameRate >= 240
    }

    // MARK: - Hardware query

    /// Scan every format's frame-rate ranges and return the highest frame rate
    /// the device can natively produce at each resolution.
    static func resolveBestSpec(for device: AVCaptureDevice?) -> VideoFormat {
        guard let device = device else {
            return VideoFormat(resolution: "1080p", frameRate: 120, codec: "HEVC",
                               isHDR: false, isProRes: false)
        }
        var bestRate: Double = 120
        var bestIs4K = false
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let is4K = dims.width >= 3840
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate > bestRate {
                    bestRate = range.maxFrameRate
                    bestIs4K = is4K
                }
            }
        }
        return VideoFormat(resolution: bestIs4K ? "4K" : "1080p",
                           frameRate: Int(bestRate),
                           codec: "HEVC",
                           isHDR: false,
                           isProRes: false)
    }

    /// Whether a given (resolution, fps) combo is natively supported.
    func supports(resolution: String, fps: Int) -> Bool {
        guard let device = device else { return false }
        let target = Double(fps)
        return device.formats.contains { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let resOK = (resolution == "4K" && dims.width >= 3840)
                || (resolution == "1080p" && dims.width >= 1920)
            return resOK && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= target }
        }
    }

    /// Apply the best available slow-mo format to the active device.
    func configureForSlowMotion() {
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if let format = device.formats.first(where: {
                let dims = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return dims.width >= 3840 &&
                    $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 240 }
            }) {
                device.activeFormat = format
                if let range = format.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= 240 }) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 240)
                    device.activeVideoMaxFrameDuration = range.minFrameDuration
                }
            }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    // MARK: - Speed curve editing

    func addKeyframe(at time: TimeInterval, speed: Double) {
        let keyframe = SpeedKeyframe(time: time, speed: speed)
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }

    func removeKeyframe(_ keyframe: SpeedKeyframe) {
        keyframes.removeAll { $0.id == keyframe.id }
    }

    /// Interpolate the playback speed at a given time from the authored keyframes.
    /// This applies only on export — native capture rate is never interpolated.
    func speed(at time: TimeInterval) -> Double {
        guard let first = keyframes.first, let last = keyframes.last else { return 1.0 }
        if time <= first.time { return first.speed }
        if time >= last.time { return last.speed }
        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i], b = keyframes[i + 1]
            if time >= a.time && time <= b.time {
                let t = (time - a.time) / max(b.time - a.time, .leastNonzeroMagnitude)
                return a.speed + (b.speed - a.speed) * t
            }
        }
        return 1.0
    }
}
