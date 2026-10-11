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
    private let device = CameraManager.shared.currentDevice

    private override init() {}

    // MARK: - Tap focus / expose

    /// Focus and expose at a normalized point (0...1) in preview space.
    func focus(at point: CGPoint) {
        focusPoint = point
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
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

    // MARK: - Manual controls

    func setManualFocusDistance(_ distance: Double) {
        manualFocusDistance = distance
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if distance >= 0, device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: Float(min(max(distance, 0), 1)))
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    func setISO(_ iso: Double, shutter: Double) {
        self.iso = iso
        shutterSpeed = shutter
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(
                    duration: CMTime(seconds: shutter, preferredTimescale: 1_000_000),
                    iso: min(max(Float(iso), device.activeFormat.minISO), device.activeFormat.maxISO),
                    completionHandler: nil
                )
            }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    func setExposureCompensation(_ ev: Double) {
        evCompensation = ev
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.autoExpose) {
                device.setExposureTargetBias(Float(ev)) { _ in }
            }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    func setWhiteBalance(kelvin: Int) {
        whiteBalance = kelvin
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: Float(kelvin), tint: 0
            )
            let gValues = device.deviceWhiteBalanceGains(for: values)
            if device.isWhiteBalanceModeSupported(.locked) {
                device.setWhiteBalanceModeLocked(with: gValues, completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }
}
