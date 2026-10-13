//
//  CameraPreviewContainer.swift
//  HJD Camera Pro
//
//  Wraps the live CameraPreviewView. Tap to focus/expose, long-press to lock
//  AE/AF, double-tap to zoom. Overlays: grid, level, focus peaking, zebra,
//  histogram, detection boxes, AI preview enhancement badge.
//

import SwiftUI
import AVFoundation

struct CameraPreviewContainer: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var focusPoint: CGPoint?
    @State private var showFocusBox = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Live preview layer — fills the whole screen (full-bleed).
                CameraPreviewView(session: cameraManager.session)
                    .environmentObject(cameraManager)
                    .frame(width: geo.size.width, height: geo.size.height)
                    // 硬件上限以上（>100×）的数字裁切由 SwiftUI 层放大，
                    // scaleEffect 不参与布局，不会被每帧重布局重置，
                    // 因此画面可以一直放大到 500×（所见即所得，中心裁切）。
                    .scaleEffect(cameraManager.digitalCropScale, anchor: .center)

                // Assistive overlays
                if settingsStore.gridEnabled {
                    AssistiveOverlays()
                        .environmentObject(appState)
                        .environmentObject(settingsStore)
                }

                // Focus gesture layer
                FocusGestureView(
                    focusPoint: $focusPoint,
                    showFocusBox: $showFocusBox
                )
                .environmentObject(appState)
                .environmentObject(cameraManager)

                // Detection boxes
                detectionBoxes
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // MARK: - Detection Boxes

    @ViewBuilder
    private var detectionBoxes: some View {
        if appState.lunarDetected {
            DetectionBox(
                color: champagneGold,
                label: "月亮",
                confidence: appState.lunarTracking ? "锁定" : "识别中"
            )
        }
        if appState.macroDetected {
            DetectionBox(
                color: .green,
                label: "微距",
                confidence: "检测到近距离物体"
            )
        }
    }

}

// MARK: - Detection Box

struct DetectionBox: View {
    let color: Color
    let label: String
    let confidence: String
    @State private var animate = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                        .overlay(
                            VStack {
                                Spacer()
                                HStack {
                                    Text(label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(color)
                                    Spacer()
                                    Text(confidence)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(6)
                                .background(Color.black.opacity(0.4))
                            }
                        )
                        .scaleEffect(animate ? 1.0 : 0.95)
                }
                Spacer()
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

#Preview {
    CameraPreviewContainer()
        .environmentObject(AppState.shared)
}
