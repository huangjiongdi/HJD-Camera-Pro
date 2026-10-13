//
//  ZoomControlView.swift
//  HJD Camera Pro
//
//  第四轮精细变焦：
//    · 顶部固定：0.5× / 1× / 5× / 10× + 倒三角（没有 2×）。
//    · 点倒三角展开更多倍率：20× / 50× / 100× / 200× / 300× / 400× / 500×
//      （无 25，含 20、300），展开后把原倍率行往上顶。
//    · 更多倍率行下方出现一条“直直的”变焦条：最左 0.5、最右 500，
//      线性、每格步进 1×，倍率显示取整数、保留 0.5 起点。
//    · 无论面板是否展开，长按 0.35s 也可单独唤出这条 0.5×–500× 全范围变焦条。
//    · 所有倍率按钮都走非线性连续丝滑变焦（flyZoom，CADisplayLink 逐帧），
//      任意倍率切换（含 500×↔0.5×）全程超级丝滑；手指拖滑条则逐帧跟手。
//

import SwiftUI
import Combine

struct ZoomControlView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var hapticEngine: HapticEngine

    @State private var showFineSlider = false

    /// 顶部固定倍率：16 Pro Max 四颗镜头（0.5 超广角 / 1 主摄 / 2 48mm / 5 长焦）。
    private let mainStops: [CGFloat] = [0.5, 1, 2, 5]
    /// 倒三角展开的更多倍率（无 25，含 20、300）。
    private let moreStops: [CGFloat] = [20, 50, 100, 200, 300, 400, 500]

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(spacing: 10) {
            // 置信度提示（低置信度时提示数字/AI 变焦为算法估算）
            if appState.zoomConfidence != .high {
                confidenceHint
            }

            // 主倍率行（被“更多倍率”往上顶的就是这一行）
            mainZoomRow

            // 展开的更多倍率行：位于主行与变焦条之间
            if appState.showExtremeZoomPanel {
                moreZoomRow
            }

            // 直变焦条：展开面板或长按唤出时都出现；范围始终 0.5–500
            if appState.showExtremeZoomPanel || showFineSlider {
                FineZoomRuler()
                    .environmentObject(cameraManager)
                    .environmentObject(hapticEngine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onLongPressGesture(minimumDuration: 0.35) {
            hapticEngine.selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) {
                showFineSlider = true
            }

        }
    }

    // MARK: - 主倍率行

    private var mainZoomRow: some View {
        HStack(spacing: 8) {
            ForEach(mainStops, id: \.self) { factor in
                zoomButton(factor: factor)
            }
            // 倒三角：展开/收起更多倍率
            Button {
                hapticEngine.selectionChanged()
                withAnimation(.easeInOut(duration: 0.22)) {
                    appState.showExtremeZoomPanel.toggle()
                }
                if appState.showExtremeZoomPanel { showFineSlider = false }
            } label: {
                Image(systemName: appState.showExtremeZoomPanel
                      ? "chevron.down" : "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(appState.showExtremeZoomPanel ? .black : champagneGold)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(appState.showExtremeZoomPanel
                                  ? champagneGold
                                  : Color.black.opacity(0.35))
                    )
            }
        }
    }

    // MARK: - 更多倍率行（横滑）

    private var moreZoomRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moreStops, id: \.self) { factor in
                    zoomButton(factor: factor)
                }
            }
        }
    }

    // MARK: - 单个倍率按钮（点击丝滑飞变焦）

    private func zoomButton(factor: CGFloat) -> some View {
        let isActive = abs(cameraManager.currentZoomFactor - factor) < 0.05
        return Button {
            hapticEngine.selectionChanged()
            // 任意倍率切换都走非线性连续丝滑变焦，跨硬件上限/镜头切换点不跳变。
            let distance = abs(cameraManager.currentZoomFactor - factor)
            let duration = min(0.32 + Double(distance) * 0.0009, 0.62)
            cameraManager.flyZoom(to: factor, duration: CGFloat(duration))
        } label: {
            Text(factor == 0.5 ? "0.5×" : "\(Int(factor))×")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 48, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? champagneGold : Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(champagneGold.opacity(isActive ? 0.9 : 0.4), lineWidth: 1)
                )
        }
    }

    // MARK: - 置信度提示

    private var confidenceHint: some View {
        Text(appState.zoomConfidence == .low
             ? "低置信度：高倍数字裁切 / AI 重建为算法估算，非光学实拍细节"
             : "中置信度：混合变焦与 AI 增强，请尽量保持稳定")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.3), in: Capsule())
    }
}

// MARK: - 极影式变焦轮盘（0.5×–500×，对数刻度、连续跟手、松手吸附）

private struct FineZoomRuler: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var hapticEngine: HapticEngine

    private let stops: [Double] = [0.5, 1, 2, 3, 5, 10, 20, 50, 100, 200, 500]
    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private var zoomValue: Binding<Double> {
        Binding(
            get: { Double(min(max(cameraManager.currentZoomFactor, 0.5), 500)) },
            set: { _ in }
        )
    }

    private var currentZoomLabel: String {
        let v = cameraManager.currentZoomFactor
        if v < 0.97 { return "0.5×" }
        if abs(v - v.rounded()) < 0.08 { return "\(Int(v.rounded()))×" }
        return String(format: "%.1f×", v)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("半轮盘变焦 · 0.5–500×")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(currentZoomLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(champagneGold)
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)

            // 极影式半轮盘：沿弧线滑动，角度 → 对数变焦，连续跟手、
            // 松手吸附档位；照片/视频/实况通用，录像中可实时变。
            SemiWheelView(
                value: zoomValue,
                range: 0.5...500,
                stops: stops,
                label: { v in
                    if v < 1 { return "0.5" }
                    return "\(Int(v))"
                },
                onChange: { v in
                    cameraManager.setZoomFactor(CGFloat(v))
                },
                onCommit: { v in
                    cameraManager.flyZoom(to: CGFloat(v), duration: 0.18)
                },
                haptic: { hapticEngine.selectionChanged() }
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ZoomControlView()
        .environmentObject(AppState.shared)
        .environmentObject(CameraManager.shared)
        .environmentObject(HapticEngine.shared)
        .background(Color.gray)
}
