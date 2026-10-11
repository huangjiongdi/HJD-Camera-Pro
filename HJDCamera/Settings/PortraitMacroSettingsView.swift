//
//  PortraitMacroSettingsView.swift
//  HJD Camera Pro
//
//  Portrait and macro settings: aperture, bokeh, skin, eye/hair, backlight,
//  macro auto-detect, focus assist, stabilization, focus stacking, multi-frame.
//

import SwiftUI

struct PortraitMacroSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var macroMode: MacroMode = .fast

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("人像") {
                HStack {
                    Text("光圈")
                    Spacer()
                    Slider(value: $settingsStore.apertureSimulation, in: 1.4...16)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "f/%.1f", settingsStore.apertureSimulation))
                        .font(.system(size: 12, design: .monospaced))
                }
                strengthRow("背景虚化", value: $settingsStore.bokehStrength)
                Picker("肤色风格", selection: $settingsStore.skinToneStyle) {
                    ForEach(SkinToneStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                strengthRow("磨皮强度", value: $settingsStore.portraitSkinTexture)
                Toggle("眼神光增强", isOn: $settingsStore.eyeDetail)
                Toggle("发丝边缘优化", isOn: $settingsStore.hairEdge)
                Toggle("逆光补偿", isOn: $settingsStore.backlightCompensation)
            }

            Section("微距") {
                Picker("默认模式", selection: $macroMode) {
                    ForEach([MacroMode.fast, .detail], id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Toggle("自动微距切换", isOn: $settingsStore.macroAutoDetect)
                Toggle("微距对焦辅助", isOn: $settingsStore.macroFocusAssist)
                Toggle("微距防抖", isOn: $settingsStore.macroStabilization)
                Toggle("焦点包围", isOn: $settingsStore.focusStacking)
                Toggle("多帧超清", isOn: $settingsStore.macroMultiFrame)
                Toggle("昆虫细节", isOn: $settingsStore.insectDetail)
                strengthRow("微距真实性", value: $settingsStore.macroAuthenticity)
            }
        }
        .navigationTitle("人像与微距")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private func strengthRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: value, in: 0...1)
                .tint(champagneGold).frame(width: 120)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

#Preview {
    NavigationStack { PortraitMacroSettingsView() }
        .environmentObject(AppSettingsStore.shared)
}
