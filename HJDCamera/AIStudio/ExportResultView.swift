//
//  ExportResultView.swift
//  HJD Camera Pro
//
//  Export result screen: show final image, quality assessment scores,
//  save to photo library / share / delete actions.
//

import SwiftUI
import Photos

struct ExportResultView: View {
    var image: UIImage? = nil
    var assessment: QualityAssessment? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @State private var showShareSheet = false

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if let image = image {
                        // Result image
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.3))
                            Text("暂无导出结果")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.top, 80)
                    }

                    // Quality assessment
                    if let qa = assessment {
                        qualitySection(qa)
                    }

                    // AI generated area warning
                    if let qa = assessment, qa.aiGeneratedAreas > 0.1 {
                        aiWarning(qa)
                    }

                    // Action buttons
                    if image != nil {
                        actionButtons
                    }
                }
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("导出结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Quality Section

    private func qualitySection(_ qa: QualityAssessment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("质量检测")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                qualityRing("清晰度", score: qa.sharpnessScore)
                qualityRing("噪点控制", score: 1.0 - qa.noiseScore)
                qualityRing("曝光", score: qa.exposureScore)
                qualityRing("综合评分", score: qa.overallScore, highlight: true)
            }

            if !qa.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(qa.warnings, id: \.self) { warning in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text(warning)
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .padding(.horizontal, 16)
    }

    private func qualityRing(_ label: String, score: Double, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: score)
                    .stroke(highlight ? champagneGold : .green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f", score * 100))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(highlight ? champagneGold : .white)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - AI Warning

    private func aiWarning(_ qa: QualityAssessment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(champagneGold)
            Text("约 \(Int(qa.aiGeneratedAreas * 100))% 区域为AI重建内容")
                .font(.system(size: 12))
                .foregroundColor(champagneGold)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(champagneGold.opacity(0.1)))
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                saveToLibrary()
            } label: {
                HStack {
                    Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                    Text(saved ? "已保存到相册" : "保存到相册")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(saved ? Color.green : champagneGold))
            }
            .disabled(saved)

            Button {
                showShareSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
    }

    private func saveToLibrary() {
        guard let image = image else { return }
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, _ in
                DispatchQueue.main.async {
                    saved = success
                }
            })
        }
    }
}

#Preview {
    NavigationStack {
        ExportResultView()
    }
}
