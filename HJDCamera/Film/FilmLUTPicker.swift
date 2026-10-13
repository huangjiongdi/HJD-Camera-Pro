//
//  FilmLUTPicker.swift
//  HJD Camera Pro
//
//  LUT picker grid: browse built-in and custom LUTs by category, preview
//  thumbnails, select active LUT.
//

import SwiftUI

struct FilmLUTPicker: View {
    @EnvironmentObject var lutManager: LUTManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: LUTCategory = .film

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private var categories: [LUTCategory] {
        var cats: [LUTCategory] = LUTCategory.allCases.filter { $0 != .custom }
        if !lutManager.customLUTs.isEmpty { cats.append(.custom) }
        return cats
    }

    private var visibleLUTs: [LUTInfo] {
        if selectedCategory == .custom {
            return lutManager.customLUTs
        }
        return lutManager.luts(in: selectedCategory)
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // None option
                        categoryTab("无", selected: lutManager.activeLUTName == "None") {
                            lutManager.selectLUT("None")
                        }
                        ForEach(categories, id: \.self) { cat in
                            categoryTab(cat.rawValue, selected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)

                // LUT grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(visibleLUTs) { lut in
                            lutCell(lut)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("选择LUT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func categoryTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func lutCell(_ lut: LUTInfo) -> some View {
        let isActive = lutManager.activeLUTName == lut.name
        return Button {
            lutManager.selectLUT(lut.name)
        } label: {
            VStack(spacing: 6) {
                // 真实 LUT 缩略图（全色相参考图上逐滤镜渲染，非假色块）。
                FilterThumbnailView(name: lut.name, size: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? champagneGold : Color.clear, lineWidth: 2)
                    )

                Text(lut.name)
                    .font(.system(size: 10))
                    .foregroundColor(isActive ? champagneGold : .white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        FilmLUTPicker()
            .environmentObject(LUTManager.shared)
    }
}
