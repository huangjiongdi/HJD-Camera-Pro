//
//  MacroPipeline.swift
//  HJD Camera Pro
//
//  微距处理流程：快速微距模式与细节微距模式。
//

import Foundation
import CoreImage
import Combine

final class MacroPipeline: ObservableObject {

    static let shared = MacroPipeline()

    @Published private(set) var state: AIProcessingState = .idle
    @Published private(set) var progress: Double = 0

    private let processingQueue = DispatchQueue(label: "com.hjd.camera.macroPipeline", qos: .userInitiated)

    private init() {}

    /// 处理微距图像。
    func process(frames: [CIImage],
                 mode: MacroMode = .fast,
                 completion: @escaping (CIImage?) -> Void) {
        state = .running
        progress = 0

        processingQueue.async { [weak self] in
            guard let self = self, !frames.isEmpty else {
                DispatchQueue.main.async {
                    self?.state = .failed
                    completion(nil)
                }
                return
            }

            // Stage 1: 主体识别
            self.progress = 0.1
            let subject = MacroSubjectDetector.shared.detect(image: frames[0])

            // Stage 2: 对焦评估
            self.progress = 0.25
            let focus = MacroFocusAssist.shared.evaluate(image: frames[0])

            // Stage 3: 多帧融合
            self.progress = 0.4
            let fusion = MacroMultiFrameFusion.shared.fuse(frames: frames)

            // Stage 4: 焦点堆叠（仅细节模式）
            var baseImage = fusion.image
            if mode == .detail {
                self.progress = 0.6
                let stack = FocusStackingEngine.shared.stack(frames: frames)
                baseImage = stack.image
            }

            // Stage 5: 细节超分
            self.progress = 0.8
            let scale: Double = mode == .detail ? 2.5 : 1.5
            let sr = MacroDetailSR.shared.superResolve(image: baseImage, scale: scale)

            // Stage 6: 质检
            self.progress = 0.95
            let report = AIQualityGuard.shared.evaluate(original: frames[0], processed: sr.image)
            let finalImage = report.shouldFallback ? baseImage : sr.image

            self.progress = 1.0
            self.state = .completed

            DispatchQueue.main.async {
                _ = subject
                _ = focus
                completion(finalImage)
            }
        }
    }
}
