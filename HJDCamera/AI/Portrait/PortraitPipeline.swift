//
//  PortraitPipeline.swift
//  HJD Camera Pro
//
//  人像完整流程：分割 → 曝光 → 超分 → 皮肤保护 → 身份检查 → 输出。
//

import Foundation
import CoreImage
import Combine

final class PortraitPipeline: ObservableObject {

    static let shared = PortraitPipeline()

    @Published private(set) var state: AIProcessingState = .idle
    @Published private(set) var progress: Double = 0

    private let processingQueue = DispatchQueue(label: "com.hjd.camera.portraitPipeline", qos: .userInitiated)

    private init() {}

    /// 完整人像处理。
    func process(image: CIImage, completion: @escaping (CIImage?) -> Void) {
        state = .processing(progress: 0)
        progress = 0

        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Stage 1: 人物分割
            self.progress = 0.15
            let segmentation = PortraitSegmentation.shared.segment(image: image)

            // Stage 2: 光照调节
            self.progress = 0.3
            let relight = PortraitRelighting.shared.relight(
                image: image, segmentation: segmentation)

            // Stage 3: 人脸超分
            self.progress = 0.5
            let sr = PortraitSR.shared.superResolveFace(image: relight.image)

            // Stage 4: 皮肤纹理保护
            self.progress = 0.7
            let skin = SkinTexturePreserver.shared.preserve(
                image: sr.image, segmentation: segmentation)

            // Stage 5: 身份检查
            self.progress = 0.9
            let identity = FaceIdentityGuard.shared.check(
                original: image, processed: skin.image)

            let finalImage = identity.identityPreserved ? skin.image : relight.image

            self.progress = 1.0
            self.state = .completed

            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
    }
}
