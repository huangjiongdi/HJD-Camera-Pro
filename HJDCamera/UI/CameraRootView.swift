//
//  CameraRootView.swift
//  HJD Camera Pro
//
//  Main camera container: top status bar + center preview + zoom control
//  + bottom mode selector + shutter bar + pull-up professional panel.
//

import SwiftUI

struct CameraRootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var hapticEngine: HapticEngine

    @State private var showExtremeZoom = false
    @State private var dragOffset: CGFloat = 0

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top status bar
                TopStatusBar()
                    .environmentObject(appState)
                    .environmentObject(settingsStore)

                Spacer(minLength: 0)

                // Center preview area
                CameraPreviewContainer()
                    .environmentObject(appState)
                    .environmentObject(cameraManager)
                    .environmentObject(settingsStore)
                    .cornerRadius(12)
                    .padding(.horizontal, 12)

                Spacer(minLength: 0)

                // Zoom control
                ZoomControlView()
                    .environmentObject(appState)
                    .environmentObject(cameraManager)
                    .environmentObject(hapticEngine)
                    .padding(.bottom, 8)

                // Mode selector
                ModeSelector()
                    .environmentObject(appState)
                    .environmentObject(hapticEngine)
                    .padding(.bottom, 12)

                // Shutter bar
                ShutterBar()
                    .environmentObject(appState)
                    .environmentObject(cameraManager)
                    .environmentObject(hapticEngine)
                    .padding(.bottom, 24)
            }

            // Pull-up professional control panel
            if appState.showProControls {
                ProControlPanel()
                    .environmentObject(appState)
                    .environmentObject(settingsStore)
                    .environmentObject(hapticEngine)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < -30 {
                        appState.showProControls = true
                    }
                }
        )
    }
}

#Preview {
    CameraRootView()
        .environmentObject(AppState.shared)
}
