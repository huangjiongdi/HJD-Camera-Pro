//
//  TopStatusBar.swift
//  HJD Camera Pro
//
//  Top status overlay: flash / timer / grid on the left; mode / ratio / format
//  in the center; settings / RAW / level on the right. Tap to expand details.
//

import SwiftUI
import AVFoundation

struct TopStatusBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var expanded = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(spacing: 6) {
            // Main row
            HStack {
                // Left controls
                HStack(spacing: 16) {
                    flashButton
                    timerButton
                    gridButton
                }

                Spacer()

                // Center info
                centerInfo
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                // Right controls
                HStack(spacing: 16) {
                    rawButton
                    levelButton
                    settingsButton
                }
            }

            // Expanded detail row
            if expanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.black.opacity(0.3))
        .onTapGesture {
            withAnimation { expanded.toggle() }
        }
    }

    // MARK: - Left

    private var flashButton: some View {
        Button {
            cycleFlashMode()
        } label: {
            Image(systemName: flashIconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(appState.flashMode == .off ? .gray : champagneGold)
        }
    }

    private var flashIconName: String {
        switch appState.flashMode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        @unknown default: return "bolt.fill"
        }
    }

    private func cycleFlashMode() {
        switch appState.flashMode {
        case .off: appState.flashMode = .auto
        case .auto: appState.flashMode = .on
        case .on: appState.flashMode = .off
        @unknown default: appState.flashMode = .auto
        }
    }

    private var timerButton: some View {
        Button {
            cycleTimer()
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(appState.timerDuration > 0 ? champagneGold : .white.opacity(0.8))
        }
    }

    private func cycleTimer() {
        let options = [0, 3, 10]
        let current = options.firstIndex(of: appState.timerDuration) ?? 0
        appState.timerDuration = options[(current + 1) % options.count]
    }

    private var gridButton: some View {
        Button {
            appState.gridEnabled.toggle()
        } label: {
            Image(systemName: appState.gridEnabled ? "grid" : "grid.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(appState.gridEnabled ? champagneGold : .white.opacity(0.8))
        }
    }

    // MARK: - Center

    @ViewBuilder
    private var centerInfo: some View {
        switch appState.currentMode {
        case .photo:
            Text("\(settingsStore.photoAspectRatio.rawValue) · \(settingsStore.photoFormat.rawValue) · \(settingsStore.photoResolution)MP")
        case .portrait:
            Text("人像 · \(settingsStore.photoAspectRatio.rawValue) · f/\(settingsStore.portraitAperture)")
        case .video, .slowMotion:
            Text("\(settingsStore.videoResolution) · \(settingsStore.videoFrameRate)fps · \(settingsStore.videoCodec.rawValue)\(settingsStore.videoHDR ? " · HDR" : "")")
        case .night:
            Text("夜景 · \(settingsStore.nightPreset.rawValue) · \(settingsStore.nightFrameCount)帧")
        case .superMoon:
            Text(appState.lunarDetected ? "月亮已识别 · \(appState.lunarTracking ? "跟踪中" : "待锁定")" : "未检测到月亮")
        case .macro:
            Text("微距 · \(settingsStore.macroMode.rawValue) · \(appState.focusLocked ? "AF锁定" : "AF")")
        case .pro:
            Text("PRO · ISO \(Int(appState.proSettings.iso)) · \(formatShutter(appState.proSettings.shutterSpeed)) · EV \(String(format: "%+.1f", appState.proSettings.evCompensation))")
        default:
            Text(appState.currentMode.rawValue)
        }
    }

    private func formatShutter(_ speed: Double) -> String {
        if speed <= 0 { return "自动" }
        if speed >= 1 { return String(format: "%.0fs", speed) }
        return String(format: "1/%.0fs", 1.0 / speed)
    }

    // MARK: - Right

    private var rawButton: some View {
        Button {
            appState.rawEnabled.toggle()
        } label: {
            Text("RAW")
                .font(.system(size: 11, weight: appState.rawEnabled ? .bold : .regular, design: .monospaced))
                .foregroundColor(appState.rawEnabled ? champagneGold : .white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(appState.rawEnabled ? champagneGold : Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var levelButton: some View {
        Button {
            appState.levelEnabled.toggle()
        } label: {
            Image(systemName: appState.levelEnabled ? "level" : "level")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(appState.levelEnabled ? champagneGold : .white.opacity(0.8))
        }
    }

    private var settingsButton: some View {
        Button {
            appState.showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    // MARK: - Expanded Detail

    private var expandedDetail: some View {
        VStack(spacing: 8) {
            Divider().background(Color.white.opacity(0.2))
            HStack {
                detailChip("AI预览", value: appState.aiPreviewLevel.rawValue, active: appState.aiPreviewLevel != .off)
                detailChip("场景", value: appState.sceneType.rawValue, active: appState.sceneType != .normal)
                detailChip("温度", value: thermalLabel, active: appState.thermalState != .nominal)
                detailChip("存储", value: storageLabel, active: appState.storageAvailable < 1_000_000_000)
            }
        }
    }

    private func detailChip(_ title: String, value: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(active ? champagneGold : .white.opacity(0.8))
        }
        .padding(.horizontal, 10)
    }

    private var thermalLabel: String {
        switch appState.thermalState {
        case .nominal: return "正常"
        case .fair: return "温热"
        case .serious: return "过热"
        case .critical: return "严重"
        @unknown default: return "未知"
        }
    }

    private var storageLabel: String {
        let gb = Double(appState.storageAvailable) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }
}

#Preview {
    TopStatusBar()
        .environmentObject(AppState.shared)
        .environmentObject(AppSettingsStore.shared)
}
