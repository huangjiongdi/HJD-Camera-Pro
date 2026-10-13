//
//  LUTManager.swift
//  HJD Camera Pro
//
//  真实 LUT 目录（第七轮）：
//  · 极影相机 HALD CLUT（512×512 = 64³，已逐像素验证排布），含徕卡生动/
//    徕卡柔和/哈苏蓝/理光GR 及柯达/富士/宝丽来经典胶卷、电影/胶片/人像/
//    风光/黑白全系列，共 86 个，捆绑在 Resources/LUT/Hald。
//  · 弓雨公系列 .cube（Resources/LUT），运行时从 bundle 扫描。
//  选中的 LUT 与强度在拍摄时由 PhotoCapturePipeline 注入成片（原图始终保留）。
//

import SwiftUI
import CoreImage

enum LUTKind {
    case hald   // Resources/LUT/Hald/*.jpg
    case cube   // Resources/LUT/*.cube
}

class LUTManager: ObservableObject {
    static let shared = LUTManager()

    @Published var customLUTs: [LUTInfo] = []
    @Published var activeLUTName: String = "None"
    /// 0...1，拍摄成片时的 LUT 强度（徕卡生动默认 0.75，与极影一致）。
    @Published var intensity: Double = 0.75

    /// 拍摄界面快捷条推荐的 LUT（徕卡与经典）。
    let quickPicks: [LUTInfo]

    let builtinLUTs: [LUTCategory: [LUTInfo]]

    private init() {
        var table = Self.haldCatalog()
        // 弓雨公 .cube 从 bundle 动态扫描（Resources/LUT/*.cube）。
        // 同步组可能保留子目录，也可能把资源扁平化到 bundle 根，两种都兜底。
        var cubeURLs = Bundle.main.urls(forResourcesWithExtension: "cube",
                                        subdirectory: "LUT") ?? []
        if cubeURLs.isEmpty {
            cubeURLs = Bundle.main.urls(forResourcesWithExtension: "cube",
                                        subdirectory: nil) ?? []
        }
        let cubes = cubeURLs
            .map { url -> LUTInfo in
                let fname = url.deletingPathExtension().lastPathComponent
                return LUTInfo(name: fname, category: .cubeSeries,
                               isBuiltin: true, resource: url.lastPathComponent, kind: .cube)
            }
            .sorted { $0.name < $1.name }
        table[.cubeSeries] = cubes
        self.builtinLUTs = table
        var quick: [LUTInfo] = []
        for key in [LUTCategory.leica, .classic] {
            quick.append(contentsOf: table[key] ?? [])
        }
        self.quickPicks = Array(quick.prefix(12))
    }

    var allLUTs: [LUTInfo] {
        builtinLUTs.flatMap { $0.value } + customLUTs
    }

    func luts(in category: LUTCategory) -> [LUTInfo] {
        builtinLUTs[category] ?? []
    }

    func info(named name: String) -> LUTInfo? {
        if name == "None" { return nil }
        if let hit = builtinLUTs.values.flatMap({ $0 }).first(where: { $0.name == name }) {
            return hit
        }
        return customLUTs.first { $0.name == name }
    }

    func presentImporter() {
        // Presented via SwiftUI .fileImporter in ColorLUTSettingsView.
    }

