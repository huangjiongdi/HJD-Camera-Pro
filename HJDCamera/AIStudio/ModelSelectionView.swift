//
//  ModelSelectionView.swift
//  HJD Camera Pro
//
//  AI model selector. Lists models grouped by category; each model shows
//  purpose / version / size / download status / input resolution / output scale
//  / inference time / memory / license / source. Actions: set default /
//  download / uninstall / run test / view source.
//

import SwiftUI

struct ModelSelectionView: View {
    @EnvironmentObject var aiModelRegistry: AIModelRegistry
    @State private var searchText = ""

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private var groupedModels: [(category: AIModelCategory, models: [AIModelInfo])] {
        let filtered = searchText.isEmpty
            ? aiModelRegistry.models
            : aiModelRegistry.models.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return AIModelCategory.allCases.map { cat in
            (cat, filtered.filter { $0.category == cat })
        }.filter { !$0.models.isEmpty }
    }

    var body: some View {
        List {
            ForEach(groupedModels, id: \.category) { group in
                Section {
                    ForEach(group.models) { model in
                        ModelRow(model: model)
                            .environmentObject(aiModelRegistry)
                    }
                } header: {
                    Text(group.category.rawValue)
                        .foregroundColor(champagneGold)
                }
            }
        }
        .navigationTitle("模型管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, prompt: "搜索模型")
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: AIModelInfo
    @EnvironmentObject var aiModelRegistry: AIModelRegistry
    @State private var testing = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        if model.isDefault {
                            Text("默认")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(champagneGold))
                        }
                    }
                    Text("v\(model.version) · \(model.recommendedDevice)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                statusBadge
            }

            // Specs grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                specChip("大小", text: formatSize(model.fileSize))
                specChip("输入", text: model.inputResolution)
                specChip("输出", text: model.outputScale)
                if let t = model.inferenceTime {
                    specChip("耗时", text: String(format: "%.0fms", t))
                }
                if let m = model.peakMemory {
                    specChip("内存", text: formatSize(m))
                }
            }

            // License + source
            HStack(spacing: 8) {
                Text(model.license)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                Text("·")
                    .foregroundColor(.white.opacity(0.3))
                Text(model.source)
                    .font(.system(size: 10))
                    .foregroundColor(.cyan.opacity(0.7))
            }

            // Action buttons
            HStack(spacing: 10) {
                if model.isDownloaded {
                    if !model.isDefault {
                        actionButton("设为默认", color: .white) {
                            aiModelRegistry.setDefault(model.id, for: model.category)
                        }
                    }
                    actionButton(testing ? "测试中..." : "运行测试", color: .cyan) {
                        testing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { testing = false }
                    }
                } else {
                    // Models are bundled; there is no runtime download.
                    Text("随包内置")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private var statusBadge: some View {
        Group {
            if model.isDownloaded {
                Text("已安装")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Text("未下载")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func specChip(_ label: String, text: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024 { return String(format: "%.1f GB", mb/1024) }
        return String(format: "%.0f MB", mb)
    }
}

#Preview {
    NavigationStack {
        ModelSelectionView()
    }
}
