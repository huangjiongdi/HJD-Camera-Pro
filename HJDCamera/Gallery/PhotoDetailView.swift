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
                NavigationLink {
                    BeforeAfterCompare(asset: asset)
                } label: {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Load Full Image

    private func loadFullImage() {
        isLoading = true
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let targetSize = PHImageManagerMaximumSize
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { img, info in
            // Ensure full-resolution load, not a degraded preview
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if let img = img, !isDegraded {
                DispatchQueue.main.async {
                    self.image = img
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    PhotoDetailView(asset: PHAsset())
}
