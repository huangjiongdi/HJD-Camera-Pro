import Foundation
import CoreML
import CoreImage
import CoreVideo

// MARK: - 内嵌模型中枢
//
// 所有模型均作为 App Bundle 资源随软件一起交付，
// 运行时直接从 Bundle.main 加载（无任何网络下载 / 模型商店）。
final class AIModelHub {

    static let shared = AIModelHub()
    private init() {}

    /// 内置模型标识
    enum ModelName: String {
        case realesrgan      = "realesrgan512"
        case realesrganAnime = "realesrganAnime512"
        case gfpgan          = "gfpgan"
        case mprnet          = "MPRNetDenoising"
        case depthPro        = "DepthPro"
        case gfpganCoreML    = "GFPGAN"
    }

    private var cache: [String: MLModel] = [:]
    private let lock = NSLock()

    // MARK: 加载模型（从 Bundle 编译后的 .mlmodelc）

    private func load(_ name: String) -> MLModel? {
        lock.lock(); defer { lock.unlock() }
        if let m = cache[name] { return m }

        let config = MLModelConfiguration()
        config.computeUnits = .all    // 优先 Neural Engine

        // .mlmodel / .mlpackage 编译后均为 .mlmodelc，
        // 资源位于 Models 子目录（同步组保留目录结构）
        var url = Bundle.main.url(forResource: name, withExtension: "mlmodelc",
                                  subdirectory: "Models")
        if url == nil {
            url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
        }
        if url == nil {
            // 兜底：枚举所有 bundle 资源
            if let found = Bundle.main.urls(forResourcesWithExtension: "mlmodelc",
                                            subdirectory: nil)?
                .first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
                url = found
            }
        }
        guard let modelURL = url else {
            print("[HJD] bundled model not found:", name)
            return nil
        }
        do {
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            cache[name] = model
            return model
        } catch {
            print("[HJD] load model failed:", name, error)
            return nil
        }
    }

    // MARK: 同步图像推理

    /// 对输入 CVPixelBuffer 执行模型，返回输出图像 CVPixelBuffer
    func predictImage(model: ModelName,
                      inputName: String,
                      outputName: String,
                      input: CVPixelBuffer) -> CVPixelBuffer? {
        guard let ml = load(model.rawValue) else { return nil }

        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: input)
        ])
        guard let provider else { return nil }
        do {
            let result = try ml.prediction(from: provider)
            return result.featureValue(for: outputName)?.imageBufferValue
        } catch {
            print("[HJD] prediction failed:", model, error)
            return nil
        }
    }

    /// 是否存在（可选模型，缺失则降级）
    func has(_ model: ModelName) -> Bool {
        return load(model.rawValue) != nil
    }
}

// MARK: - CVPixelBuffer 工具

enum PixelBufferFactory {

    static func make(width: Int, height: Int,
                     pixelFormat: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            pixelFormat, attrs as CFDictionary, &pb)
        return pb
    }

    /// 从 CIImage 渲染到指定尺寸的 CVPixelBuffer
    static func render(_ ci: CIImage, width: Int, height: Int,
                       context: CIContext) -> CVPixelBuffer? {
        guard let pb = make(width: width, height: height) else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / ci.extent.width,
            y: CGFloat(height) / ci.extent.height))
        context.render(scaled, to: pb)
        return pb
    }
}
