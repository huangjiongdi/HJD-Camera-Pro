//
//  RetroFrameView.swift
//  HJD Camera Pro
//
//  OldRoll 式复古相机：
//    · 拍立得白框 / 胶片黑框 / 无框
//    · 橙色日期戳、胶片颗粒、暗角
//    · 全分辨率渲染后写入相册，原图保留
//

import SwiftUI
import Photos
import CoreImage
import UIKit

struct RetroFrameView: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var busy = true
    @State private var saving = false
    @State private var toast: String?

    @State private var frameStyle: FrameStyle = .polaroid
    @State private var dateStamp: Bool = true
    @State private var grain: Double = 0.35
    @State private var vignette: Double = 0.45

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)
    private let engine = RetroFrameEngine.shared

    init(asset: PHAsset) {
        self.asset = asset
    }

    enum FrameStyle: String, CaseIterable {
        case polaroid = "拍立得"
        case film = "胶片"
        case borderless = "无框"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 380)
                            .padding(.horizontal, 14)
                    } else {
                        ProgressView().tint(champagneGold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 400)

                controls
                    .padding(.horizontal, 18)
            }
            .safeAreaInset(edge: .top) { topBar }
            .safeAreaInset(edge: .bottom) { bottomBar }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(champagneGold))
                        .padding(.bottom, 90)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("取消") { dismiss() }
                .foregroundColor(.white.opacity(0.85))
                .font(.system(size: 15))
            Spacer()
            Text("复古相机")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6))
    }

    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                ForEach(FrameStyle.allCases, id: \.self) { style in
                    Button {
                        frameStyle = style
                        HapticEngine.shared.selectionChanged()
                        renderPreview()
                    } label: {
                        Text(style.rawValue)
                            .font(.system(size: 13, weight: frameStyle == style ? .bold : .regular))
                            .foregroundColor(frameStyle == style ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(frameStyle == style ? champagneGold : Color.white.opacity(0.08)))
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { dateStamp },
                set: { v in dateStamp = v; renderPreview() }
            )) {
                Text("橙色日期戳")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
            }
            .tint(champagneGold)

            sliderRow("颗粒", value: Binding(
                get: { grain },
                set: { v in grain = v; renderPreview() }
            ), range: 0...1)
            sliderRow("暗角", value: Binding(
                get: { vignette },
                set: { v in vignette = v; renderPreview() }
            ), range: 0...1)
        }
        .onAppear(perform: prepare)
    }

    private func sliderRow(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 52, alignment: .leading)
            Slider(value: value, in: range).tint(champagneGold)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 54, alignment: .trailing)
        }
    }

    private var bottomBar: some View {
        Button {
            save()
        } label: {
            HStack {
                if saving {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
                Text(saving ? "渲染保存中…" : "保存到相册")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(champagneGold))
        }
        .disabled(saving)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Logic

    private func prepare() {
        busy = true
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let manager = PHCachingImageManager()
        manager.requestImage(for: asset, targetSize: CGSize(width: 2048, height: 2048),
                            contentMode: .aspectFit, options: options) { img, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let img, !degraded else { return }
            DispatchQueue.main.async {
                original = img
                busy = false
                renderPreview()
            }
        }
    }

    @State private var workItem: DispatchWorkItem?
    private func renderPreview() {
        workItem?.cancel()
        let work = DispatchWorkItem {
            guard let img = original else { return }
            let out = engine.render(
                image: img,
                style: frameStyle,
                dateStamp: dateStamp,
                date: asset.creationDate ?? Date(),
                grain: grain,
                vignette: vignette,
                maxSide: 1500)
            DispatchQueue.main.async { preview = out }
        }
        workItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func save() {
        guard let img = original else { return }
        saving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = engine.render(
                image: img,
                style: frameStyle,
                dateStamp: dateStamp,
                date: asset.creationDate ?? Date(),
                grain: grain,
                vignette: vignette,
                maxSide: 4096)
            guard let data = out.jpegData(compressionQuality: 0.95) else {
                DispatchQueue.main.async { saving = false; toast = "渲染失败" }
                return
            }
            Task {
                let result = await PhotoLibraryExporter.shared.exportPhoto(data: data)
                await MainActor.run {
                    saving = false
                    switch result {
                    case .success:
                        toast = "已保存到相册（原图保留）"
                        HapticEngine.shared.trigger(.exportComplete)
                    case .failure(let e):
                        toast = e.description
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        toast = nil
                        if case .success = result { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Engine

final class RetroFrameEngine {
    static let shared = RetroFrameEngine()
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private init() {}

    func render(image: UIImage,
                style: RetroFrameView.FrameStyle,
                dateStamp: Bool,
                date: Date,
                grain: Double,
                vignette: Double,
                maxSide: CGFloat) -> UIImage {
        guard let src = CIImage(image: image) else { return image }
        let scale = min(1, maxSide / max(src.extent.width, src.extent.height))
        var base = src
        if scale < 1 {
            base = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // 1) 暗角
        if vignette > 0.01 {
            let intensity = Float(vignette * 2.2)
            let radius = Float(min(base.extent.width, base.extent.height) * 0.9)
            base = base.applyingFilter("CIVignette", parameters: [
                "inputIntensity": intensity,
                "inputRadius": radius
            ])
        }

        // 2) 颗粒：灰度噪声 contrast=0 时为中性灰，叠加混合等于原图。
        if grain > 0.01, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let gray = noise
                .applyingFilter("CIPhotoEffectMono")
                .cropped(to: base.extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0,
                    kCIInputContrastKey: grain * 0.55,
                    kCIInputSaturationKey: 0
                ])
            base = base.applyingFilter("CIOverlayBlendMode", parameters: [
                kCIInputBackgroundImageKey: gray
            ]).cropped(to: base.extent)
        }
        base = base.cropped(to: CGRect(origin: .zero, size: base.extent.size))

        guard let cg = ciContext.createCGImage(base, from: base.extent) else { return image }
        let styled = UIImage(cgImage: cg, scale: 1, orientation: image.imageOrientation)

        // 3) 相框 + 日期戳（UIKit 合成）
        return composeFrame(styled: styled, style: style, dateStamp: dateStamp, date: date)
    }

    private func composeFrame(styled: UIImage,
                              style: RetroFrameView.FrameStyle,
                              dateStamp: Bool,
                              date: Date) -> UIImage {
        let imgSize = styled.size
        let width = imgSize.width

        let pad: CGFloat
        let bottomPad: CGFloat
        let canvasSize: CGSize

        switch style {
        case .polaroid:
            pad = width * 0.045
            bottomPad = width * 0.22
            canvasSize = CGSize(width: width + pad * 2,
                                height: imgSize.height + pad * 2 + bottomPad)
        case .film:
            pad = width * 0.03
            bottomPad = pad
            canvasSize = CGSize(width: width + pad * 2,
                                height: imgSize.height + pad * 2)
        case .borderless:
            pad = 0
            bottomPad = 0
            canvasSize = imgSize
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            // 背景
            let bgColor: UIColor = style == .film ? .black : .white
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            let imageOrigin = CGPoint(x: pad, y: pad)
            styled.draw(in: CGRect(origin: imageOrigin, size: imgSize))

            if style == .film {
                // 胶片内细白线
                let line = CGRect(x: pad * 0.45, y: pad * 0.45,
                                  width: width + pad * 1.1,
                                  height: imgSize.height + pad * 1.1)
                UIColor.white.withAlphaComponent(0.25).setStroke()
                let path = UIBezierPath(rect: line)
                path.lineWidth = 1.5
                path.stroke()
            }

            if dateStamp {
                let f = DateFormatter()
                f.dateFormat = "yyyy.MM.dd"
                let text = f.string(from: date)
                let fontSize: CGFloat = max(18, width * 0.032)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "CourierNewPS-BoldMT", size: fontSize)
                        ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor(red: 1.0, green: 0.38, blue: 0.12, alpha: 1.0)
                ]
                let textSize = (text as NSString).size(withAttributes: attrs)
                let margin: CGFloat = width * 0.05
                let point: CGPoint
                if style == .polaroid {
                    point = CGPoint(x: canvasSize.width - margin - textSize.width,
                                    y: pad + imgSize.height + (bottomPad - textSize.height) / 2)
                } else {
                    point = CGPoint(x: canvasSize.width - margin - textSize.width,
                                    y: canvasSize.height - margin - textSize.height)
                }
                (text as NSString).draw(at: point, withAttributes: attrs)
            }
        }
    }
}
