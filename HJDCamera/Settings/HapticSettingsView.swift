//
//  HapticSettingsView.swift
//  HJD Camera Pro
//
//  Haptic feedback settings: 4 presets (natural / camera / pro / cinematic)
//  plus individual toggles for each event.
//

import SwiftUI

struct HapticSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var hapticEngine: HapticEngine

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("触感预设") {
                ForEach(HapticPreset.allCases, id: \.self) { preset in
                    Button {
                        settingsStore.hapticPreset = preset
                        hapticEngine.applyPreset(preset)
                        hapticEngine.preview()
                    } label: {
                        HStack {
                            Text(presetName(preset))
                                .foregroundColor(.white)
                            Spacer()
                            if settingsStore.hapticPreset == preset {
                                Image(systemName: "checkmark")
                                    .foregroundColor(champagneGold)
                            }
                        }
                    }
                }
            }

            Section("单独开关") {
                Toggle("快门", isOn: $settingsStore.hapticShutter)
                Toggle("对焦", isOn: $settingsStore.hapticFocus)
                Toggle("月亮锁定", isOn: $settingsStore.hapticLunarLock)
                Toggle("变焦节点", isOn: $settingsStore.hapticZoomNode)
                Toggle("AI完成", isOn: $settingsStore.hapticAIComplete)
                Toggle("导出完成", isOn: $settingsStore.hapticExportComplete)
                Toggle("错误提示", isOn: $settingsStore.hapticError)
            }
        }
        .navigationTitle("触觉反馈")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func presetName(_ preset: HapticPreset) -> String {
        switch preset {
        case .natural: return "自然"
        case .camera: return "相机"
        case .pro: return "专业"
        case .cinematic: return "电影感"
        }
    }
}

#Preview {
    NavigationStack { HapticSettingsView() }
}
