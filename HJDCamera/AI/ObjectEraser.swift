//
//  ObjectEraser.swift
//  HJD Camera Pro
//
//  物体擦除：智能移除指定区域的物体，用周围纹理填充。
//

import Foundation
import CoreImage

final class ObjectEraser {

    static let shared = ObjectEraser()

    struct EraseResult {
        var image: CIImage
        var regionFilled: CGRect
    }

    private init() {}

    /// 擦除指定区域的物体。
    func erase(image: CIImage, region: CGRect) -> EraseResult {
        // 提取周围纹理
        let expanded = region.insetBy(dx: -20, dy: -20)
        let surrounding = image.cropped(to: expanded)

        // 用周围区域的模糊版填充目标区域
        let fill = surrounding.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 15.0
        ])

        // 创建掩码
        let mask = CIImage(color: CIColor.white).cropped(to: region)
        let blurredMask = mask.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 5.0
        ])

        // 混合
        let blended = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: fill,
            kCIInputMaskImageKey: blurredMask
        ])

        return EraseResult(image: blended, regionFilled: region)
    }
}
