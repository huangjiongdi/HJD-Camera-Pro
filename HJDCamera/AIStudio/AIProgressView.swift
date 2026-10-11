//
//  AIProgressView.swift
//  HJD Camera Pro
//
//  Processing progress overlay: progress bar, cancel button, estimated
//  remaining time, current step description.
//

import SwiftUI

struct AIProgressView: View {
    @EnvironmentObject var aiProcessingQueue: AIProcessingQueue
    @Environment(\.dismiss) private var dismiss

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated icon
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: aiProcessingQueue.currentProgress)
                        .stroke(champagneGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundColor(champagneGold)
                }

                // Status text
                VStack(spacing: 8) {
                    Text(aiProcessingQueue.currentStep)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(Int(aiProcessingQueue.currentProgress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(champagneGold)
                }

                // Progress bar
                ProgressView(value: aiProcessingQueue.currentProgress)
                    .tint(champagneGold)
                    .frame(width: 240)

                // Estimated time
                if let remaining = aiProcessingQueue.estimatedRemaining {
                    Text("预计剩余 \(formatTime(remaining))")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }

                // Cancel button
                Button {
                    aiProcessingQueue.cancelCurrent()
                } label: {
                    Text("取消")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)秒" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    AIProgressView()
}
