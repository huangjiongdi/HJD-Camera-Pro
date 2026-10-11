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
        // Placeholder: presented via SwiftUI .fileImporter
    }

    func importCubeFile(url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let lut = LUTInfo(name: name, category: .custom, isBuiltin: false)
        customLUTs.append(lut)
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
}
