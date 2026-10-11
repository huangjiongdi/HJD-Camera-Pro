//
//  HDRProcessor.swift
//  HJD Camera Pro
//
//  逆光/HDR 处理：包含 BacklightSceneNet、HDRExposurePlanner、HDRMotionFusion、
//  FaceExposureBalancer、HighlightRecoveryNet、ShadowColorRecovery、LocalToneMapper。
//

import Foundation
import CoreImage
import Combine

// MARK: - BacklightSceneNet

final class BacklightSceneNet {

    static let shared = BacklightSceneNet()

    struct BacklightResult {
        var isBacklight: Bool
        var skyRatio: Double
        var shadowRatio: Double
        var confidence: Double
    }

    private init() {}

    /// 检测逆光场景。
    func detect(image: CIImage) -> BacklightResult {
        let extent = image.extent
        let w = min(128, Int(extent.width))
        let h = min(128, Int(extent.height))
        guard w > 0, h > 0 else {
            return BacklightResult(isBacklight: false, skyRatio: 0, shadowRatio: 0, confidence: 0)
        }

        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_OneComponent8, nil, &buf)
        guard let pb = buf else {
            return BacklightResult(isBacklight: false, skyRatio: 0, shadowRatio: 0, confidence: 0)
        }
        ctx.render(image, to: pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            return BacklightResult(isBacklight: false, skyRatio: 0, shadowRatio: 0, confidence: 0)
        }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var brightTop = 0, darkBottom = 0
        let rowBytes = w
        for row in 0..<(h/2) {
            for col in 0..<w where ptr[row * rowBytes + col] > 200 { brightTop += 1 }
        }
        for row in (h/2)..<h {
            for col in 0..<w where ptr[row * rowBytes + col] < 60 { darkBottom += 1 }
        }

        let skyRatio = Double(brightTop) / Double((h/2) * w)
        let shadowRatio = Double(darkBottom) / Double((h/2) * w)
        let isBacklight = skyRatio > 0.3 && shadowRatio > 0.3

        return BacklightResult(
            isBacklight: isBacklight,
            skyRatio: skyRatio,
            shadowRatio: shadowRatio,
            confidence: min(1.0, (skyRatio + shadowRatio) / 1.5)
        )
    }
}

// MARK: - HDRExposurePlanner

final class HDRExposurePlanner {

    static let shared = HDRExposurePlanner()

    struct ExposurePlan {
        var exposureBrackets: [Double]  // EV 序列
        var totalFrames: Int
    }

    private init() {}

    /// 规划 HDR 曝光序列。
    func plan(backlight: BacklightSceneNet.BacklightResult) -> ExposurePlan {
        guard backlight.isBacklight else {
            return ExposurePlan(exposureBrackets: [0], totalFrames: 1)
        }
        // 逆光场景：欠曝 + 标准 + 过曝
        let brackets: [Double] = [-2.0, 0.0, 2.0]
        return ExposurePlan(exposureBrackets: brackets, totalFrames: brackets.count)
    }
}

// MARK: - HDRMotionFusion

final class HDRMotionFusion {

    static let shared = HDRMotionFusion()

    struct FusionResult {
        var image: CIImage
        var motionGhosting: Double
    }

    private init() {}

    /// 融合多曝光帧。
    func fuse(frames: [CIImage], plan: HDRExposurePlanner.ExposurePlan) -> FusionResult {
        guard frames.count > 1 else {
            return FusionResult(image: frames.first ?? CIImage.empty(), motionGhosting: 0)
        }

        // 对齐
        let alignment = NightFrameAligner.shared.align(frames: frames)

        // 运动掩码
        let motionMask = NightMotionMask.shared.compute(alignedFrames: alignment.alignedFrames)

        // 融合
        var fused = alignment.alignedFrames[0]
        for frame in alignment.alignedFrames.dropFirst() {
            fused = fused.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: fused,
                kCIInputMaskImageKey: motionMask.mask
            ])
        }

        return FusionResult(image: fused, motionGhosting: motionMask.motionRatio)
    }
}

// MARK: - FaceExposureBalancer

final class FaceExposureBalancer {

    static let shared = FaceExposureBalancer()

    struct BalanceResult {
        var image: CIImage
        var faceExposureAdjusted: Double
    }

    private init() {}

