//
//  WatermarkGenerator.swift
//  HJD Camera Pro
//
//  Draws customizable watermarks (text, date, lens parameters, device tag)
//  onto finished images using Core Graphics.
//

import Foundation
import CoreGraphics
import UIKit

struct WatermarkConfig {
    var style: WatermarkStyle
    var showDate: Bool
    var showLensParams: Bool
    var showDeviceTag: Bool
    var customText: String
    var corner: Corner
    var fontSize: CGFloat

    enum Corner {
        case bottomLeading, bottomTrailing, topLeading, topTrailing
    }

    static let `default` = WatermarkConfig(
        style: .minimal,
        showDate: true,
        showLensParams: false,
        showDeviceTag: true,
        customText: "HJD Camera Pro",
        corner: .bottomTrailing,
        fontSize: 24
    )
}

final class WatermarkGenerator {
    static let shared = WatermarkGenerator()

    private init() {}

    // MARK: - Apply watermark to a CGImage

    func apply(
        to image: CGImage,
        config: WatermarkConfig,
        params: String? = nil
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        let scale = CGFloat(max(width, height)) / 1000.0  // scale font to image size

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw the base image.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard config.style != .none else {
            return context.makeImage()
        }

        // Compose the watermark text lines.
        var lines: [String] = []
        if !config.customText.isEmpty { lines.append(config.customText) }
        if config.showDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            lines.append(formatter.string(from: Date()))
        }
        if config.showLensParams, let params = params, !params.isEmpty {
            lines.append(params)
        }
        if config.showDeviceTag {
            lines.append(DeviceCapabilityManager.shared.deviceModelName())
        }

        draw(lines: lines,
             context: context,
             width: width,
             height: height,
             fontSize: config.fontSize * max(scale, 0.5),
             corner: config.corner)

        return context.makeImage()
    }

    // MARK: - Drawing

    private func draw(
        lines: [String],
        context: CGContext,
        width: Int,
        height: Int,
        fontSize: CGFloat,
        corner: WatermarkConfig.Corner
    ) {
        guard !lines.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        switch corner {
        case .bottomLeading, .topLeading:
            paragraph.alignment = .left
        case .bottomTrailing, .topTrailing:
            paragraph.alignment = .right
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            .paragraphStyle: paragraph
        ]

        let lineHeight = fontSize * 1.3
        let inset = fontSize * 1.2
        let totalHeight = CGFloat(lines.count) * lineHeight

        var y: CGFloat
        switch corner {
        case .topLeading, .topTrailing:
            y = inset
        case .bottomLeading, .bottomTrailing:
            y = CGFloat(height) - inset - totalHeight
        }

        for (index, line) in lines.enumerated() {
            let rect: CGRect
            switch corner {
            case .topLeading, .bottomLeading:
                rect = CGRect(x: inset, y: y + CGFloat(index) * lineHeight,
                              width: CGFloat(width) - inset * 2, height: lineHeight)
            case .topTrailing, .bottomTrailing:
                rect = CGRect(x: inset, y: y + CGFloat(index) * lineHeight,
                              width: CGFloat(width) - inset * 2, height: lineHeight)
            }
            (line as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
