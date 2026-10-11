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

            // Standard zoom buttons
            HStack(spacing: 12) {
                ForEach(ZoomLevel.standard) { level in
                    zoomButton(level)
                }
            }

            // Fine slider (expanded)
            if showFineSlider {
                fineSlider
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Extreme zoom panel (swipe up)
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
            VStack(spacing: 2) {
                Text(level.label)
                    .font(.system(size: isSelected ? 16 : 13, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? champagneGold : .white.opacity(0.8))
                Text(sourceLabel(level.source))
                    .font(.system(size: 8))
                    .foregroundColor(sourceColor(level.source))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? champagneGold.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? champagneGold : Color.clear, lineWidth: 1)
            )
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
        cameraManager.setZoom(level.factor)
        hapticEngine.zoomNode()
        sliderValue = level.factor
    }

    // MARK: - Fine Slider

    private var fineSlider: some View {
        HStack {
            Text("0.5×")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Slider(value: $sliderValue, in: 0.5...10, onEditingChanged: { editing in
                if !editing {
                    appState.setZoom(sliderValue, source: sliderValue > 5 ? .hybrid : .optical)
                    cameraManager.setZoom(sliderValue)
                }
            })
            .tint(champagneGold)
            Text("10×")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Extreme Zoom

    private var extremeZoomRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ZoomLevel.extreme) { level in
                    let isSelected = abs(appState.currentZoomFactor - level.factor) < 0.1
                    Button {
                        selectZoom(level)
                    } label: {
                        Text(level.label)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .foregroundColor(isSelected ? champagneGold : .white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected ? champagneGold.opacity(0.2) : Color.white.opacity(0.08))
                            )
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
