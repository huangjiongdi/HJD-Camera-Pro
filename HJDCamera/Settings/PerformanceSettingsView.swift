//
//  PerformanceSettingsView.swift
//  HJD Camera Pro
//
//  Performance and device settings: thermal throttling behavior, memory
//  pressure, resolution degradation, background processing, hardware accel.
//

import SwiftUI

struct PerformanceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("设备状态") {
                HStack {
                    Text("设备温度")
                    Spacer()
                    Text(thermalLabel)
                        .foregroundColor(appState.thermalState == .nominal ? .green : .orange)
                }
                HStack {
                    Text("内存压力")
                    Spacer()
                    Text(String(format: "%.0f%%", appState.memoryPressure * 100))
                        .foregroundColor(appState.memoryPressure > 0.7 ? .orange : .green)
                }
            }

            Section("性能策略") {
                Picker("过热降级", selection: $settingsStore.thermalThrottleMode) {
                    Text("自动").tag(0)
                    Text("降低分辨率").tag(1)
                    Text("关闭AI预览").tag(2)
                    Text("暂停处理").tag(3)
                }
                Toggle("后台处理", isOn: $settingsStore.backgroundProcessing)
                Toggle("Metal加速", isOn: $settingsStore.metalAcceleration)
                Toggle("禁用后台刷新", isOn: $settingsStore.disableBackgroundRefresh)
            }

            Section("预览性能") {
                Toggle("高帧率预览", isOn: $settingsStore.highFpsPreview)
                Toggle("预览降分辨率省电", isOn: $settingsStore.previewResolutionSaver)
            }
        }
        .navigationTitle("性能与设备")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var thermalLabel: String {
        switch appState.thermalState {
        case .nominal: return "正常"
        case .fair: return "温热"
        case .serious: return "过热"
        case .critical: return "严重过热"
        @unknown default: return "未知"
        }
    }
}

#Preview {
    NavigationStack { PerformanceSettingsView() }
}
