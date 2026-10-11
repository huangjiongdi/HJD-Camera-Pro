//
//  ColorLUTSettingsView.swift
//  HJD Camera Pro
//
//  Color and LUT settings: default LUT, intensity, import .cube files,
//  film simulation toggles, color grading.
//

import SwiftUI

struct ColorLUTSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var lutManager: LUTManager

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some Form {
        Form {
            Section("默认LUT") {
                NavigationLink {
                    FilmLUTPicker()
                        .environmentObject(lutManager)
                } label: {
                    HStack {
                        Text("当前LUT")
                        Spacer()
                        Text(settingsStore.activeLUTName)
                            .foregroundColor(champagneGold)
                    }
                }
                HStack {
                    Text("强度")
                    Spacer()
                    Slider(value: $settingsStore.lUTIntensity, in: 0...1)
                        .tint(champagneGold).frame(width: 120)
                    Text(String(format: "%.0f%%", settingsStore.lUTIntensity * 100))
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            Section("胶片模拟") {
                Toggle("富士胶片模拟", isOn: $settingsStore.fujiFilmSimulation)
                Toggle("柯达胶片模拟", isOn: $settingsStore.kodakFilmSimulation)
                Toggle("电影级调色", isOn: $settingsStore.cinematicGrade)
            }

            Section("色彩") {
                HStack {
                    Text("饱和度")
                    Spacer()
                    Slider(value: $settingsStore.saturation, in: 0...2)
                        .tint(champagneGold).frame(width: 120)
                }
                HStack {
                    Text("对比度")
                    Spacer()
                    Slider(value: $settingsStore.contrast, in: 0...2)
                        .tint(champagneGold).frame(width: 120)
                }
                HStack {
                    Text("色温偏移")
                    Spacer()
                    Slider(value: $settingsStore.colorTempShift, in: -100...100)
                        .tint(champagneGold).frame(width: 120)
                }
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
}

#Preview {
    NavigationStack { ColorLUTSettingsView() }
}
