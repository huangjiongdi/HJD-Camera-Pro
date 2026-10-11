//
//  ProControlPanel.swift
//  HJD Camera Pro
//
//  Pull-up professional control panel: ISO, shutter speed, EV, white balance,
//  color temperature, manual focus, sharpness, AI intensity, output scale.
//  P/A/S/M mode switch, one-tap reset, auto vs manual-lock indicators.
//

import SwiftUI

struct ProControlPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var hapticEngine: HapticEngine
    @State private var exposureMode: ExposureMode = .auto

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Mode switch row
            modeRow

            ScrollView {
                VStack(spacing: 16) {
                    isoRow
                    shutterRow
                    evRow
                    whiteBalanceRow
                    colorTempRow
                    focusRow
                    sharpnessRow
                    aiIntensityRow
                    outputScaleRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // Reset button
            Button {
                resetToAuto()
                hapticEngine.selectionChanged()
            } label: {
                Text("复位")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(champagneGold))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Mode Row

    private var modeRow: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { mode in
                Button {
                    exposureMode = mode
                    hapticEngine.selectionChanged()
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: exposureMode == mode ? .bold : .regular))
                        .foregroundColor(exposureMode == mode ? champagneGold : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private let modes: [ExposureMode] = [.auto, .program, .aperturePriority, .shutterPriority, .manual]

    // MARK: - Control Rows

    private var isoRow: some View {
        ProSliderRow(
            title: "ISO",
            value: Binding(
                get: { appState.proSettings.iso },
                set: { appState.proSettings.iso = $0 }
            ),
            range: 25...6400,
            format: { Int($0).description },
            isLocked: exposureMode == .manual || exposureMode == .shutterPriority,
            accent: champagneGold
        )
    }

    private var shutterRow: some View {
        ProSliderRow(
            title: "快门",
            value: Binding(
                get: { appState.proSettings.shutterSpeed },
                set: { appState.proSettings.shutterSpeed = $0 }
            ),
            range: 0.0001...30,
            format: { speed in
                if speed <= 0.0001 { return "自动" }
                if speed >= 1 { return String(format: "%.0fs", speed) }
                return String(format: "1/%.0f", 1.0/speed)
            },
            isLocked: exposureMode == .manual || exposureMode == .aperturePriority,
            accent: champagneGold
        )
    }

    private var evRow: some View {
        ProSliderRow(
            title: "曝光补偿",
            value: Binding(
                get: { appState.proSettings.evCompensation },
                set: { appState.proSettings.evCompensation = $0 }
            ),
            range: -8...8,
            format: { String(format: "%+.1f", $0) },
            isLocked: exposureMode != .manual,
            accent: champagneGold
        )
    }

    private var whiteBalanceRow: some View {
        ProSliderRow(
            title: "白平衡",
            value: Binding(
                get: { Double(appState.proSettings.whiteBalance) },
                set: { appState.proSettings.whiteBalance = Int($0) }
            ),
            range: 2000...10000,
            format: { "\(Int($0))K" },
            isLocked: true,
            accent: champagneGold
        )
    }

    private var colorTempRow: some View {
        ProSliderRow(
            title: "色调",
            value: Binding(
                get: { Double(appState.proSettings.colorTemperature - 5500) },
                set: { appState.proSettings.colorTemperature = Int($0) + 5500 }
            ),
            range: -150...150,
            format: { String(format: "%+.0f", $0) },
            isLocked: true,
            accent: champagneGold
        )
    }

    private var focusRow: some View {
        ProSliderRow(
            title: "手动对焦",
            value: Binding(
                get: { appState.proSettings.manualFocusDistance },
                set: { appState.proSettings.manualFocusDistance = $0 }
            ),
            range: 0.01...10,
            format: { $0 < 0 ? "AF" : String(format: "%.2fm", $0) },
            isLocked: appState.focusLocked,
            accent: champagneGold
        )
    }

    private var sharpnessRow: some View {
        ProSliderRow(
            title: "锐化",
            value: Binding(
                get: { appState.proSettings.sharpness },
                set: { appState.proSettings.sharpness = $0 }
            ),
            range: 0...1,
            format: { String(format: "%.0f%%", $0 * 100) },
            isLocked: false,
            accent: champagneGold
        )
    }

    private var aiIntensityRow: some View {
        ProSliderRow(
            title: "AI强度",
            value: Binding(
                get: { appState.proSettings.aiIntensity },
                set: { appState.proSettings.aiIntensity = $0 }
            ),
            range: 0...1,
            format: { String(format: "%.0f%%", $0 * 100) },
            isLocked: false,
            accent: champagneGold
        )
    }

    private var outputScaleRow: some View {
        ProSliderRow(
            title: "输出倍率",
            value: Binding(
                get: { appState.proSettings.outputScale },
                set: { appState.proSettings.outputScale = $0 }
            ),
            range: 1...8,
            format: { String(format: "%.0f×", $0) },
            isLocked: false,
            accent: champagneGold
        )
    }

    private func resetToAuto() {
        appState.proSettings.iso = 0
        appState.proSettings.shutterSpeed = 0
        appState.proSettings.evCompensation = 0
        appState.proSettings.whiteBalance = 0
        appState.proSettings.colorTemperature = 5500
        appState.proSettings.manualFocusDistance = -1
        exposureMode = .auto
    }
}

// MARK: - Pro Slider Row

struct ProSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let isLocked: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(format(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(isLocked ? accent : .white.opacity(0.9))
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accent)
                }
            }
            Slider(value: $value, in: range)
                .tint(accent)
        }
    }
}

#Preview {
    ProControlPanel()
        .environmentObject(AppState.shared)
}