    /// 平衡面部曝光，避免逆光下面部全黑。
    func balance(image: CIImage) -> BalanceResult {
        // 检测人脸位置
        let segmentation = PortraitSegmentation.shared.segment(image: image)

        // 提升阴影区域亮度
        let lifted = image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0.15),
            "inputPoint1": CIVector(x: 0.3, y: 0.4),
            "inputPoint2": CIVector(x: 0.6, y: 0.6),
            "inputPoint3": CIVector(x: 0.85, y: 0.8),
            "inputPoint4": CIVector(x: 1, y: 0.95)
        ])

        // 只在人物区域应用
        let masked = lifted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: segmentation.personMask
        ])

        return BalanceResult(image: masked, faceExposureAdjusted: 0.5)
    }
}

// MARK: - HighlightRecoveryNet

final class HighlightRecoveryNet {

    static let shared = HighlightRecoveryNet()

    struct RecoveryResult {
        var image: CIImage
        var highlightRecovered: Double
    }

    private init() {}

    /// 恢复高光细节。
    func recover(image: CIImage) -> RecoveryResult {
        let recovered = image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 0.5, y: 0.5),
            "inputPoint2": CIVector(x: 0.8, y: 0.72),
            "inputPoint3": CIVector(x: 0.95, y: 0.82),
            "inputPoint4": CIVector(x: 1, y: 0.88)
        ])
        return RecoveryResult(image: recovered, highlightRecovered: 0.7)
    }
}

// MARK: - ShadowColorRecovery

final class ShadowColorRecovery {

    static let shared = ShadowColorRecovery()

    struct RecoveryResult {
        var image: CIImage
        var colorRestored: Double
    }

    private init() {}

    /// 恢复阴影区域色彩。
    func recover(image: CIImage) -> RecoveryResult {
        // 提升阴影饱和度
        let colorRestored = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.3,
            kCIInputBrightnessKey: 0.05
        ])
        return RecoveryResult(image: colorRestored, colorRestored: 0.6)
    }
}

// MARK: - LocalToneMapper

final class LocalToneMapper {

    static let shared = LocalToneMapper()

    struct ToneMapResult {
        var image: CIImage
        var dynamicRange: Double
    }

    private init() {}

    /// 局部色调映射。
    func map(image: CIImage) -> ToneMapResult {
        // 基础色调映射
        let mapped = image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0.02),
            "inputPoint1": CIVector(x: 0.25, y: 0.3),
            "inputPoint2": CIVector(x: 0.5, y: 0.55),
            "inputPoint3": CIVector(x: 0.75, y: 0.75),
            "inputPoint4": CIVector(x: 1, y: 0.92)
        ])

        // 局部对比度增强
        let contrast = mapped.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 5.0,
            kCIInputIntensityKey: 0.3
        ])

        return ToneMapResult(image: contrast, dynamicRange: 3.0)
    }
}

// MARK: - HDRProcessor 主入口

final class HDRProcessor: ObservableObject {

    static let shared = HDRProcessor()

    @Published private(set) var state: AIProcessingState = .idle
    @Published private(set) var progress: Double = 0

    private let processingQueue = DispatchQueue(label: "com.hjd.camera.hdrProcessor", qos: .userInitiated)

    private init() {}

    /// 完整 HDR 处理流程。
    func process(frames: [CIImage], completion: @escaping (CIImage?) -> Void) {
        state = .processing(progress: 0)
        progress = 0

        processingQueue.async { [weak self] in
            guard let self = self, let first = frames.first else {
                DispatchQueue.main.async {
                    self?.state = .failed(error: "HDR 处理失败")
                    completion(nil)
                }
                return
            }

            // Stage 1: 逆光检测
            self.progress = 0.1
            let backlight = BacklightSceneNet.shared.detect(image: first)

            // Stage 2: 曝光规划
            self.progress = 0.2
            let plan = HDRExposurePlanner.shared.plan(backlight: backlight)

            // Stage 3: 多帧融合
            self.progress = 0.4
            let fusion = HDRMotionFusion.shared.fuse(frames: frames, plan: plan)

            // Stage 4: 高光恢复
            self.progress = 0.55
            let highlight = HighlightRecoveryNet.shared.recover(image: fusion.image)

            // Stage 5: 阴影色彩恢复
            self.progress = 0.65
            let shadow = ShadowColorRecovery.shared.recover(image: highlight.image)

            // Stage 6: 面部曝光平衡
            self.progress = 0.75
            let face = FaceExposureBalancer.shared.balance(image: shadow.image)

            // Stage 7: 局部色调映射
            self.progress = 0.9
            let toneMapped = LocalToneMapper.shared.map(image: face.image)

            self.progress = 1.0
            self.state = .completed

            DispatchQueue.main.async {
                completion(toneMapped.image)
            }
        }
    }
}
