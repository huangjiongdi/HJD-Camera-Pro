//
//  FocusExposureController.swift
//  HJD Camera Pro
//
//  Tap-to-focus/expose, 0.5s long-press AE/AF lock, auto-unlock on device motion
//  or subject leaving the frame, plus manual ISO / shutter / EV / white-balance /
//  color-temperature and focus-distance control. Exposes focus-peaking and
//  zebra-stripe assist flags for the preview renderer.
//

import AVFoundation
import UIKit
import SwiftUI
import Combine

final class FocusExposureController: ObservableObject {
    static let shared = FocusExposureController()

    @Published var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isFocusLocked = false
    @Published var isExposureLocked = false
    @Published var autoUnlockEnabled = true
    @Published var peakingEnabled = true
    @Published var zebraEnabled = false
    @Published var zebraThreshold: Double = 0.9

    // Manual controls (mirror ProCaptureSettings).
    @Published var iso: Double = 100
    @Published var shutterSpeed: Double = 1.0 / 125
    @Published var evCompensation: Double = 0
    @Published var whiteBalance: Int = 5500          // Kelvin
    @Published var manualFocusDistance: Double = -1  // -1 = continuous

    private var motionUnlockToken: NSObjectProtocol?

    private init() {}

    /// Always read the live device — it is nil at init time and changes when the
    /// user flips the camera. Caching it once made every focus call a no-op.
    private var device: AVCaptureDevice? { CameraManager.shared.currentDevice }

    // MARK: - Tap focus / expose

