//
//  LiveVisionChipsBar.swift
//  HJD Camera Pro
//
//  从 LiveVisionHUD 拆出的顶部信息胶囊：左=内容识别（实时场景），
//  右=实际镜头/焦距。放在 CameraRootView 的安全区 VStack 中、
//  TopStatusBar 下方独立一行，不再与闪光/RAW 按钮重叠。
//

import SwiftUI

struct LiveVisionChipsBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        if appState.aiPreviewLevel != .off {
            HStack(spacing: 8) {
                chip(systemName: "eye.fill",
                     text: appState.liveSceneLabel.isEmpty ? "实时识别中" : appState.liveSceneLabel,
                     darkText: true, fill: champagneGold)
                Spacer()
                chip(systemName: "camera.aperture",
                     text: "\(cameraManager.activeLensLabel) · \(cameraManager.activeFocalText)",
                     darkText: false, fill: Color.black.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .allowsHitTesting(false)
        }
    }

    private func chip(systemName: String, text: String, darkText: Bool, fill: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(darkText ? .black : .white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(fill))
    }
}
