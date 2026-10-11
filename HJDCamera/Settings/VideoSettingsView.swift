//
//  VideoSettingsView.swift
//  HJD Camera Pro
//
//  Video settings: resolution, frame rate, codec, HDR, color space,
//  stabilization, audio, wind noise, file size estimate, thermal warning,
//  interruption recovery.
//

import SwiftUI

struct VideoSettingsView: View {
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private let resolutions = ["480p", "720p", "1080p", "4K"]
    private let frameRates = [24, 25, 30, 60, 120, 240]

    var body: some View {
        Form {
            Section("分辨率与帧率") {
                Picker("分辨率", selection: $settingsStore.videoResolution) {
                    ForEach(resolutions, id: \.self) { Text($0).tag($0) }
                }
                Picker("帧率", selection: $settingsStore.videoFrameRate) {
                    ForEach(frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
            }

            Section("编码与色彩") {
                Picker("编码", selection: $settingsStore.videoCodec) {
                    ForEach([VideoCodec.h264, .hevc, .proRes422, .proRes422HQ], id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Picker("色彩空间", selection: $settingsStore.videoColorSpace) {
                    ForEach([ColorSpace.sdr, .hdr, .dolbyVision, .p3, .log], id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Toggle("HDR 录制", isOn: $settingsStore.videoHDR)
            }

            Section("防抖与音频") {
                Picker("防抖模式", selection: $settingsStore.videoStabilization) {
                    ForEach(VideoStabilization.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("音频来源", selection: $settingsStore.audioSource) {
                    ForEach(AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Toggle("风噪抑制", isOn: $settingsStore.windNoiseReduction)
                Toggle("录制时锁定曝光", isOn: $settingsStore.lockExposureWhileRecording)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("预计文件大小")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Text(estimatedFileSize)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(champagneGold)
                }
            } footer: {
                Text("基于当前分辨率和编码估算每分钟录制所需空间")
            }

            Section("保护机制") {
                Toggle("过热警告", isOn: $settingsStore.thermalWarning)
                Toggle("中断自动恢复", isOn: $settingsStore.interruptRecovery)
                Toggle("低存储空间提醒", isOn: $settingsStore.lowStorageReminder)
            }
        }
        .navigationTitle("视频设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var estimatedFileSize: String {
        let base: Double
        switch settingsStore.videoResolution {
        case "4K": base = 400
        case "1080p": base = 130
        case "720p": base = 60
        default: base = 30
        }
        let fpsFactor = Double(settingsStore.videoFrameRate) / 30.0
        let size = base * fpsFactor * (settingsStore.videoHDR ? 1.3 : 1.0)
        return String(format: "约 %.0f MB / 分钟", size)
    }
}

#Preview {
    NavigationStack { VideoSettingsView() }
}
