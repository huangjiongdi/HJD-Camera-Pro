//
//  ShutterBar.swift
//  HJD Camera Pro
//
//  Bottom shutter bar: last-photo thumbnail on the left, large shutter button
//  in the center (round for photo, red for video, stop-square while recording),
//  camera flip on the right. Mode-specific hints for super-moon and macro.
//

import SwiftUI
import AVFoundation

struct ShutterBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var hapticEngine: HapticEngine
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        HStack(spacing: 30) {
            // Left: last photo thumbnail
            Button {
                appState.showGallery = true
            } label: {
                Group {
                    if let url = appState.lastCapturedImageURL {
                        AsyncThumbnail(url: url)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
            }

            Spacer()

            // Center: shutter button
            shutterButton

            Spacer()

            // Right: camera flip
            Button {
                cameraManager.switchCamera()
                hapticEngine.selectionChanged()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .top) {
            modeHint
        }
    }

    // MARK: - Shutter

    private var shutterButton: some View {
        Button {
            shutterAction()
        } label: {
            ZStack {
                if appState.isRecording {
                    // Stop recording
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                } else if appState.currentMode.isVideoMode {
                    // Video record
                    Circle()
                        .fill(Color.red)
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        .frame(width: 72, height: 72)
                } else {
                    // Photo
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 3)
                        .frame(width: 80, height: 80)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func shutterAction() {
        // 快门点击埋点：记录模式/闪光灯/RAW/倍率/会话状态，闪退时最后一条
        // [SHUTTER] 记录可定位到具体步骤。
        let tap = ShutterTrace.nextTap()
        ShutterTrace.mark(
            tap, "快门按下",
            extra: "模式=\(appState.currentMode.rawValue) 闪光=\(flashName(AppState.shared.flashMode)) RAW=\(AppState.shared.rawEnabled) 倍率=\(String(format: "%.2f", Double(cameraManager.currentZoomFactor))) 录像中=\(appState.isRecording) 会话运行=\(cameraManager.isSessionRunning) 前置=\(cameraManager.usingFrontCamera)"
        )
        hapticEngine.trigger(.shutter)
        if appState.currentMode.isVideoMode {
            if appState.isRecording {
                ShutterTrace.mark(tap, "停止录像")
                cameraManager.stopRecording()
                appState.isRecording = false
            } else {
                ShutterTrace.mark(tap, "开始录像")
                cameraManager.startRecording()
                appState.isRecording = true
            }
        } else if appState.currentMode.isTrailMode
                    && PhotoCapturePipeline.shared.isTrailActive {
            // 多帧序列进行中，快门锁定，避免重复触发。
            ShutterTrace.mark(tap, "序列拍摄中，忽略快门")
        } else {
            cameraManager.capturePhoto(tap: tap)
        }
    }

    private func flashName(_ m: AVCaptureDevice.FlashMode) -> String {
        switch m {
        case .off: return "off"
        case .on: return "on"
        case .auto: return "auto"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Mode Hints

    @ViewBuilder
    private var modeHint: some View {
        if appState.currentMode == .superMoon && appState.lunarTracking {
            Text("月面已锁定")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(champagneGold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .offset(y: -40)
        }
        if appState.currentMode.isTrailMode {
            if PhotoCapturePipeline.shared.isTrailActive {
                HStack(spacing: 8) {
                    ProgressView().tint(champagneGold).scaleEffect(0.8)
                    Text(String(format: "保持稳定… %.0f%%", appState.processingProgress * 100))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.65)))
                .offset(y: -40)
            } else {
                Text(appState.currentMode == .multiExposure
                     ? "保持稳定：自动连拍5张叠加"
                     : "固定手机：自动连排长曝光合成")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .offset(y: -40)
            }
        }
        if appState.currentMode == .macro {
            HStack(spacing: 8) {
                ForEach([MacroMode.fast, .detail], id: \.rawValue) { mode in
                    let selected = settingsStore.macroMode == mode
                    Button {
                        settingsStore.macroMode = mode
                        hapticEngine.selectionChanged()
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundColor(selected ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .offset(y: -40)
        }
    }
}

// MARK: - Async Thumbnail

struct AsyncThumbnail: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color.gray.opacity(0.3)
            default:
                Color.white.opacity(0.1)
            }
        }
    }
}

#Preview {
    ShutterBar()
        .environmentObject(AppState.shared)
}
