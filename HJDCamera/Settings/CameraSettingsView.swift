//
//  CameraSettingsView.swift
//  HJD Camera Pro
//
//  Photo capture settings: aspect ratio, format, resolution, HDR, flash,
//  grid, timer, RAW.
//

import SwiftUI

struct CameraSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        Form {
            Section("照片比例") {
                Picker("比例", selection: $settingsStore.photoAspectRatio) {
                    ForEach(PhotoAspectRatio.allCases, id: \.self) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("文件格式") {
                Picker("格式", selection: $settingsStore.photoFormat) {
                    ForEach(PhotoFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
            }

            Section("分辨率") {
                Picker("像素", selection: $settingsStore.photoResolution) {
                    Text("12 MP").tag("12")
                    Text("24 MP").tag("24")
                    Text("48 MP").tag("48")
                    Text("自定义").tag("custom")
                }
            }

            Section {
                Toggle("RAW 格式", isOn: $settingsStore.rawEnabled)
                Toggle("智能HDR", isOn: $settingsStore.smartHDREnabled)
                Toggle("夜景模式自动", isOn: $settingsStore.nightAutoEnabled)
            } header: {
                Text("高级")
            } footer: {
                Text("RAW文件占用较大存储空间")
            }
        }
        .navigationTitle("拍摄设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { CameraSettingsView() }
}
