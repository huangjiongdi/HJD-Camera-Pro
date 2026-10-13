//
//  GalleryView.swift
//  HJD Camera Pro
//
//  Lightroom 式图库：
//    · 顶部智能相册（全部 / 视频 / 收藏 / 精选 / 已拒绝）+ 自定义相簿
//    · 网格捏合改变列数（3/4/5/8 列），视频角标
//    · 长按进入多选：批量精选 / 拒绝 / 星级
//    · 媒体类型筛选 + 旗标筛选
//    · 点开为全屏左右滑详情（EXIF / 评分 / AI 超算 / 大光圈 / 复古）
//

import SwiftUI
import Photos

struct GalleryView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var meta = GalleryMetadataStore.shared

    @State private var assets: [PHAsset] = []
    @State private var authorized = false
    @State private var columnsCount: Int = 4
    @State private var selectedIndex: Int? = nil
    @State private var showDetail = false

    @State private var album: AlbumItem = .all
    @State private var mediaFilter: MediaFilter = .all
    @State private var flagFilter: FlagFilter = .all

    @State private var userAlbums: [PHAssetCollection] = []
    @State private var multiSelect: Bool = false
    @State private var selectedIds: Set<String> = []

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)
    private let imageManager = PHCachingImageManager()

    enum MediaFilter: String, CaseIterable {
        case all = "全部"
        case image = "照片"
        case video = "视频"
    }

    enum FlagFilter: String, CaseIterable {
        case all = "全部"
        case picked = "精选"
        case rejected = "拒绝"
        case rated = "已评分"
    }

    enum AlbumItem: Equatable {
        case all
        case favorites
        case videos
        case collection(PHAssetCollection)

        var title: String {
            switch self {
            case .all: return "全部照片"
            case .favorites: return "收藏"
            case .videos: return "视频"
            case .collection(let c): return c.localizedTitle ?? "相簿"
            }
        }

        var icon: String {
            switch self {
            case .all: return "rectangle.stack"
            case .favorites: return "heart.fill"
            case .videos: return "video"
            case .collection: return "folder"
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columnsCount)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()

                if authorized {
                    VStack(spacing: 0) {
                        albumRail
                        filterBar
                        gridArea
                        if multiSelect {
                            multiSelectBar
                        }
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
                        Image(systemName: "xmark").foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            CaptureHistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath").foregroundColor(.white)
                        }
                        Button {
                            withAnimation { multiSelect.toggle() }
                            if !multiSelect { selectedIds.removeAll() }
                        } label: {
                            Image(systemName: multiSelect ? "xmark.circle.fill" : "checkmark.circle")
                                .foregroundColor(multiSelect ? champagneGold : .white)
                        }
                    }
                }
            }
            .onAppear {
                checkPermission()
            }
            .fullScreenCover(isPresented: $showDetail) {
                if let idx = selectedIndex {
                    PhotoDetailPagerView(assets: assets, initialIndex: idx)
                        .environmentObject(meta)
                }
            }
        }
    }

    // MARK: - Album rail

    private var albumRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                albumChip(.all)
                albumChip(.favorites)
                albumChip(.videos)
                ForEach(userAlbums, id: \.localIdentifier) { col in
                    albumChip(.collection(col))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func albumChip(_ item: AlbumItem) -> some View {
        let selected = album == item
        return Button {
            album = item
            hapticSelection()
            fetchAssets()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 12, weight: selected ? .bold : .regular))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $mediaFilter) {
                ForEach(MediaFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: mediaFilter) { _, _ in fetchAssets() }

            Picker("", selection: $flagFilter) {
                ForEach(FlagFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(champagneGold)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Grid

    private var gridArea: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    thumbnailCell(asset, index: index)
                }
            }
            .padding(2)
        }
        .gesture(
            MagnificationGesture()
                .onEnded { scale in
                    if scale < 0.85 {
                        columnsCount = min(8, columnsCount + 1)
                    } else if scale > 1.15 {
                        columnsCount = max(3, columnsCount - 1)
                    }
                }
        )
    }

    private func thumbnailCell(_ asset: PHAsset, index: Int) -> some View {
        let isPicked = meta.flag(for: asset.localIdentifier) == .picked
        let isRejected = meta.flag(for: asset.localIdentifier) == .rejected
        let isSelected = selectedIds.contains(asset.localIdentifier)
        let side = UIScreen.main.bounds.width / CGFloat(columnsCount) - 2
        return PhAssetThumbnail(asset: asset, imageManager: imageManager,
                                targetSize: CGSize(width: side * UIScreen.main.scale,
                                                  height: side * UIScreen.main.scale))
            .aspectRatio(1, contentMode: .fill)
            .frame(width: side, height: side)
            .clipped()
            .overlay(alignment: .topLeading) {
                if isPicked {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(champagneGold.opacity(0.9)))
                        .padding(3)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if asset.mediaType == .video {
                        Text(durationText(asset.duration))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                    }
                    if multiSelect {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(isSelected ? champagneGold : .white.opacity(0.85))
                    }
                }
                .padding(3)
            }
            .overlay(alignment: .bottomLeading) {
                let stars = meta.rating(for: asset.localIdentifier)
                if stars > 0 {
                    Text(String(repeating: "★", count: stars))
                        .font(.system(size: 9))
                        .foregroundColor(champagneGold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(3)
                }
            }
            .overlay {
                if isRejected {
                    ZStack {
                        Rectangle().fill(Color.black.opacity(0.55))
                        Image(systemName: "xmark").foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .onTapGesture {
                if multiSelect {
                    toggleSelection(asset.localIdentifier)
                } else {
                    selectedIndex = index
                    showDetail = true
                }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                if !multiSelect {
                    withAnimation { multiSelect = true }
                    selectedIds = [asset.localIdentifier]
                    hapticSelection()
                }
            }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }

    // MARK: - Multi-select bar

    private var multiSelectBar: some View {
        VStack(spacing: 8) {
            Text("已选 \(selectedIds.count) 张")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 14) {
                Button {
                    applyFlag(.picked)
                } label: {
                    Label("精选", systemImage: "flag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(champagneGold))
                }
                Button {
                    applyFlag(.rejected)
                } label: {
                    Label("拒绝", systemImage: "xmark")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                Menu {
                    ForEach(1..<6, id: \.self) { star in
                        Button {
                            applyRating(star)
                        } label: {
                            Label(String(repeating: "★", count: star), systemImage: "star")
                        }
                    }
                    Button("清除评分", role: .destructive) { applyRating(0) }
                } label: {
                    Label("星级", systemImage: "star")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
    }

    private func applyFlag(_ flag: GalleryMetadataStore.Flag) {
        for id in selectedIds { meta.toggleFlag(flag, id: id) }
        selectedIds.removeAll()
        withAnimation { multiSelect = false }
        fetchAssets()
    }

    private func applyRating(_ stars: Int) {
        for id in selectedIds {
            if stars == 0 {
                meta.toggleRating(meta.rating(for: id), id: id)
            } else {
                meta.toggleRating(stars, id: id)
            }
        }
        selectedIds.removeAll()
        withAnimation { multiSelect = false }
        fetchAssets()
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
                        if authorized { fetchAssets(); fetchUserAlbums() }
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

    private func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus()
        authorized = (status == .authorized || status == .limited)
        if authorized {
            fetchAssets()
            fetchUserAlbums()
        }
    }

    // MARK: - Fetch

    private func fetchUserAlbums() {
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any,
            options: nil)
        var cols: [PHAssetCollection] = []
        result.enumerateObjects { col, _, stop in
            if col.estimatedAssetCount > 0 { cols.append(col) }
            if cols.count >= 20 { stop.pointee = true }
        }
        userAlbums = cols
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1500

        switch mediaFilter {
        case .image: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .video: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        case .all: break
        }

        let result: PHFetchResult<PHAsset>
        switch album {
        case .all:
            result = PHAsset.fetchAssets(with: options)
        case .videos:
            let o = PHFetchOptions()
            o.sortDescriptors = options.sortDescriptors
            o.fetchLimit = options.fetchLimit
            o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            result = PHAsset.fetchAssets(with: o)
        case .favorites:
            if let fav = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil).firstObject {
                result = PHAsset.fetchAssets(in: fav, options: options)
            } else {
                result = PHAsset.fetchAssets(with: options)
            }
        case .collection(let col):
            result = PHAsset.fetchAssets(in: col, options: options)
        }

        var all = result.objects(at: IndexSet(0..<result.count))

        // 旗标 / 评分筛选在本机元数据上做。
        switch flagFilter {
        case .all:
            break
        case .picked:
            all = all.filter { meta.flag(for: $0.localIdentifier) == .picked }
        case .rejected:
            all = all.filter { meta.flag(for: $0.localIdentifier) == .rejected }
        case .rated:
            all = all.filter { meta.rating(for: $0.localIdentifier) > 0 }
        }
        assets = all
    }

    private func hapticSelection() {
        HapticEngine.shared.selectionChanged()
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
