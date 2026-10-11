//
//  GalleryView.swift
//  HJD Camera Pro
//
//  Grid gallery loaded directly from PHAsset. Correctly handles orientation,
//  EXIF and color space. Tap a thumbnail to open the full-screen viewer.
//

import SwiftUI
import Photos
import PhotosUI

struct GalleryView: View {
    @EnvironmentObject var appState: AppState
    @State private var assets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?
    @State private var showDetail = false
    @State private var authorized = false
    private let columns = [GridItem(.adaptive(minimum: 100, spacing: 2))]

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private let imageManager = PHCachingImageManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.05)
                    .ignoresSafeArea()

                if authorized {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                thumbnailCell(asset)
                                    .onTapGesture {
                                        selectedAsset = asset
                                        showDetail = true
                                    }
                            }
                        }
                        .padding(2)
                    }
                } else {
                    permissionView
                }
            }
            .navigationTitle("图库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        appState.showGallery = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        CaptureHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.white)
                    }
                }
            }
            .onAppear { checkPermission() }
            .sheet(isPresented: $showDetail) {
                if let asset = selectedAsset {
                    PhotoDetailView(asset: asset)
                }
            }
        }
    }

    // MARK: - Thumbnail

    private func thumbnailCell(_ asset: PHAsset) -> some View {
        PhAssetThumbnail(asset: asset, imageManager: imageManager, targetSize: CGSize(width: 200, height: 200))
            .aspectRatio(1, contentMode: .fill)
            .clipped()
    }

    // MARK: - Permission

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.4))
            Text("需要访问照片库")
                .font(.system(size: 16))
                .foregroundColor(.white)
            Button {
                PHPhotoLibrary.requestAuthorization { status in
                    DispatchQueue.main.async {
                        authorized = (status == .authorized || status == .limited)
                        if authorized { fetchAssets() }
                    }
                }
            } label: {
                Text("授权访问")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(champagneGold))
            }
        }
    }

    // MARK: - Fetch

    private func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus()
        authorized = (status == .authorized || status == .limited)
        if authorized { fetchAssets() }
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 500
        let result = PHAsset.fetchAssets(with: .image, options: options)
        assets = result.objects(at: IndexSet(0..<result.count))
    }
}

// MARK: - PHAsset Thumbnail

struct PhAssetThumbnail: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    let targetSize: CGSize
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.05)
                    .onAppear { loadThumbnail() }
            }
        }
    }

    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            if let img = img {
                DispatchQueue.main.async { self.image = img }
            }
        }
    }
}

#Preview {
    GalleryView()
        .environmentObject(AppState.shared)
}
