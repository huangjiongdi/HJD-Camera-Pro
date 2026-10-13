//
//  SemiWheelView.swift
//  HJD Camera Pro
//
//  极影式半轮盘变焦控件：
//    底部上凸半圆，手指沿弧线滑动，角度 → 对数变焦。
//    连续跟手、跨刻度震动、松手吸附最近档位；
//    照片 / 视频 / 实况模式通用（onChange 直接下发 setZoomFactor，
//    硬件档位由 CameraManager 负责切换，超出部分数字裁切）。
//

import SwiftUI

struct SemiWheelView: View {
    /// 显示变焦（0.5…500）。
    @Binding var value: Double
    let range: ClosedRange<Double>
    let stops: [Double]
    let label: (Double) -> String
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void
    var haptic: (() -> Void)?

    /// 半轮盘覆盖的圆心角（弧度），左右各 maxAngle。
    private let maxAngle: Double = .pi * 0.78   // 约 140°
    private let gold = Color(red: 0.85, green: 0.75, blue: 0.55)

    @State private var dragAngle: Double?      // 手指当前相对圆心的角（弧度）
    @State private var lastTickIndex: Int = -999

    // 对数映射，和 LogWheelView 保持一致：0.5…500 一盘走完。
    private var logMin: Double { Foundation.log(range.lowerBound) }
    private var logMax: Double { Foundation.log(range.upperBound) }
    private var span: Double { max(logMax - logMin, 0.0001) }

    private func angle(for zoom: Double) -> Double {
        let t = (Foundation.log(min(max(zoom, range.lowerBound), range.upperBound)) - logMin) / span
        return -maxAngle + t * 2 * maxAngle
    }
    private func zoom(for angle: Double) -> Double {
        let a = min(max(angle, -maxAngle), maxAngle)
        let t = (a + maxAngle) / (2 * maxAngle)
        return Foundation.exp(logMin + t * span)
    }
    private var currentAngle: Double { angle(for: value) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // 圆心放在底边中点，半径按高度取（弧在上半圆）。
            let radius = min(h - 24, w / 2 - 18)
            let center = CGPoint(x: w / 2, y: h - 6)

            ZStack {
                // 弧轨
                ArcTrack(center: center, radius: radius,
                         start: -maxAngle, end: maxAngle)
                    .stroke(Color.white.opacity(0.22), lineWidth: 5)

                // 刻度
                ForEach(Array(stopTicks.enumerated()), id: \.offset) { _, tick in
                    let a = angle(for: tick)
                    let p1 = point(center: center, radius: radius - 9, angle: a)
                    let p2 = point(center: center, radius: radius + 7, angle: a)
                    Path { p in p.move(to: p1); p.addLine(to: p2) }
                        .stroke(tick <= 5 ? gold : Color.white.opacity(0.4),
                                lineWidth: tick <= 5 ? 2 : 1.2)
                    if isLabeledStop(tick) {
                        let lp = point(center: center, radius: radius + 22, angle: a)
                        Text(label(tick))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(tick <= 5 ? gold : .white.opacity(0.55))
                            .position(lp)
                    }
                }

                // 跟手指针（当前变焦）
                let pa = dragAngle ?? currentAngle
                let pp = point(center: center, radius: radius, angle: pa)
                Circle()
                    .fill(gold)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 2))
                    .overlay(
                        Text(currentZoomText)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.black)
                    )
                    .position(pp)
                    .shadow(color: gold.opacity(0.7), radius: 6)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let a = angleAt(g.location, center: center)
                        dragAngle = min(max(a, -maxAngle), maxAngle)
                        let z = zoom(for: dragAngle!)
                        tickHaptic(for: z)
                        onChange(z)
                    }
                    .onEnded { g in
                        let a = angleAt(g.location, center: center)
                        let z = zoom(for: min(max(a, -maxAngle), maxAngle))
                        let snapped = nearestStop(to: z)
                        dragAngle = nil
                        lastTickIndex = -999
                        onCommit(snapped)
                    }
            )
        }
        .frame(height: 92)
    }

    // 均匀刻度（几何上按对数等角分布，所以按角度均匀取点）。
    private var stopTicks: [Double] {
        let count = 27
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return Foundation.exp(logMin + t * span)
        }
    }

    private func isLabeledStop(_ v: Double) -> Bool {
        let labels: [Double] = [0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500]
        return labels.contains { abs($0 - v) / max($0, 0.001) < 0.03 }
    }

    private var currentZoomText: String {
        let z = value
        if z < 1 { return String(format: "%.1f", z) }
        return "\(Int(z.rounded()))"
    }

    private func nearestStop(to z: Double) -> Double {
        stops.min(by: { abs($0 - z) < abs($1 - z) }) ?? z
    }

    private func tickHaptic(for z: Double) {
        // 跨过对数刻度索引时震动一次。
        let idx = Int((Foundation.log(min(max(z, range.lowerBound), range.upperBound)) - logMin)
                      / span * 26)
        if idx != lastTickIndex {
            lastTickIndex = idx
            haptic?()
        }
    }

    /// 触点相对圆心的角度（上半圆，0=正上方，左负右正）。
    private func angleAt(_ p: CGPoint, center: CGPoint) -> Double {
        let dx = p.x - center.x
        let dy = center.y - p.y        // 上为正
        var a = atan2(dx, dy)
        a = min(max(a, -maxAngle), maxAngle)
        return a
    }

    private func point(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * Foundation.sin(angle),
                y: center.y - radius * Foundation.cos(angle))
    }
}

/// 半圆弧 Path。
private struct ArcTrack: Shape {
    let center: CGPoint
    let radius: Double
    let start: Double      // 弧度
    let end: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 72
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = start + (end - start) * t
            let x = center.x + radius * Foundation.sin(a)
            let y = center.y - radius * Foundation.cos(a)
            let q = CGPoint(x: x, y: y)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }
}
