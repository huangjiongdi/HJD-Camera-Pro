//
//  AIStudioView.swift
//  HJD Camera Pro
//
//  AI Studio home. Functional sections: quality enhancement / night HDR /
//  super-moon / macro-architecture / portrait / repair & creation.
//

import SwiftUI

struct AIStudioView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var aiProcessingQueue: AIProcessingQueue
    @Environment(\.dismiss) private var dismiss

    private let champagneGold = Color(red: 0.85, green: 0.75, blue: 0.55)

    private let sections: [AISection] = [
        AISection(title: "画质增强", icon: "wand.and.stars", tasks: [.superResolution, .denoise, .deblur]),
        AISection(title: "夜景HDR", icon: "moon.stars.fill", tasks: [.nightRestore, .hdr]),
        AISection(title: "超级月亮", icon: "moon.fill", tasks: [.lunarEnhance]),
        AISection(title: "微距与建筑", icon: "building.2", tasks: [.macroEnhance, .architectureEnhance, .textEnhance]),
        AISection(title: "人像", icon: "person.crop.circle", tasks: [.portraitOptimize]),
        AISection(title: "修复与创作", icon: "sparkles.tv", tasks: [.oldPhotoRestore, .objectErase, .outpaint, .skyReplace, .dereflection, .demoire]),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.05)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection

                        // Processing status banner
                        if aiProcessingQueue.isProcessing {
                            processingBanner
                        }

                        // Functional sections
                        ForEach(sections) { section in
                            sectionCard(section)
                        }

                        // Bottom actions
                        bottomActions
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("AI 工作室")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        appState.showAIStudio = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        ModelSelectionView()
                    } label: {
                        Image(systemName: "cube.box")
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 画质工作室")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("智能增强 · 多帧融合 · 真实性保护")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Processing Banner

    private var processingBanner: some View {
        HStack {
            ProgressView(value: aiProcessingQueue.currentProgress)
                .tint(champagneGold)
            Text("处理中 \(Int(aiProcessingQueue.currentProgress * 100))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(champagneGold)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(champagneGold.opacity(0.1)))
    }

    // MARK: - Section Card

    private func sectionCard(_ section: AISection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: section.icon)
                    .font(.system(size: 16))
                    .foregroundColor(champagneGold)
                Text(section.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(section.tasks, id: \.rawValue) { task in
                    NavigationLink {
                        AIEditorView(taskType: task)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: iconForTask(task))
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.85))
                            Text(task.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BatchProcessView()
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("批量处理")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(champagneGold))
            }

            NavigationLink {
                ExportResultView()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("导出结果")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().stroke(champagneGold, lineWidth: 1.5))
            }
        }
    }

    private func iconForTask(_ task: AITaskType) -> String {
        switch task {
        case .superResolution: return "arrow.up.left.and.arrow.down.right"
        case .nightRestore: return "moon.zzz"
        case .portraitOptimize: return "person.crop.circle.badge.checkmark"
        case .lunarEnhance: return "moon.fill"
        case .macroEnhance: return "macro"
        case .architectureEnhance: return "building.columns"
        case .deblur: return "drop.halffull"
        case .dereflection: return "sun.max"
        case .demoire: return "circle.grid.cross"
        case .textEnhance: return "text.viewfinder"
        case .objectErase: return "sparkles.rectangle.stack"
        case .outpaint: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case .skyReplace: return "cloud.sun"
        case .denoise: return "wind"
        case .oldPhotoRestore: return "photo.on.rectangle"
        default: return "wand.and.stars"
        }
    }
}

// MARK: - AI Section

struct AISection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tasks: [AITaskType]
}

#Preview {
    AIStudioView()
        .environmentObject(AppState.shared)
}
