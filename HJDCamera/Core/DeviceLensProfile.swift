//
//  DeviceLensProfile.swift
//  HJD Camera Pro
//
//  iPhone 16 Pro Max 镜头档案与"显示倍率 -> 硬件倍率/实际镜头"映射。
//
//  16 Pro Max 后置三颗真实镜头（虚拟三摄 builtInTripleCamera 统一调度）：
//    0.5× 超广角  13mm  (48MP)
//    1×   主摄    24mm  (48MP Fusion)
//    2×   主摄四合一传感器裁切 48mm（没有独立长焦镜头，是主摄中心 12MP 裁切）
//    5×   四重反射潜望长焦 120mm (48MP)
//
//  关键：虚拟相机的 videoZoomFactor 以"超广角 = 1.0"为基准。AVFoundation 给出的
//  virtualDeviceSwitchOverVideoZoomFactors 就是各真实镜头切换点（硬件坐标）：
//    典型 16 Pro Max 为 [2.0, 10.0] —— 硬件 2.0 切到主摄(=显示 1×)，
//    硬件 10.0 切到潜望长焦(=显示 5×)。显示 2× 时硬件 4.0 仍在主摄区间，
//    属于主摄传感器裁切，而不是独立长焦。
//
//  不再硬编码假设 ×2：所有倍率坐标均从当前设备的真实 switchOver 因子推导，
//  这样在非 16 Pro Max 设备上也能正确降级。
//

import AVFoundation
import UIKit

enum HJDLens: Equatable {
    case front
    case ultrawide      // 超广角
    case wide           // 主摄
    case wideCrop2x     // 主摄 2× 传感器裁切
    case telephoto      // 潜望长焦
    case digital        // 纯数字/AI 区域

    /// 取景器 HUD 上显示的镜头名。
    var shortName: String {
        switch self {
        case .front:       return "前置"
        case .ultrawide:   return "超广角"
        case .wide:        return "主摄"
        case .wideCrop2x:  return "主摄 2×"
        case .telephoto:   return "潜望长焦"
        case .digital:     return "数字变焦"
        }
    }
}

struct DeviceLensProfile {
    /// 显示倍率 → 硬件倍率 的乘算系数（主摄 1× 对应的硬件倍率）。
    let displayToHardware: CGFloat
    /// 硬件坐标下的镜头切换点（升序）。
    let switchOverHardware: [CGFloat]
    /// 该设备是否为含超广角的虚拟多摄。
    let isVirtual: Bool
    /// 硬件可达的最大显示倍率。
    let maxHardwareDisplayZoom: CGFloat
    /// 是否为后置相机。
    let isBack: Bool

    // MARK: - Build from device

    static func profile(for device: AVCaptureDevice, isBack: Bool) -> DeviceLensProfile {
        let sw = (device.virtualDeviceSwitchOverVideoZoomFactors as [NSNumber])
            .map { CGFloat($0.doubleValue) }
            .sorted()
        let hasUltraWide = device.constituentDevices.contains {
            $0.deviceType == .builtInUltraWideCamera
        } || device.deviceType == .builtInTripleCamera
            || device.deviceType == .builtInDualWideCamera
        let isVirtual = !device.constituentDevices.isEmpty || hasUltraWide

        // 主摄 1× 对应的硬件倍率：优先用第一个真实切换点（超广角→主摄）。
        // 回退：含超广角时用 minAvailableVideoZoomFactor/0.5；普通单摄为 1.0。
        var mult: CGFloat = 1.0
        if let first = sw.first, first > 1.0 {
            mult = first
        } else if hasUltraWide {
            mult = max(device.minAvailableVideoZoomFactor / 0.5, 1.0)
        }

        let maxHW = device.maxAvailableVideoZoomFactor
        let maxDisplay = max(maxHW / mult, 1.0)

        return DeviceLensProfile(
            displayToHardware: mult,
            switchOverHardware: sw,
            isVirtual: isVirtual,
            maxHardwareDisplayZoom: maxDisplay,
            isBack: isBack
        )
    }

    // MARK: - Mapping

    /// 显示倍率 → 硬件 videoZoomFactor（clamp 到设备真实范围）。
    func hardwareZoom(forDisplay display: CGFloat, on device: AVCaptureDevice) -> CGFloat {
        let hw = display * displayToHardware
        return min(max(hw, device.minAvailableVideoZoomFactor),
                   device.maxAvailableVideoZoomFactor)
    }

    /// 超出硬件能力后，预览层/成片需要额外做的数字裁切（显示空间）。
    func digitalCrop(forDisplay display: CGFloat) -> CGFloat {
        display > maxHardwareDisplayZoom ? display / maxHardwareDisplayZoom : 1.0
    }

    /// 当前显示倍率实际使用的物理镜头。
    func activeLens(forDisplay display: CGFloat) -> HJDLens {
        guard isBack else { return .front }
        if display > maxHardwareDisplayZoom + 0.01 { return .digital }

        let hw = display * displayToHardware
        // 切换点：第一个为超广角→主摄，第二个为主摄→长焦。
        let toWide = switchOverHardware.first ?? displayToHardware
        if let toTele = switchOverHardware.dropFirst().first {
            if hw < toWide * 0.999 { return .ultrawide }
            if hw >= toTele * 0.999 { return .telephoto }
            // 处于主摄覆盖区间：靠近 2×（48mm）标注为传感器裁切。
            if display >= 1.5 { return .wideCrop2x }
            return .wide
        }
        // 只有超广角+主摄的双摄
        if hw < toWide * 0.999 { return .ultrawide }
        if display >= 1.5 { return .wideCrop2x }
        return .wide
    }

    /// 各镜头切换点对应的"显示倍率"，用于 UI 与非线性变焦动画。
    var switchOverDisplay: [CGFloat] {
        switchOverHardware.map { $0 / displayToHardware }
    }

    /// 焦距（16 Pro Max 典型值），用于 HUD 显示；非目标设备给近似值。
    func focalLengthText(forDisplay display: CGFloat) -> String {
        switch activeLens(forDisplay: display) {
        case .front:      return "前置"
        case .ultrawide:  return "13mm"
        case .wide:       return "24mm"
        case .wideCrop2x: return "48mm"
        case .telephoto:  return "120mm"
        case .digital:
            // 数字区：基于长焦继续数字放大，给出等效焦距（近似）。
            let mm = Int((120 * max(display / 5.0, 1.0)).rounded())
            return "\(mm)mm 数字"
        }
    }
}
