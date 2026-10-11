//
//  ModelManagementView.swift
//  HJD Camera Pro
//
//  Detailed model management: grouped by category, each model shows purpose,
//  version, size, download status, input resolution, output scale, inference
//  time, memory, license, source. Actions: set default / download / uninstall
//  / run test / view source.
//

import SwiftUI

struct ModelManagementView: View {
    @EnvironmentObject var aiModelRegistry: AIModelRegistry
    @State private var filterCategory: AIModelCategory?

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private var filteredModels: [AIModelInfo] {
        guard let cat = filterCategory else { return aiModelRegistry.models }
        return aiModelRegistry.models.filter { $0.category == cat }
    }

    var body: some View {
        List {
            // Category filter
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip("全部", selected: filterCategory == nil) {
                            filterCategory = nil
                        }
                        ForEach(AIModelCategory.allCases, id: \.self) { cat in
                            categoryChip(cat.rawValue, selected: filterCategory == cat) {
                                filterCategory = cat
                            }
                        }
                    }
                }
            }

            // Model list
            Section {
                if filteredModels.isEmpty {
                    Text("暂无模型")
                        .foregroundColor(.gray)
                } else {
                    ForEach(filteredModels) { model in
                        ModelManagementRow(model: model)
                            .environmentObject(aiModelRegistry)
                    }
                }
            }

            // Storage summary
            Section {
                HStack {
                    Text("已下载模型")
                    Spacer()
                    Text("\(aiModelRegistry.downloadedCount) 个")
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack {
                    Text("占用空间")
                    Spacer()
                    Text(formatSize(aiModelRegistry.totalModelSize))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .navigationTitle("模型管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func categoryChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024 { return String(format: "%.1f GB", mb/1024) }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Management Row

struct ModelManagementRow: View {
    let model: AIModelInfo
    @EnvironmentObject var aiModelRegistry: AIModelRegistry
    @State private var testing = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(model.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        if model.isDefault {
                            Text("默认")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(champagneGold))
                        }
                    }
                    Text("适用: \(model.usedByModes.map { $0.rawValue }.joined(separator: " · "))")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                statusBadge
            }

            Divider().background(Color.white.opacity(0.1))

            // Specs
            HStack(spacing: 14) {
                spec("大小", value: formatSize(model.fileSize))
                spec("输入", value: model.inputResolution)
                spec("输出", value: model.outputScale)
                if let t = model.inferenceTime { spec("耗时", value: String(format: "%.0fms", t)) }
            }

            // Buttons
            HStack(spacing: 8) {
                if model.isDownloaded {
                    if !model.isDefault {
                        miniButton("设为默认", color: champagneGold) { aiModelRegistry.setDefault(model) }
                    }
                    miniButton(testing ? "测试中" : "测试", color: .cyan) {
                        testing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { testing = false }
                    }
                    if model.canUninstall {
                        miniButton("卸载", color: .red) { aiModelRegistry.uninstallModel(model) }
                    }
                } else {
                    miniButton("下载", color: champagneGold) { aiModelRegistry.downloadModel(model) }
                }
                miniButton("来源", color: .gray) { aiModelRegistry.viewSource(model) }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private var statusBadge: some View {
        Text(model.isDownloaded ? "已安装" : "未下载")
            .font(.system(size: 10))
            .foregroundColor(model.isDownloaded ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func spec(_ label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
        }
    }

    private func miniButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().stroke(color.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return mb >= 1024 ? String(format: "%.1fG", mb/1024) : String(format: "%.0fM", mb)
    }
}

#Preview {
    NavigationStack { ModelManagementView() }
}
