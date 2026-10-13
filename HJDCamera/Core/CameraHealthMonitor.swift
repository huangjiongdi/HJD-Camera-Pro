//
//  CameraHealthMonitor.swift
//  HJD Camera Pro
//
//  Watches camera subsystem health: startup failures, thermal state, memory
//  pressure, and crash recovery. Publishes state so the UI can warn the user
//  and degrade gracefully (e.g. stop recording before a thermal shutdown).
//

import SwiftUI
import UIKit
import Combine
import Foundation

final class CameraHealthMonitor: ObservableObject {
    static let shared = CameraHealthMonitor()

    /// Last captured startup/session error, if the session failed to run.
    @Published var lastStartupError: String?

    /// Current system thermal state, mirrored into AppState.
    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    /// App-wide memory pressure (0.0 = nominal ... 1.0 = critical).
    @Published var memoryPressure: Float = 0.0

    /// True when the previous launch ended in an abnormal camera termination.
    @Published var recoveredFromCrash = false

    /// True when the system has signalled we should stop heavy capture work.
    @Published var isThrottled = false

    private var thermalObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private let crashFlagKey = "hjd.camera.crashedLastSession"

    private init() {
        checkCrashRecovery()
        startThermalMonitoring()
        startMemoryMonitoring()
        markSessionActive()
    }

    // MARK: - Startup failure

    /// Record a session-startup error and publish it.
    func recordStartupFailure(_ error: Error) {
        lastStartupError = error.localizedDescription
        NotificationCenter.default.post(name: .hjdStorageWarning, object: error)
    }

    func clearStartupError() {
        lastStartupError = nil
    }

    // MARK: - Crash recovery

    /// On next launch, if the "session active" flag is still set, the previous
    /// run died without clearing it — treat as a crash and offer recovery.
    private func checkCrashRecovery() {
        recoveredFromCrash = UserDefaults.standard.bool(forKey: crashFlagKey)
    }

    private func markSessionActive() {
        UserDefaults.standard.set(true, forKey: crashFlagKey)
    }

    /// Call from the app's normal teardown to clear the crash flag.
    func markSessionInactive() {
        UserDefaults.standard.set(false, forKey: crashFlagKey)
    }

    // MARK: - Thermal

    private func startThermalMonitoring() {
        thermalState = ProcessInfo.processInfo.thermalState
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let state = ProcessInfo.processInfo.thermalState
            self.thermalState = state
            self.isThrottled = (state == .serious || state == .critical)
            if state == .serious || state == .fair {
                NotificationCenter.default.post(name: .hjdThermalWarning, object: state)
            }
        }
    }

    // MARK: - Memory

    private func startMemoryMonitoring() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.memoryPressure = min(self.memoryPressure + 0.25, 1.0)
                NotificationCenter.default.post(name: .hjdMemoryWarning, object: nil)
            }
            .store(in: &cancellables)
    }

    /// Called after a successful heavy allocation settles; gradually relax the pressure reading.
    func relaxMemoryPressure() {
        memoryPressure = max(memoryPressure - 0.1, 0.0)
    }
}
