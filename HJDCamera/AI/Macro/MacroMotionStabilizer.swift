//
//  MacroMotionStabilizer.swift
//  HJD Camera Pro
//
//  微距防抖：估计手抖与昆虫运动，对齐多帧微距图像。
//

import Foundation
import CoreImage

final class MacroMotionStabilizer {

    static let shared = MacroMotionStabilizer()

    struct StabilizeResult {
        var alignedFrames: [CIImage]
        var shakeMagnitude: Double   // 手抖幅度
        var subjectMotion: Double     // 主体运动幅度
    }

    private init() {}

    /// 稳定微距多帧。
    func stabilize(frames: [CIImage]) -> StabilizeResult {
        guard frames.count > 1 else {
            return StabilizeResult(alignedFrames: frames, shakeMagnitude: 0, subjectMotion: 0)
        }

        // 使用通用对齐器
        let alignment = NightFrameAligner.shared.align(frames: frames)

        // 估计手抖幅度（帧间全局位移）
        let shake = alignment.error

        // 估计主体运动（局部差异）
        let motionMask = NightMotionMask.shared.compute(alignedFrames: alignment.alignedFrames)
        let subjectMotion = motionMask.motionRatio

        return StabilizeResult(
            alignedFrames: alignment.alignedFrames,
            shakeMagnitude: shake,
            subjectMotion: subjectMotion
        )
    }
}
