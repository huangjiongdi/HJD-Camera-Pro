//
//  ModelCompatibilityChecker.swift
//  HJD Camera Pro
//
//  Checks whether a given CoreML model can run on this device: neural engine
//  availability, memory headroom, and required iOS / CoreML runtime version.
//

import Foundation
import CoreML

struct CompatibilityReport {
    let modelID: String
    let isCompatible: Bool
    let recommendedComputeUnit: MLComputeUnits
    let reasons: [String]
}

final class ModelCompatibilityChecker {
    static let shared = ModelCompatibilityChecker()

    private let device = DeviceCapabilityManager.shared

    private init() {}

    // MARK: - Check

    func compatibility(for model: AIModelInfo) -> CompatibilityReport {
        var reasons: [String] = []
        var compatible = true

        // 1. Neural Engine / ANE requirement.
        let hasNeuralEngine = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17
        if model.category == .superResolution || model.category == .lunar {
            if !hasNeuralEngine {
                reasons.append("此模型建议在配备神经引擎的设备上运行")
                // Still allow CPU/GPU fallback, but flag it.
            }
        }

        // 2. Memory headroom.
        let requiredMemory = StorageBudgetManager.shared.estimatedRuntimeMemory(for: model)
        let availableMemory = ProcessInfo().physicalMemory
        if requiredMemory > Int64(Double(availableMemory) * 0.25) {
            reasons.append("模型内存占用较高，可能触发内存压力")
            compatible = false
        }

        // 3. Device-specific feature support.
        if model.usedByModes.contains(.superMoon) && !device.hasTelephoto {
            reasons.append("未检测到长焦镜头，超级月亮模型效果受限")
        }

        // 4. Pick compute unit.
        let computeUnit: MLComputeUnits
        if hasNeuralEngine {
            computeUnit = .cpuAndNeuralEngine
        } else {
            computeUnit = .cpuAndGPU
            reasons.append("降级为 CPU/GPU 推理")
        }

        return CompatibilityReport(
            modelID: model.id,
            isCompatible: compatible,
            recommendedComputeUnit: computeUnit,
            reasons: reasons
        )
    }

    func filterCompatible(models: [AIModelInfo]) -> [AIModelInfo] {
        models.filter { compatibility(for: $0).isCompatible }
    }
}
