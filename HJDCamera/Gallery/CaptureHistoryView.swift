//
//  CaptureHistoryView.swift
//  HJD Camera Pro
//
//  Capture history with per-shot parameters: mode, lens, zoom, ISO, shutter,
//  EV, WB, AI model, LUT, timestamp.
//

import SwiftUI

struct CaptureHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var recipes: [CaptureRecipe] = []
    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        List {
            if recipes.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("暂无拍摄记录")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(recipes) { recipe in
                    recipeRow(recipe)
                }
            }
        }
        .navigationTitle("拍摄历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { loadHistory() }
    }

    private func recipeRow(_ recipe: CaptureRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(recipe.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(recipe.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Mode + lens
            HStack(spacing: 12) {
                tag(recipe.mode, color: champagneGold)
                tag(recipe.lens, color: .cyan.opacity(0.7))
                tag(String(format: "%.1f×", recipe.zoomFactor), color: .orange.opacity(0.7))
            }

            // Parameters
            HStack(spacing: 12) {
                param("ISO", value: recipe.iso > 0 ? "\(Int(recipe.iso))" : "自动")
                param("快门", value: formatShutter(recipe.shutterSpeed))
                param("EV", value: String(format: "%+.1f", recipe.ev))
                param("WB", value: "\(recipe.whiteBalance)K")
            }

            // AI + LUT
            if !recipe.modelName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(champagneGold)
                    Text(recipe.modelName)
                        .font(.system(size: 11))
                        .foregroundColor(champagneGold)
                    if !recipe.lutName.isEmpty {
                        Text("· \(recipe.lutName)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func param(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func formatShutter(_ speed: Double) -> String {
        if speed <= 0 { return "自动" }
        if speed >= 1 { return String(format: "%.0fs", speed) }
        return String(format: "1/%.0f", 1.0/speed)
    }

    private func loadHistory() {
        // Load from persistent store; placeholder demo data
        recipes = [
            CaptureRecipe(
                id: UUID(), name: "月面特写", mode: "超级月亮", lens: "长焦",
                zoomFactor: 100, iso: 100, shutterSpeed: 0.005, ev: -0.5,
                whiteBalance: 5500, modelName: "LunarPro v2.1", lutName: "胶片5207",
                aiIntensity: 0.8, createdAt: Date().addingTimeInterval(-3600)
            )
        ]
    }
}

#Preview {
    NavigationStack {
        CaptureHistoryView()
            .environmentObject(AppState.shared)
    }
}
