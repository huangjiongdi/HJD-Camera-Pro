import SwiftUI

// MARK: - 底部模式选择器

struct ModeSelector: View {
    @Binding var mode: ShootingMode
    @State private var showMore = false
    var onSelect: (ShootingMode) -> Void

    private let coreModes: [ShootingMode] = [
        .photo, .portrait, .video, .sloMo, .night, .moon
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(coreModes) { m in
                    chip(m)
                }
                // 更多（打开其他模式，而非设置）
                Menu {
                    ForEach(ShootingMode.allCases.filter {
                        !coreModes.contains($0)
                    }) { m in
                        Button(m.rawValue) { select(m) }
                    }
                } label: {
                    Text("更多")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
    }

    private func chip(_ m: ShootingMode) -> some View {
        let selected = m == mode
        return Button(action: { select(m) }) {
            Text(m.rawValue)
                .font(.system(size: 15, weight: selected ? .bold : .medium))
                .foregroundColor(selected ? .black : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(
                    selected ? Color.yellow : Color.white.opacity(0.18)))
        }
    }

    private func select(_ m: ShootingMode) {
        withAnimation(.easeInOut(duration: 0.15)) { mode = m }
        onSelect(m)
    }
}
