//
//  ProControlPanel.swift
//  HJD Camera Pro
//
//  上滑专业面板（第七轮全部真实接线）：
//    P/S/A/M 档位、ISO/快门/EV/白平衡/对焦滑块 → ProManualEngine →
//    AVCaptureDevice（clamp 到 activeFormat 范围）；锐化/AI 强度/输出倍率；
//    拍摄用 LUT 快捷条（徕卡/经典）+ 强度滑杆；下滑手势关闭面板。
//

import SwiftUI

struct ProControlPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var hapticEngine: HapticEngine
    @StateObject private var lutManager = LUTManager.shared
    @State private var showLUTPicker = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private var limits: FocusExposureController.ExposureLimits {
        FocusExposureController.shared.exposureLimits
    }

    var body: some View {
        VStack(spacing: 0) {
            // Grabber（下滑关闭）
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onEnded { v in
                            if v.translation.height > 40 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    appState.showProControls = false
                                }
                                hapticEngine.trigger(.focus, type: .light)
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.showProControls = false
                    }
                }

            // Mode switch row（真实档位）
            modeRow

            ScrollView {
                VStack(spacing: 14) {
                    // 曝光参数
                    isoRow
                    shutterRow
                    evRow
                    focusRow
                    wbRow
                    Divider().background(Color.white.opacity(0.12))

                    // 拍摄 LUT（徕卡/胶片）快捷条
                    lutStrip
                    lutIntensityRow
                    Divider().background(Color.white.opacity(0.12))

                    // 高级项
                    sharpnessRow
                    aiIntensityRow
                    outputScaleRow
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }

            // Reset button
            Button {
                resetToAuto()
                hapticEngine.selectionChanged()
            } label: {
                Text("复位 · 全部恢复自动")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(champagneGold))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.62)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(isPresented: $showLUTPicker) {
            NavigationStack { FilmLUTPicker() }
                .environmentObject(LUTManager.shared)
        }
    }

    // MARK: - 档位行

    private var modeRow: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { mode in
                Button {
                    appState.exposureMode = mode
                    if mode == .auto {
                        ProManualEngine.reset()
                    } else {
                        ProManualEngine.initializeManualValues(
                            mode: mode, settings: &appState.proSettings)
                        ProManualEngine.apply(mode: mode, settings: appState.proSettings)
                    }
                    hapticEngine.selectionChanged()
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: appState.exposureMode == mode ? .bold : .regular))
                        .foregroundColor(appState.exposureMode == mode ? champagneGold : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private let modes: [ExposureMode] = [.auto, .program, .aperturePriority, .shutterPriority, .manual]

    // MARK: - 曝光参数（真实下发）

    private var isoRow: some View {
        let enabled = appState.exposureMode == .manual || appState.exposureMode == .shutterPriority
        return ProLogSliderRow(
            title: "ISO",
            value: isoBinding,
            range: Double(limits.minISO)...Double(limits.maxISO),
            format: { "ISO \(Int($0.rounded()))" },
            enabled: enabled,
            accent: champagneGold,
            onEdit: { commit() }
        )
    }

    private var shutterRow: some View {
        let enabled = appState.exposureMode == .manual || appState.exposureMode == .shutterPriority
        return ProLogSliderRow(
            title: "快门",
            value: shutterBinding,
            range: limits.minShutter...limits.maxShutter,
            format: formatShutter,
            enabled: enabled,
            accent: champagneGold,
            onEdit: { commit() }
        )
    }

    private var evRow: some View {
        let enabled = appState.exposureMode == .program
            || appState.exposureMode == .aperturePriority
        return ProSliderRow(
            title: "曝光补偿",
            value: Binding(get: { appState.proSettings.evCompensation },
                          set: { appState.proSettings.evCompensation = $0; commit() }),
            range: Double(limits.minBias)...Double(limits.maxBias),
            step: 1.0/3.0,
            format: { $0 == 0 ? "0 EV" : String(format: "%+.1f EV", $0) },
            enabled: enabled,
            accent: champagneGold
        )
    }

    private var wbRow: some View {
        HStack(spacing: 10) {
            Text("白平衡").font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 64, alignment: .leading)
            Button {
                appState.proSettings.whiteBalance = 0
                commit()
            } label: {
                Text("自动")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(appState.proSettings.whiteBalance == 0 ? .black : .white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(
                        appState.proSettings.whiteBalance == 0 ? champagneGold : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Slider(value: wbBinding, in: 2000...10000, step: 100).tint(champagneGold)
            Text(appState.proSettings.whiteBalance == 0
                 ? "AWB" : "\(appState.proSettings.whiteBalance)K")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var focusRow: some View {
        HStack(spacing: 10) {
            Text("手动对焦").font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 64, alignment: .leading)
            Button {
                appState.proSettings.manualFocusDistance = -1
                commit()
            } label: {
                Text("AF")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(appState.proSettings.manualFocusDistance < 0 ? .black : .white.opacity(0.8))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(
                        appState.proSettings.manualFocusDistance < 0 ? champagneGold : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Slider(value: focusBinding, in: 0...1, step: 0.005).tint(champagneGold)
            Text(focusText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - 高级项

    private var sharpnessRow: some View {
        ProSliderRow(
            title: "锐化",
            value: Binding(get: { appState.proSettings.sharpness },
                          set: { appState.proSettings.sharpness = $0 }),
            range: 0...1, step: 0.01,
            format: { String(format: "%.0f%%", $0 * 100) },
            enabled: true, accent: champagneGold
        )
    }

    private var aiIntensityRow: some View {
        ProSliderRow(
            title: "AI强度",
            value: Binding(get: { appState.proSettings.aiIntensity },
                          set: { appState.proSettings.aiIntensity = $0 }),
            range: 0...1, step: 0.01,
            format: { String(format: "%.0f%%", $0 * 100) },
            enabled: true, accent: champagneGold
        )
    }

    private var outputScaleRow: some View {
        ProSliderRow(
            title: "输出倍率",
            value: Binding(get: { appState.proSettings.outputScale },
                          set: { appState.proSettings.outputScale = $0 }),
            range: 1...8, step: 1,
            format: { String(format: "%.0f×", $0) },
            enabled: true, accent: champagneGold
        )
    }

    // MARK: - LUT 快捷条

    private var lutStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("拍摄滤镜（徕卡/经典）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button {
                    showLUTPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Text("更多")
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }
                    .font(.system(size: 12))
                    .foregroundColor(champagneGold)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    lutChip(name: "无", active: lutManager.activeLUTName == "None") {
                        lutManager.selectLUT("None")
                    }
                    ForEach(lutManager.quickPicks) { info in
                        lutChip(name: info.name,
                                active: lutManager.activeLUTName == info.name) {
                            lutManager.selectLUT(info.name)
                            hapticEngine.trigger(.focus, type: .light)
                        }
                    }
                }
            }
        }
    }

    private func lutChip(name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 12, weight: active ? .bold : .medium))
                .foregroundColor(active ? .black : .white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(active ? champagneGold : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private var lutIntensityRow: some View {
        ProSliderRow(
            title: "滤镜强度",
            value: Binding(get: { lutManager.intensity },
                          set: { lutManager.intensity = $0 }),
            range: 0...1, step: 0.01,
            format: { String(format: "%.0f%%", $0 * 100) },
            enabled: lutManager.activeLUTName != "None",
            accent: champagneGold
        )
    }

    // MARK: - 绑定与下发

    private var isoBinding: Binding<Double> {
        Binding(get: {
            appState.proSettings.iso > 0
                ? appState.proSettings.iso
                : Double(FocusExposureController.shared.currentAutoISO)
        }, set: { appState.proSettings.iso = $0 })
    }
    private var shutterBinding: Binding<Double> {
        Binding(get: {
            appState.proSettings.shutterSpeed > 0
                ? appState.proSettings.shutterSpeed
                : 1.0 / 125
        }, set: { appState.proSettings.shutterSpeed = $0 })
    }
    private var wbBinding: Binding<Double> {
        Binding(get: { Double(max(appState.proSettings.whiteBalance, 2000)) },
                set: { appState.proSettings.whiteBalance = Int($0); commit() })
    }
    private var focusBinding: Binding<Double> {
        Binding(get: { appState.proSettings.manualFocusDistance < 0
                        ? 1 : appState.proSettings.manualFocusDistance },
                set: { appState.proSettings.manualFocusDistance = $0; commit() })
    }

    private var focusText: String {
        let v = appState.proSettings.manualFocusDistance
        if v < 0 { return "AF" }
        if v >= 0.999 { return "∞" }
        return String(format: "%.2f", v)
    }

    private func formatShutter(_ s: Double) -> String {
        if s >= 1 { return String(format: "%.0fs", s) }
        return String(format: "1/%.0f", 1.0 / s)
    }

    private func commit() {
        ProManualEngine.apply(mode: appState.exposureMode,
                              settings: appState.proSettings)
    }

    private func resetToAuto() {
        appState.exposureMode = .auto
        appState.proSettings.iso = 100
        appState.proSettings.shutterSpeed = 1.0 / 125
        appState.proSettings.evCompensation = 0
        appState.proSettings.whiteBalance = 0
        appState.proSettings.colorTemperature = 5500
        appState.proSettings.manualFocusDistance = -1
        ProManualEngine.reset()
    }
}

// MARK: - 线性滑块行

struct ProSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let format: (Double) -> String
    let enabled: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(enabled ? .white.opacity(0.8) : .white.opacity(0.35))
                Spacer()
                Text(format(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(enabled ? .white.opacity(0.95) : .white.opacity(0.4))
            }
            if step > 0 {
                Slider(value: $value, in: range, step: step).tint(accent)
            } else {
                Slider(value: $value, in: range).tint(accent)
            }
        }
        .disabled(!enabled)
    }
}

// MARK: - 对数滑块行（ISO / 快门）

struct ProLogSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let enabled: Bool
    let accent: Color
    let onEdit: () -> Void

    private var fraction: Binding<Double> {
        Binding(
            get: {
                let lo = log(range.lowerBound), hi = log(range.upperBound)
                let v = log(min(max(value, range.lowerBound), range.upperBound))
                return (v - lo) / (hi - lo)
            },
            set: { f in
                let lo = log(range.lowerBound), hi = log(range.upperBound)
                value = exp(lo + min(max(f, 0), 1) * (hi - lo))
                onEdit()
            }
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(enabled ? .white.opacity(0.8) : .white.opacity(0.35))
                Spacer()
                Text(format(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(enabled ? .white.opacity(0.95) : .white.opacity(0.4))
            }
            Slider(value: fraction).tint(accent)
        }
        .disabled(!enabled)
    }
}

#Preview {
    ProControlPanel()
        .environmentObject(AppState.shared)
        .environmentObject(AppSettingsStore.shared)
        .environmentObject(HapticEngine.shared)
}
