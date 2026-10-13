//
//  RootView.swift
//  HJD Camera Pro
//
//  Root container that switches between Camera / Gallery / AI Studio / Settings
//  based on AppState navigation flags. Full-screen, status bar hidden.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Camera is the always-present base layer
            CameraRootView()
                .environmentObject(appState)

            // Gallery overlay
            if appState.showGallery {
                GalleryView()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }

            // AI Studio overlay
            if appState.showAIStudio {
                AIStudioView()
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            // Settings overlay
            if appState.showSettings {
                SettingsRootView()
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: appState.showGallery)
        .animation(.easeInOut(duration: 0.25), value: appState.showAIStudio)
        .animation(.easeInOut(duration: 0.25), value: appState.showSettings)
    }
}

#Preview {
    RootView()
        .environmentObject(AppState.shared)
}
