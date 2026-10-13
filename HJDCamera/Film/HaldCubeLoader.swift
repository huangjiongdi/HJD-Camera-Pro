//
//  HaldCubeLoader.swift
//  HJD Camera Pro
//
//  极影相机 HALD CLUT 图（512×512 = 64³）→ CIColorCube 立方体数据。
//
//  HALD 排布（已在 Windows 端用 709lut.png 逐像素验证）：
//    整张图是 8×8 个 64×64 方块，方块号 b（蓝通道）：
//      tileX = b % 8, tileY = b / 8
//    方块内 x = r（红最快）, y = g（绿次之）。
//    像素坐标：x = r + 64 * (b % 8)
//              y = g + 64 * (b / 8)
//    CIColorCube 的 cubeData 顺序：idx = r + N*g + N*N*b（红最快、绿次之、蓝最慢），
//    与上述排布逐通道对应。
//

import UIKit
import CoreImage
import simd

enum HaldCubeLoader {
    /// 缓存：资源名 -> 满强度 RGBA Float32 cubeData（4MB/个），只缓存当前/近期 LUT。
    private static var cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 8
        return c
    }()

    /// 读取 bundle 中 Resources/LUT/Hald/<name> 的 512×512 HALD 图，
    /// 返回 64³ RGBA Float32 立方体数据。失败返回 nil。
    static func cubeData(resourceName: String) -> Data? {
        if let cached = cache.object(forKey: resourceName as NSString) {
            return cached as Data
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: nil,
                                       subdirectory: "LUT/Hald")
                ?? Bundle.main.url(forResource: resourceName, withExtension: nil) else {
            DiagnosticLogger.shared.log("Hald LUT missing: \(resourceName)", category: .app)
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            DiagnosticLogger.shared.log("Hald LUT decode failed: \(resourceName)", category: .app)
            return nil
        }
        let n = 64
        let side = 512
        let bytesPerRow = side * 4
        guard let bitmap = calloc(side * side * 4, 1) else { return nil }
        defer { free(bitmap) }

        guard let context = CGContext(
            data: bitmap,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let pixels = bitmap.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var cube = Data(count: n * n * n * 16)
        let count = n * n * n
        cube.withUnsafeMutableBytes { raw in
            guard let out = raw.bindMemory(to: SIMD4<Float>.self).baseAddress else { return }
            for b in 0..<n {
                let tileX = b % 8
                let tileY = b / 8
                for g in 0..<n {
                    for r in 0..<n {
                        // CGContext 数据行从下往上：翻转 y。
                        let px = r + n * tileX
                        let py = g + n * tileY
                        let srcRow = (side - 1 - py)
                        let src = (srcRow * bytesPerRow) + px * 4
                        let rr = Float(pixels[src]) / 255.0
                        let gg = Float(pixels[src + 1]) / 255.0
                        let bb = Float(pixels[src + 2]) / 255.0
                        let idx = r + n * g + n * n * b
                        out[idx] = SIMD4<Float>(rr, gg, bb, 1.0)
                    }
                }
            }
        }
        cache.setObject(cube as NSData, forKey: resourceName as NSString)
        return cube
    }

    /// 把满强度立方体按强度 0...1 与 identity 混合，返回新的 cubeData。
    /// 强度直接烘焙进立方体，避免在成片阶段再做一次全分辨率 mask 混合。
    static func bakeIntensity(_ cube: Data, dimension n: Int, intensity: Float) -> Data {
        guard intensity < 1.0 else { return cube }
        var out = Data(count: cube.count)
        cube.withUnsafeBytes { srcRaw in
            guard let src = srcRaw.bindMemory(to: SIMD4<Float>.self).baseAddress else { return }
            out.withUnsafeMutableBytes { dstRaw in
                guard let dst = dstRaw.bindMemory(to: SIMD4<Float>.self).baseAddress else { return }
                for b in 0..<n {
                    for g in 0..<n {
                        for r in 0..<n {
                            let idx = r + n * g + n * n * b
                            let mapped = src[idx]
                            let identity = SIMD4<Float>(
                                Float(r) / Float(n - 1),
                                Float(g) / Float(n - 1),
                                Float(b) / Float(n - 1),
                                1.0
                            )
                            dst[idx] = identity + (mapped - identity) * intensity
                        }
                    }
                }
            }
        }
        return out
    }
}
