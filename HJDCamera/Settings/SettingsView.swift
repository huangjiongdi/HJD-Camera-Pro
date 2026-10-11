import SwiftUI

// MARK: - 设置页

struct SettingsView: View {
    @EnvironmentObject var camera: CameraManager
    @StateObject private var settings = AppSettingsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("拍摄") {
                    Toggle("自动切换镜头", isOn: $settings.autoSwitchLens)
                    Toggle("激光雷达切镜头", isOn: $settings.lidarLensSwitch)
                    Toggle("自动夜景", isOn: $settings.autoNight)
                    Toggle("月亮防伪", isOn: $settings.moonGuard)
                    Picker("变焦显示", selection: $settings.zoomDisplay) {
                        Text("倍数").tag(ZoomDisplayMode.multiplier)
                        Text("焦段").tag(ZoomDisplayMode.focalLength)
                    }
                }

                Section("AI 差异化功能") {
                    Toggle("AI 时间机器（最佳瞬间）", isOn: $settings.aiMomentEnabled)
                    Toggle("多镜头协同融合", isOn: $settings.multiCamFusionEnabled)
                    Toggle("追踪预测", isOn: $settings.predictiveTrackingEnabled)
                    Toggle("真实度地图", isOn: $settings.realityMapEnabled)
                    Toggle("RAW+ 可逆底片", isOn: $settings.rawPlusEnabled)
                    Toggle("光场工作室", isOn: $settings.depthStudioEnabled)
                    Toggle("计算长曝光", isOn: $settings.computationalShutterEnabled)
                    Toggle("摄影导演", isOn: $settings.cameraCoachEnabled)
                    Toggle("空气与热扰动修复", isOn: $settings.atmosphereRestoreEnabled)
                    Toggle("视频导演", isOn: $settings.videoDirectorEnabled)
                    Toggle("一镜多片", isOn: $settings.oneShotMultiCropEnabled)
                    Toggle("盲拍助手", isOn: $settings.blindCaptureEnabled)
                    Toggle("触感语言", isOn: $settings.hapticLanguageEnabled)
                    Toggle("闪烁雷达", isOn: $settings.flickerRadarEnabled)
                    Toggle("色彩匹配", isOn: $settings.colorMatchEnabled)
                    Toggle("镜头指纹档案", isOn: $settings.lensProfileEnabled)
                    Toggle("拍摄回放", isOn: $settings.capturePlaybackEnabled)
                    Toggle("隐私快门", isOn: $settings.privacyShutterEnabled)
                    Toggle("AI 故事相册", isOn: $settings.aiStoryEnabled)
                    Toggle("相机健康中心", isOn: $settings.cameraHealthCenterEnabled)
                }

                Section("实时与画质") {
                    Toggle("实时超清预览", isOn: $settings.realtimeEnhance)
                    Toggle("保存原片", isOn: $settings.saveOriginal)
                    Toggle("保存 AI 成片", isOn: $settings.saveAIResult)
                }

                Section("水印") {
                    Toggle("启用水印", isOn: $settings.watermarkEnabled)
                    Picker("水印品牌", selection: $settings.watermarkBrand) {
                        ForEach(settings.watermarkBrands, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }

                Section("元数据") {
                    Toggle("自定义 EXIF", isOn: $settings.customEXIF)
                }

                Section("音频") {
                    Toggle("空间音效", isOn: $settings.spatialAudio)
                    Toggle("抗风噪", isOn: $settings.antiWindNoise)
                }

                Section("关于") {
                    HStack {
                        Text("版本"); Spacer()
                        Text("HJD Camera Pro 2.0").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
