//
//  NightLunarSettingsView.swift
//  HJD Camera Pro
//
//  Night mode and super-moon settings: preset, frame count, denoise strength,
//  lunar quality mode, tracking sensitivity, AI fusion ratio cap.
//

import SwiftUI

struct NightLunarSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("夜景模式") {
                Picker("预设", selection: $settingsStore.nightPreset) {
                    ForEach([NightPreset.natural, .clean, .detail, .portrait], id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Stepper("多帧数量: \(settingsStore.nightFrameCount)", value: $settingsStore.nightFrameCount, in: 4...20)
                HStack {
                    Text("降噪强度")
                    Spacer()
                    Slider(value: $settingsStore.denoiseStrength, in: 0...1)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "%.0f%%", settingsStore.denoiseStrength * 100))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Section("超级月亮") {
                Picker("月面模式", selection: $settingsStore.lunarQualityMode) {
                    ForEach([LunarQualityMode.realSurface, .detailEnhanced, .experimental], id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Toggle("自动月亮识别", isOn: $settingsStore.moonAutoDetect)
                Toggle("自动跟踪锁定", isOn: $settingsStore.moonTracking)
                HStack {
                    Text("AI融合上限")
                    Spacer()
                    Slider(value: $settingsStore.moonUpscaleStrength, in: 0...1)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "%.0f%%", settingsStore.moonUpscaleStrength * 100))
                        .font(.system(size: 12, design: .monospaced))
                }
            } footer: {
                Text("实验性高细节模式会增加AI重建比例，真实性保护建议开启")
            }
        }
        .navigationTitle("夜景与超级月亮")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { NightLunarSettingsView() }
}
