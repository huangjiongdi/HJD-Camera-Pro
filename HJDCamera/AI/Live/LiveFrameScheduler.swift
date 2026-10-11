//
//  LiveFrameScheduler.swift
//  HJD Camera Pro
//
//  帧调度：不是每帧都跑重模型，根据场景复杂度调度轻量/重量增强。
//

import Foundation

final class LiveFrameScheduler {

    static let shared = LiveFrameScheduler()

    enum ScheduledTask {
        case lightweight   // 每帧执行（轻量锐化）
        case medium       // 每 3 帧执行（中量增强）
        case heavy        // 每 10 帧执行（重模型推理）
    }

    private var frameCounter = 0
    private var currentLevel: LivePreviewLevel = .balanced

    private init() {}

    /// 更新帧率与热状态，调整调度策略。
    func update(fps: Double, thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal, .fair:
            currentLevel = .balanced
        case .serious:
            currentLevel = .low
        case .critical:
            currentLevel = .off
        @unknown default:
            currentLevel = .balanced
        }

        if fps < 20 {
            currentLevel = .low
        }
    }

    /// 判断当前帧应该执行哪一级任务。
    func schedule() -> ScheduledTask {
        frameCounter += 1

        switch currentLevel {
        case .off:
            return .lightweight
        case .low:
            return frameCounter % 5 == 0 ? .medium : .lightweight
        case .balanced:
            if frameCounter % 10 == 0 { return .heavy }
            return frameCounter % 3 == 0 ? .medium : .lightweight
        case .high, .ultra:
            if frameCounter % 5 == 0 { return .heavy }
            return frameCounter % 2 == 0 ? .medium : .lightweight
        }
    }

    /// 当前级别。
    var level: LivePreviewLevel {
        return currentLevel
    }

    /// 重置计数器。
    func reset() {
        frameCounter = 0
    }
}
