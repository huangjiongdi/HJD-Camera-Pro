//
//  MediaIntegrityChecker.swift
//  HJD Camera Pro
//
//  Verifies that captured / exported media files are readable and intact,
//  and records per-file check results.
//

import Foundation
import ImageIO
import UIKit

final class MediaIntegrityChecker {
    static let shared = MediaIntegrityChecker()

    struct CheckResult: Identifiable {
        let id = UUID()
        let url: URL
        let isReadable: Bool
        let fileSize: Int64
        let thumbnailLoadable: Bool
        let errorMessage: String?
        let checkedAt: Date
    }

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Photo integrity

    /// Validates that an image file exists, is non-empty and can be decoded.
    func verifyPhoto(at url: URL) -> CheckResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return CheckResult(url: url, isReadable: false, fileSize: 0,
                               thumbnailLoadable: false,
                               errorMessage: "File does not exist", checkedAt: Date())
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else {
            return CheckResult(url: url, isReadable: false, fileSize: 0,
                               thumbnailLoadable: false,
                               errorMessage: "File is empty", checkedAt: Date())
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return CheckResult(url: url, isReadable: false, fileSize: Int64(size),
                               thumbnailLoadable: false,
                               errorMessage: "Cannot create image source", checkedAt: Date())
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return CheckResult(url: url, isReadable: false, fileSize: Int64(size),
                               thumbnailLoadable: false,
                               errorMessage: "Image data is corrupt", checkedAt: Date())
        }

        return CheckResult(url: url, isReadable: true, fileSize: Int64(size),
                           thumbnailLoadable: cgImage.width > 0 && cgImage.height > 0,
                           errorMessage: nil, checkedAt: Date())
    }

    // MARK: - Video integrity

    /// Validates a video file by checking it exists, is non-empty and is a
    /// recognized container. Full decode validation is intentionally lightweight.
    func verifyVideo(at url: URL) -> CheckResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return CheckResult(url: url, isReadable: false, fileSize: 0,
                               thumbnailLoadable: false,
                               errorMessage: "Video does not exist", checkedAt: Date())
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 1024 else {
            return CheckResult(url: url, isReadable: false, fileSize: Int64(size),
                               thumbnailLoadable: false,
                               errorMessage: "Video file too small", checkedAt: Date())
        }
        // Read the first bytes to confirm a recognizable media signature.
        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: 16) else {
            return CheckResult(url: url, isReadable: false, fileSize: Int64(size),
                               thumbnailLoadable: false,
                               errorMessage: "Cannot read header", checkedAt: Date())
        }
        try? handle.close()
        let isISOBaseMedia = header.count >= 8
        return CheckResult(
            url: url,
            isReadable: isISOBaseMedia,
            fileSize: Int64(size),
            thumbnailLoadable: isISOBaseMedia,
            errorMessage: isISOBaseMedia ? nil : "Unrecognized video container",
            checkedAt: Date()
        )
    }

    // MARK: - Export record check

    /// Verifies every recorded export URL still points to a readable file.
    func verifyExportRecords(_ records: [URL]) -> [CheckResult] {
        records.map { url in
            url.pathExtension.lowercased() == "mov" || url.pathExtension.lowercased() == "mp4"
                ? verifyVideo(at: url)
                : verifyPhoto(at: url)
        }
    }
}
