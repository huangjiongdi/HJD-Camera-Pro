//
//  PhotoLibraryExporter.swift
//  HJD Camera Pro
//
//  Exports finished photos / videos into the system Photos library with
//  permission handling, low-space fallbacks and metadata embedding.
//

import Foundation
import Photos
import UIKit

final class PhotoLibraryExporter {
    static let shared = PhotoLibraryExporter()

    enum ExportError: Error, CustomStringConvertible {
        case permissionDenied
        case insufficientSpace
        case writeFailed(String)

        var description: String {
            switch self {
            case .permissionDenied: return "相册权限被拒绝"
            case .insufficientSpace: return "存储空间不足"
            case .writeFailed(let msg): return "写入失败: \(msg)"
            }
        }
    }

    private init() {}

    // MARK: - Permission

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    // MARK: - Export photo

    @discardableResult
    func exportPhoto(data: Data) async -> Result<String, ExportError> {
        guard await requestAuthorization() else {
            return .failure(.permissionDenied)
        }
        let space = StorageManager.shared.availableSpace()
        guard space == 0 || space > Int64(data.count) else {
            return .failure(.insufficientSpace)
        }

        do {
            var localId: String?
            try await PHPhotoLibrary.shared().performChanges {
                // Must use the factory initializer — a bare PHAssetCreationRequest()
                // is not attached to the change request and silently saves nothing.
                let creation = PHAssetCreationRequest.creationRequestForAsset()
                creation.addResource(with: .photo, data: data, options: nil)
                localId = creation.placeholderForCreatedAsset?.localIdentifier
            }
            guard let id = localId else {
                return .failure(.writeFailed("No placeholder"))
            }
            DiagnosticLogger.shared.log("Photo exported to library: \(id)", category: .storage)
            return .success(id)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    // MARK: - Export video

    @discardableResult
    func exportVideo(fileURL: URL) async -> Result<String, ExportError> {
        guard await requestAuthorization() else {
            return .failure(.permissionDenied)
        }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let space = StorageManager.shared.availableSpace()
        guard space == 0 || space > Int64(size) else {
            return .failure(.insufficientSpace)
        }

        do {
            var localId: String?
            try await PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.creationRequestForAsset()
                creation.addResource(with: .video, fileURL: fileURL, options: nil)
                localId = creation.placeholderForCreatedAsset?.localIdentifier
            }
            guard let id = localId else {
                return .failure(.writeFailed("No placeholder"))
            }
            DiagnosticLogger.shared.log("Video exported to library: \(id)", category: .storage)
            return .success(id)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }
}
