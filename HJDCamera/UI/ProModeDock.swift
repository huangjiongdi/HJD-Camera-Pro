//
//  ProModeDock.swift
//  HJD Camera Pro
//
//  极影式 Pro 轮盘（取景界面直接可用）：
//    顶行 P/S/A/M 档位 + 参数芯片（对焦 / ISO / 快门 / EV / 白平衡）
//    下方对数/线性轮盘，中央固定指针，松手吸附档位，拖动实时下发设备。
//  全部参数真实接线 FocusExposureController，不做纯 UI 假高亮。
//

import SwiftUI

struct ProModeDock: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var hapticEngine: HapticEngine

    private let gold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private var limits: FocusExposureController.ExposureLimits {
        FocusExposureController.shared.exposureLimits
    }

    var body: some View {
        VStack(spacing: 8) {
            // 档位 + 参数
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    modeChip(.auto, "AUTO")
                    modeChip(.program, "P")
                    modeChip(.shutterPriority, "S")
                    modeChip(.aperturePriority, "A")
                    modeChip(.manual, "M")
                    Divider().frame(height: 20).overlay(Color.white.opacity(0.25))
                    paramChip(.focus)
                    paramChip(.iso)
                    paramChip(.shutter)
                    paramChip(.ev)
                    paramChip(.wb)
                }
                .padding(.horizontal, 12)
            }
            HStack {
                Text(appState.proWheelParam.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(valueText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(gold)
                Spacer()
                Button {
                    appState.proSettings.iso = 100
                    appState.proSettings.shutterSpeed = 1.0 / 125
                    appState.proSettings.evCompensation = 0
                    appState.proSettings.whiteBalance = 0
                    appState.proSettings.manualFocusDistance = -1
                    ProManualEngine.reset()
                    applyCurrent()
                    hapticEngine.trigger(.focus, type: .light)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            wheel
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 轮盘

    @ViewBuilder
    private var wheel: some View {
        let p = appState.proWheelParam
        switch p {
        case .iso:
            LogWheelView(
                value: isoBinding,
                range: Double(limits.minISO)...Double(limits.maxISO),
                stops: isoStops,
                label: { v in v >= 100 ? "\(Int(v))" : String(format: "%.0f", v) },
                onChange: { _ in commitLive() },
                onCommit: { _ in commitLive() },
                logarithmic: true,
                haptic: { hapticEngine.selectionChanged() }
            )
        case .shutter:
            LogWheelView(
                value: shutterBinding,
                range: limits.minShutter...limits.maxShutter,
                stops: shutterStops,
                label: shutterLabel,
                onChange: { _ in commitLive() },
                onCommit: { _ in commitLive() },
                logarithmic: true,
                haptic: { hapticEngine.selectionChanged() }
            )
        case .ev:
            LogWheelView(
                value: evBinding,
                range: Double(limits.minBias)...Double(limits.maxBias),
                stops: [-5.0, -2.0, -1.0, 0.0, 1.0, 2.0, 5.0].filter {
                    $0 >= Double(limits.minBias) && $0 <= Double(limits.maxBias)
                },
                label: { v in
                    if v == 0 { return "0" }
                    return (v > 0 ? "+\(Int(v))" : "\(Int(v))")
                },
                onChange: { _ in commitLive() },
                onCommit: { _ in commitLive() },
                logarithmic: false,
                haptic: { hapticEngine.selectionChanged() }
            )
        case .wb:
            LogWheelView(
                value: wbBinding,
                range: 0...10000,
                stops: [0.0, 2500.0, 3200.0, 4000.0, 5000.0, 6000.0, 7000.0, 8000.0, 10000.0],
                label: { v in v == 0 ? "AWB" : "\(Int(v / 1000))K" },
                onChange: { _ in commitLive() },
                onCommit: { _ in commitLive() },
                logarithmic: false,
                haptic: { hapticEngine.selectionChanged() }
            )
        case .focus:
            LogWheelView(
                value: focusBinding,
                range: 0...1,
                stops: [0, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9, 1.0],
                label: { v in
                    if v == 0 { return "近" }
                    if v == 1 { return "∞" }
                    return String(format: "%.1f", v)
                },
                onChange: { _ in commitLive() },
                onCommit: { _ in commitLive() },
                logarithmic: false,
                haptic: { hapticEngine.selectionChanged() }
            )
        }
    }

    // MARK: - 绑定

    private var isoBinding: Binding<Double> {
        Binding(get: {
            let v = appState.proSettings.iso
            return v > 0 ? v : Double(FocusExposureController.shared.currentAutoISO)
        }, set: { appState.proSettings.iso = $0 })
    }
    private var shutterBinding: Binding<Double> {
        Binding(get: {
            let v = appState.proSettings.shutterSpeed
            return v > 0 ? v : 1.0 / 125
        }, set: { appState.proSettings.shutterSpeed = $0 })
    }
    private var evBinding: Binding<Double> {
        Binding(get: { appState.proSettings.evCompensation },
                set: { appState.proSettings.evCompensation = $0 })
    }
    private var wbBinding: Binding<Double> {
        Binding(get: { Double(appState.proSettings.whiteBalance) },
                set: { appState.proSettings.whiteBalance = Int($0) })
    }
    private var focusBinding: Binding<Double> {
        Binding(get: {
            let v = appState.proSettings.manualFocusDistance
            return v < 0 ? 1 : v
        }, set: { appState.proSettings.manualFocusDistance = $0 })
    }

    private var isoStops: [Double] {
        [50, 100, 200, 400, 800, 1600, 3200, 6400, 12800, 5000]
            .sorted()
            .filter { $0 >= Double(limits.minISO) && $0 <= Double(limits.maxISO) }
    }
    private var shutterStops: [Double] {
        [1.0/8000, 1.0/4000, 1.0/2000, 1.0/1000, 1.0/500, 1.0/250, 1.0/125,
         1.0/60, 1.0/30, 1.0/15, 1.0/8, 1.0/4, 1.0/2, 1, 2, 4, 8, 15, 30]
            .filter { $0 >= limits.minShutter - 1e-9 && $0 <= limits.maxShutter + 1e-9 }
    }

    private func shutterLabel(_ s: Double) -> String {
        if s < 0.4 {
            let denom = Int((1.0 / s).rounded())
            return "1/\(denom)"
        }
        if s >= 1 { return "\(Int(s.rounded()))s" }
        return String(format: "%.1fs", s)
    }

    private var valueText: String {
        switch appState.proWheelParam {
        case .iso:
            return "ISO \(Int(isoBinding.wrappedValue.rounded()))"
        case .shutter:
            return shutterLabel(shutterBinding.wrappedValue) + "s"
        case .ev:
            let v = evBinding.wrappedValue
            return v == 0 ? "EV 0" : String(format: "EV %+.1f", v)
        case .wb:
            let k = wbBinding.wrappedValue
            return k == 0 ? "AWB 自动" : "白平衡 \(Int(k))K"
        case .focus:
            let v = focusBinding.wrappedValue
            return v >= 1 ? "MF ∞" : String(format: "MF %.2f", v)
        }
    }

    // MARK: - 下发

    private func commitLive() {
        ProManualEngine.apply(mode: appState.exposureMode,
                              settings: appState.proSettings)
    }

    private func applyCurrent() {
        ProManualEngine.apply(mode: appState.exposureMode,
                              settings: appState.proSettings)
    }

    // MARK: - 芯片

    private func modeChip(_ mode: ExposureMode, _ title: String) -> some View {
        let selected = appState.exposureMode == mode
        return Button {
            appState.exposureMode = mode
            // 切档位后把轮盘落到该档位可调的参数上。
            switch mode {
            case .auto:
                appState.proWheelParam = .focus
                ProManualEngine.reset()
            case .program, .aperturePriority:
                appState.proWheelParam = .ev
                ProManualEngine.apply(mode: mode, settings: appState.proSettings)
            case .shutterPriority, .manual:
                appState.proWheelParam = .iso
                ProManualEngine.initializeManualValues(
                    mode: mode, settings: &appState.proSettings)
                ProManualEngine.apply(mode: mode, settings: appState.proSettings)
            }
            hapticEngine.trigger(.focus, type: .light)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: selected ? .bold : .medium))
                .foregroundColor(selected ? .black : .white.opacity(0.8))
                .frame(width: 44, height: 30)
                .background(Capsule().fill(selected ? gold : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func paramChip(_ param: ProWheelParam) -> some View {
        let selected = appState.proWheelParam == param
        let enabled = paramEnabled(param)
        return Button {
            appState.proWheelParam = param
            hapticEngine.trigger(.focus, type: .light)
        } label: {
            Text(param.rawValue)
                .font(.system(size: 12, weight: selected ? .bold : .medium))
                .foregroundColor(enabled
                                 ? (selected ? .black : .white.opacity(0.8))
                                 : .white.opacity(0.3))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(
                    selected && enabled ? gold : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func paramEnabled(_ p: ProWheelParam) -> Bool {
        switch p {
        case .ev:
            return appState.exposureMode == .program || appState.exposureMode == .aperturePriority
        case .iso, .shutter:
            return appState.exposureMode == .shutterPriority
                || appState.exposureMode == .manual
        case .focus, .wb:
            return true
        }
    }
}
