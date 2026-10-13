//
//  PhotoDetailView.swift
//  HJD Camera Pro
//
//  Full-screen photo viewer. Loads full-resolution image directly from PHAsset
//  (not from cache) to avoid black-screen issues. Supports pinch zoom, pan,
//  and swipe-down to dismiss.
//

import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers

struct PhotoDetailView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true
    @State private var showAIEditor = false
    @State private var showCompare = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)
    private let imageManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(champagneGold)
            } else if let image = image {
                fullImage(image)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text("无法加载图片")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
            }

            // Top bar
            if showControls {
                topBar
                    .transition(.opacity)
            }
        }
        .onAppear { loadFullImage() }
        .sheet(isPresented: $showAIEditor) {
            NavigationStack {
                AIEditorView(taskType: .superResolution, initialAsset: asset)
                    .environmentObject(AppSettingsStore.shared)
                    .environmentObject(AIProcessingQueue.shared)
            }
        }
    }

    // MARK: - Full Image

    private func fullImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1 { resetZoom() }
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.25)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack {
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
                HStack(spacing: 12) {
                    Button {
                        showAIEditor = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(champagneGold.opacity(0.85)))
                    }
                    Button {
                        showCompare = true
                    } label: {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
        .sheet(isPresented: $showCompare) {
            BeforeAfterCompare(asset: asset)
        }
    }

    // MARK: - Load Full Image

    private func loadFullImage() {
        isLoading = true
        image = nil

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // 用原始数据 + ImageIO 缩略图解码，可靠避免：
        // ① 只收到 degraded 帧后再也不回 full 帧导致永远黑屏；
        // ② 超大照片（含 260MP）整图解码 OOM 黑屏。
        // 显示用长边 4096 的缩略图，既清晰又稳；AI 超算时另行读取完整数据。
        imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if let data = data, !isCancelled {
                let display = Self.downsample(data: data, maxPixelSize: 4096)
                DispatchQueue.main.async {
                    self.image = display
                    self.isLoading = false
                }
            } else if let error = info?[PHImageErrorKey] as? Error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("[PhotoDetail] 读取失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// ImageIO 边下边解码，生成方向正确、长边不超过 maxPixelSize 的预览图。
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

// PHAsset 无公开构造器，详情页由相册列表传入真实 asset，故不提供 #Preview。
