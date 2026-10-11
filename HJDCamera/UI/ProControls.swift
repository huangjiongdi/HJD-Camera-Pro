import SwiftUI
import AVFoundation

// MARK: - 专业手动控制（P/A/S/M + 主界面可调）

struct ProControls: View {
    @ObservedObject var camera: CameraManager
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 8) {
            if expanded {
                // 档位
                HStack(spacing: 6) {
                    ForEach(ExposureMode.allCases) { em in
                        let sel = camera.exposureMode == em
                        Button(em.rawValue) {
                            camera.exposureMode = em
                            applyExposureMode(em)
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(sel ? .black : .white)
                        .frame(width: 36, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(sel ? Color.yellow : Color.white.opacity(0.18)))
                    }
                    Spacer()
                }

                sliderRow("ISO", value: Double(camera.manualISO),
                          range: 25...8000, fmt: "%.0f") { v in
                    camera.manualISO = Float(v)
                    applyManual()
                }
                sliderRow("快门", value: camera.manualShutter,
                          range: 1.0/8000...1, fmt: "1/%.0f") { v in
                    camera.manualShutter = v
                    applyManual()
                }
                sliderRow("EV", value: Double(camera.manualEV),
                          range: -3...3, fmt: "%.1f") { v in
                    camera.manualEV = Float(v)
                    applyManual()
                }
                sliderRow("WB", value: Double(camera.manualWBTemp),
                          range: 2000...10000, fmt: "%.0fK") { v in
                    camera.manualWBTemp = Float(v)
                    applyManual()
                }
                sliderRow("对焦", value: Double(camera.manualFocus),
                          range: 0...1, fmt: "%.2f") { v in
                    camera.manualFocus = Float(v)
                    applyManualFocus()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(7)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
        }
    }

    private func sliderRow(_ title: String, value: Double,
                           range: ClosedRange<Double>, fmt: String,
                           onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange),
                   in: range)
                .tint(.yellow)
            Text(String(format: fmt, value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }

    // MARK: 应用到设备

    private func applyExposureMode(_ em: ExposureMode) {
        switch em {
        case .program:
            applyAuto()
        case .aperture:
            // A：光圈优先（固定光圈等效为自动曝光，EV可调）
            applyAuto()
        case .shutter:
            applyManual()
        case .manual:
            applyManual()
        }
    }

    private func applyAuto() {
        camera.sessionQueueSafe { device in
            device.exposureMode = .continuousAutoExposure
            device.focusMode = .continuousAutoFocus
        }
    }

    private func applyManual() {
        let iso = camera.manualISO
        let shutter = camera.manualShutter
        let ev = camera.manualEV
        let wb = camera.manualWBTemp
        camera.sessionQueueSafe { device in
            let clampedISO = min(max(iso, device.activeFormat.minISO),
                                 device.activeFormat.maxISO)
            let dur = CMTime(seconds: shutter, preferredTimescale: 1_000_000)
            device.setExposureModeCustom(duration: dur, iso: clampedISO,
                                         completionHandler: nil)
            if device.isWhiteBalanceModeSupported(.locked) {
                let maxGain = device.maxWhiteBalanceGain
                let rGain = min(max(1.0, wb / 5600), maxGain)
                let bGain = min(max(1.0, 5600 / wb), maxGain)
                let gains = AVCaptureDevice.WhiteBalanceGains(
                    redGain: rGain, greenGain: 1.0, blueGain: bGain)
                device.setWhiteBalanceModeLocked(
                    with: gains, completionHandler: nil)
            }
        }
    }

    private func applyManualFocus() {
        let pos = camera.manualFocus
        camera.sessionQueueSafe { device in
            if device.isFocusModeSupported(.locked) {
                device.setFocusModeLocked(lensPosition: pos, completionHandler: nil)
            }
        }
    }
}

// MARK: - CameraManager 会话队列安全辅助

extension CameraManager {
    func sessionQueueSafe(_ block: @escaping (AVCaptureDevice) -> Void) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                block(device)
                device.unlockForConfiguration()
            } catch {}
        }
    }
}
