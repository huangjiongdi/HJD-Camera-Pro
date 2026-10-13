//
//  SettingsRootView.swift
//  HJD Camera Pro
//
//  Settings home: grouped list navigation to all sub-settings pages.
//

import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { CameraSettingsView() } label: {
                        settingsRow("camera", "拍摄设置", "分辨率 · 格式 · 比例")
                    }
                    NavigationLink { VideoSettingsView() } label: {
                        settingsRow("video", "视频设置", "编码 · HDR · 防抖")
                    }
                    NavigationLink { NightLunarSettingsView() } label: {
                        settingsRow("moon.stars", "夜景与超级月亮", "多帧 · 月面模式")
                    }
                    NavigationLink { PortraitMacroSettingsView() } label: {
                        settingsRow("person", "人像与微距", "光圈 · 散景 · 对焦")
                    }
                }

                Section {
                    NavigationLink { AIQualitySettingsView() } label: {
                        settingsRow("wand.and.stars", "AI画质设置", "降噪 · 超分 · 真实性保护")
                    }
                    NavigationLink { ModelManagementView() } label: {
                        settingsRow("cube.box", "模型管理", "下载 · 默认 · 测试")
                    }
                } header: {
                    Text("AI 工作室")
                }

                Section {
                    NavigationLink { ArchitectureZoomSettingsView() } label: {
                        settingsRow("building.2", "建筑与极限变焦", "校正 · 长焦")
                    }
                    NavigationLink { ColorLUTSettingsView() } label: {
                        settingsRow("paintpalette", "色彩与LUT", "胶片模拟 · 导入")
                    }
                }

                Section {
                    NavigationLink { StorageSettingsView() } label: {
                        settingsRow("internaldrive", "图库与存储", "缓存 · RAW · 清理")
                    }
                    NavigationLink { PerformanceSettingsView() } label: {
                        settingsRow("gauge", "性能与设备", "温度 · 内存 · 降级")
                    }
                    NavigationLink { HapticSettingsView() } label: {
                        settingsRow("waveform", "触觉反馈", "预设 · 单独开关")
                    }
                }

                Section {
                    NavigationLink { AboutSettingsView() } label: {
                        settingsRow("info.circle", "关于与隐私", "版本 · 开发者工具")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        appState.showSettings = false
                    }
                    .foregroundColor(champagneGold)
                }
            }
        }
    }

    private func settingsRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(champagneGold)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

#Preview {
    SettingsRootView()
        .environmentObject(AppState.shared)
}
