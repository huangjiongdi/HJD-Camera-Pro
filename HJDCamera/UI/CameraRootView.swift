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
    /// 上次拍照闪退的原因横幅（ShutterTrace 启动时从诊断日志读取）。
    @State private var crashBanner: String? = ShutterTrace.lastCrashReport
    @State private var crashDismissed = false

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

                    // 实时识别/镜头信息胶囊：独立一行，不再与闪光/RAW 重叠。
                    LiveVisionChipsBar()
                        .environmentObject(appState)
                        .environmentObject(cameraManager)

                    // 上次拍照闪退的原因横幅（安全区内、灵动岛下方）。
                    if !crashDismissed, let crash = crashBanner {
                        crashBannerView(crash)
                    }

                    Spacer(minLength: 12)

                    // 极影式 Pro 轮盘（仅 Pro 模式）：P/S/A/M + 对焦/ISO/快门/EV/WB。
                    if appState.currentMode == .pro {
                        ProModeDock()
                            .environmentObject(appState)
                            .environmentObject(hapticEngine)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }

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
                .onEnded { value in
                    // 上滑打开 Pro 面板；面板打开时下滑收回。
                    if value.translation.height < -40 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.showProControls = true
                        }
                        hapticEngine.trigger(.focus, type: .light)
                    } else if value.translation.height > 60 && appState.showProControls {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.showProControls = false
                        }
                        hapticEngine.trigger(.focus, type: .light)
                    }
                }
        )
        .onAppear {
            // 拍照成功后 ShutterTrace 会清空；回到相机界面时同步刷新。
            crashBanner = ShutterTrace.lastCrashReport
            if crashBanner == nil { crashDismissed = true }
        }
        .onChange(of: appState.currentMode) { _, mode in
            // 离开 Pro 模式：所有手动参数恢复自动，避免影响其它模式。
            if mode != .pro && appState.exposureMode != .auto {
                appState.exposureMode = .auto
                appState.proSettings.iso = 100
                appState.proSettings.shutterSpeed = 1.0 / 125
                appState.proSettings.evCompensation = 0
                appState.proSettings.whiteBalance = 0
                appState.proSettings.manualFocusDistance = -1
                ProManualEngine.reset()
            }
        }
    }

    // MARK: - 闪退原因横幅
    @ViewBuilder
    private func crashBannerView(_ crash: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("上次拍照闪退，原因已记录")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        crashDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Text(crash)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(10)
            Text("完整步骤：设置 → 关于 → 诊断日志")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.55, green: 0.1, blue: 0.1).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(champagneGold.opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

#Preview {
    CameraRootView()
        .environmentObject(AppState.shared)
}
