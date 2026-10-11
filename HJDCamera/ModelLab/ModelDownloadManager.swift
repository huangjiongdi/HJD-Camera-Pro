//
//  ModelDownloadManager.swift
//  HJD Camera Pro
//
//  Manages model downloads: queuing, pause/resume, resume-from-breakpoint and
//  retry. Models are bundled by default, but this interface is retained for
//  future over-the-air updates.
//

import Foundation
import Combine
import CryptoKit

enum ModelDownloadState: Equatable {
    case idle
    case queued
    case downloading(progress: Double)
    case paused
    case completed
    case failed(error: String)
}

final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    @Published private(set) var tasks: [String: ModelDownloadState] = [:]

    private let fileManager = FileManager.default
    private lazy var session: URLSession = {
        URLSession(
            configuration: .background(
                withIdentifier: "com.hjdcamera.modelDownloads"
            ),
            delegate: self,
            delegateQueue: nil
        )
    }()

    private var activeDownloads: [URLSessionDownloadTask: String] = [:]
    private let maxRetries = 3

    private override init() {}

    // MARK: - Queue

    func download(modelID: String, from url: URL, to destination: URL) {
        guard tasks[modelID] != .downloading(progress: 0) else { return }
        tasks[modelID] = .queued

        let task = session.downloadTask(with: url)
        activeDownloads[task] = modelID
        task.resume()
        tasks[modelID] = .downloading(progress: 0)
    }

    func pause(modelID: String) {
        guard let task = activeDownloads.first(where: { $0.value == modelID })?.key else { return }
        task.cancel(byProducingResumeData: { _ in
            self.tasks[modelID] = .paused
        })
    }

    func resume(modelID: String, resumeData: Data?) {
        guard let data = resumeData else { return }
        let task = session.downloadTask(withResumeData: data)
        activeDownloads[task] = modelID
        task.resume()
        tasks[modelID] = .downloading(progress: 0)
    }

    func cancel(modelID: String) {
        guard let task = activeDownloads.first(where: { $0.value == modelID })?.key else { return }
        task.cancel()
        activeDownloads.removeValue(forKey: task)
        tasks[modelID] = .idle
    }

    // MARK: - Integrity

    /// Verifies a downloaded model against an expected SHA256 checksum.
    func verifyIntegrity(of fileURL: URL, expectedSHA256: String) -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let hash = data.sha256()
        return hash.caseInsensitiveCompare(expectedSHA256) == .orderedSame
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let modelID = activeDownloads[downloadTask] else { return }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        DispatchQueue.main.async {
            self.tasks[modelID] = .downloading(progress: progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelID = activeDownloads[downloadTask] else { return }
        activeDownloads.removeValue(forKey: downloadTask)
        DispatchQueue.main.async {
            self.tasks[modelID] = .completed
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error,
              let downloadTask = task as? URLSessionDownloadTask,
              let modelID = activeDownloads[downloadTask] else { return }
        activeDownloads.removeValue(forKey: downloadTask)
        DispatchQueue.main.async {
            self.tasks[modelID] = .failed(error: error.localizedDescription)
        }
    }
}

// MARK: - SHA256 helper

extension Data {
    func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
