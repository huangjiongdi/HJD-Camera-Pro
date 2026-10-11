//
//  SkinTexturePreserver.swift
//  HJD Camera Pro
//
//  皮肤纹理保护：磨皮时保留毛孔、细纹等真实皮肤纹理。
//

import Foundation
import CoreImage

final class SkinTexturePreserver {

    static let shared = SkinTexturePreserver()

    struct PreserveResult {
        var image: CIImage
        var textureRetention: Double  // 保留的纹理比例 0-1
    }

    private init() {}

    /// 平滑皮肤但保留纹理。
    func preserve(image: CIImage, segmentation: PortraitSegmentation.SegmentationResult) -> PreserveResult {
        // 轻度平滑
        let smoothed = image.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 1.5
        ])

        // 提取高频纹理
        let texture = image.applyingFilter("CIDifferenceBlendMode", parameters: [
            kCIInputBackgroundImageKey: smoothed
        ])

        // 以 30% 强度加回纹理，保留真实皮肤质感
        let blended = smoothed.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: texture.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.3, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.3, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.3, w: 0)
            ])
        ])

        // 只在人物区域应用
        let masked = blended.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: segmentation.personMask
        ])

        return PreserveResult(image: masked, textureRetention: 0.3)
    }
}
