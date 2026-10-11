//
//  AIModelRunner.swift
//  HJD Camera Pro
//
//  CoreML 模型统一运行器：自动选择 CPU/GPU/ANE，分块处理大图，统计耗时，失败回退。
//

import Foundation
import CoreML
import CoreImage
import Vision

final class AIModelRunner {

    static let shared = AIModelRunner()

    /// 分块大小（像素）
    enum TileSize {
        static let small: CGFloat = 512
        static let large: CGFloat = 1024
    }

    private let queue = DispatchQueue(label: "com.hjd.camera.modelRunner", qos: .userInitiated)
    private var modelCache: [String: MLModel] = [:]
    private let cacheLock = NSLock()

    private init() {}

    // MARK: - Execution

    /// 运行指定模型。输入输出均为 CIImage。
    /// - Parameters:
    ///   - modelID: 注册表中的模型 id
    ///   - ciImage: 输入图像
    ///   - completion: 主线程回调，成功返回处理后图像，失败返回 nil
    func run(model modelID: String,
             input ciImage: CIImage,
             completion: @escaping (CIImage?) -> Void) {
        queue.async {
            let result = self._run(modelID: modelID, input: ciImage)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func _run(modelID: String, input: CIImage) -> CIImage? {
        guard let model = loadModel(id: modelID) else {
            return nil // 模型不可用，由上层走传统 fallback
        }

        let config = MLModelConfiguration()
        // 自动选择计算设备：优先 ANE，其次 GPU，最后 CPU
        config.computeUnits = .all

        let startTime = CFAbsoluteTimeGetCurrent()

        // 大图分块处理
        let extent = input.extent
        let tile: CGFloat = extent.width > 2048 ? TileSize.large : TileSize.small

        var outputImages: [CIImage] = []
        let cols = Int(ceil(extent.width / tile))
        let rows = Int(ceil(extent.height / tile))

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * tile
                let y = CGFloat(row) * tile
                let w = min(tile, extent.width - x)
                let h = min(tile, extent.height - y)
                let cropRect = CGRect(x: x, y: y, width: w, height: h)

                guard let tileImage = _processTile(input.cropped(to: cropRect),
                                                  model: model,
                                                  config: config) else {
                    continue
                }
                // 将分块输出贴回原坐标
                let translated = tileImage.transformed(by: CGAffineTransform(translationX: x, y: y))
                outputImages.append(translated)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        recordTiming(modelID: modelID, seconds: elapsed)

        guard !outputImages.isEmpty else { return nil }
        return outputImages.reduce(into: CIImage?.none) { partial, img in
            if let existing = partial {
                return existing.composited(over: img)
            } else {
                return img
            }
        }
    }

    private func _processTile(_ tile: CIImage,
                              model: MLModel,
                              config: MLModelConfiguration) -> CIImage? {
        // 构造 MLPixelBuffer
        let targetSize = modelDescriptionInputSize(model)
        guard let pxBuffer = pixelBuffer(from: tile, size: targetSize) else {
            return nil
        }

        let featureProvider = try? MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pxBuffer)
        ])

        guard let provider = featureProvider else { return nil }

        do {
            let prediction = try model.prediction(from: provider)
            // 假设输出名为 "output"
            if let outputBuf = prediction.featureValue(for: "output")?.imageBufferValue {
                return CIImage(cvPixelBuffer: outputBuf)
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Model Loading

    private func loadModel(id: String) -> MLModel? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = modelCache[id] {
            return cached
        }

        guard let url = bundleURL(for: id) else { return nil }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: config)
            modelCache[id] = model
            return model
        } catch {
            return nil
        }
    }

    private func bundleURL(for id: String) -> URL? {
        // 优先 .mlmodelc
        if let path = Bundle.main.path(forResource: id, ofType: "mlmodelc") {
            return URL(fileURLWithPath: path)
        }
        if let path = Bundle.main.path(forResource: id, ofType: "mlmodel") {
            do {
                return try MLModel.compileModel(at: URL(fileURLWithPath: path))
            } catch {
                return nil
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func modelDescriptionInputSize(_ model: MLModel) -> CGSize {
        let desc = model.modelDescription
        if let inputDesc = desc.inputDescriptionsByName["image"],
           let constraint = inputDesc.imageConstraint {
            return CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
        }
        return CGSize(width: 256, height: 256)
    }

    private func pixelBuffer(from image: CIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: size.width / max(image.extent.width, 1),
            scaleY: size.height / max(image.extent.height, 1)))

        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        ciCtx.render(scaled, to: buffer)
        return buffer
    }

    // MARK: - Timing

    private var timings: [String: [Double]] = [:]

    private func recordTiming(modelID: String, seconds: Double) {
        queue.async {
            self.timings[modelID, default: []].append(seconds)
            if self.timings[modelID]!.count > 20 {
                self.timings[modelID]!.removeFirst()
            }
        }
    }

    /// 返回某模型最近 N 次平均推理耗时（秒）。
    func averageLatency(for modelID: String) -> Double {
        return timings[modelID]?.reduce(0, +) / Double(timings[modelID]?.count ?? 1) ?? 0
    }
}
