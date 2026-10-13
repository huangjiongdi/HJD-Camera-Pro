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
        GeometryReader { _ in
            ZStack {
                // Full-bleed live preview (background layer). 仅预览层与识别框
                // 忽略安全区，控制层一律保留在安全区内，灵动岛永不遮挡。
                CameraPreviewContainer()
                    .environmentObject(appState)
                    .environmentObject(cameraManager)
                    .environmentObject(settingsStore)
                    .ignoresSafeArea()

                // Live Vision AI overlay: recognition boxes + scene/lens chips.
                // 识别框全屏铺满；顶部信息胶囊内部保证落在安全区内。
                LiveVisionHUD()
                    .environmentObject(appState)
                    .environmentObject(cameraManager)

                // Foreground UI：整个控制容器不忽略安全区，由 SwiftUI 自动
                // 把它限制在灵动岛下方、Home 指示条上方，不再依赖手动
                // safeAreaInsets（旧写法在整体 ignoresSafeArea 后 inset 恒为 0，
                // 导致灵动岛再次挡住顶部按钮）。
                VStack(spacing: 0) {
                    TopStatusBar()
                        .environmentObject(appState)
                        .environmentObject(settingsStore)
                        .padding(.top, 6)

                    Spacer(minLength: 12)

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
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 0)

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
        }
        // 根容器不调用 .ignoresSafeArea()：让 SwiftUI 为控制层自动避让
        // 灵动岛与 Home 指示条；全屏元素各自忽略安全区。
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
