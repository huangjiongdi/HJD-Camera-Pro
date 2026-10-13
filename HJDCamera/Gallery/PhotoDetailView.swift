//
//  PhotoDetailView.swift
//  HJD Camera Pro
//
//  Lightroom 式全屏查看器：
//    · 左右滑切换（与图库筛选结果同序）
//    · 双指缩放 / 双击放大 / 下滑关闭
//    · 底部工具条：信息(EXIF) / 星级 / 旗标 / AI 超算 / 大光圈 / 复古 / 对比 / 分享
//

import SwiftUI
import Photos
import PhotosUI
import AVKit
import ImageIO

struct PhotoDetailPagerView: View {
    let assets: [PHAsset]
    let initialIndex: Int

    @EnvironmentObject var meta: GalleryMetadataStore
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var showEXIF = false
    @State private var showAIEditor = false
    @State private var showAperture = false
    @State private var showRetro = false
    @State private var showCompare = false
    @State private var showShare = false
    @State private var dragOffset: CGSize = .zero

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    init(assets: [PHAsset], initialIndex: Int) {
        self.assets = assets
        self.initialIndex = initialIndex
        _index = State(initialValue: initialIndex)
    }

    private var asset: PHAsset { assets[index] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { i, a in
                    PhotoPageView(asset: a)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.bottom, 16)
        }
        .offset(y: dragOffset.height)
        // 同时手势 + 仅响应竖向主导的拖动，避免拦截 TabView 左右翻页。
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { v in
                    let t = v.translation
                    if t.height > 0 && abs(t.height) > abs(t.width) {
                        dragOffset = t
                    }
                }
                .onEnded { v in
                    if v.translation.height > 110
                        && abs(v.translation.height) > abs(v.translation.width) {
                        dismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = .zero }
                    }
                }
        )
        .sheet(isPresented: $showEXIF) {
            EXIFSheet(asset: asset).environmentObject(meta)
        }
        .sheet(isPresented: $showAIEditor) {
            NavigationStack {
                AIEditorView(taskType: .superResolution, initialAsset: asset)
                    .environmentObject(AppSettingsStore.shared)
                    .environmentObject(AIProcessingQueue.shared)
            }
        }
        .fullScreenCover(isPresented: $showAperture) {
            ApertureBlurView(asset: asset)
        }
        .fullScreenCover(isPresented: $showRetro) {
            RetroFrameView(asset: asset)
        }
        .sheet(isPresented: $showCompare) {
            BeforeAfterCompare(asset: asset)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(asset: asset)
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            Spacer()
            Text("\(index + 1) / \(assets.count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            Spacer()
            flagButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var flagButton: some View {
        let flag = meta.flag(for: asset.localIdentifier)
        return Button {
            meta.cycleFlag(id: asset.localIdentifier)
            HapticEngine.shared.selectionChanged()
        } label: {
            Image(systemName: flag == .picked ? "flag.fill" : (flag == .rejected ? "xmark.circle.fill" : "flag"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(flag == .none ? .white : .black)
                .padding(10)
                .background(Circle().fill(flag == .none ? Color.white.opacity(0.15) : champagneGold))
        }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 12) {
            starRow
            HStack(spacing: 0) {
                toolButton("info.circle", "信息") { showEXIF = true }
                toolButton("wand.and.stars", "AI 超算", highlight: true) { showAIEditor = true }
                toolButton("circle.hexagongrid", "大光圈") { showAperture = true }
                toolButton("camera.viewfinder", "复古") { showRetro = true }
                toolButton("square.on.square", "对比") { showCompare = true }
                toolButton("square.and.arrow.up", "分享") { showShare = true }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }

    private var starRow: some View {
        let current = meta.rating(for: asset.localIdentifier)
        return HStack(spacing: 10) {
            ForEach(1..<6, id: \.self) { star in
                Button {
                    meta.toggleRating(star, id: asset.localIdentifier)
                    HapticEngine.shared.selectionChanged()
                } label: {
                    Image(systemName: star <= current ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(champagneGold)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    private func toolButton(_ icon: String, _ label: String, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.selectionChanged()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: highlight ? .bold : .regular))
                    .foregroundColor(highlight ? champagneGold : .white)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Single zoomable page

struct PhotoPageView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var lastZoomAt: Date?
    private let imageManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
            } else if asset.mediaType == .video {
                VideoPlaceholderView(asset: asset)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.gray)
                    .font(.system(size: 32))
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { v in scale = lastScale * v }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if scale < 1 { scale = 1 }
                        lastScale = scale
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.25)) {
                scale = scale > 1 ? 1 : 2.5
                lastScale = scale
            }
        }
        .onAppear { if image == nil { load() } }
    }

    private func load() {
        guard asset.mediaType == .image else {
            isLoading = false
            return
        }
        isLoading = true
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if let data, !cancelled {
                let display = PhotoPageView.downsample(data: data, maxPixelSize: 4096)
                DispatchQueue.main.async {
                    self.image = display
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }
    }

    /// ImageIO 边下边解码，长边不超过 maxPixelSize，方向自动转正。
    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else {
            return UIImage(data: data)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as [CFString: Any] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Video placeholder

struct VideoPlaceholderView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var playerVC: AVPlayerViewController?
    private let imageManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.gray.opacity(0.2)
            }
            Button {
                playVideo()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.resizeMode = .fast
            imageManager.requestImage(for: asset, targetSize: CGSize(width: 1080, height: 1080),
                                     contentMode: .aspectFit, options: opts) { img, _ in
                if let img { DispatchQueue.main.async { self.image = img } }
            }
        }
        .fullScreenCover(item: Binding(
            get: { playerVC.map { PlayerBox(vc: $0) } },
            set: { _ in playerVC = nil }
        )) { box in
            PlayerContainer(vc: box.vc).ignoresSafeArea()
        }
    }

    private struct PlayerBox: Identifiable { let id = UUID(); let vc: AVPlayerViewController }

    private func playVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            DispatchQueue.main.async {
                guard let item else { return }
                let vc = AVPlayerViewController()
                vc.player = AVPlayer(playerItem: item)
                vc.player?.play()
                self.playerVC = vc
            }
        }
    }
}

struct PlayerContainer: UIViewControllerRepresentable {
    let vc: AVPlayerViewController
    func makeUIViewController(context: Context) -> AVPlayerViewController { vc }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

// MARK: - EXIF sheet

struct EXIFSheet: View {
    let asset: PHAsset
    @EnvironmentObject var meta: GalleryMetadataStore
    @Environment(\.dismiss) private var dismiss
    @State private var info: EXIFInfo?

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let info {
                            section("拍摄参数") {
                                row("相机", info.cameraModel ?? "—")
                                row("镜头", info.lensModel ?? "—")
                                row("曝光组合", info.exposureLine ?? "—")
                                row("曝光补偿", info.exposureBias.map { "\($0) EV" } ?? "—")
                                row("白平衡", info.whiteBalance ?? "—")
                            }
                            section("文件") {
                                row("格式", info.fileType ?? "—")
                                row("分辨率", info.resolution)
                                row("像素", info.megapixels)
                                row("大小", byteText(info.fileSize))
                            }
                            section("时间与位置") {
                                row("拍摄时间", info.formattedDate ?? "—")
                                if let loc = info.location {
                                    row("位置", String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                                } else {
                                    row("位置", "无位置信息")
                                }
                            }
                        } else {
                            ProgressView().tint(champagneGold).padding(.top, 60)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("照片信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(champagneGold)
                }
            }
            .onAppear {
                EXIFInfo.load(asset: asset) { info = $0 }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(champagneGold)
            VStack(spacing: 0) { content() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }

    private func byteText(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let asset: PHAsset

    func makeUIViewController(context: Context) -> ShareWrapperVC {
        let vc = ShareWrapperVC()
        vc.asset = asset
        return vc
    }

    func updateUIViewController(_ uiViewController: ShareWrapperVC, context: Context) {}
}

final class ShareWrapperVC: UIViewController {
    var asset: PHAsset?
    private var didPresent = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent, let asset else { return }
        didPresent = true

        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { av, _, _ in
                guard let urlAsset = av as? AVURLAsset else {
                    DispatchQueue.main.async { self.dismiss(animated: true) }
                    return
                }
                DispatchQueue.main.async {
                    self.presentActivity(items: [urlAsset.url])
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHCachingImageManager().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data else {
                    DispatchQueue.main.async { self.dismiss(animated: true) }
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("share-\(UUID().uuidString).jpg")
                try? data.write(to: url)
                DispatchQueue.main.async {
                    self.presentActivity(items: [url])
                }
            }
        }
    }

    private func presentActivity(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.dismiss(animated: true)
        }
        present(vc, animated: true)
    }
}
