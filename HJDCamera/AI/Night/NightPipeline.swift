//
//  NightPipeline.swift
//  HJD Camera Pro
//
//  夜景完整处理流程：分析 → 选帧 → 对齐 → 降噪 → 高光恢复 → 超分 → 质检 → 输出。
//

import Foundation
import CoreImage
import Combine

final class NightPipeline: ObservableObject {

    static let shared = NightPipeline()

    @Published private(set) var state: AIProcessingState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentStage: String = ""

    private let processingQueue = DispatchQueue(label: "com.hjd.camera.nightPipeline", qos: .userInitiated)

    private init() {}

    /// 完整夜景处理。
    /// - Parameters:
    ///   - frames: 多帧夜景图像
    ///   - preset: 夜景预设
    ///   - completion: 主线程回调最终结果
    func process(frames: [CIImage],
                 preset: NightPreset = .natural,
                 completion: @escaping (CIImage?) -> Void) {
        state = .processing(progress: 0)
        progress = 0

        processingQueue.async { [weak self] in
            guard let self = self, !frames.isEmpty else {
                DispatchQueue.main.async {
                    self?.state = .failed(error: "夜景处理失败")
                    completion(nil)
                }
                return
            }

            // Stage 1: 分析
            self.currentStage = "分析场景与噪声"
            self.progress = 0.1
            let noiseProfile = NightNoiseEstimator.shared.estimate(image: frames[0])

            // Stage 2: 选帧
            self.currentStage = "选择最佳清晰帧"
            self.progress = 0.25
            let bestFrames = AIFrameSelector.shared.selectBestFrames(frames, topK: min(8, frames.count))

            // Stage 3: 对齐
            self.currentStage = "多帧对齐"
            self.progress = 0.4
            let alignment = NightFrameAligner.shared.align(frames: bestFrames)

            // Stage 4: 运动掩码
            self.currentStage = "检测运动区域"
            self.progress = 0.5
            let motionMask = NightMotionMask.shared.compute(alignedFrames: alignment.alignedFrames)

            // Stage 5: HDR 融合
            self.currentStage = "HDR 融合"
            self.progress = 0.6
            let fusion = NightHDRFusion.shared.fuse(alignedFrames: alignment.alignedFrames,
                                                    motionMask: motionMask)

            // Stage 6: 降噪
            self.currentStage = "AI 降噪"
            self.progress = 0.7
            let denoised = NightDenoise.shared.denoise(image: fusion.image, noiseProfile: noiseProfile)

            // Stage 7: 超分
            self.currentStage = "细节超分"
            self.progress = 0.85
            let sr = NightDetailSR.shared.superResolve(image: denoised.image, scale: 2.0)

            // Stage 8: 质检
            self.currentStage = "质量检查"
            self.progress = 0.95
            let report = AIQualityGuard.shared.evaluate(original: frames[0], processed: sr.image)
            let finalImage = report.shouldFallback ? denoised.image : sr.image

            self.progress = 1.0
            self.state = .completed
            self.currentStage = "完成"

            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
    }
}
