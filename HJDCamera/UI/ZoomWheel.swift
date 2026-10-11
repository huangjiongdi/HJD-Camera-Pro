import SwiftUI
import CoreImage

// MARK: - 变焦半圆轮盘

struct ZoomWheel: View {
    @Binding var factor: CGFloat
    let isMacro: Bool
    var onCommit: (CGFloat) -> Void

    private let stops = NonlinearZoom.stops

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 半圆刻度弧（轻微弧形）
                arcPath(w: w, h: h)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                    .foregroundColor(.white.opacity(0.25))

                // 档位标签（沿弧分布）
                ForEach(stops, id: \.self) { stop in
                    let pos = CGFloat(NonlinearZoom.position(for: stop))
                    let x = 16 + pos * (w - 32)
                    let arc = arcOffset(pos)
                    Text(label(stop))
                        .font(.system(size: 13, weight: stop == factor ? .bold : .medium))
                        .foregroundColor(stop == factor ? .black : .white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(
                            Capsule().fill(stop == factor
                                           ? Color.yellow
                                           : Color.white.opacity(0.18)))
                        .position(x: x, y: h * 0.42 - arc)
                        .onTapGesture { commit(stop) }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(w: w))
        }
        .frame(height: 46)
    }

    // 拖动（非线性映射）
    private func dragGesture(w: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { v in
                let pos = max(0, min(1, (v.location.x - 16) / (w - 32)))
                let f = NonlinearZoom.factor(for: CGFloat(pos))
                factor = f
            }
            .onEnded { v in
                let pos = max(0, min(1, (v.location.x - 16) / (w - 32)))
                let f = NonlinearZoom.factor(for: CGFloat(pos))
                let snapped = NonlinearZoom.nearestStop(to: f)
                commit(snapped)
            }
    }

    private func commit(_ f: CGFloat) {
        let snapped = NonlinearZoom.nearestStop(to: f)
        factor = snapped
        onCommit(snapped)
        HapticEngine.shared.play(.zoomStep)
    }

    private func label(_ s: CGFloat) -> String {
        let n = s == floor(s) ? String(Int(s)) : String(format: "%.1f", s)
        return n + "×"
    }

    private func arcOffset(_ pos: CGFloat) -> CGFloat {
        // 中间档位略微上拱（半圆感）
        let x = pos - 0.5
        return -10 * (1 - 4 * x * x)
    }

    private func arcPath(w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 16, y: h*0.5))
            p.addQuadCurve(to: CGPoint(x: w-16, y: h*0.5),
                           control: CGPoint(x: w/2, y: h*0.1))
        }
    }
}

// MARK: - 微距花按钮（左下）

struct MacroFlowerButton: View {
    @Binding var enabled: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: {
            enabled.toggle(); onToggle()
        }) {
            Image(systemName: "flower")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(enabled ? .black : .gray)
                .frame(width: 32, height: 32)
                .background(
                    ZStack {
                        Circle().fill(enabled ? Color.yellow :
                                        Color.black.opacity(0.45))
                        if !enabled {
                            // 斜杠表示关闭
                            Rectangle()
                                .fill(Color.gray)
                                .frame(width: 22, height: 2)
                                .rotationEffect(.degrees(-45))
                        }
                    })
        }
    }
}
