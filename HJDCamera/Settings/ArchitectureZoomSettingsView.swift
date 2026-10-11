//
//  ArchitectureZoomSettingsView.swift
//  HJD Camera Pro
//
//  Architecture correction and extreme zoom settings: keystone/frame-line
//  protection, moiré/repeat-texture suppression, zoom curve, snapping,
//  telephoto stabilization, high-zoom AI enhancement.
//

import SwiftUI

struct ArchitectureZoomSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("建筑校正") {
                Toggle("窗框/直线锁定", isOn: $settingsStore.windowFrameLines)
                strengthRow("摩尔纹抑制", value: $settingsStore.archMoire)
                strengthRow("重复纹理抑制", value: $settingsStore.repeatTexture)
                strengthRow("窗格真实性", value: $settingsStore.windowPaneAuthenticity)
            }

            Section("变焦曲线") {
                strengthRow("曲线灵敏度", value: $settingsStore.zoomCurveSensitivity)
                Toggle("双速变焦", isOn: $settingsStore.dualSpeedZoom)
                Toggle("倍率吸附", isOn: $settingsStore.zoomSnapping)
            }

            Section("极限变焦") {
                strengthRow("高变焦 AI 强度", value: $settingsStore.highZoomAIStrength)
                Toggle("长焦防抖", isOn: $settingsStore.extremeZoomStabilization)
                Toggle("低可信度警告", isOn: $settingsStore.extremeZoomWarning)
                HStack {
                    Text("镜头切换过渡")
                    Spacer()
                    Slider(value: $settingsStore.lensSwitchTransition, in: 0...1)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "%.2fs", settingsStore.lensSwitchTransition))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            } footer: {
                Text("超过 10× 后为混合/数字变焦，超过 100× 需要 AI 重建。")
            }
        }
        .navigationTitle("建筑与极限变焦")
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
    NavigationStack { ArchitectureZoomSettingsView() }
        .environmentObject(AppSettingsStore.shared)
}
