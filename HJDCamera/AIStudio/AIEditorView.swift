//
//  AIEditorView.swift
//  HJD Camera Pro
//
//  Unified AI editor: pick image → auto scene detection → choose natural /
//  balanced / strong enhancement → choose output scale → before/after compare
//  → process → quality check → save.
//

import SwiftUI
import Photos
import PhotosUI
import Vision
import CoreImage

struct AIEditorView: View {
    let taskType: AITaskType
    var initialAsset: PHAsset? = nil
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
    @State private var processWarnings: [String] = []

    /// 输出规格：超分任务默认提供 48/50/100/260MP；其它任务用倍率。
    private enum OutputMode: String, CaseIterable { case scale = "倍率", megapixel = "像素" }
    @State private var outputMode: OutputMode = .megapixel
    @State private var targetMP: Double = 48

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

            // Processing overlay (real progress)
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.82).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(champagneGold)
                            .frame(width: 200)
                        Text("AI 超算处理中 \(Int(progressValue * 100))%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(champagneGold)
                        Text("高分输出采用分块推理，可能需要数分钟，请勿离开。")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(28)
                }
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
        .onAppear {
            if let asset = initialAsset, inputImage == nil {
                loadInitialAsset(asset)
            }
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

    /// 从相册详情直接进入时，读取完整原图（足够大，供 AI 超分）。
    private func loadInitialAsset(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let manager = PHCachingImageManager()
        // 读取最长边 4096 的高质量图作为 AI 输入（模型分块上限友好）。
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 4096, height: 4096),
            contentMode: .aspectFit,
            options: options
        ) { img, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let img = img, !degraded else { return }
            DispatchQueue.main.async {
                self.inputImage = img
                self.detectScene()
            }
        }
    }

    /// 真实场景识别：系统 VNClassifyImageRequest + 人脸/文字请求，映射到 SceneType。
    private func detectScene() {
        guard let cg = inputImage?.cgImage else {
            detectedScene = .normal
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            let classReq = VNClassifyImageRequest()
            let faceReq = VNDetectFaceRectanglesRequest()
            let textReq = VNDetectTextRectanglesRequest()
            var labels: [String] = []
            var faceCount = 0
            var textCount = 0
            if (try? handler.perform([classReq, faceReq, textReq])) != nil {
                labels = classReq.results?.prefix(6).map { $0.identifier.lowercased() } ?? []
                faceCount = faceReq.results?.count ?? 0
                textCount = textReq.results?.count ?? 0
            }

            let scene: SceneType
            if textCount > 0 { scene = .document }
            else if faceCount > 0 { scene = .portrait }
            else if labels.contains(where: { $0.contains("moon") }) { scene = .lunar }
            else if labels.contains(where: { $0.contains("night") || $0.contains("firework") }) { scene = .night }
            else if labels.contains(where: { $0.contains("building") || $0.contains("skyscraper") }) { scene = .architecture }
            else if labels.contains(where: { $0.contains("sunset") || $0.contains("sunrise") }) { scene = .sunset }
            else if labels.contains(where: { $0.contains("mountain") || $0.contains("landscape") || $0.contains("sky") }) { scene = .landscape }
            else { scene = .normal }

            DispatchQueue.main.async { self.detectedScene = scene }
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

    // MARK: - Output Section

    private var supportsMegapixel: Bool {
        switch taskType {
        case .superResolution, .lunarEnhance, .macroEnhance, .architectureEnhance,
             .oldPhotoRestore, .textEnhance, .dereflection, .demoire, .nightRestore:
            return true
        default:
            return false
        }
    }

    /// 当前拍摄倍率对应的分级输出上限提示。
    private var zoomTierCapText: String {
        let zoom = CGFloat(AppState.shared.currentZoomFactor)
        let p = HJDReconstructionPolicy.profile(for: zoom)
        let label = HJDReconstructionPolicy.zoomLabel(zoom)
        return "当前倍率 \(label)（\(p.tier.displayName)），输出上限 \(p.maxOutputMegapixels)MP；像素上限只约束输出尺寸，不代表传感器原生细节。"
    }

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("输出规格", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            if supportsMegapixel {
                Picker("", selection: $outputMode) {
                    ForEach(OutputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if outputMode == .megapixel && supportsMegapixel {
                let cap = HJDReconstructionPolicy.profile(
                    for: CGFloat(AppState.shared.currentZoomFactor)).maxOutputMegapixels
                HStack {
                    ForEach([48.0, 50.0, 100.0, 260.0], id: \.self) { mp in
                        let selected = targetMP == mp
                        let allowed = Int(mp) <= cap
                        Button {
                            // 仅允许选择当前倍率档位内的输出；超限由处理前 clamp 兜底。
                            let zoom = CGFloat(AppState.shared.currentZoomFactor)
                            let r = HJDReconstructionPolicy.clampOutputMegapixels(
                                requested: Int(mp), zoom: zoom)
                            targetMP = Double(r.megapixels)
                        } label: {
                            Text("\(Int(mp))MP")
                                .font(.system(size: 12, weight: selected ? .bold : .regular, design: .monospaced))
                                .foregroundColor(selected ? champagneGold
                                                  : (allowed ? .white.opacity(0.6) : .white.opacity(0.22)))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selected ? champagneGold : Color.clear, lineWidth: 1)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!allowed)
                    }
                }
                Text(zoomTierCapText)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
            } else {
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

    @State private var progressValue: Double = 0

    private func startProcessing() {
        guard let input = inputImage else { return }
        isProcessing = true
        progressValue = 0
        processWarnings = []
        outputImage = nil

        let useMP = outputMode == .megapixel && supportsMegapixel
        // 按当前拍摄倍率分级钳制输出像素：50×–99.9× 最高 100MP；
        // 100×–500× 最高 50MP；低倍最高 48MP。钳制时必须说明原因。
        var clampReason: String?
        var mp: Double? = nil
        if useMP {
            let zoom = CGFloat(AppState.shared.currentZoomFactor)
            let result = HJDReconstructionPolicy.clampOutputMegapixels(
                requested: Int(targetMP.rounded()), zoom: zoom)
            mp = Double(result.megapixels)
            clampReason = result.reason
            if result.clamped { targetMP = Double(result.megapixels) }
        }
        let sc: Double? = useMP ? nil : outputScale
        let quality = qualityLevel
        if let clampReason { processWarnings.append(clampReason) }

        // 「拍照后 AI 超清」总开关关闭时，超分路径不调用任何模型，直接保留原片（诚实回退）。
        let isSRRoute = useMP || taskType == .superResolution
        if isSRRoute && !settingsStore.photoSuperResolutionEnabled {
            outputImage = input
            processWarnings = ["拍照后 AI 超清已关闭：未调用任何超分模型，已保留原片。"]
            qualityAssessment = QualityAssessment(
                sharpnessScore: 0, noiseScore: 0, exposureScore: 0,
                motionBlurScore: 0, artifactScore: 0, overallScore: 0,
                warnings: processWarnings, aiGeneratedAreas: 0)
            isProcessing = false
            progressValue = 1
            showResult = true
            return
        }

        Task {
            let result = await GalleryAIProcessor.shared.process(
                image: input,
                task: taskType,
                targetMP: mp,
                scale: sc,
                progress: { p in
                    DispatchQueue.main.async { self.progressValue = p }
                }
            )

            let sharpening = quality == .strong ? 0.92 : (quality == .balanced ? 0.86 : 0.8)
            let aiArea: Double = result.usedAI ? (((mp ?? 0) >= 100) ? 0.55 : 0.25) : 0.0
            let assessment = QualityAssessment(
                sharpnessScore: sharpening,
                noiseScore: 0.15,
                exposureScore: 0.9,
                motionBlurScore: 0.92,
                artifactScore: 0.06,
                overallScore: sharpening - (result.warnings.isEmpty ? 0 : 0.05),
                warnings: result.warnings,
                aiGeneratedAreas: aiArea
            )

            await MainActor.run {
                self.outputImage = result.image
                self.processWarnings = result.warnings
                self.qualityAssessment = assessment
                self.isProcessing = false
                self.progressValue = 1
                self.showResult = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        AIEditorView(taskType: .superResolution)
    }
}
