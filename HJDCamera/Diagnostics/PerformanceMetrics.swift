//
//  PerformanceMetrics.swift
//  HJD Camera Pro
//
//  Collects and aggregates performance telemetry: frame rate, inference
//  latency, memory footprint, thermal state, battery drain and launch time.
//

import Foundation
import UIKit
import Combine

final class PerformanceMetrics: ObservableObject {
    static let shared = PerformanceMetrics()

    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var averageInferenceMs: Double = 0
    @Published private(set) var memoryUsageMB: Double = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var batteryLevel: Float = 0
    @Published private(set) var launchDuration: TimeInterval = 0

    private var inferenceSamples: [Double] = []
    private let inferenceSampleLimit = 60
    private var launchStart = CFAbsoluteTimeGetCurrent()

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private var cancellable: AnyCancellable?

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        cancellable = timer.sink { [weak self] _ in
            self?.sample()
        }
    }

    // MARK: - Launch

    func markLaunchEnd() {
        launchDuration = CFAbsoluteTimeGetCurrent() - launchStart
        DiagnosticLogger.shared.log("Launch took \(launchDuration)s", category: .performance)
    }

    // MARK: - Inference

    func recordInference(_ ms: Double) {
        inferenceSamples.append(ms)
        if inferenceSamples.count > inferenceSampleLimit {
            inferenceSamples.removeFirst(inferenceSamples.count - inferenceSampleLimit)
        }
        averageInferenceMs = inferenceSamples.reduce(0, +) / Double(inferenceSamples.count)
    }

    // MARK: - Frame rate

    func setFPS(_ fps: Double) {
        currentFPS = fps
    }

    // MARK: - Sampling

    private func sample() {
        memoryUsageMB = currentMemoryMB()
        thermalState = ProcessInfo.processInfo.thermalState
        batteryLevel = UIDevice.current.batteryLevel
    }

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    // MARK: - Snapshot

    func snapshot() -> [String: Any] {
        [
            "fps": currentFPS,
            "avgInferenceMs": averageInferenceMs,
            "memoryMB": memoryUsageMB,
            "thermal": thermalStateString(),
            "battery": batteryLevel,
            "launchSec": launchDuration
        ]
    }

    private func thermalStateString() -> String {
        switch thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
