//
//  StorageManager.swift
//  HJD Camera Pro
//
//  Manages on-device storage: originals, RAW, AI-processed masters, video
//  proxies, model caches and temporary capture files, plus space warnings.
//

import Foundation
import Combine

final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    private let fileManager = FileManager.default

    // MARK: Published state

    @Published private(set) var budget = StorageBudget(
        modelCacheSize: 0,
        tempFilesSize: 0,
        rawPhotosSize: 0,
        processedPhotosSize: 0,
        videoProxySize: 0,
        totalAvailable: 0
    )
    @Published private(set) var lowSpaceWarning = false

    // MARK: Directory URLs

    private var baseURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("HJDCamera", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    var originalsDirectory: URL {
        baseURL.appendingPathComponent("Originals", isDirectory: true).created()
    }

    var rawDirectory: URL {
        baseURL.appendingPathComponent("RAW", isDirectory: true).created()
    }

    var processedDirectory: URL {
        baseURL.appendingPathComponent("Processed", isDirectory: true).created()
    }

    var proxyDirectory: URL {
        baseURL.appendingPathComponent("Proxies", isDirectory: true).created()
    }

    var modelCacheDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("HJDModels", isDirectory: true).created()
    }

    var tempDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("HJDTemp", isDirectory: true).created()
    }

    private init() {
        refreshBudget()
    }

    // MARK: - Space

    func availableSpace() -> Int64 {
        do {
            let values = try baseURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return available
            }
        } catch {
            DiagnosticLogger.shared.error("Failed to read available space: \(error.localizedDescription)")
        }
        return 0
    }

    // MARK: - Budget

    func refreshBudget() {
        let model = directorySize(modelCacheDirectory)
        let temp = directorySize(tempDirectory)
        let raw = directorySize(rawDirectory)
        let processed = directorySize(processedDirectory)
        let proxy = directorySize(proxyDirectory)
        let available = availableSpace()

        budget = StorageBudget(
            modelCacheSize: model,
            tempFilesSize: temp,
            rawPhotosSize: raw,
            processedPhotosSize: processed,
            videoProxySize: proxy,
            totalAvailable: available
        )

        let threshold = AppSettingsStore.shared.storageWarningThreshold
        lowSpaceWarning = available < threshold
        if lowSpaceWarning {
            NotificationCenter.default.post(name: .hjdStorageWarning, object: nil)
        }
    }

    var usedSpace: Int64 {
        budget.modelCacheSize + budget.tempFilesSize +
        budget.rawPhotosSize + budget.processedPhotosSize + budget.videoProxySize
    }

    // MARK: - Estimation

    /// Rough estimate of the exported file size for a given megapixel count and format.
    func estimateExportSize(for megapixels: Double, format: PhotoFormat = .heif, upscale: Double = 1.0) -> Int64 {
        let scaledPixels = megapixels * upscale * upscale
        switch format {
        case .heif:
            return Int64(scaledPixels * 1.6)   // ~1.6 bytes per compressed pixel
        case .jpeg:
            return Int64(scaledPixels * 2.2)
        case .raw, .rawPlus:
            return Int64(scaledPixels * 12.0)   // 12-bit raw
        }
    }

    // MARK: - Cleanup

    @discardableResult
    func cleanupTempFiles() -> Int64 {
        let freed = directorySize(tempDirectory)
        purgeContents(of: tempDirectory)
        refreshBudget()
        DiagnosticLogger.shared.log("Temp files cleaned, freed \(freed) bytes", category: .storage)
        return freed
    }

    @discardableResult
    func clearCache() -> Int64 {
        var freed: Int64 = 0
        freed += directorySize(modelCacheDirectory)
        purgeContents(of: modelCacheDirectory)
        freed += cleanupTempFiles()
        refreshBudget()
        return freed
    }

    // MARK: - Helpers

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDir = values.isDirectory, !isDir,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private func purgeContents(of directory: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }
}

// MARK: - URL helper

private extension URL {
    func created() -> URL {
        try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