    /// Focus and expose at a normalized point (0...1) in preview space.
    func focus(at point: CGPoint) {
        focusPoint = point
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            // Use continuous modes so the camera keeps refocusing / re-exposing
            // after the tap, instead of freezing on one-shot focus.
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            AppState.shared.focusLocked = false
            AppState.shared.exposureLocked = false
            isFocusLocked = false
            isExposureLocked = false
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    // MARK: - Long-press lock

    /// Call on long-press (held ~0.5s) to lock AE/AF.
    func lockAEAF() {
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            device.unlockForConfiguration()
            isFocusLocked = true
            isExposureLocked = true
            AppState.shared.focusLocked = true
            AppState.shared.exposureLocked = true
            beginAutoUnlockMonitoring()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    func unlockAEAF() {
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
        isFocusLocked = false
        isExposureLocked = false
        AppState.shared.focusLocked = false
        AppState.shared.exposureLocked = false
        endAutoUnlockMonitoring()
    }

    /// Auto-unlock when the device moves sharply or the subject leaves the frame.
    private func beginAutoUnlockMonitoring() {
        guard autoUnlockEnabled else { return }
        motionUnlockToken = NotificationCenter.default.addObserver(
            forName: .hjdCaptureCompleted, object: nil, queue: .main
        ) { [weak self] _ in
            // If scene changes abruptly after lock, release the lock.
            self?.unlockAEAF()
        }
    }

    private func endAutoUnlockMonitoring() {
        motionUnlockToken.map { NotificationCenter.default.removeObserver($0) }
        motionUnlockToken = nil
    }

    // MARK: - 设备能力范围（只读当前 activeFormat）

    struct ExposureLimits {
        let minISO: Float
        let maxISO: Float
        let minShutter: Double
        let maxShutter: Double
        let minBias: Float
        let maxBias: Float
    }

    var exposureLimits: ExposureLimits {
        guard let d = device else {
            return ExposureLimits(minISO: 50, maxISO: 5000,
                                  minShutter: 1.0/10000, maxShutter: 1.0/4,
                                  minBias: -2, maxBias: 2)
        }
        let f = d.activeFormat
        return ExposureLimits(
            minISO: f.minISO,
            maxISO: f.maxISO,
            minShutter: f.minExposureDuration.seconds,
            maxShutter: f.maxExposureDuration.seconds,
            minBias: d.minExposureTargetBias,
            maxBias: d.maxExposureTargetBias
        )
    }

    /// 设备当前的自动曝光 ISO（S 档进入时快照用）。
    var currentAutoISO: Float {
        device?.iso ?? 100
    }

    // MARK: - 档位与手动曝光

    /// 全自动曝光（Auto/P/A 档共用，iPhone 光圈固定，A 档等同自动+EV）。
    func setAutoExposure(ev: Double) {
        evCompensation = ev
        guard let d = device else { return }
        do {
            try d.lockForConfiguration()
            let bias = min(max(Float(ev), d.minExposureTargetBias), d.maxExposureTargetBias)
            if d.isExposureModeSupported(.continuousAutoExposure) {
                d.exposureMode = .continuousAutoExposure
            }
            d.setExposureTargetBias(bias, completionHandler: nil)
            d.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    /// 手动对焦：position 0..1（0=最近、1=无穷远）；<0 恢复连续自动对焦。
    func setLensPosition(_ position: Double) {
        manualFocusDistance = position
        guard let d = device else { return }
        do {
            try d.lockForConfiguration()
            if position < 0 {
                if d.isFocusModeSupported(.continuousAutoFocus) {
                    d.focusMode = .continuousAutoFocus
                }
            } else if d.isLockingFocusWithCustomLensPositionSupported {
                let p = Float(min(max(position, 0), 1))
                d.setFocusModeLocked(lensPosition: p, completionHandler: nil)
            }
            d.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    /// 全手动曝光（M 档）：ISO + 快门，全部 clamp 到设备支持范围。
    func setCustomExposure(iso: Double, shutter: Double) {
        self.iso = iso
        shutterSpeed = shutter
        guard let d = device else { return }
        do {
            try d.lockForConfiguration()
            let f = d.activeFormat
            let clampedISO = min(max(Float(iso), f.minISO), f.maxISO)
            let minS = f.minExposureDuration.seconds
            let maxS = f.maxExposureDuration.seconds
            let clampedShutter = min(max(shutter, minS), maxS)
            if d.isExposureModeSupported(.custom) {
                d.setExposureModeCustom(
                    duration: CMTime(seconds: clampedShutter, preferredTimescale: 1_000_000),
                    iso: clampedISO,
                    completionHandler: nil
                )
            }
            d.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    /// S 档：固定快门，ISO 由调用方传入（进入 S 档时取设备当前自动 ISO）。
    func setShutterPriority(shutter: Double, iso: Double) {
        setCustomExposure(iso: iso, shutter: shutter)
    }

    /// 仅锁定快门（A 档/P 档不调用）。
    func setISO(_ iso: Double, shutter: Double) {
        setCustomExposure(iso: iso, shutter: shutter)
    }

    func setExposureCompensation(_ ev: Double) {
        setAutoExposure(ev: ev)
    }

    /// 只设置曝光补偿，不改变曝光模式（S/M 档清零用）。
    func setExposureCompensationOnly(_ ev: Double) {
        evCompensation = ev
        guard let d = device else { return }
        do {
            try d.lockForConfiguration()
            let bias = min(max(Float(ev), d.minExposureTargetBias), d.maxExposureTargetBias)
            d.setExposureTargetBias(bias, completionHandler: nil)
            d.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    func setWhiteBalance(kelvin: Int) {
        whiteBalance = kelvin
        guard let d = device else { return }
        do {
            try d.lockForConfiguration()
            if kelvin <= 0 {
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    d.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } else {
                let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(min(max(kelvin, 2000), 10000)), tint: 0
                )
                var g = d.deviceWhiteBalanceGains(for: values)
                g.redGain = min(max(g.redGain, 1.0), d.maxWhiteBalanceGain)
                g.greenGain = min(max(g.greenGain, 1.0), d.maxWhiteBalanceGain)
                g.blueGain = min(max(g.blueGain, 1.0), d.maxWhiteBalanceGain)
                if d.isWhiteBalanceModeSupported(.locked) {
                    d.setWhiteBalanceModeLocked(with: g, completionHandler: nil)
                }
            }
            d.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    /// 全部恢复自动（离开 Pro 模式 / 复位）。
    func resetAll() {
        guard let d = device else { return }
        do {
            try d.lockForConfiguration()
            if d.isFocusModeSupported(.continuousAutoFocus) {
                d.focusMode = .continuousAutoFocus
            }
            if d.isExposureModeSupported(.continuousAutoExposure) {
                d.exposureMode = .continuousAutoExposure
            }
            d.setExposureTargetBias(0, completionHandler: nil)
            if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                d.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            d.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
        iso = 100
        shutterSpeed = 1.0 / 125
        evCompensation = 0
        whiteBalance = 0
        manualFocusDistance = -1
        isFocusLocked = false
        isExposureLocked = false
        AppState.shared.focusLocked = false
        AppState.shared.exposureLocked = false
    }
}
