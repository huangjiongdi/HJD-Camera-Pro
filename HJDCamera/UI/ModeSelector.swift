//
//  ModeSelector.swift
//  HJD Camera Pro
//
//  Bottom mode selector. Shows 6 core modes by default; "更多" or swipe reveals
//  pro / macro / time-lapse / burst / multi-exposure / panorama.
//

import SwiftUI

struct ModeSelector: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hapticEngine: HapticEngine
    @State private var showMore = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(spacing: 6) {
            // Core modes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(appState.currentMode.coreModes) { mode in
                        modeButton(mode)
                    }

                    // More toggle
                    Button {
                        withAnimation { showMore.toggle() }
                        hapticEngine.selectionChanged()
                    } label: {
                        Image(systemName: showMore ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
            }

            // More modes panel
            if showMore {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(appState.currentMode.moreModes) { mode in
                            modeButton(mode)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let isSelected = appState.currentMode == mode
        return Button {
            appState.setMode(mode)
            hapticEngine.selectionChanged()
        } label: {
            Text(mode.rawValue)
                .font(.system(size: isSelected ? 15 : 13, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? champagneGold : .white.opacity(0.65))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModeSelector()
        .environmentObject(AppState.shared)
}
