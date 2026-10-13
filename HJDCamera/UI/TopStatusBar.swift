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
            // Row 1 — corner controls only. These sit at the two sides of the
            // Dynamic Island rather than underneath its centre.
            HStack {
                HStack(spacing: 16) {
                    flashButton
                    timerButton
                    gridButton
                    filterButton
                }
                Spacer()
                HStack(spacing: 16) {
                    rawButton
                    levelButton
                    settingsButton
                }
            }

            // Row 2 — mode / format info, full-width and BELOW the Dynamic
            // Island so the island never covers it.
            centerInfo
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentShape(Capsule())
                .onTapGesture { withAnimation { expanded.toggle() } }

            // Expanded detail row
            if expanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
        // Tap on the format pill expands details; the icon buttons keep taps.
    }

    // MARK: - Left

    private var flashButton: some View {
        Button {
            cycleFlashMode()
        } label: {
            let mode = AppState.shared.flashMode
            Image(systemName: flashIcon(for: mode))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(mode == .off ? .white.opacity(0.8) : champagneGold)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func flashIcon(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        @unknown default: return "bolt.fill"
        }
    }

    private func cycleFlashMode() {
        switch AppState.shared.flashMode {
        case .off: AppState.shared.flashMode = .auto
        case .auto: AppState.shared.flashMode = .on
        case .on: AppState.shared.flashMode = .off
        @unknown default: AppState.shared.flashMode = .auto
        }
    }

    private var timerButton: some View {
        Button {
            cycleTimer()
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(appState.timerDuration > 0 ? champagneGold : .white.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func cycleTimer() {
        let options = [0, 3, 10]
        let current = options.firstIndex(of: appState.timerDuration) ?? 0
        appState.timerDuration = options[(current + 1) % options.count]
    }

    private var gridButton: some View {
        // 取景网格线统一以 settingsStore.gridEnabled 为准（AssistiveOverlays /
        // CameraPreviewContainer 读的就是它）；旧版切 appState.gridEnabled，
        // 导致九宫格点了没反应。
        Button {
            settingsStore.gridEnabled.toggle()
        } label: {
            Image(systemName: settingsStore.gridEnabled ? "grid" : "grid.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(settingsStore.gridEnabled ? champagneGold : .white.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 滤镜（极影式横滑条）

    private var filterButton: some View {
        let active = appState.showFilterStrip || LUTManager.shared.activeLUTName != "None"
        return Button {
            hapticToggle()
            withAnimation(.easeOut(duration: 0.2)) {
                appState.showFilterStrip.toggle()
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(active ? .black : .white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(active ? champagneGold : Color.black.opacity(0.35)))
                if LUTManager.shared.activeLUTName != "None" {
                    Circle()
                        .fill(champagneGold)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func hapticToggle() {
        // 触感引擎在环境里没有注入到顶栏，直接走单例。
        HapticEngine.shared.selectionChanged()
    }

    // MARK: - Center

    @ViewBuilder
    private var centerInfo: some View {
        switch appState.currentMode {
        case .photo:
            Text("\(settingsStore.defaultAspectRatio.rawValue) · \(settingsStore.defaultFormat.rawValue) · \(settingsStore.photoResolution)")
        case .portrait:
            Text("人像 · \(settingsStore.defaultAspectRatio.rawValue) · f/\(String(format: "%.1f", settingsStore.apertureSimulation))")
        case .video, .slowMotion:
            Text("\(settingsStore.videoResolution) · \(settingsStore.videoFrameRate)fps · \(settingsStore.videoCodec.rawValue)\(settingsStore.videoHDR ? " · HDR" : "")")
        case .night:
            Text("夜景 · \(settingsStore.nightHandholdMode.rawValue) · \(settingsStore.nightFrameCount)帧")
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
                .font(.system(size: 11, weight: appState.rawEnabled ? .bold : .medium, design: .monospaced))
                .foregroundColor(appState.rawEnabled ? champagneGold : .white.opacity(0.85))
                .frame(width: 44, height: 38)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                        .overlay(Capsule().stroke(appState.rawEnabled ? champagneGold : Color.white.opacity(0.3), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private var levelButton: some View {
        Button {
            appState.levelEnabled.toggle()
        } label: {
            Image(systemName: appState.levelEnabled ? "level" : "level")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(appState.levelEnabled ? champagneGold : .white.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button {
            appState.showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
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
