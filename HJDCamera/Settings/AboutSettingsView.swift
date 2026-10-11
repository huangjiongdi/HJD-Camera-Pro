//
//  AboutSettingsView.swift
//  HJD Camera Pro
//
//  About / privacy / developer tools: version info, licenses, privacy policy,
//  diagnostic logs, compatibility report, reset all settings.
//

import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject var diagnosticLogger: DiagnosticLogger
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var showResetConfirm = false
    @State private var developerMode = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0 (Build 1)")
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack {
                    Text("设备")
                    Spacer()
                    Text(DeviceCapabilityManager.shared.deviceModelName())
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack {
                    Text("iOS")
                    Spacer()
                    Text(UIDevice.current.systemVersion)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Section("隐私") {
                Link(destination: URL(string: "https://hjdcamera.com/privacy")!) {
                    Label("隐私政策", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://hjdcamera.com/terms")!) {
                    Label("用户协议", systemImage: "doc.text")
                }
            }

            Section("开发者工具") {
                NavigationLink {
                    DiagnosticLogView()
                        .environmentObject(diagnosticLogger)
                } label: {
                    Label("诊断日志", systemImage: "doc.badge.ellipsis")
                }
                NavigationLink {
                    CompatibilityReportView()
                } label: {
                    Label("兼容性报告", systemImage: "info.circle")
                }
                Toggle("开发者模式", isOn: $developerMode)
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("重置所有设置", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("确认重置所有设置？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                settingsStore.resetToDefaults()
            }
        } message: {
            Text("此操作将恢复所有设置为默认值，不会删除照片。")
        }
    }
}

// MARK: - Diagnostic Log View

struct DiagnosticLogView: View {
    @EnvironmentObject var diagnosticLogger: DiagnosticLogger
    @State private var logText = ""

    var body: some View {
        ScrollView {
            Text(logText.isEmpty ? "暂无日志" : logText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle("诊断日志")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { logText = diagnosticLogger.currentLogContents() }
    }
}

// MARK: - Compatibility Report

struct CompatibilityReportView: View {
    private let report = DeviceCapabilityManager.shared.compatibilityReport()

    var body: some View {
        List {
            ForEach(report.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key).foregroundColor(.white)
                    Spacer()
                    Text("\(report[key] ?? "")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .navigationTitle("兼容性报告")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { AboutSettingsView() }
}
