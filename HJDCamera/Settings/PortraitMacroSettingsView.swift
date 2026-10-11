//
//  PortraitMacroSettingsView.swift
//  HJD Camera Pro
//
//  Portrait and macro settings: aperture, bokeh, skin smoothing, eye
//  enhancement, macro mode default, focus distance, flash for macro.
//

import SwiftUI

struct PortraitMacroSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("人像") {
                HStack {
                    Text("光圈")
                    Spacer()
                    Slider(value: $settingsStore.portraitAperture, in: 1.4...16)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "f/%.1f", settingsStore.portraitAperture))
                        .font(.system(size: 12, design: .monospaced))
                }
                Toggle("背景虚化增强", isOn: $settingsStore.bokehEnhance)
                Toggle("肤色调亮", isOn: $settingsStore.skinToneEnhance)
                HStack {
                    Text("磨皮强度")
                    Spacer()
                    Slider(value: $settingsStore.skinSmooth, in: 0...1)
                        .tint(champagneGold).frame(width: 120)
                }
                Toggle("眼神光增强", isOn: $settingsStore.eyeEnhance)
            }

            Section("微距") {
                Picker("默认模式", selection: $settingsStore.macroMode) {
                    ForEach([MacroMode.fast, .detail], id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Toggle("自动微距切换", isOn: $settingsStore.macroAutoSwitch)
                Toggle("微距补光灯", isOn: $settingsStore.macroFlashEnabled)
                HStack {
                    Text("最近对焦距离")
                    Spacer()
                    Text(String(format: "%.1f cm", settingsStore.macroMinFocusDistance))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .navigationTitle("人像与微距")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { PortraitMacroSettingsView() }
}
