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
                    ForEach([LivePreviewLevel.off, .smooth, .balanced, .highDetail],
                            id: \.rawValue) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
            }

            Section("降噪与超分") {
                strengthRow("AI 降噪", value: $settingsStore.denoiseStrength)
                HStack {
                    Text("超分输出倍率")
                    Spacer()
                    Slider(value: $settingsStore.defaultOutputScale, in: 1...4, step: 1)
                        .tint(champagneGold)
                        .frame(width: 120)
                    Text(String(format: "%.0f×", settingsStore.defaultOutputScale))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                strengthRow("细节增强", value: $settingsStore.detailEnhance)
                strengthRow("锐化强度", value: $settingsStore.sharpen)
            }

            Section("场景优化") {
                Toggle("人像优化", isOn: $settingsStore.portraitRepair)
                strengthRow("高光保护", value: $settingsStore.highlightRecovery)
                strengthRow("暗部提亮", value: $settingsStore.shadowRecovery)
                Toggle("逆光优化", isOn: $settingsStore.backlightOptimize)
                strengthRow("建筑纹理", value: $settingsStore.architectureTexture)
                strengthRow("文字增强", value: $settingsStore.textEnhance)
            }

            Section("伪影处理") {
                strengthRow("去摩尔纹", value: $settingsStore.moireReduction)
                strengthRow("去反光", value: $settingsStore.reflectionRemoval)
            }

            Section {
                strengthRow("真实性保护", value: $settingsStore.authenticityProtection)
                Toggle("失败保留原图", isOn: $settingsStore.fallbackOnFailure)
                Toggle("保留原始照片", isOn: $settingsStore.keepOriginal)
            } header: {
                Text("质量安全")
            } footer: {
                Text("真实性保护会限制 AI 重建区域比例，保留原始细节。")
            }
        }
        .navigationTitle("AI画质设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private func strengthRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: value, in: 0...1)
                .tint(champagneGold)
                .frame(width: 120)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

#Preview {
    NavigationStack { AIQualitySettingsView() }
        .environmentObject(AppSettingsStore.shared)
}
