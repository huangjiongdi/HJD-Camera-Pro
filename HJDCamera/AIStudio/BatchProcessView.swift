//
//  BatchProcessView.swift
//  HJD Camera Pro
//
//  Batch AI processing: select multiple photos, choose task type, quality
//  level, output scale, then process sequentially with overall progress.
//

import SwiftUI
import PhotosUI

struct BatchProcessView: View {
    @EnvironmentObject var aiProcessingQueue: AIProcessingQueue
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var taskType: AITaskType = .superResolution
    @State private var qualityLevel: AIQualityLevel = .balanced
    @State private var outputScale: Double = 2.0
    @State private var isProcessing = false
    @State private var completedCount = 0

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Photo picker
                    pickerSection

                    // Selected count
                    if !selectedItems.isEmpty {
                        selectedInfo
                    }

                    // Task type
                    taskSection

                    // Quality + scale
                    if !selectedItems.isEmpty {
                        settingsSection
                    }

                    // Process button
                    if !selectedItems.isEmpty && !isProcessing {
                        processButton
                    }

                    // Processing progress
                    if isProcessing {
                        processingSection
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("批量处理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Picker

    private var pickerSection: some View {
        PhotosPicker(selection: $selectedItems, maxSelectionCount: 20, matching: .images) {
            HStack {
                Image(systemName: "photo.stack")
                    .font(.system(size: 24))
                Text(selectedItems.isEmpty ? "选择多张图片" : "已选 \(selectedItems.count) 张")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(champagneGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(champagneGold.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [8]))
            )
        }
    }

    private var selectedInfo: some View {
        HStack {
            Text("已选择 \(selectedItems.count) 张图片")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Button("清空") { selectedItems.removeAll() }
                .font(.system(size: 13))
                .foregroundColor(.red)
        }
    }

    // MARK: - Task Type

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("处理类型")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                ForEach([AITaskType.superResolution, .denoise, .nightRestore, .portraitOptimize, .lunarEnhance, .architectureEnhance], id: \.rawValue) { task in
                    let selected = taskType == task
                    Button {
                        taskType = task
                    } label: {
                        Text(task.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(selected ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(spacing: 12) {
            // Quality
            VStack(alignment: .leading, spacing: 6) {
                Text("增强强度")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                HStack(spacing: 10) {
                    ForEach([AIQualityLevel.natural, .balanced, .strong], id: \.rawValue) { level in
                        let selected = qualityLevel == level
                        Button { qualityLevel = level } label: {
                            Text(level.rawValue)
                                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                .foregroundColor(selected ? .black : .white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Scale
            VStack(alignment: .leading, spacing: 6) {
                Text("输出倍率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                HStack(spacing: 10) {
                    ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { scale in
                        let selected = outputScale == scale
                        Button { outputScale = scale } label: {
                            Text("\(Int(scale))×")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(selected ? champagneGold : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Process

    private var processButton: some View {
        Button {
            startBatch()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("开始批量处理 (\(selectedItems.count)张)")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(champagneGold))
        }
    }

    private var processingSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(completedCount) / Double(selectedItems.count))
                .tint(champagneGold)
            Text("已完成 \(completedCount) / \(selectedItems.count)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            Button {
                aiProcessingQueue.cancelBatch()
                isProcessing = false
            } label: {
                Text("取消批量处理")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func startBatch() {
        isProcessing = true
        completedCount = 0
        // Simulate sequential processing
        for i in 0..<selectedItems.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i + 1) * 2.0) {
                completedCount = i + 1
                if completedCount == selectedItems.count {
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        BatchProcessView()
    }
}
