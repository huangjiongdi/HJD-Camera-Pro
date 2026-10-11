//
//  StorageSettingsView.swift
//  HJD Camera Pro
//
//  Gallery and storage settings: cache size, temp files, RAW photos,
//  processed photos, video proxies, cleanup actions, auto-delete.
//

import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var storageManager: StorageManager

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("存储概览") {
                storageRow("模型缓存", size: storageManager.budget.modelCacheSize)
                storageRow("临时文件", size: storageManager.budget.tempFilesSize)
                storageRow("RAW 照片", size: storageManager.budget.rawPhotosSize)
                storageRow("处理后照片", size: storageManager.budget.processedPhotosSize)
                storageRow("视频代理", size: storageManager.budget.videoProxySize)
                HStack {
                    Text("可用空间")
                        .foregroundColor(.white)
                    Spacer()
                    Text(formatSize(storageManager.budget.totalAvailable))
                        .foregroundColor(storageManager.budget.totalAvailable < 1_000_000_000 ? .orange : .green)
                        .font(.system(size: 13, design: .monospaced))
                }
            }

            Section("自动管理") {
                Toggle("自动清理临时文件", isOn: $settingsStore.autoCleanupTemp)
                Stepper("临时文件保留天数: \(settingsStore.tempRetentionDays)",
                        value: $settingsStore.tempRetentionDays, in: 1...30)
                Toggle("AI处理后自动保存", isOn: $settingsStore.autoSaveProcessed)
                Toggle("保留原始文件", isOn: $settingsStore.keepOriginalAfterProcess)
            }

            Section {
                Button(role: .destructive) {
                    storageManager.clearTempFiles()
                } label: {
                    Label("清理临时文件", systemImage: "trash")
                }
                Button(role: .destructive) {
                    storageManager.clearModelCache()
                } label: {
                    Label("清除模型缓存", systemImage: "cube.box")
                }
            }
        }
        .navigationTitle("图库与存储")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func storageRow(_ label: String, size: Int64) -> some View {
        HStack {
            Text(label).foregroundColor(.white)
            Spacer()
            Text(formatSize(size))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

#Preview {
    NavigationStack { StorageSettingsView() }
}
