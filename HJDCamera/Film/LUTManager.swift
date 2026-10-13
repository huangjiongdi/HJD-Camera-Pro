//
//  LUTManager.swift
//  HJD Camera Pro
//
//  LUT management: 69 built-in LUTs + imported .cube files. Handles
//  loading, categorizing, and listing available LUTs.
//

import SwiftUI
import CoreImage

class LUTManager: ObservableObject {
    static let shared = LUTManager()

    @Published var customLUTs: [LUTInfo] = []
    @Published var activeLUTName: String = "None"

    // 69 built-in LUTs organized by category
    let builtinLUTs: [LUTCategory: [LUTInfo]] = [
        .film: (1...15).map { LUTInfo(name: "Film \($0)", category: .film, isBuiltin: true) },
        .cinematic: (1...12).map { LUTInfo(name: "Cinematic \($0)", category: .cinematic, isBuiltin: true) },
        .portrait: (1...10).map { LUTInfo(name: "Portrait \($0)", category: .portrait, isBuiltin: true) },
        .landscape: (1...12).map { LUTInfo(name: "Landscape \($0)", category: .landscape, isBuiltin: true) },
        .blackWhite: (1...10).map { LUTInfo(name: "B&W \($0)", category: .blackWhite, isBuiltin: true) },
    ]

    private init() {}

    var allLUTs: [LUTInfo] {
        builtinLUTs.flatMap { $0.value } + customLUTs
    }

    func luts(in category: LUTCategory) -> [LUTInfo] {
        builtinLUTs[category] ?? []
    }

    func presentImporter() {
        // Presented via SwiftUI .fileImporter in ColorLUTSettingsView.
    }

    /// Copy the picked .cube into the app's Documents folder (security-scoped
    /// access required for security-scoped bookmarks / document picker URLs).
    func importCubeFile(url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = url.deletingPathExtension().lastPathComponent
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LUTs")
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            let dest = docs.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            // Avoid duplicates.
            if !customLUTs.contains(where: { $0.name == name }) {
                let lut = LUTInfo(name: name, category: .custom, isBuiltin: false, fileURL: dest)
                customLUTs.append(lut)
            }
            activeLUTName = name
        } catch {
            DiagnosticLogger.shared.log("copy LUT failed: \(error.localizedDescription)", category: .storage)
        }
    }

    func selectLUT(_ name: String) {
        activeLUTName = name
    }
}

// MARK: - LUT Info

enum LUTCategory: String, CaseIterable {
    case film = "胶片"
    case cinematic = "电影感"
    case portrait = "人像"
    case landscape = "风景"
    case blackWhite = "黑白"
    case custom = "自定义"
}

struct LUTInfo: Identifiable {
    let id = UUID()
    let name: String
    let category: LUTCategory
    let isBuiltin: Bool
    var fileURL: URL? = nil
}
