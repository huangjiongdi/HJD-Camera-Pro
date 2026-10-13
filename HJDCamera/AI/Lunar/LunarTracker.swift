//
//  LunarTracker.swift
//  HJD Camera Pro
//
//  月亮跟踪：基于帧间运动估计的抖动补偿，保持月亮在画面中心。
//

import Foundation
import CoreImage

final class LunarTracker {

    static let shared = LunarTracker()

    struct TrackingResult {
        var center: CGPoint
        var offset: CGVector      // 相对上一帧的偏移
        var stability: Double    // 0-1，越高越稳定
    }

    private var lastCenter: CGPoint?

    private init() {}

    /// 跟踪月亮位置。
    func track(image: CIImage, detection: LunarDetector.DetectionResult) -> TrackingResult {
        let current = detection.center
        let offset: CGVector

        if let last = lastCenter {
            offset = CGVector(dx: current.x - last.x, dy: current.y - last.y)
        } else {
            offset = .zero
        }

        let stability = 1.0 - min(1.0, sqrt(offset.dx*offset.dx + offset.dy*offset.dy) / 50.0)
        lastCenter = current

        return TrackingResult(center: current, offset: offset, stability: stability)
    }

    /// 重置跟踪状态。
    func reset() {
        lastCenter = nil
    }
}
