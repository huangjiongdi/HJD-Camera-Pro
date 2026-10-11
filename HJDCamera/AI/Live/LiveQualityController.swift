//
//  LiveQualityController.swift
//  HJD Camera Pro
//
//  实时质量控制：根据帧率、温度、内存动态调整效果强度。
//

import Foundation
import Combine

final class LiveQualityController: ObservableObject {

    static let shared = LiveQualityController()

    @Published private(set) var currentLevel: LivePreviewLevel = .balanced
    @Published private(set) var temperature: Double = 0
    @Published private(set) var memoryPressure: Double = 0

    private init() {}

    /// 根据当前状态计算最佳质量级别。
    func evaluate(fps: Double,
                  thermalState: ProcessInfo.ThermalState,
                  memoryUsage: Double) -> LivePreviewLevel {
        var level: LivePreviewLevel = .highDetail

        // 温度降级
        switch thermalState {
        case .nominal: level = .highDetail
        case .fair: level = .balanced
        case .serious: level = .smooth
        case .critical: level = .off
        @unknown default: break
        }

        // 帧率降级
        if fps < 25 && level == .highDetail {
            level = .balanced
        }
        if fps < 15 && level == .balanced {
            level = .smooth
        }

        // 内存压力降级
        if memoryUsage > 0.8 {
            level = .smooth
        }
        if memoryUsage > 0.95 {
            level = .off
        }

        DispatchQueue.main.async {
            self.currentLevel = level
        }
        return level
    }

    /// 建议的增强强度（0-1）。
    var suggestedIntensity: Double {
        switch currentLevel {
        case .off: return 0
        case .smooth: return 0.2
        case .balanced: return 0.4
        case .highDetail: return 0.7
        }
    }
}
