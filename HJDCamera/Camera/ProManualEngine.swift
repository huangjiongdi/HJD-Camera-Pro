//
//  ProManualEngine.swift
//  HJD Camera Pro
//
//  把 Pro 面板/轮盘的参数（P/S/A/M、ISO、快门、EV、白平衡、对焦）
//  真实下发到 AVCaptureDevice。所有值 clamp 到 activeFormat 支持范围。
//

import Foundation

enum ProManualEngine {
    private static var ctrl: FocusExposureController { .shared }

    /// 档位 + 当前设置 → 设备。参数变化即调用（轮盘/滑块拖动结束时也会调用）。
    static func apply(mode: ExposureMode, settings: ProCaptureSettings) {
        let limits = ctrl.exposureLimits
        // 白平衡与对焦独立于曝光档位。
        ctrl.setWhiteBalance(kelvin: settings.whiteBalance)
        applyFocus(settings.manualFocusDistance)

        switch mode {
        case .auto:
            ctrl.setAutoExposure(ev: 0)
        case .program, .aperturePriority:
            // iPhone 光圈固定，A 档等同 P 档：连续自动曝光 + EV 补偿。
            ctrl.setAutoExposure(ev: settings.evCompensation)
        case .shutterPriority:
            // 固定快门（clamp 到设备范围）；ISO 未手动指定时取设备当前自动 ISO。
            var shutter = settings.shutterSpeed
            if shutter <= 0 { shutter = 1.0 / 125 }
            shutter = min(max(shutter, limits.minShutter), limits.maxShutter)
            var iso = settings.iso
            if iso <= 0 { iso = Double(ctrl.currentAutoISO) }
            iso = min(max(iso, Double(limits.minISO)), Double(limits.maxISO))
            ctrl.setShutterPriority(shutter: shutter, iso: iso)
            // 自定义模式下 bias 无效，先清零避免回到自动档时残留。
            ctrl.setExposureCompensationOnly(0)
        case .manual:
            var shutter = settings.shutterSpeed
            if shutter <= 0 { shutter = 1.0 / 125 }
            var iso = settings.iso
            if iso <= 0 { iso = Double(ctrl.currentAutoISO) }
            ctrl.setCustomExposure(iso: iso, shutter: shutter)
            ctrl.setExposureCompensationOnly(0)
        }
    }

    /// 仅设置 EV bias（不改曝光模式）。
    static func applyEV(_ ev: Double) {
        ctrl.setAutoExposure(ev: ev)
    }

    /// 对焦：-1 = 连续 AF；0...1 = 手动 lensPosition。
    static func applyFocus(_ value: Double) {
        if value < 0 {
            ctrl.setLensPosition(-1)
        } else {
            ctrl.setLensPosition(min(max(value, 0), 1))
        }
    }

    /// 离开 Pro 模式或复位：全部恢复自动。
    static func reset() {
        ctrl.resetAll()
    }

    /// 档位切换时给出合理的初始值（S/M 档进入时快门/ISO 不能为 0）。
    static func initializeManualValues(mode: ExposureMode, settings: inout ProCaptureSettings) {
        let limits = ctrl.exposureLimits
        switch mode {
        case .shutterPriority:
            if settings.shutterSpeed <= 0 { settings.shutterSpeed = 1.0 / 125 }
            if settings.iso <= 0 { settings.iso = Double(ctrl.currentAutoISO) }
        case .manual:
            if settings.shutterSpeed <= 0 { settings.shutterSpeed = 1.0 / 125 }
            if settings.iso <= 0 { settings.iso = Double(ctrl.currentAutoISO) }
        default:
            break
        }
        _ = limits
    }
}
