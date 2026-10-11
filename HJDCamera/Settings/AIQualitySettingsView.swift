//
//  AIQualitySettingsView.swift
//  HJD Camera Pro
//
//  AI quality settings: live preview level, denoise, super-resolution, detail,
//  sharpening, portrait, highlight/shadow, backlight, architecture, text,
//  moiré, reflection, authenticity protection, rollback strategy.
//

import SwiftUI

struct AIQualitySettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("实时预览") {
                Picker("预览级别", selection: $settingsStore.livePreviewLevel) {
                    ForEach([LivePreviewLevel.off, .smooth, .balanced, .highDetail], id: \.rawValue) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
            }

            Section("降噪与超分") {
                Toggle("AI 降噪", isOn: $settingsStore.aiDenoiseEnabled)
                Toggle("超分辨率", isOn: $settingsStore.superResolutionEnabled)
                HStack {
                    Text("细节增强")
                    Spacer()
                    Slider(value: $settingsStore.detailEnhance, in: 0...1)
                        .tint(champagneGold)
                        .frame(width: 120)
                    Text(String(format: "%.0f%%", settingsStore.detailEnhance * 100))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                HStack {
                    Text("锐化强度")
                    Spacer()
                    Slider(value: $settingsStore.sharpenIntensity, in: 0...1)
                        .tint(champagneGold)
                        .frame(width: 120)
                }
            }

            Section("场景优化") {
                Toggle("人像优化", isOn: $settingsStore.portraitOptimizeEnabled)
                Toggle("高光保护", isOn: $settingsStore.highlightProtection)
                Toggle("暗部提亮", isOn: $settingsStore.shadowLift)
                Toggle("逆光HDR", isOn: $settingsStore.backlightHDREnabled)
                Toggle("建筑纹理", isOn: $settingsStore.architectureEnhanceEnabled)
                Toggle("文字增强", isOn: $settingsStore.textEnhanceEnabled)
            }

            Section("伪影处理") {
                Toggle("去摩尔纹", isOn: $settingsStore.moireRemovalEnabled)
                Toggle("去反光", isOn: $settingsStore.reflectionRemovalEnabled)
            }

            Section {
                Toggle("真实性保护", isOn: $settingsStore.authenticityProtection)
                Picker("处理回退策略", selection: $settingsStore.rollbackStrategy) {
                    Text("失败保留原图").tag(0)
                    Text("保留原图+失败通知").tag(1)
                    Text("自动重试一次").tag(2)
                }
            } header: {
                Text("质量安全")
            } footer: {
                Text("真实性保护会限制AI重建区域比例，保留原始细节")
            }
        }
        .navigationTitle("AI画质设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { AIQualitySettingsView() }
}
