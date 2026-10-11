//
//  DiagnosticLogger.swift
//  HJD Camera Pro
//
//  Centralized file-backed diagnostic logging with category support.
//

import Foundation
import OSLog

// MARK: - Log Category

enum LogCategory: String, CaseIterable {
    case app = "app"
    case camera = "camera"
    case ai = "ai"
    case storage = "storage"
    case performance = "performance"
    case error = "error"

    var displayName: String { rawValue }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let category: String
    let message: String
    let tid: String

    init(date: Date, category: LogCategory, message: String) {
        self.id = UUID()
        self.date = date
        self.category = category.rawValue
        self.message = message
        self.tid = Thread.isMainThread ? "main" : "bg"
    }

    var line: String {
        let iso = ISO8601DateFormatter()
        return "[\(iso.string(from: date))] [\(category)] [\(tid)] \(message)"
    }
}

// MARK: - Logger

final class DiagnosticLogger: ObservableObject {
    static let shared = DiagnosticLogger()

    @Published private(set) var recentEntries: [LogEntry] = []

    private let fileManager = FileManager.default
    private let logDirectoryName = "DiagnosticLogs"
    private let maxRecentEntries = 200

    private var logFileURL: URL {
        let dirs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let base = dirs[0].appendingPathComponent(logDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("hjd_diag.log")
    }

    private let queue = DispatchQueue(label: "com.hjdcamera.diagnosticLogger", qos: .utility)

    private init() {
        try? fileManager.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    // MARK: - Logging

    func log(_ message: String, category: LogCategory) {
        let entry = LogEntry(date: Date(), category: category, message: message)

        queue.async { [weak self] in
            guard let self = self else { return }
            self.appendToDisk(entry)
            DispatchQueue.main.async {
                self.recentEntries.insert(entry, at: 0)
                if self.recentEntries.count > self.maxRecentEntries {
                    self.recentEntries.removeLast(self.recentEntries.count - self.maxRecentEntries)
                }
            }
        }

        let osLog = OSLog(subsystem: "com.hjdcamera.app", category: category.rawValue)
        os_log("%{public}@", log: osLog, type: .default, message)
    }

    func error(_ message: String) {
        log(message, category: .error)
    }

    // MARK: - Disk IO

    private func appendToDisk(_ entry: LogEntry) {
        let line = entry.line + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if fileManager.fileExists(atPath: logFileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Ignore write failures to avoid recursion.
            }
        } else {
            do {
                try data.write(to: logFileURL, options: .atomic)
            } catch {
                // Ignore.
            }
        }
    }

    // MARK: - Export / Clear

    func exportLogs() -> URL? {
        guard fileManager.fileExists(atPath: logFileURL.path) else { return nil }
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let exportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HJD_Diagnostics_\(stamp).log")
        do {
            try fileManager.copyItem(at: logFileURL, to: exportURL)
            return exportURL
        } catch {
            log("Failed to export logs: \(error.localizedDescription)", category: .error)
            return nil
        }
    }

    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                if self.fileManager.fileExists(atPath: self.logFileURL.path) {
                    try self.fileManager.removeItem(at: self.logFileURL)
                }
            } catch {
                // Ignore.
            }
            DispatchQueue.main.async {
                self.recentEntries.removeAll()
            }
        }
    }

    func currentLogContents() -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
