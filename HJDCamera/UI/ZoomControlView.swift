//
//  ZoomControlView.swift
//  HJD Camera Pro
//
//  Zoom control: common magnifications (0.5× 1× 2× 5× 10×), tap current to
//  expand fine slider, swipe up to reveal extreme telephoto panel
//  (25×–500×). Each level labeled by source (optical/hybrid/digital/AI).
//

import SwiftUI

struct ZoomControlView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var hapticEngine: HapticEngine
    @State private var showFineSlider = false
    @State private var sliderValue: Double = 1.0

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)
    private let allPoints: [Double] = [0.5, 1, 2, 5, 10, 25, 50, 100, 200, 400, 500]

    var body: some View {
        VStack(spacing: 8) {
            // Confidence hint
            if appState.zoomConfidence != .high {
                Text(appState.zoomConfidence.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(appState.zoomConfidence == .low ? .orange : .yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }

            // Standard zoom buttons — whole row long-press reveals the
            // 0.5–500 slider (per-button gestures can swallow the tap).
            HStack(spacing: 8) {
                ForEach(ZoomLevel.standard) { level in
                    zoomButton(level)
                }
                // Entry to extreme telephoto (25×–500×) and the full slider.
                Button {
                    withAnimation { appState.showExtremeZoomPanel.toggle() }
                    hapticEngine.selectionChanged()
                } label: {
                    Text("500×")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(appState.showExtremeZoomPanel ? .black : champagneGold)
                        .frame(width: 50, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(appState.showExtremeZoomPanel ? champagneGold : Color.black.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(champagneGold.opacity(0.8), lineWidth: 1.2)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                sliderValue = appState.currentZoomFactor
                withAnimation { showFineSlider = true }
                hapticEngine.selectionChanged()
            }

            // Full-range slider (0.5×–500×), shown on long-press of any zoom button.
            if showFineSlider {
                fullRangeSlider
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Extreme zoom panel (25×–500×)
            if appState.showExtremeZoomPanel {
                extremeZoomRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .onAppear { sliderValue = appState.currentZoomFactor }
    }

    // MARK: - Zoom Button

    private func zoomButton(_ level: ZoomLevel) -> some View {
        let isSelected = abs(appState.currentZoomFactor - level.factor) < 0.01
        return Button {
            selectZoom(level)
        } label: {
            VStack(spacing: 1) {
                Text(level.label)
                    .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .black : .white)
                Text(sourceLabel(level.source))
                    .font(.system(size: 8))
                    .foregroundColor(isSelected ? .black.opacity(0.65) : sourceColor(level.source))
            }
            .frame(width: 50, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? champagneGold : Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? champagneGold : Color.white.opacity(0.45), lineWidth: 1.2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func sourceLabel(_ source: ZoomSource) -> String {
        switch source {
        case .optical: return "光学"
        case .hybrid: return "混合"
        case .digital: return "数字"
        case .ai: return "AI"
        }
    }

    private func sourceColor(_ source: ZoomSource) -> Color {
        switch source {
        case .optical: return .white.opacity(0.6)
        case .hybrid: return .cyan.opacity(0.8)
        case .digital: return .orange.opacity(0.8)
        case .ai: return champagneGold
        }
    }

    private func selectZoom(_ level: ZoomLevel) {
        appState.setZoom(level.factor, source: level.source)
        // Within the hardware range, animate the optical ramp; above the
        // hardware maximum (all-digital / AI zone) set directly so it actually
        // reaches 25×–500× instead of being clamped at a hardware limit.
        if CGFloat(level.factor) > cameraManager.maxHardwareDisplayZoom {
            cameraManager.setZoomFactor(CGFloat(level.factor))
        } else {
            cameraManager.rampZoom(to: CGFloat(level.factor), rate: 8.0)
        }
        hapticEngine.trigger(.zoomNode)
        sliderValue = level.factor
    }

    // MARK: - Full-range slider (0.5× – 500×, long-press)

    /// Slider position is mapped non-linearly: the lower half of the track covers
    /// 0.5×–10× (precise framing), the upper half covers 10×–500× with heavier
    /// damping so high powers can be dialled in without overshooting.
    private var fullRangeSlider: some View {
        VStack(spacing: 4) {
            HStack {
                Text("0.5×")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.1f×", sliderValue))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(champagneGold)
                Spacer()
                Text("500×")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            Slider(value: Binding(
                get: { Self.nonLinearToUnit(sliderValue) },
                set: { unit in
                    let z = Self.unitToNonLinear(unit)
                    sliderValue = z
                    appState.setZoom(z, source: z >= 100 ? .ai : (z > 10 ? .digital : .optical))
                    cameraManager.setZoomFactor(CGFloat(z))
                }
            ))
            .tint(champagneGold)
            HStack(spacing: 6) {
                ForEach(allPoints, id: \.self) { p in
                    Text(p == 500 ? "500" : String(format: "%g", p))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(abs(sliderValue - p) < 0.5 ? champagneGold : .white.opacity(0.4))
                        .onTapGesture {
                            sliderValue = p
                            let src: ZoomSource = p >= 100 ? .ai : (p > 10 ? .digital : .optical)
                            selectZoom(ZoomLevel(factor: p, label: String(format: "%g×", p), source: src, isExtreme: p >= 25))
                        }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
    }

    // Non-linear zoom mapping (log-ish): unit 0..1 -> zoom 0.5..500.
    static func unitToNonLinear(_ u: Double) -> Double {
        let lo = Foundation.log10(0.5 as Double)
        let hi = Foundation.log10(500.0 as Double)
        return Foundation.pow(10.0, lo + (hi - lo) * u)
    }
    static func nonLinearToUnit(_ z: Double) -> Double {
        let lo = Foundation.log10(0.5 as Double)
        let hi = Foundation.log10(500.0 as Double)
        return (Foundation.log10(min(max(z, 0.5), 500.0)) - lo) / (hi - lo)
    }

    // MARK: - Extreme Zoom

    private var extremeZoomRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ZoomLevel.extreme) { level in
                    let isSelected = abs(appState.currentZoomFactor - level.factor) < 0.5
                    Button {
                        selectZoom(level)
                    } label: {
                        Text(level.label)
                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .monospaced))
                            .foregroundColor(isSelected ? .black : champagneGold)
                            .frame(width: 54, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? champagneGold : Color.black.opacity(0.4))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(champagneGold.opacity(0.7), lineWidth: 1.1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    ZoomControlView()
        .environmentObject(AppState.shared)
}
