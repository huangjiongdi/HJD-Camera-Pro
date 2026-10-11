//
//  BeforeAfterCompare.swift
//  HJD Camera Pro
//
//  Split-view comparison between original and AI-processed result.
//  Drag the divider to compare side by side.
//

import SwiftUI
import Photos

struct BeforeAfterCompare: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var dividerPosition: CGFloat = 0.5
    @State private var originalImage: UIImage?
    @State private var processedImage: UIImage?

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Processed (bottom layer)
                if let processed = processedImage {
                    Image(uiImage: processed)
                        .resizable()
                        .scaledToFit()
                }

                // Original (top layer, clipped to left of divider)
                if let original = originalImage {
                    Image(uiImage: original)
                        .resizable()
                        .scaledToFit()
                        .clipShape(
                            Rectangle()
                                .path(in: CGRect(x: 0, y: 0, width: dividerPosition * geo.size.width, height: geo.size.height))
                        )
                }

                // Divider line
                Rectangle()
                    .fill(champagneGold)
                    .frame(width: 2)
                    .position(x: dividerPosition * geo.size.width, y: geo.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dividerPosition = min(max(value.location.x / geo.size.width, 0.05), 0.95)
                            }
                    )

                // Labels
                VStack {
                    HStack {
                        Text("原图")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                        Spacer()
                        Text("AI处理")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(champagneGold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .navigationTitle("前后对比")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { loadImages() }
    }

    private func loadImages() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true

        manager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            DispatchQueue.main.async {
                self.originalImage = img
                self.processedImage = img // Placeholder: will be replaced with AI-processed version
            }
        }
    }
}

#Preview {
    NavigationStack {
        BeforeAfterCompare(asset: PHAsset())
    }
}
