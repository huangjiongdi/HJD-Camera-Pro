import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - LUT 管理（.cube 内嵌 / 导入）

final class LUTManager {

    static let shared = LUTManager()
    private init() {}

    private var lutCache: [String: CIFilter] = [:]
    private let lock = NSLock()

    /// 内置 LUT 名称（Resources/LUT）
    func availableLUTs() -> [String] {
        var names: [String] = []
        if let urls = Bundle.main.urls(forResourcesWithExtension: "cube",
                                      subdirectory: nil) {
            names = urls.map { $0.deletingPathExtension().lastPathComponent }
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: "cube",
                                      subdirectory: "LUT") {
            names += urls.map { $0.deletingPathExtension().lastPathComponent }
        }
        return Array(Set(names)).sorted()
    }

    /// 应用内置 LUT 到 UIImage
    func applyLUT(named name: String, to image: UIImage,
                  intensity: Double = 1.0) -> UIImage? {
        guard let ci = CIImage(image: image),
              let filter = loadLUT(named: name) else { return nil }
        let filtered = applyIntensity(filter: filter, source: ci, intensity: intensity)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(filtered, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 应用 .cube 数据（来自文件）
    func applyCubeData(url: URL, to image: CIImage) -> CIImage? {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let filter = parseCube(data) else { return nil }
        return filter.outputImage
    }

    // MARK: 加载

    private func loadLUT(named name: String) -> CIFilter? {
        lock.lock(); defer { lock.unlock() }
        if let f = lutCache[name] { return f }

        var url = Bundle.main.url(forResource: name, withExtension: "cube")
        if url == nil {
            url = Bundle.main.url(forResource: name, withExtension: "cube",
                                  subdirectory: "LUT")
        }
        guard let u = url,
              let text = try? String(contentsOf: u, encoding: .utf8),
              let filter = parseCube(text) else { return nil }
        lutCache[name] = filter
        return filter
    }

    // MARK: 解析 .cube

    private func parseCube(_ text: String) -> CIFilter? {
        var dimension = 0
        var rgb: [Float] = []
        let lines = text.components(separatedBy: .newlines)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            if line.uppercased().hasPrefix("LUT_3D_SIZE") {
                let parts = line.components(separatedBy: .whitespaces)
                dimension = Int(parts.last ?? "") ?? 0
                continue
            }
            if line.uppercased().hasPrefix("LUT_") { continue }
            let vals = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }.compactMap { Float($0) }
            if vals.count >= 3 {
                rgb += vals.prefix(3)
            }
        }
        guard dimension > 0, rgb.count == dimension*dimension*dimension*3 else {
            return nil
        }
        // 转 RGBA（CIColorCube 数据，红最快）
        var data = [Float](repeating: 0, count: dimension*dimension*dimension*4)
        var i = 0
        for k in 0..<dimension*dimension*dimension {
            data[i]   = rgb[k*3]
            data[i+1] = rgb[k*3+1]
            data[i+2] = rgb[k*3+2]
            data[i+3] = 1
            i += 4
        }
        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(dimension)
        filter.cubeData = Data(bytes: &data,
                               count: data.count * MemoryLayout<Float>.size)
        return filter
    }

    // MARK: 强度混合

    private func applyIntensity(filter: CIFilter, source: CIImage,
                                intensity: Double) -> CIImage {
        guard intensity < 1.0 else {
            return filter.outputImage ?? source
        }
        if let out = filter.outputImage {
            return source.applyingFilter("CILerp", parameters: [
                "inputTarget": out,
                "inputAmount": intensity
            ])
        }
        return source
    }
}
