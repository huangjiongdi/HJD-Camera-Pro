//
//  StorageBudgetManager.swift
//  HJD Camera Pro
//
//  Computes storage budgets: model cache footprint, working caches and the
//  estimated size of upcoming exports before they are written.
//

import Foundation

final class StorageBudgetManager {
    static let shared = StorageBudgetManager()

    private let fileManager = FileManager.default
    private let storage = StorageManager.shared

    private init() {}

    // MARK: - Current budget breakdown

    struct Breakdown {
        var modelCache: Int64
        var tempWorking: Int64
        var masters: Int64
        var proxies: Int64
        var available: Int64
        var recommendedHeadroom: Int64 { 500_000_000 } // keep 500 MB free
        var safeForExport: Bool {
            available > recommendedHeadroom
        }
    }

    func currentBreakdown() -> Breakdown {
        let budget = storage.budget
        return Breakdown(
            modelCache: budget.modelCacheSize,
            tempWorking: budget.tempFilesSize,
            masters: budget.rawPhotosSize + budget.processedPhotosSize,
            proxies: budget.videoProxySize,
            available: budget.totalAvailable
        )
    }

    // MARK: - Planned export cost

    enum ExportPlan {
        case photo(megapixels: Double, format: PhotoFormat, upscale: Double)
        case video(seconds: Double, bitrate: Int)
        case batch(count: Int, unitBytes: Int64)
    }

    func estimatedSize(for plan: ExportPlan) -> Int64 {
        switch plan {
        case .photo(let mp, let format, let upscale):
            return storage.estimateExportSize(for: mp, format: format, upscale: upscale)
        case .video(let seconds, let bitrate):
            // bitrate is bits per second -> bytes
            return Int64(seconds * Double(bitrate) / 8.0)
        case .batch(let count, let unitBytes):
            return Int64(count) * unitBytes
        }
    }

    func fits(plan: ExportPlan) -> Bool {
        let needed = estimatedSize(for: plan)
        let breakdown = currentBreakdown()
        return breakdown.available - needed > breakdown.recommendedHeadroom
    }

    // MARK: - Model footprint

    /// Total disk footprint of all bundled / downloaded CoreML models.
    func modelFootprint(models: [AIModelInfo]) -> Int64 {
        models.reduce(0) { $0 + $1.fileSize }
    }

    /// Estimated working memory (not disk) a model run will require.
    func estimatedRuntimeMemory(for model: AIModelInfo) -> Int64 {
        if let peak = model.peakMemory { return peak }
        // Heuristic: assume ~1.5x the model file size for the inference workspace.
        return Int64(Double(model.fileSize) * 1.5)
    }
}
