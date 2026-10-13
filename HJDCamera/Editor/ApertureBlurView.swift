//
//  ApertureBlurView.swift
//  HJD Camera Pro
//
//  ReLens 式大光圈：
//    · Vision 人像分割（人物清晰、背景虚化）；无人像时用径向对焦
//    · 光圈 f/1.4–f/16 无级调节、虚化强度、光斑口径
//    · 点按画面选择对焦点
//    · 全分辨率渲染后写入相册，原图不受影响
//

import SwiftUI
import Photos
import CoreImage
import Vision
import UIKit

struct ApertureBlurView: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var mask: CIImage?
    @State private var focus: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var fStop: Double = 2.0
    @State private var intensity: Double = 1.0
    @State private var ringSize: Double = 0.2
    @State private var personDetected = false
    @State private var busy = true
    @State private var saving = false
    @State private var toast: String?

    private let engine = ApertureBlurEngine.shared
    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)
    private let fStops: [Double] = [1.4, 1.8, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack {
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            let p = value.location
                                            let nx = min(1, max(0, p.x / geo.size.width))
                                            let ny = min(1, max(0, p.y / geo.size.height))
                                            focus = CGPoint(x: nx, y: ny)
                                            HapticEngine.shared.selectionChanged()
                                            renderPreview()
                                        }
                                )
                                .overlay(alignment: .center) {
                                    if !personDetected {
                                        Image(systemName: "scope")
                                            .font(.system(size: 26))
                                            .foregroundColor(champagneGold.opacity(0.9))
                                            .position(x: focus.x * geo.size.width,
                                                      y: focus.y * geo.size.height)
                                    }
                                }
                        } else {
                            ProgressView().tint(champagneGold)
                        }
                        if busy {
                            VStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("正在生成景深…")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipped()

                controls
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
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
            Text("大光圈")
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
        VStack(spacing: 16) {
            HStack {
                Text("光圈")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 52, alignment: .leading)
                Slider(value: Binding(
                    get: { fStop },
                    set: { v in
                        fStop = v
                        renderPreview()
                    }), in: 1.4...16.0)
                .tint(champagneGold)
                Text("f/\(String(format: fStop < 2 ? "%.1f" : "%.0f", fStop))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(champagneGold)
                    .frame(width: 54, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach(fStops, id: \.self) { f in
                    Button {
                        fStop = f
                        HapticEngine.shared.selectionChanged()
                        renderPreview()
                    } label: {
                        Text(String(format: f < 2 ? "%.1f" : "%.0f", f))
                            .font(.system(size: 11, weight: abs(f - fStop) < 0.01 ? .bold : .regular))
                            .foregroundColor(abs(f - fStop) < 0.01 ? .black : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(abs(f - fStop) < 0.01 ? champagneGold : Color.white.opacity(0.08)))
                    }
                }
            }
            HStack {
                Text("虚化")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 52, alignment: .leading)
                Slider(value: Binding(
                    get: { intensity },
                    set: { v in
                        intensity = v
                        renderPreview()
                    }), in: 0.2...1.5)
                .tint(champagneGold)
                Text(String(format: "%.1f", intensity))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 54, alignment: .trailing)
            }
            HStack {
                Text("光斑")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 52, alignment: .leading)
                Slider(value: Binding(
                    get: { ringSize },
                    set: { v in
                        ringSize = v
                        renderPreview()
                    }), in: 0...0.8)
                .tint(champagneGold)
                Text(String(format: "%.2f", ringSize))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 54, alignment: .trailing)
            }
            Text(personDetected ? "已识别人物：人物清晰、背景大光圈虚化" : "未识别人物：以对焦点为中心径向虚化，点画面可移动对焦")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .onAppear(perform: prepare)
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
            DispatchQueue.global(qos: .userInitiated).async {
                let ci = CIImage(image: img)
                let m = engine.personMask(image: ci)
                DispatchQueue.main.async {
                    self.original = img
                    self.mask = m
                    self.personDetected = m != nil
                    self.busy = false
                    renderPreview()
                }
            }
        }
    }

    private var renderWorkItem: DispatchWorkItem?
    private func renderPreview() {
        renderWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard let img = original else { return }
            let out = engine.apply(
                image: img,
                personMask: mask,
                focusNormalized: focus,
                fStop: fStop,
                intensity: intensity,
                ringSize: ringSize,
                maxSide: 1600)
            DispatchQueue.main.async {
                self.preview = out
            }
        }
        renderWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func save() {
        guard let img = original else { return }
        saving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = engine.apply(
                image: img,
                personMask: mask,
                focusNormalized: focus,
                fStop: fStop,
                intensity: intensity,
                ringSize: ringSize,
                maxSide: 4096)
            guard let data = out.jpegData(compressionQuality: 0.95) else {
                DispatchQueue.main.async {
                    saving = false
                    toast = "渲染失败"
                }
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

final class ApertureBlurEngine {
    static let shared = ApertureBlurEngine()
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    private init() {}

    /// Vision 人像分割：白色=人物。返回的 mask 已缩放到图像 extent。
    func personMask(image: CIImage?) -> CIImage? {
        guard let image else { return nil }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image.oriented(.up), options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        var mask = CIImage(cvPixelBuffer: buffer)
        // Vision 坐标系与 CIImage 一致（纵向翻转后），统一缩放到输入尺寸。
        let sx = image.extent.width / mask.extent.width
        let sy = image.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        // 羽化边缘，避免抠像硬边。
        mask = mask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
            .cropped(to: image.extent)
        return mask
    }

    /// 大光圈渲染。
    /// - Parameters:
    ///   - fStop: 1.4（虚化最强）… 16（最弱）
    ///   - intensity: 整体虚化倍率
    ///   - ringSize: 光斑口径 0…0.8
    func apply(image: UIImage,
               personMask: CIImage?,
               focusNormalized: CGPoint,
               fStop: Double,
               intensity: Double,
               ringSize: Double,
               maxSide: CGFloat) -> UIImage {
        guard let src = CIImage(image: image) else { return image }
        let scale = min(1, maxSide / max(src.extent.width, src.extent.height))
        var base = src
        if scale < 1 {
            base = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let extent = base.extent

        // 光圈映射：f/1.4≈半径 28，f/16≈半径 3，非线性。
        let radius = max(2, (32.0 / fStop) * intensity) * Double(scale)

        var blurred: CIImage = base
            .applyingFilter("CIBokehBlur", parameters: [
                kCIInputRadiusKey: radius,
                "inputRingAmount": 0.35,
                "inputRingSize": ringSize,
                "inputSoftness": 1.0
            ])

        var mask: CIImage
        if let personMask {
            var m = personMask
            if scale < 1 {
                m = m.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            mask = m.cropped(to: extent)
        } else {
            // 径向对焦：以对焦点为中心，近清远虚。
            let center = CIVector(x: focusNormalized.x * extent.width,
                                  y: (1 - focusNormalized.y) * extent.height)
            let r = min(extent.width, extent.height) * 0.32
            let radial = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": r * 0.45,
                "inputRadius1": r,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0)
            ])?.outputImage?.cropped(to: extent)
            mask = radial ?? CIImage(color: CIColor.white).cropped(to: extent)
        }

        let composited = blurred
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputImageKey: base,
                kCIInputBackgroundImageKey: blurred,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: extent)

        if let cg = ciContext.createCGImage(composited, from: extent) {
            return UIImage(cgImage: cg, scale: 1, orientation: image.imageOrientation)
        }
        return image
    }
}
