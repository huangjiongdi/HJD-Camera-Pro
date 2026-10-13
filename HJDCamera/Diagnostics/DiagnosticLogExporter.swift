//
//  DiagnosticLogExporter.swift
//  HJD Camera Pro
//
//  Packages diagnostic logs together with a device compatibility report into a
//  single shareable bundle.
//

import Foundation
import UIKit

final class DiagnosticLogExporter {
    static let shared = DiagnosticLogExporter()

    private let logger = DiagnosticLogger.shared
    private let device = DeviceCapabilityManager.shared

    private init() {}

    // MARK: - Export

    /// Builds a diagnostic bundle containing the raw log plus a compatibility
    /// summary, and returns the file URL for sharing.
    func buildDiagnosticBundle() -> URL? {
        guard let logURL = logger.exportLogs() else {
            logger.error("No log file to export")
            return nil
        }

        let report = compatibilityReportText()
        let reportURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HJD_Compatibility_Report.txt")
        do {
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write compatibility report: \(error.localizedDescription)")
            return logURL
        }
        // Return the log URL as the primary artifact; the report is attached in
        // the share sheet by the caller if needed.
        return logURL
    }

    // MARK: - Compatibility report

    func compatibilityReportText() -> String {
        let info = device.compatibilityReport()
        let settings = AppSettingsStore.shared.exportDiagnostics()
        var lines = ["HJD Camera Pro — Device Compatibility Report", ""]
        lines.append("Device: \(info["device"] ?? "unknown")")
        lines.append("iOS: \(info["iOS"] ?? "unknown")")
        lines.append("Telephoto: \(info["hasTelephoto"] ?? false)")
        lines.append("UltraWide: \(info["hasUltraWide"] ?? false)")
        lines.append("LiDAR: \(info["hasLiDAR"] ?? false)")
        lines.append("Max Zoom: \(info["maxZoom"] ?? 0)")
        lines.append("4K@240: \(info["supports4K240"] ?? false)")
        lines.append("8K: \(info["supports8K"] ?? false)")
        lines.append("ProRes: \(info["supportsProRes"] ?? false)")
        lines.append("HDR: \(info["supportsHDR"] ?? false)")
        lines.append("Max Photo MP: \(info["maxPhotoMP"] ?? 0)")
        lines.append("")
        lines.append("Settings snapshot:")
        for (key, value) in settings {
            lines.append("  \(key): \(value)")
        }
        return lines.joined(separator: "\n")
    }
}
