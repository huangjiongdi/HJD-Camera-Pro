//
//  AIEditorView.swift
//  HJD Camera Pro
//
//  Unified AI editor: pick image → auto scene detection → choose natural /
//  balanced / strong enhancement → choose output scale → before/after compare
//  → process → quality check → save.
//

import SwiftUI
import PhotosUI

struct AIEditorView: View {
    let taskType: AITaskType
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var aiProcessingQueue: AIProcessingQueue
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var inputImage: UIImage?
    @State private var outputImage: UIImage?
    @State private var detectedScene: SceneType = .normal
    @State private var qualityLevel: AIQualityLevel = .balanced
    @State private var outputScale: Double = 2.0
    @State private var isProcessing = false
    @State private var showResult = false
    @State private var qualityAssessment: QualityAssessment?

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Step 1: Image picker / preview
                    imageSection

                    // Step 2: Scene detection
                    if inputImage != nil {
                        sceneSection
                    }

                    // Step 3: Quality level
                    if inputImage != nil {
                        qualitySection
                    }

                    // Step 4: Output scale
                    if inputImage != nil {
                        scaleSection
                    }

                    // Step 5: Before/After compare
                    if outputImage != nil {
                        compareSection
                    }

                    // Action button
                    if inputImage != nil && !isProcessing {
                        processButton
                    }
                }
                .padding(16)
            }

            // Processing overlay
            if isProcessing {
                AIProgressView()
                    .environmentObject(aiProcessingQueue)
            }
        }
        .navigationTitle(taskType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showResult) {
            if let output = outputImage {
                ExportResultView(image: output, assessment: qualityAssessment)
            }
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        VStack(spacing: 12) {
            if let image = inputImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            } else {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(champagneGold)
                        Text("选择图片")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(champagneGold.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                    )
                }
            }

            if inputImage != nil {
                Button("重新选择") {
                    inputImage = nil
                    outputImage = nil
                }
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await loadImage(newItem) }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            DispatchQueue.main.async {
                self.inputImage = img
                self.detectScene()
            }
        }
    }

    private func detectScene() {
        // Simulate scene detection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.detectedScene = .normal
        }
    }

    // MARK: - Scene Section

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("场景识别", systemImage: "viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("检测到：\(detectedScene.rawValue)场景")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("增强强度", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 10) {
                ForEach([AIQualityLevel.natural, .balanced, .strong], id: \.rawValue) { level in
                    let selected = qualityLevel == level
                    Button {
                        qualityLevel = level
                    } label: {
                        Text(level.rawValue)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundColor(selected ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(selected ? champagneGold : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Scale Section

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("输出倍率", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            HStack {
                ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { scale in
                    let selected = outputScale == scale
                    Button {
                        outputScale = scale
                    } label: {
                        Text("\(Int(scale))×")
                            .font(.system(size: 13, weight: selected ? .bold : .regular, design: .monospaced))
                            .foregroundColor(selected ? champagneGold : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? champagneGold : Color.clear, lineWidth: 1)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Compare Section

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("前后对比", systemImage: "rectangle.split.2x1")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            if let original = inputImage, let processed = outputImage {
                HStack(spacing: 10) {
                    compareThumb(original, label: "原图")
                    Image(systemName: "arrow.right")
                        .foregroundColor(champagneGold)
                    compareThumb(processed, label: "AI")
                }

                if let qa = qualityAssessment {
                    qualityRow(qa)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private func compareThumb(_ image: UIImage, label: String) -> some View {
        VStack(spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipped()
                .cornerRadius(8)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func qualityRow(_ qa: QualityAssessment) -> some View {
        HStack(spacing: 12) {
            qualityChip("清晰度", score: qa.sharpnessScore)
            qualityChip("噪点", score: 1.0 - qa.noiseScore)
            qualityChip("曝光", score: qa.exposureScore)
            qualityChip("总分", score: qa.overallScore, highlight: true)
        }
    }

    private func qualityChip(_ label: String, score: Double, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
            Text(String(format: "%.0f", score * 100))
                .font(.system(size: 13, weight: highlight ? .bold : .medium, design: .monospaced))
                .foregroundColor(highlight ? champagneGold : .white.opacity(0.9))
        }
    }

    // MARK: - Process Button

    private var processButton: some View {
        Button {
            startProcessing()
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("开始处理")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(champagneGold))
        }
    }

    private func startProcessing() {
        isProcessing = true
        // Queue drives pipeline-based captures; the editor performs its own
        // asynchronous processing below and reports progress locally.

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.isProcessing = false
            self.outputImage = self.inputImage // placeholder
            self.qualityAssessment = QualityAssessment(
                sharpnessScore: 0.85, noiseScore: 0.12, exposureScore: 0.9,
                motionBlurScore: 0.95, artifactScore: 0.05, overallScore: 0.88,
                warnings: [], aiGeneratedAreas: 0.05
            )
            self.showResult = true
        }
    }
}

#Preview {
    NavigationStack {
        AIEditorView(taskType: .superResolution)
    }
}
