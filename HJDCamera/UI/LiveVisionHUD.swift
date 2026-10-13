//
//  LiveVisionHUD.swift
//  HJD Camera Pro
//
//  实时识别叠加层：在取景框上绘制主体识别框、标签，以及场景/镜头信息胶囊。
//  识别框坐标来自 Vision（归一化、左下原点），这里转换为 SwiftUI（左上原点）。
//

import SwiftUI

struct LiveVisionHUD: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var cameraManager: CameraManager

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        ZStack {
            // 识别框：铺满整个屏幕（含安全区），不随顶部胶囊避让。
            GeometryReader { proxy in
                if appState.aiPreviewLevel != .off && !appState.isRecording {
                    boxesLayer(in: proxy.size)
                }
            }
            .ignoresSafeArea()

            // 顶部信息胶囊（场景 + 实际镜头）：不忽略安全区，
            // 永远落在灵动岛下方，不再被遮挡。
            if appState.aiPreviewLevel != .off {
                VStack {
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
                    .padding(.top, 10)
                    .allowsHitTesting(false)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 识别框

    private func boxesLayer(in size: CGSize) -> some View {
        ZStack {
            ForEach(appState.liveSubjects) { subject in
                let rect = swiftRect(subject.boundingBox, in: size)
                Rectangle()
                    .stroke(color(for: subject.kind), lineWidth: 1.6)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .topLeading) {
                        Text(subject.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color(for: subject.kind))
                            .offset(y: -18)
                    }
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func swiftRect(_ box: CGRect, in size: CGSize) -> CGRect {
        // Vision 左下原点 → SwiftUI 左上原点。
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }

    private func color(for kind: LiveSubjectKind) -> Color {
        switch kind {
        case .face, .person: return Color(red: 0.35, green: 0.95, blue: 0.55)
        case .animal:       return Color(red: 1.0, green: 0.72, blue: 0.25)
        case .vehicle:      return Color(red: 0.4, green: 0.75, blue: 1.0)
        case .plant:        return Color(red: 0.55, green: 0.9, blue: 0.4)
        case .text:         return Color(red: 1.0, green: 0.9, blue: 0.3)
        case .object:       return Color.white.opacity(0.85)
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
