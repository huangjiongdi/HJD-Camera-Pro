//
//  ArchitectureZoomSettingsView.swift
//  HJD Camera Pro
//
//  Architecture correction and extreme zoom settings: keystone correction,
//  perspective lock, telephoto stabilization, extreme zoom AI enhancement,
//  maximum zoom limit, shake reduction.
//

import SwiftUI

struct ArchitectureZoomSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("建筑校正") {
                Toggle("自动透视校正", isOn: $settingsStore.keystoneAutoCorrect)
                Toggle("垂直线锁定", isOn: $settingsStore.verticalLock)
                Toggle("广角畸变校正", isOn: $settingsStore.lensDistortionCorrection)
            }

            Section("极限变焦") {
                Picker("最大倍率", selection: $settingsStore.maxZoomLimit) {
                    Text("10×").tag(10.0)
                    Text("25×").tag(25.0)
                    Text("100×").tag(100.0)
                    Text("500×").tag(500.0)
                }
                Toggle("极限长焦AI增强", isOn: $settingsStore.extremeZoomAIEnhance)
                Toggle("长焦防抖", isOn: $settingsStore.telephotoStabilization)
                HStack {
                    Text("数字变焦上限")
                    Spacer()
                    Slider(value: $settingsStore.digitalZoomLimit, in: 10...100)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "%.0f×", settingsStore.digitalZoomLimit))
                        .font(.system(size: 12, design: .monospaced))
                }
            } footer: {
                Text("超过10×后为混合/数字变焦，超过100×需要AI重建")
            }
        }
        .navigationTitle("建筑与极限变焦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { ArchitectureZoomSettingsView() }
}
