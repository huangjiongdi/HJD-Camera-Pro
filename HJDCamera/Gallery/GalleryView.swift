import SwiftUI
import Photos
import UIKit

// MARK: - 相册（网格 + 详情）

struct GalleryView: View {
    @EnvironmentObject var camera: CameraManager
    @StateObject private var loader = PhotoGridLoader()
    @State private var selected: PHAsset?

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 2) {
                        ForEach(loader.assets, id: \.localIdentifier) { asset in
                            GridThumbnail(asset: asset)
                                .frame(height: 110)
                                .onTapGesture { selected = asset }
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button {
                            camera.backToCamera()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.yellow)
                        }
                        Spacer()
                        Text("相册 / AI 编辑").foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                }
            }
        }
        .sheet(item: Binding(
            get: { selected.map { AssetBox($0) } },
            set: { selected = $0?.asset })) { box in
            PhotoDetail(asset: box.asset)
        }
        .onAppear { loader.load() }
    }
}

// 包装为 Identifiable
struct AssetBox: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

// MARK: - 网格缩略图

struct GridThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .clipped()
        .onAppear { load() }
    }

    private func load() {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.resizeMode = .fast
        let scale = UIScreen.main.scale
        let target = CGSize(width: 220, height: 220)
        PHImageManager.default().requestImage(
            for: asset, targetSize: target,
            contentMode: .aspectFill, options: opts) { img, _ in
            self.image = img
        }
    }
}

// MARK: - 照片详情（不再黑屏）

struct PhotoDetail: View {
    let asset: PHAsset
    @EnvironmentObject var camera: CameraManager
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var fullImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
            } else {
                ProgressView()
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                Spacer()
                HStack(spacing: 20) {
                    Button {
                        if let f = fullImage {
                            camera.openEditor(f)
                        }
                    } label: {
                        Label("AI 编辑", systemImage: "wand.and.stars")
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(Color.yellow))
                            .foregroundColor(.black)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        // 先取适合屏幕的图（快速），再取全尺寸
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        let target = CGSize(width: UIScreen.main.bounds.width * 2,
                            height: UIScreen.main.bounds.height * 2)
        PHImageManager.default().requestImage(
            for: asset, targetSize: target,
            contentMode: .aspectFit, options: opts) { img, info in
            if let img {
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                self.image = img
                if !degraded { self.fullImage = img }
            }
        }
    }
}

// MARK: - 网格加载器

final class PhotoGridLoader: ObservableObject {
    @Published var assets: [PHAsset] = []

    func load() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] s in
                if s == .authorized || s == .limited { self?.fetch() }
            }
            return
        }
        fetch()
    }

    private func fetch() {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        var list: [PHAsset] = []
        result.enumerateObjects { a, _, _ in list.append(a) }
        DispatchQueue.main.async { self.assets = list }
    }
}
