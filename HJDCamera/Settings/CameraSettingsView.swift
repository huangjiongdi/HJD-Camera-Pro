//
//  CameraSettingsView.swift
//  HJD Camera Pro
//
//  Photo capture settings: aspect ratio, format, resolution, multi-frame,
//  night multi-frame, RAW.
//

import SwiftUI

struct CameraSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("照片比例") {
                Picker("比例", selection: $settingsStore.defaultAspectRatio) {
                    ForEach(PhotoAspectRatio.allCases, id: \.self) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("文件格式") {
                Picker("格式", selection: $settingsStore.defaultFormat) {
                    ForEach(PhotoFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
            }

            Section("分辨率") {
                Picker("像素", selection: $settingsStore.photoResolution) {
                    Text("12 MP").tag("12MP")
                    Text("24 MP").tag("24MP")
                    Text("48 MP").tag("48MP")
                    Text("50 MP").tag("50MP")
                    Text("100 MP (AI超算)").tag("100MP")
                    Text("260 MP (AI超算)").tag("260MP")
                }
                Text("100MP/260MP 通过多帧融合 + Real-ESRGAN AI 超分输出，非传感器原生像素。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            Section {
                Toggle("多帧融合", isOn: $settingsStore.multiFrameFusion)
                Toggle("夜景多帧", isOn: $settingsStore.nightMultiFrame)
                Toggle("RAW 格式", isOn: $appState.rawEnabled)
            } header: {
                Text("高级")
            } footer: {
                Text("RAW 文件占用较大存储空间")
            }
        }
        .navigationTitle("拍摄设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { CameraSettingsView() }
        .environmentObject(AppSettingsStore.shared)
        .environmentObject(AppState.shared)
}
