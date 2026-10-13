//
//  FilterStripView.swift
//  HJD Camera Pro
//
//  极影式拍摄页滤镜条（r10）：
//    · 横向圆形真实 LUT 缩略图（缩略图由真实 HALD/cube 在一张全色相
//      参考图上逐滤镜渲染，不是假色块），选中金圈、自动滚动居中。
//    · 顶部分类胶囊：徕卡 / 经典 / 胶片 / 电影感 / 人像 / 风景 / 黑白 /
//      风格 / Log 系列，首个固定为“无”。
//    · 强度滑杆 0–100，成片强度实时联动（拍照链路按 LUTManager 烘焙）。
//    · 长按任意缩略图：临时对比原图，松手恢复滤镜。
//    · 照片/视频/实况通用；选中后成片由 PhotoCapturePipeline 注入，
//      原图始终保留（keepOriginal）。
//

import SwiftUI
import CoreImage
import UIKit

struct FilterStripView: View {
    @EnvironmentObject var lut: LUTManager
    @EnvironmentObject var haptic: HapticEngine
    @State private var category: LUTCategory = .leica
    @State private var thumbs: [String: UIImage] = [:]
    @State private var compareBackup: String? = nil
    /// 跨分类时作废旧渲染批次（引用类型，保证后台闭包读到实时值）。
    @State private var genBox = FilterGenToken()

    private final class FilterGenToken { var token: Int = 0 }

    private let gold = Color(red: 0.85, green: 0.75, blue: 0.55)
    private let tile: CGFloat = 54

    private var categories: [LUTCategory] {
        var cats = LUTCategory.allCases.filter { $0 != .custom }
        if !lut.customLUTs.isEmpty { cats.append(.custom) }
        return cats
    }

    private var items: [LUTInfo] {
        category == .custom ? lut.customLUTs : lut.luts(in: category)
    }

