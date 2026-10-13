//
//  FocusGestureView.swift
//  HJD Camera Pro
//
//  Focus gesture handling over the preview: tap to focus/expose, long-press to
//  lock AE/AF, double-tap to zoom. Animated focus box and lock indicator.
//

import SwiftUI

struct FocusGestureView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager
    @Binding var focusPoint: CGPoint?
    @Binding var showFocusBox: Bool
    @State private var boxScale: CGFloat = 1.0
    @State private var lockIndicatorShown = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Transparent gesture layer
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: location, in: geo.size)
                    }
                    .onLongPressGesture(minimumDuration: 0.6) {
                        handleLongPress()
                    }
                    .onTapGesture(count: 2) {
                        handleDoubleTap()
                    }

                // Focus box
                if showFocusBox, let point = focusPoint {
                    focusBox
                        .position(point)
                        .scaleEffect(boxScale)
                }

                // AE/AF lock badge
                if lockIndicatorShown || (appState.focusLocked && appState.exposureLocked) {
                    lockBadge
                        .position(
                            x: focusPoint?.x ?? geo.size.width / 2,
                            y: (focusPoint?.y ?? geo.size.height / 2) - 50
                        )
                }
            }
        }
    }

    // MARK: - Focus Box

    private var focusBox: some View {
        Rectangle()
            .stroke(appState.focusLocked ? .cyan : champagneGold, lineWidth: 1.5)
            .frame(width: 80, height: 80)
            .overlay(
                Rectangle()
                    .stroke(appState.focusLocked ? .cyan : champagneGold, lineWidth: 1)
                    .frame(width: 90, height: 90)
                    .opacity(0.3)
            )
    }

    private var lockBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text("AE/AF锁定")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.cyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.7)))
    }

    // MARK: - Gestures

    private func handleTap(at point: CGPoint, in size: CGSize) {
        focusPoint = point
        showFocusBox = true
        boxScale = 0.8
        withAnimation(.easeOut(duration: 0.2)) { boxScale = 1.0 }

        // Focus-at-interest expects a normalized point (0...1).
        let normalized = CGPoint(
            x: min(max(point.x / max(size.width, 1), 0), 1),
            y: min(max(point.y / max(size.height, 1), 0), 1)
        )
        FocusExposureController.shared.focus(at: normalized)

        // Auto-hide focus box after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showFocusBox = false }
        }
    }

    private func handleLongPress() {
        appState.focusLocked = true
        appState.exposureLocked = true
        lockIndicatorShown = true
        FocusExposureController.shared.lockAEAF()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { lockIndicatorShown = false }
        }
    }

    private func handleDoubleTap() {
        let newZoom = appState.currentZoomFactor > 2 ? 1.0 : 2.0
        appState.setZoom(newZoom, source: .optical)
        cameraManager.setZoomFactor(CGFloat(newZoom))
    }
}

#Preview {
    FocusGestureView(focusPoint: .constant(nil), showFocusBox: .constant(false))
        .environmentObject(AppState.shared)
}
