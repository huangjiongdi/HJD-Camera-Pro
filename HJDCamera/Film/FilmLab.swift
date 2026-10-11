import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 色彩立方体工具

enum ColorCube {

    /// 从 RGB 变换生成 CIColorCube
    static func make(size: Int = 24,
                     transform: (SIMD3<Float>) -> SIMD3<Float>) -> CIFilter {
        let count = size * size * size * 4
        var data = [Float](repeating: 0, count: count)
        var i = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let inColor = SIMD3<Float>(
                        Float(r)/Float(size-1),
                        Float(g)/Float(size-1),
                        Float(b)/Float(size-1))
                    var out = transform(inColor)
                    out.x = min(1, max(0, out.x))
                    out.y = min(1, max(0, out.y))
                    out.z = min(1, max(0, out.z))
                    data[i] = out.x; data[i+1] = out.y
                    data[i+2] = out.z; data[i+3] = 1
                    i += 4
                }
            }
        }
        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(size)
        filter.cubeData = Data(bytes: &data, count: count * MemoryLayout<Float>.size)
        return filter
    }

    static func apply(_ image: CIImage,
                      transform: @escaping (SIMD3<Float>) -> SIMD3<Float>) -> CIImage {
        let f = make(transform: transform)
        return f.outputImage ?? image
    }
}

// MARK: - 胶片实验室

enum FilmLab {

    static let styles: [String] = [
        "经典自然", "M9经典", "高反差", "单色", "暖调", "街拍",
        "人像", "中画幅", "电影感", "日威", "诺威", "港风",
        "青橙", "复古", "夜景", "富士", "尼康", "索尼",
    ]

    static func apply(styleName: String, to image: CIImage) -> CIImage {
        switch styleName {
        case "经典自然":
            return ColorCube.apply(image) { c in
                SIMD3(c.x^0.95, c.y^0.98, c.z^1.02)
            }
        case "M9经典":
            return ColorCube.apply(image) { c in
                SIMD3(min(1,c.x*1.08), c.y*1.0, c.z*0.92)
            }
        case "高反差":
            return ColorCube.apply(image) { c in
                let f: (Float)->Float = { v in
                    let v = (v - 0.5) * 1.4 + 0.5
                    return min(1, max(0, v))
                }
                return SIMD3(f(c.x), f(c.y), f(c.z))
            }
        case "单色":
            return ColorCube.apply(image) { c in
                let l = c.x*0.299 + c.y*0.587 + c.z*0.114
                return SIMD3(l, l, l)
            }
        case "暖调":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.06, c.y*1.0, c.z*0.92)
            }
        case "街拍":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.04, c.y*1.02, c.z*0.95)
            }
        case "人像":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.05, c.y*1.02, c.z*1.0)
            }
        case "中画幅":
            return ColorCube.apply(image) { c in
                SIMD3(c.x^0.98, c.y^0.98, c.z^1.0)
            }
        case "电影感":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.05, c.y*0.98, c.z*0.9)
            }
        case "日威":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.04, c.y, c.z*0.96)
            }
        case "诺威":
            return ColorCube.apply(image) { c in
                SIMD3(c.x, c.y, c.z*1.03)
            }
        case "港风":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.08, c.y*0.98, c.z*0.9)
            }
        case "青橙":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.08, c.y*1.02, c.z*0.94)
            }
        case "复古":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.07, c.y*1.02, c.z*0.9)
            }
        case "夜景":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.03, c.y*1.03, c.z*1.08)
            }
        case "富士":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.05, c.y*1.02, c.z*0.95)
            }
        case "尼康":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.0, c.y*1.02, c.z*1.04)
            }
        case "索尼":
            return ColorCube.apply(image) { c in
                SIMD3(c.x*1.02, c.y*1.0, c.z*1.05)
            }
        default:
            return image
        }
    }

    private static let ci = CIContext()

    static func render(_ image: CIImage) -> UIImage? {
        guard let cg = ci.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
