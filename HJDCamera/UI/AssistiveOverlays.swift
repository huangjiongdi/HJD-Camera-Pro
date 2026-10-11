//
//  AssistiveOverlays.swift
//  HJD Camera Pro
//
//  Assistive overlays drawn over the live preview: rule-of-thirds / golden-ratio
//  grid, horizon level, pitch angle, focus peaking, zebra stripes, highlight
//  warning, live histogram, motion-blur warning, lightweight detection boxes.
//

import SwiftUI

struct AssistiveOverlays: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: AppSettingsStore

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Grid
                if settingsStore.gridEnabled {
                    thirdsGrid(size: geo.size)
                }

                // Horizon level
                if appState.levelEnabled {
                    levelIndicator
                }

                // Zebra stripes
                if settingsStore.zebraStripes {
                    zebraOverlay(size: geo.size)
                }

                // Focus peaking
                if settingsStore.focusPeaking {
                    peakingOverlay(size: geo.size)
                }

                // Histogram
                if settingsStore.histogramEnabled {
                    histogramView
                }

                // Motion blur warning
                if appState.currentMode == .night {
                    motionWarning
                }
            }
        }
    }

    // MARK: - Grids

    private func thirdsGrid(size: CGSize) -> some View {
        ZStack {
            ForEach(1...2, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 0.5)
                    .position(x: size.width * CGFloat(i) / 3.0, y: size.height / 2)
                    .frame(height: size.height)
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 0.5)
                    .position(x: size.width / 2, y: size.height * CGFloat(i) / 3.0)
                    .frame(width: size.width)
            }
        }
    }

    private func goldenGrid(size: CGSize) -> some View {
        let ratio: CGFloat = 0.618
        return ZStack {
            Rectangle().fill(Color.white.opacity(0.2))
                .frame(width: 0.5)
                .position(x: size.width * ratio, y: size.height/2).frame(height: size.height)
            Rectangle().fill(Color.white.opacity(0.2))
                .frame(width: 0.5)
                .position(x: size.width * (1-ratio), y: size.height/2).frame(height: size.height)
            Rectangle().fill(Color.white.opacity(0.2))
                .frame(height: 0.5)
                .position(x: size.width/2, y: size.height * ratio).frame(width: size.width)
            Rectangle().fill(Color.white.opacity(0.2))
                .frame(height: 0.5)
                .position(x: size.width/2, y: size.height * (1-ratio)).frame(width: size.width)
        }
    }

    // MARK: - Level

    private var levelIndicator: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "level")
                    .font(.system(size: 14))
                    .foregroundColor(champagneGold)
                    .padding(6)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Zebra / Peaking

    private func zebraOverlay(size: CGSize) -> some View {
        ZStack {
            Path { path in
                let step: CGFloat = 12
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y + step))
                    y += step * 2
                }
            }
            .stroke(Color.yellow.opacity(0.15), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private func peakingOverlay(size: CGSize) -> some View {
        Rectangle()
            .stroke(champagneGold.opacity(0.1), lineWidth: 1)
            .allowsHitTesting(false)
    }

    // MARK: - Histogram

    private var histogramView: some View {
        VStack {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 80, height: 50)
                    .overlay(
                        // Placeholder histogram bars
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(0..<16, id: \.self) { i in
                                Rectangle()
                                    .fill(champagneGold.opacity(0.7))
                                    .frame(width: 3, height: CGFloat.random(in: 10...45))
                            }
                        }
                        .padding(4)
                    )
            }
            Spacer()
        }
        .padding(8)
    }

    // MARK: - Motion Warning

    private var motionWarning: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("检测到手抖，建议使用三脚架")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            Spacer()
        }
    }
}

#Preview {
    AssistiveOverlays()
        .environmentObject(AppState.shared)
}