    /// Copy the picked .cube into the app's Documents folder.
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
            if !customLUTs.contains(where: { $0.name == name }) {
                let lut = LUTInfo(name: name, category: .custom, isBuiltin: false,
                                  resource: url.lastPathComponent, kind: .cube, fileURL: dest)
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

    // MARK: - 极影 HALD 目录（资源名见 Resources/LUT/Hald）

    private static func hald(_ name: String, _ resource: String,
                             _ category: LUTCategory) -> LUTInfo {
        LUTInfo(name: name, category: category, isBuiltin: true,
                resource: resource, kind: .hald)
    }

    private static func haldCatalog() -> [LUTCategory: [LUTInfo]] {
        var t: [LUTCategory: [LUTInfo]] = [:]
        t[.leica] = [
            hald("徕卡生动", "leica_vivid.jpg", .leica),
            hald("徕卡柔和", "leica_soft.jpg", .leica),
            hald("哈苏蓝", "hasselblad_blue.jpg", .leica),
            hald("理光GR", "ricoh_gr.jpg", .leica),
        ]
        t[.classic] = [
            hald("柯达EK80", "kodak_ek80.jpg", .classic),
            hald("柯达Ektar100", "kodak_ektar100.jpg", .classic),
            hald("柯达Portra160", "kodak_portra160.jpg", .classic),
            hald("柯达Chrome64", "kodak_chrome64.jpg", .classic),
            hald("柯达金200", "kodak_gold200.jpg", .classic),
            hald("富士FP100", "fuji_fp100.jpg", .classic),
            hald("富士Natura1600", "fuji_natura1600.jpg", .classic),
            hald("富士Superia200", "fuji_superia200.jpg", .classic),
            hald("富士Superia400", "fuji_superia400.jpg", .classic),
            hald("爱克发Optima", "agfa_optima100.jpg", .classic),
            hald("宝丽来600", "polaroid600.jpg", .classic),
            hald("宝丽来669", "polaroid669.jpg", .classic),
            hald("禄来LOMO", "rollei_lomo.jpg", .classic),
            hald("CineStill800T", "cinestill800t.jpg", .classic),
        ]
        t[.film] = (1...10).map { hald("胶片\($0)", "film\($0).jpg", .film) }
        t[.cinematic] = (1...10).map { hald("电影\($0)", "cine\($0).jpg", .cinematic) }
            + [hald("动作电影", "action_movie.jpg", .cinematic),
               hald("LOG电影1", "cinelog1.jpg", .cinematic),
               hald("LOG电影2", "cinelog2.jpg", .cinematic),
               hald("AriiLOG", "arii_log.jpg", .cinematic)]
        t[.portrait] = (1...10).map { hald("人像\($0)", "portrait\($0).jpg", .portrait) }
        t[.landscape] = (1...10).map { hald("风光\($0)", "land\($0).jpg", .landscape) }
        t[.blackWhite] = (1...8).map { hald("黑白\($0)", "bw\($0).jpg", .blackWhite) }
            + [hald("默片", "silent.jpg", .blackWhite),
               hald("银盐", "silver_salt.jpg", .blackWhite)]
        t[.style] = [
            hald("青绿", "green_tone.jpg", .style),
            hald("冷调", "cool_tone.jpg", .style),
            hald("青橙", "teal_orange.jpg", .style),
            hald("赛博朋克", "cyberpunk.jpg", .style),
            hald("好莱坞", "hollywood.jpg", .style),
            hald("港风夜景", "hk_night.jpg", .style),
            hald("黑金", "black_gold.jpg", .style),
            hald("褪色", "fade.jpg", .style),
            hald("高对比", "high_contrast.jpg", .style),
            hald("深秋", "fall.jpg", .style),
            hald("赫本", "hepburn.jpg", .style),
            hald("湿版", "wet_plate.jpg", .style),
            hald("湛蓝", "clear_blue.jpg", .style),
            hald("70年代", "seventies.jpg", .style),
        ]
        return t
    }
}

// MARK: - LUT Info

enum LUTCategory: String, CaseIterable {
    case leica = "徕卡"
    case classic = "经典"
    case film = "胶片"
    case cinematic = "电影感"
    case portrait = "人像"
    case landscape = "风景"
    case blackWhite = "黑白"
    case style = "风格"
    case cubeSeries = "Log系列"
    case custom = "自定义"
}

struct LUTInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let category: LUTCategory
    let isBuiltin: Bool
    let resource: String
    let kind: LUTKind
    var fileURL: URL? = nil
}
