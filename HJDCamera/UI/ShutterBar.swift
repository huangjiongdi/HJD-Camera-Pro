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
                hapticEngine.impact()
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
        hapticEngine.shutter()
        if appState.currentMode.isVideoMode {
            if appState.isRecording {
                cameraManager.stopRecording()
                appState.isRecording = false
            } else {
                cameraManager.startRecording()
                appState.isRecording = true
            }
        } else {
            cameraManager.capturePhoto()
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
        if appState.currentMode == .macro {
            HStack(spacing: 8) {
                ForEach([MacroMode.fast, .detail], id: \.rawValue) { mode in
                    let selected = settingsStore.macroMode == mode
                    Button {
                        settingsStore.macroMode = mode
                        hapticEngine.impact()
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
