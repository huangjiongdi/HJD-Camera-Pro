import SwiftUI
import UIKit

// MARK: - 对焦手势层（点击对焦 / 长按锁定）

struct FocusGestureView: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let long = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        long.minimumPressDuration = 0.5
        let double = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.double(_:)))
        double.numberOfTapsRequired = 2
        tap.require(toFail: double)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(long)
        view.addGestureRecognizer(double)
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        return view
    }

    func updateUIView(_ uiView: GestureView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onTap: ((CGPoint) -> Void)?
        var onLongPress: ((CGPoint) -> Void)?

        @objc func tap(_ g: UITapGestureRecognizer) {
            onTap?(g.location(in: g.view))
        }
        @objc func double(_ g: UITapGestureRecognizer) {
            // 双击可放大（此处简单对焦）
            onTap?(g.location(in: g.view))
        }
        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            onLongPress?(g.location(in: g.view))
        }
    }

    final class GestureView: UIView {}
}

// MARK: - 对焦框（黄色）

struct FocusSquare: View {
    let point: CGPoint
    var locked: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(locked ? Color.yellow : Color.yellow, lineWidth: 1.5)
            .frame(width: 70, height: 70)
            .position(point)
    }
}
