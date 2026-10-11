//
//  PerformanceSettingsView.swift
//  HJD Camera Pro
//
//  Performance and device settings: thermal / low-power / memory degrade,
//  background policy, AI task concurrency, model preload, launch priority.
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

            Section("自适应降级") {
                Toggle("过热自动降级", isOn: $settingsStore.thermalDegrade)
                Toggle("低电量降级", isOn: $settingsStore.lowPowerDegrade)
                Toggle("内存压力保护", isOn: $settingsStore.memoryPressureProtection)
            }

            Section("性能策略") {
                Picker("后台处理策略", selection: $settingsStore.backgroundPolicy) {
                    ForEach(BackgroundPolicy.allCases, id: \.self) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                Stepper(value: $settingsStore.aiTaskConcurrency, in: 1...4) {
                    Text("AI 任务并发数：\(settingsStore.aiTaskConcurrency)")
                }
                Toggle("预加载模型", isOn: $settingsStore.preloadModels)
                Toggle("启动速度优先", isOn: $settingsStore.launchSpeedPriority)
            }

            Section("提醒与报告") {
                Toggle("电量警告", isOn: $settingsStore.batteryWarning)
                Toggle("兼容性报告", isOn: $settingsStore.compatibilityReport)
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
        .environmentObject(AppState.shared)
        .environmentObject(AppSettingsStore.shared)
}
