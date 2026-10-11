//
//  ColorLUTSettingsView.swift
//  HJD Camera Pro
//
//  Color and LUT settings: default LUT, intensity, import .cube files,
//  color-space and grading toggles.
//

import SwiftUI

struct ColorLUTSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var lutManager: LUTManager

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("默认LUT") {
                NavigationLink {
                    FilmLUTPicker()
                        .environmentObject(lutManager)
                } label: {
                    HStack {
                        Text("当前LUT")
                        Spacer()
                        Text(lutManager.activeLUTName)
                            .foregroundColor(champagneGold)
                    }
                }
                HStack {
                    Text("强度")
                    Spacer()
                    Slider(value: $settingsStore.lutStrength, in: 0...1)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "%.0f%%", settingsStore.lutStrength * 100))
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            Section("色彩空间") {
                Toggle("LOG 还原", isOn: $settingsStore.logRestore)
                Toggle("HDR 转换", isOn: $settingsStore.hdrConversion)
                Toggle("P3 广色域", isOn: $settingsStore.useP3)
            }

            Section("色彩") {
                sliderRow("高光压缩", value: $settingsStore.highlightCompression)
                sliderRow("暗部色调", value: $settingsStore.shadowTint)
                sliderRow("肤色保护", value: $settingsStore.skinProtection)
            }

            Section("导入LUT") {
                Button {
                    lutManager.presentImporter()
                } label: {
                    Label("导入 .cube 文件", systemImage: "square.and.arrow.down.on.square")
                }
                Text("已导入 \(lutManager.customLUTs.count) 个自定义LUT")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .navigationTitle("色彩与LUT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Slider(value: value, in: 0...1)
                .tint(champagneGold).frame(width: 120)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

#Preview {
    NavigationStack { ColorLUTSettingsView() }
        .environmentObject(AppSettingsStore.shared)
        .environmentObject(LUTManager.shared)
}