    var body: some View {
        VStack(spacing: 7) {
            categoryRow
            strip
            if lut.activeLUTName != "None" {
                intensityRow
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.42))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(gold.opacity(0.25), lineWidth: 1))
        )
        .padding(.horizontal, 10)
        .onAppear {
            if let cat = lut.info(named: lut.activeLUTName)?.category {
                category = cat
            }
            generateThumbnails(for: category)
        }
        .onChange(of: category) { _, cat in
            generateThumbnails(for: cat)
        }
    }

    // MARK: 分类

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let on = category == cat
                    Button {
                        haptic.selectionChanged()
                        withAnimation(.easeOut(duration: 0.18)) { category = cat }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 11, weight: on ? .semibold : .regular))
                            .foregroundColor(on ? .black : .white.opacity(0.72))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(on ? gold : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    // MARK: 滤镜横滑条

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    noneTile
                    ForEach(items) { info in
                        filterTile(info)
                            .id(info.name)
                    }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: lut.activeLUTName) { _, name in
                if name != "None" {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(name, anchor: .center)
                    }
                }
            }
            .onChange(of: category) { _, cat in
                if lut.info(named: lut.activeLUTName)?.category == cat,
                   lut.activeLUTName != "None" {
                    proxy.scrollTo(lut.activeLUTName, anchor: .center)
                }
            }
        }
        .frame(height: tile + 22)
    }

    private var noneTile: some View {
        let on = lut.activeLUTName == "None"
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: tile, height: tile)
                Image(systemName: "slash.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .overlay(Circle().stroke(on ? gold : Color.white.opacity(0.22),
                                     lineWidth: on ? 2.5 : 1))
            Text("原图")
                .font(.system(size: 9, weight: on ? .semibold : .regular))
                .foregroundColor(on ? gold : .white.opacity(0.6))
        }
        .onTapGesture {
            haptic.selectionChanged()
            lut.selectLUT("None")
        }
    }

    private func filterTile(_ info: LUTInfo) -> some View {
        let on = lut.activeLUTName == info.name
        return VStack(spacing: 4) {
            ZStack {
                if let img = thumbs[info.name] {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tile, height: tile)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: tile, height: tile)
                        .overlay(ProgressView().tint(.white.opacity(0.7)))
                }
            }
            .overlay(Circle().stroke(on ? gold : Color.white.opacity(0.22),
                                     lineWidth: on ? 2.5 : 1))
            .scaleEffect(on ? 1.08 : 1.0)
            .shadow(color: on ? gold.opacity(0.55) : .clear, radius: 6)
            Text(info.name)
                .font(.system(size: 9, weight: on ? .semibold : .regular))
                .foregroundColor(on ? gold : .white.opacity(0.65))
                .lineLimit(1)
                .frame(width: 64)
        }
        .onTapGesture {
            haptic.selectionChanged()
            if lut.activeLUTName == info.name {
                lut.selectLUT("None")
            } else {
                lut.selectLUT(info.name)
            }
        }
        .onLongPressGesture(minimumDuration: 0.28, perform: {
            // 长按：开始对比原图（onPressingChanged 里处理按下与松手）。
        }, onPressingChanged: { pressing in
            if pressing {
                if compareBackup == nil, lut.activeLUTName != "None" {
                    compareBackup = lut.activeLUTName
                    lut.selectLUT("None")
                    haptic.trigger(.focus, type: .light)
                }
            } else {
                if let old = compareBackup {
                    lut.selectLUT(old)
                    compareBackup = nil
                    haptic.selectionChanged()
                }
            }
        })
    }

    // MARK: 强度

    private var intensityRow: some View {
        HStack(spacing: 10) {
            Text("强度")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            Image(systemName: "circle")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
            Slider(value: Binding(
                get: { lut.intensity },
                set: { v in
                    lut.intensity = v
                    if Int(v * 100) % 10 == 0 { haptic.selectionChanged() }
                }
            ), in: 0...1, step: 0.01)
            .tint(gold)
            Image(systemName: "circle.fill")
                .font(.system(size: 11))
                .foregroundColor(gold)
            Text("\(Int(lut.intensity * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(gold)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }

    // MARK: 缩略图渲染

    private func generateThumbnails(for cat: LUTCategory) {
        genBox.token += 1
        let token = genBox.token
        let box = genBox
        let list = cat == .custom ? lut.customLUTs : lut.luts(in: cat)
        let names = list.map { $0.name }
        // 立刻用缓存命中的图刷新。
        var cached: [String: UIImage] = [:]
        for n in names { if let img = FilterThumbnailCache.shared.image(named: n) { cached[n] = img } }
        thumbs = cached

        let missing = names.filter { FilterThumbnailCache.shared.image(named: $0) == nil }
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let renderer = FilterThumbnailRenderer()
            for (idx, name) in missing.enumerated() {
                if box.token != token { return }
                let img = renderer.render(name: name)
                if let img {
                    FilterThumbnailCache.shared.store(img, named: name)
                    DispatchQueue.main.async {
                        if box.token != token { return }
                        thumbs[name] = img
                    }
                }
                // 每渲染 4 个让一次主线程，避免抢占拍照 UI。
                if idx % 4 == 3 { Thread.sleep(forTimeInterval: 0.012) }
            }
        }
    }
}

// MARK: - 全色相参考图 + LUT 缩略图渲染

final class FilterThumbnailRenderer {
    private let ctx: CIContext
    private let refCIImage: CIImage
    private let refSize: CGFloat = 96

    init() {
        self.ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        let ui = FilterThumbnailRenderer.makeReference(size: Int(refSize))
        self.refCIImage = CIImage(image: ui) ?? CIImage()
    }

    func render(name: String) -> UIImage? {
        guard !refCIImage.extent.isEmpty else { return nil }
        let out = LUTApplier.shared.applyLUT(named: name, to: refCIImage, intensity: 0.8)
        guard let cg = ctx.createCGImage(out, from: refCIImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 横向全色相、纵向亮度渐变的参考图，保证任意 LUT 的色调变化可见。
    static func makeReference(size: Int) -> UIImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let cgctx = CGContext(data: nil, width: size, height: size,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return UIImage() }
        for y in 0..<size {
            let bright = 0.18 + 0.82 * (CGFloat(y) / CGFloat(size - 1))
            for x in 0..<size {
                let hue = CGFloat(x) / CGFloat(size)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                UIColor(hue: hue, saturation: 0.78, brightness: bright, alpha: 1)
                    .getRed(&r, green: &g, blue: &b, alpha: nil)
                cgctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
                cgctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        // 底部画一条中性灰阶，让黑白/对比度类 LUT 也能看出差异。
        let grayH = size / 8
        for x in 0..<size {
            let v = CGFloat(x) / CGFloat(size - 1)
            cgctx.setFillColor(red: v, green: v, blue: v, alpha: 1)
            cgctx.fill(CGRect(x: x, y: 0, width: 1, height: grayH))
        }
        guard let cg = cgctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

/// 可复用的真实 LUT 缩略图（滤镜设置页/拍摄页共用）。
struct FilterThumbnailView: View {
    let name: String
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    ProgressView().tint(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: load)
    }

    private func load() {
        if let cached = FilterThumbnailCache.shared.image(named: name) {
            image = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = FilterThumbnailRenderer().render(name: name)
            if let img {
                FilterThumbnailCache.shared.store(img, named: name)
                DispatchQueue.main.async { image = img }
            }
        }
    }
}

/// 全局缩略图缓存（全滤镜共用，切分类不重算）。
final class FilterThumbnailCache {
    static let shared = FilterThumbnailCache()
    private let lock = NSLock()
    private var images: [String: UIImage] = [:]
    private init() {}

    func image(named name: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[name]
    }
    func store(_ image: UIImage, named name: String) {
        lock.lock(); images[name] = image; lock.unlock()
    }
}
