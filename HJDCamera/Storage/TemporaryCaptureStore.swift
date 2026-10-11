//
//  TemporaryCaptureStore.swift
//  HJD Camera Pro
//
//  Safe, atomic staging area for in-flight captures. If processing fails the
//  original capture buffer is recoverable; completed items are promoted to the
//  permanent originals directory.
//

import Foundation

final class TemporaryCaptureStore {
    static let shared = TemporaryCaptureStore()

    private let fileManager = FileManager.default

    private var stagingDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HJDStaging", isDirectory: true)
            .created()
    }

    private let queue = DispatchQueue(label: "com.hjdcamera.tempCaptureStore", qos: .userInitiated)

    private init() {}

    // MARK: - Atomic write

    /// Writes capture data to a temporary file using an atomic write-then-rename
    /// strategy so a crash mid-write never leaves a truncated staged file.
    func stageCapture(data: Data, filename: String) -> URL {
        let staging = stagingDirectory.appendingPathComponent(filename)
        let intermediate = staging.appendingPathExtension("partial")
        queue.sync {
            // Write to an intermediate file first.
            do {
                try data.write(to: intermediate, options: .atomic)
                // Atomically move into place.
                if fileManager.fileExists(atPath: staging.path) {
                    try fileManager.removeItem(at: staging)
                }
                try fileManager.moveItem(at: intermediate, to: staging)
            } catch {
                DiagnosticLogger.shared.error("Failed to stage capture: \(error.localizedDescription)")
            }
        }
        return staging
    }

    // MARK: - Promote / recover

    /// Moves a staged capture into the permanent originals directory.
    @discardableResult
    func promote(stagedURL: URL, to destination: URL) -> URL? {
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: stagedURL, to: destination)
            return destination
        } catch {
            DiagnosticLogger.shared.error("Failed to promote capture: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns all staged (unprocessed) captures still on disk, so a failed
    /// session can recover the originals.
    func recoverableCaptures() -> [URL] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items.filter { !$0.pathExtension.contains("partial") }
    }

    /// Abandons a staged file (used when processing succeeded and the staged
    /// original no longer needs recovery).
    func discard(stagedURL: URL) {
        try? fileManager.removeItem(at: stagedURL)
    }

    /// Removes any leftover partial writes from an interrupted atomic write.
    func purgePartialWrites() {
        guard let items = try? fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for item in items where item.pathExtension == "partial" {
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
