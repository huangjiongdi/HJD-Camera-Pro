import Foundation
import UIKit
import CoreImage

// MARK: - 水印系统

enum Watermark {

    /// 给图像加品牌水印
    static func apply(to image: UIImage, brand: String) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let W = CGFloat(cg.width)
        let H = CGFloat(cg.height)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
        return renderer.image { ctx in
            // 原图
            image.draw(in: CGRect(x: 0, y: 0, width: W, height: H))

            // 水印文字（右下角）
            let title = brand
            let subtitle = "HJD Camera Pro"
            let scale = W / 4032
            let titleSize = 56 * scale
            let subSize = 30 * scale
            let margin = 60 * scale

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: titleSize, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: subSize, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]

            let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
            let subStr = NSAttributedString(string: subtitle, attributes: subAttrs)

            let titleSize2 = titleStr.size()
            let subSize2 = subStr.size()
            let x = W - max(titleSize2.width, subSize2.width) - margin
            let y = H - titleSize2.height - subSize2.height - margin - 20*scale

            // 半透明阴影提升可读性
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.4)
            shadow.shadowBlurRadius = 6 * scale

            titleStr.draw(at: CGPoint(x: x, y: y))
            subStr.draw(at: CGPoint(x: x, y: y + titleSize2.height + 6*scale))
        }
    }
}
