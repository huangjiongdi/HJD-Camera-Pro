//
//  MacroMultiFrameFusion.swift
//  HJD Camera Pro
//
//  微距多帧融合：对齐后融合多帧，提升信噪比与有效分辨率。
//

import Foundation
import CoreImage

final class MacroMultiFrameFusion {

    static let shared = MacroMultiFrameFusion()

    struct FusionResult {
        var image: CIImage
        var frameCount: Int
    }

    private init() {}

    /// 融合微距多帧。
    func fuse(frames: [CIImage]) -> FusionResult {
        guard !frames.isEmpty else {
            return FusionResult(image: CIImage.empty(), frameCount: 0)
        }

        let stabilization = MacroMotionStabilizer.shared.stabilize(frames: frames)
        let aligned = stabilization.alignedFrames

        var fused: CIImage = aligned[0]
        for frame in aligned.dropFirst() {
            fused = fused.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: frame
            ])
        }

        let norm = 1.0 / Double(aligned.count)
        let normalized = fused.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: norm, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: norm, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: norm, w: 0)
        ])

        return FusionResult(image: normalized, frameCount: aligned.count)
    }
}
