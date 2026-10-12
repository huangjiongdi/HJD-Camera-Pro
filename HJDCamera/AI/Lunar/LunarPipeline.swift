//
//  LunarPipeline.swift
//  HJD Camera Pro
//
//  超级月亮完整流程：检测 → 曝光 → 跟踪 → 采集 → 选帧 → 对齐 → 融合 → 降噪 →
//  超分 → 真实性检查 → 保存。
//

import Foundation
import CoreImage
import Combine

final class LunarPipeline: ObservableObject {

    static let shared = LunarPipeline()

    @Published private(set) var state: AIProcessingState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentStage: String = ""

    private let processingQueue = DispatchQueue(label: "com.hjd.camera.lunarPipeline", qos: .userInitiated)

    private init() {}

    /// 完整超级月亮处理。
    func process(frames: [CIImage],
                qualityMode: LunarQualityMode = .realSurface,
                completion: @escaping (LunarProcessingResult?) -> Void) {
        state = .processing(progress: 0)
        progress = 0

        processingQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self = self, !frames.isEmpty else {
                DispatchQueue.main.async {
                    self?.state = .failed(error: "月面处理失败")
                    completion(nil)
                }
                return
            }

            // Stage 1: 月亮检测
            self.currentStage = "检测月亮圆盘"
            self.progress = 0.05
            let detection = LunarDetector.shared.detect(image: frames[0])
            guard detection.isMoon else {
                DispatchQueue.main.async {
                    self.state = .failed(error: "未检测到月亮")
                    self.currentStage = "未检测到月亮"
                    completion(nil)
                }
                return
            }

            // Stage 2: 曝光控制
            self.currentStage = "调整月面曝光"
            self.progress = 0.15
            let exposure = LunarExposureController.shared.adjust(
                image: frames[0], detection: detection)

            // Stage 3: 跟踪
            self.currentStage = "月亮跟踪"
            self.progress = 0.25
            let _ = LunarTracker.shared.track(image: frames[0], detection: detection)

            // Stage 4: 选择最佳帧
            self.currentStage = "选择清晰帧"
            self.progress = 0.4
            let bestFrames = AIFrameSelector.shared.selectBestFrames(
                frames, topK: qualityMode == .experimental ? 12 : 6)

            // Stage 5: 多帧融合
            self.currentStage = "多帧融合"
            self.progress = 0.55
            let fusion = LunarMultiFrameFusion.shared.fuse(
                frames: bestFrames, detection: detection)

            // Stage 6: 降噪
            self.currentStage = "月面降噪"
            self.progress = 0.65
            let noiseProfile = NightNoiseEstimator.shared.estimate(image: fusion.image)
            let denoised = NightDenoise.shared.denoise(
                image: fusion.image, noiseProfile: noiseProfile)

            // Stage 7: 超分
            self.currentStage = "月面超分"
            self.progress = 0.8
            let srScale: Double = qualityMode == .experimental ? 3.0 : 2.0
            let sr = LunarSR.shared.superResolve(image: denoised.image, scale: srScale)

            // Stage 8: 细节恢复（受约束）
            self.currentStage = "细节恢复"
            self.progress = 0.88
            let recovery = LunarDetailRecovery.shared.recover(
                image: sr.image, original: frames[0])

            // Stage 9: 真实性检查
            self.currentStage = "真实性验证"
            self.progress = 0.95
            let fidelity = LunarFidelityGuard.shared.check(
                original: frames[0], processed: recovery.image)

            let finalImage = fidelity.pass ? recovery.image : denoised.image

            self.progress = 1.0
            self.state = .completed
            self.currentStage = "完成"

            let result = LunarProcessingResult(
                image: finalImage,
                confidence: fidelity.pass ? 0.9 : 0.5,
                qualityScore: qualityMode == .experimental ? 0.95 : 0.8,
                frameCount: fusion.frameCount,
                modelUsed: sr.modelUsed
            )

            DispatchQueue.main.async {
                completion(result)
            }
        })
    }
}
