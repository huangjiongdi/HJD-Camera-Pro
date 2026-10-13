//
//  LogWheelView.swift
//  HJD Camera Pro
//
//  极影式横向轮盘：对数刻度、连续跟手（不吸附整数）、中央固定指针、
//  刻度标签、刻度触觉、松手吸附附近档位。用于变焦与 Pro 参数（ISO/快门/
//  EV/白平衡/对焦）。
//

import SwiftUI

struct LogWheelView: View {
    /// 连续值（拖动中实时更新）。
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// 刻度与吸附点（必须在 range 内、按递增顺序）。
    let stops: [Double]
    /// 刻度显示文案。
    let label: (Double) -> String
    /// 拖动中每帧回调（如下发 setZoomFactor）。
    var onChange: ((Double) -> Void)?
    /// 松手回调（如吸附后飞变焦）。
    var onCommit: ((Double) -> Void)?
    /// 对数映射：true 用对数（变焦/ISO/快门），false 线性（EV/对焦）。
    var logarithmic: Bool = true
    /// 触觉回调（跨过刻度时）。
    var haptic: (() -> Void)?

    @State private var dragStartValue: Double = 0
    @State private var dragStartX: CGFloat = 0
    @State private var lastHapticStopIndex: Int = -2
    @State private var dragging = false

    private let gold = Color(red: 0.85, green: 0.75, blue: 0.55)

    // MARK: - 映射

    private func norm(_ v: Double) -> Double {
        if logarithmic {
            let lo = log(range.lowerBound), hi = log(range.upperBound)
            return (log(min(max(v, range.lowerBound), range.upperBound)) - lo) / (hi - lo)
        } else {
            return (v - range.lowerBound) / (range.upperBound - range.lowerBound)
        }
    }

    private func denorm(_ f: Double) -> Double {
        let f = min(max(f, 0), 1)
        if logarithmic {
            let lo = log(range.lowerBound), hi = log(range.upperBound)
            return exp(lo + f * (hi - lo))
        } else {
            return range.lowerBound + f * (range.upperBound - range.lowerBound)
        }
    }

    private func nearestStop(_ v: Double) -> Double {
        stops.min(by: { abs($0 - v) < abs($1 - v) }) ?? v
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // 轨道
                Capsule().fill(Color.black.opacity(0.45)).frame(height: 5)
                // 刻度
                ticks(width: w)
                // 中央固定指针
                Rectangle()
                    .fill(gold)
                    .frame(width: 2, height: 26)
                    .position(x: w / 2, y: geo.size.height / 2)
                    .allowsHitTesting(false)
                // 数值游标条（中央指针两侧的高亮段，跟随当前值）
                Capsule().fill(gold.opacity(0.8))
                    .frame(width: 3, height: 22)
                    .position(x: w * CGFloat(norm(value)), y: geo.size.height / 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            dragStartValue = value
                            dragStartX = g.startLocation.x
                        }
                        // 轮盘像素行程覆盖整个量程；1 屏宽 = 全量程，
                        // 拖动越多变化越大，跟手连续，无整数跳变。
                        let dx = g.translation.width
                        let f0 = norm(dragStartValue)
                        let f = min(max(f0 + Double(dx / w), 0), 1)
                        let v = denorm(f)
                        value = v
                        onChange?(v)
                        // 跨过吸附刻度时给触觉。
                        let idx = stops.indices.min(by: {
                            abs(stops[$0] - v) < abs(stops[$1] - v)
                        }) ?? 0
                        if idx != lastHapticStopIndex {
                            lastHapticStopIndex = idx
                            haptic?()
                        }
                    }
                    .onEnded { g in
                        let dx = g.translation.width
                        let f = min(max(norm(dragStartValue) + Double(dx / w), 0), 1)
                        let raw = denorm(f)
                        let snapped = nearestStop(raw)
                        withAnimation(.easeOut(duration: 0.18)) {
                            value = snapped
                        }
                        onCommit?(snapped)
                        dragging = false
                        lastHapticStopIndex = -2
                    }
            )
        }
        .frame(height: 34)
    }

    // MARK: - 刻度

    @ViewBuilder
    private func ticks(width w: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, s in
                let f = CGFloat(norm(s))
                let near = abs(s - value) <= tickTolerance(s)
                Rectangle()
                    .fill(near ? gold : Color.white.opacity(0.45))
                    .frame(width: 1.5, height: near ? 16 : 10)
                    .position(x: w * f, y: 17)
                Text(label(s))
                    .font(.system(size: 9, weight: near ? .bold : .regular))
                    .foregroundColor(near ? gold : .white.opacity(0.6))
                    .position(x: w * f, y: 30)
            }
        }
    }

    private func tickTolerance(_ s: Double) -> Double {
        // 对数刻度用相对误差，线性格用绝对误差。
        if logarithmic, s > 0 { return s * 0.06 }
        return (range.upperBound - range.lowerBound) * 0.03
    }
}
