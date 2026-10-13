//
//  ModelBenchmarkRunner.swift
//  HJD Camera Pro
//
//  Runs standardized benchmarks over bundled models: inference latency, peak
//  memory and thermal delta. Results are recorded for regression comparisons.
//

import Foundation
import UIKit

struct BenchmarkResult: Identifiable, Codable {
    let id: UUID
    let modelID: String
    let modelVersion: String
    let device: String
    let ios: String
    let averageInferenceMs: Double
    let peakMemoryMB: Double
    let temperatureDelta: Double
    let ranAt: Date

    init(modelID: String, modelVersion: String, averageInferenceMs: Double,
         peakMemoryMB: Double, temperatureDelta: Double) {
        self.id = UUID()
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.device = DeviceCapabilityManager.shared.deviceModelName()
        self.ios = UIDevice.current.systemVersion
        self.averageInferenceMs = averageInferenceMs
        self.peakMemoryMB = peakMemoryMB
        self.temperatureDelta = temperatureDelta
        self.ranAt = Date()
    }
}

final class ModelBenchmarkRunner: ObservableObject {
    static let shared = ModelBenchmarkRunner()

    @Published private(set) var results: [BenchmarkResult] = []

    private let fileManager = FileManager.default

    private var storeURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ModelBenchmarks.json")
    }

    private init() {
        load()
    }

    // MARK: - Run

    /// Measures inference time over `iterations` dummy passes. The actual model
    /// invocation is injected via `block` so this runner stays model-agnostic.
    func run(
        model: AIModelInfo,
        iterations: Int = 5,
        block: () throws -> Void
    ) -> BenchmarkResult {
        let startTemp = currentTemperature()
        var total: Double = 0

        for _ in 0..<max(1, iterations) {
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                try block()
            } catch {
                DiagnosticLogger.shared.error("Benchmark pass failed: \(error.localizedDescription)")
            }
            total += (CFAbsoluteTimeGetCurrent() - t0)
        }

        let avgMs = (total / Double(max(1, iterations))) * 1000.0
        let peakMB = currentMemoryMB()
        let delta = currentTemperature() - startTemp

        let result = BenchmarkResult(
            modelID: model.id,
            modelVersion: model.version,
            averageInferenceMs: avgMs,
            peakMemoryMB: peakMB,
            temperatureDelta: delta
        )
        results.append(result)
        persist()
        DiagnosticLogger.shared.log(
            "Benchmark \(model.name): \(avgMs)ms avg, \(peakMB)MB peak",
            category: .performance
        )
        return result
    }

    // MARK: - Telemetry

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

    private func currentTemperature() -> Double {
        // Placeholder telemetry: iOS does not expose sensor temperature directly;
        // the thermal state is used as a coarse proxy.
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0.0
        case .fair: return 1.0
        case .serious: return 2.0
        case .critical: return 3.0
        @unknown default: return 0.0
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        results = (try? JSONDecoder().decode([BenchmarkResult].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(results) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
