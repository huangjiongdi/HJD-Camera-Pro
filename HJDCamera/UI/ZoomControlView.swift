//
//  ZoomControlView.swift
//  HJD Camera Pro
//
//  极影式变焦（r10 对齐）：
//    · 主倍率行 0.5× / 1× / 2× / 5×（16 Pro Max 四颗镜头），点击直接
//      非线性飞变焦；最后一个“轮盘”按钮一键展开半轮盘（长按主行也可）。
//    · 半轮盘展开：上方一排高倍快捷档 10/20/50/100/200/300/400/500，
//      下方 0.5×–500× 半圆弧轮盘，手指沿弧线滑动，角度 → 对数变焦，
//      连续跟手、跨刻度震动、过硬件档位加强震动、松手吸附最近档位。
//    · 照片 / 视频 / 实况 / 录像中都可用，所有倍率切换走 flyZoom
//      （CADisplayLink 逐帧），跨硬件镜头切换点不跳变。
//

import SwiftUI
import Combine

struct ZoomControlView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var hapticEngine: HapticEngine

    @State private var showWheel = false

    /// 顶部固定倍率：16 Pro Max 四颗镜头（0.5 超广角 / 1 主摄 / 2 48mm / 5 长焦）。
    private let mainStops: [CGFloat] = [0.5, 1, 2, 5]
    /// 半轮盘上方的高倍快捷档。
    private let highStops: [CGFloat] = [10, 20, 50, 100, 200, 300, 400, 500]

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        VStack(spacing: 10) {
            if appState.zoomConfidence != .high {
                confidenceHint
            }

            mainZoomRow

            if showWheel {
                wheelPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.35) {
            hapticEngine.selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) {
                showWheel = true
                appState.showExtremeZoomPanel = true
            }
        }
    }

    // MARK: 主倍率行

    private var mainZoomRow: some View {
        HStack(spacing: 8) {
            ForEach(mainStops, id: \.self) { factor in
                zoomButton(factor: factor)
            }
            // 半轮盘开关：极影式转盘入口。
            Button {
                hapticEngine.selectionChanged()
                withAnimation(.easeInOut(duration: 0.22)) {
                    showWheel.toggle()
                    appState.showExtremeZoomPanel = showWheel
                }
            } label: {
                Image(systemName: showWheel ? "chevron.down" : "circle.dashed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(showWheel ? .black : champagneGold)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(showWheel ? champagneGold : Color.black.opacity(0.35))
                    )
                    .overlay(
                        Circle().stroke(champagneGold.opacity(showWheel ? 0 : 0.5), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: 半轮盘面板

    private var wheelPanel: some View {
        VStack(spacing: 4) {
            // 高倍快捷档（横滑）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(highStops, id: \.self) { factor in
                        zoomButton(factor: factor, compact: true)
                    }
                }
                .padding(.horizontal, 2)
            }
            FineZoomRuler()
                .environmentObject(cameraManager)
                .environmentObject(hapticEngine)
        }
    }

    // MARK: 单个倍率按钮（点击丝滑飞变焦）

    private func zoomButton(factor: CGFloat, compact: Bool = false) -> some View {
        let isActive = abs(cameraManager.currentZoomFactor - factor) < 0.05
        return Button {
            hapticEngine.selectionChanged()
            let distance = abs(cameraManager.currentZoomFactor - factor)
            let duration = min(0.32 + Double(distance) * 0.0009, 0.62)
            cameraManager.flyZoom(to: factor, duration: CGFloat(duration))
        } label: {
            Text(factor == 0.5 ? "0.5×" : "\(Int(factor))×")
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: compact ? 44 : 48, height: 36)
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

    // MARK: 置信度提示

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
                Text("半轮盘 · 沿弧滑动 · 0.5–500×")
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
                haptic: { hapticEngine.selectionChanged() },
                stopHaptic: {
                    hapticEngine.trigger(.zoomNode, type: .light)
                }
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
