//
//  Outpainter.swift
//  HJD Camera Pro
//
//  智能扩图：扩展图像边界，用 AI 生成合理的边缘内容。
//

import Foundation
import CoreImage

final class Outpainter {

    static let shared = Outpainter()

    struct OutpaintResult {
        var image: CIImage
        var originalExtent: CGRect
        var expandedExtent: CGRect
    }

    private init() {}

    /// 向四周扩展图像。
    /// - Parameters:
    ///   - image: 原始图像
    ///   - expansion: 扩展量（点）
    func outpaint(image: CIImage, expansion: CGFloat = 100) -> OutpaintResult {
        let originalExtent = image.extent
        let expandedExtent = CGRect(
            x: originalExtent.origin.x - expansion,
            y: originalExtent.origin.y - expansion,
            width: originalExtent.width + expansion * 2,
            height: originalExtent.height + expansion * 2
        )

        // 提取边缘条带
        let topStrip = image.cropped(to: CGRect(
            x: originalExtent.minX,
            y: originalExtent.maxY - 10,
            width: originalExtent.width,
            height: 10
        ))
        let bottomStrip = image.cropped(to: CGRect(
            x: originalExtent.minX,
            y: originalExtent.minY,
            width: originalExtent.width,
            height: 10
        ))
        let leftStrip = image.cropped(to: CGRect(
            x: originalExtent.minX,
            y: originalExtent.minY,
            width: 10,
            height: originalExtent.height
        ))
        let rightStrip = image.cropped(to: CGRect(
            x: originalExtent.maxX - 10,
            y: originalExtent.minY,
            width: 10,
            height: originalExtent.height
        ))

        // 拉伸边缘条带填充扩展区域
        let topFill = topStrip.transformed(by: CGAffineTransform(
            scaleX: 1, y: expansion / 10))
        let bottomFill = bottomStrip.transformed(by: CGAffineTransform(
            scaleX: 1, y: expansion / 10))
        let leftFill = leftStrip.transformed(by: CGAffineTransform(
            scaleX: expansion / 10, y: 1))
        let rightFill = rightStrip.transformed(by: CGAffineTransform(
            scaleX: expansion / 10, y: 1))

        // 组合
        var result = CIImage(color: .black).cropped(to: expandedExtent)
        result = result.composited(over: topFill.transformed(
            by: CGAffineTransform(translationX: 0, y: originalExtent.height)))
        result = result.composited(over: bottomFill)
        result = result.composited(over: leftFill.transformed(
            by: CGAffineTransform(translationX: 0, y: 0)))
        result = result.composited(over: rightFill.transformed(
            by: CGAffineTransform(translationX: originalExtent.width, y: 0)))
        result = result.composited(over: image.transformed(
            by: CGAffineTransform(translationX: expansion, y: expansion)))

        // 模糊接缝
        let final = result.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 2.0
        ])

        return OutpaintResult(
            image: final,
            originalExtent: originalExtent,
            expandedExtent: expandedExtent
        )
    }
}
