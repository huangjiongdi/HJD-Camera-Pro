//
//  AIModelRunner.swift
//  HJD Camera Pro
//
//  CoreML 模型统一运行器：自动选择 CPU/GPU/ANE，按模型真实输入尺寸分块，
//  按真实放大倍数把输出贴回最终画布，统计耗时，失败回退。
//

import Foundation
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins

final class AIModelRunner {

    static let shared = AIModelRunner()

    private let queue = DispatchQueue(label: "com.hjd.camera.modelRunner", qos: .userInitiated)
    private var modelCache: [String: MLModel] = [:]
    private let cacheLock = NSLock()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    // MARK: - Public API

    /// 运行指定模型。输入输出均为 CIImage。
    /// - Parameters:
    ///   - modelID: 注册表 id 或逻辑用途别名
    ///   - ciImage: 输入图像
    ///   - completion: 主线程回调，成功返回处理后图像，失败返回 nil
    func run(model modelID: String,
             input ciImage: CIImage,
             completion: @escaping (CIImage?) -> Void) {
        queue.async {
            let result = self._run(requested: modelID, input: ciImage)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    // MARK: - Core

    private func _run(requested: String, input: CIImage) -> CIImage? {
        guard let id = AIModelRegistry.shared.resolveModelID(requested),
              let model = loadModel(id: id) else {
            return nil // 模型不可用，由上层走传统 fallback
        }

        // 发现输入/输出
        guard let inputName = firstImageInputName(model),
              let outputName = firstOutputName(model) else {
            return nil
        }
        let inputTile = inputTileSize(model, inputName: inputName, image: input)

        // 归一化到原点 0,0
        let extent = input.extent
        let normalized = input.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        let inW = extent.width
        let inH = extent.height
        let tileW = min(inputTile.width, inW)
        let tileH = min(inputTile.height, inH)

        var placedTiles: [CIImage] = []
        var scale: CGFloat = 1.0
        var scaleResolved = false

        var y0: CGFloat = 0
        while y0 < inH {
            var x0: CGFloat = 0
            let th = min(tileH, inH - y0)
            while x0 < inW {
                let tw = min(tileW, inW - x0)

                if let tileBuffer = makeTileBuffer(width: Int(tileW), height: Int(tileH)),
                   let outImage = processTile(
                        model: model,
                        inputName: inputName,
                        outputName: outputName,
                        normalized: normalized,
                        sourceRect: CGRect(x: x0, y: y0, width: tw, height: th),
                        tileBuffer: tileBuffer) {

                    let outExtent = outImage.extent
                    if !scaleResolved {
                        scale = outExtent.width / tileW
                        scaleResolved = true
                    }
                    let validW = scale * tw
                    let validH = scale * th
                    let valid = outImage.cropped(to: CGRect(x: 0, y: 0,
                                                            width: validW, height: validH))
                        .transformed(by: CGAffineTransform(
                            translationX: scale * x0, y: scale * y0))
                    placedTiles.append(valid)
                }

                x0 += tileW
            }
            y0 += tileH
        }

        guard !placedTiles.isEmpty else { return nil }

        // 合成全部瓦片
        let canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0,
                                width: scale * inW, height: scale * inH))
        let assembled = placedTiles.reduce(canvas) { base, tile in
            tile.composited(over: base)
        }
        return assembled.cropped(to: CGRect(x: 0, y: 0,
                                            width: scale * inW,
                                            height: scale * inH))
    }

    /// 处理单个瓦片：渲染源区域 → 预测 → 输出图像。
    private func processTile(model: MLModel,
                             inputName: String,
                             outputName: String,
                             normalized: CIImage,
                             sourceRect: CGRect,
                             tileBuffer: CVPixelBuffer) -> CIImage? {
        let sub = normalized.cropped(to: sourceRect)
        ciContext.render(sub,
                         to: tileBuffer,
                         bounds: CGRect(x: 0, y: 0,
                                        width: sourceRect.width,
                                        height: sourceRect.height),
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: tileBuffer)
        ]),
              let prediction = try? model.prediction(from: provider),
              let feature = prediction.featureValue(for: outputName) else {
            return nil
        }

        // 图像输出
        if let buffer = feature.imageBufferValue {
            return CIImage(cvPixelBuffer: buffer)
        }
        // 多维数组输出（兜底）
        if let multiArray = feature.multiArrayValue {
            return CIImageHelper.image(from: multiArray, context: ciContext)
        }
        return nil
    }

    // MARK: - I/O discovery

    private func firstImageInputName(_ model: MLModel) -> String? {
        model.modelDescription.inputDescriptionsByName
            .first { $0.value.type == .image }?.key
    }

    private func firstOutputName(_ model: MLModel) -> String? {
        model.modelDescription.outputDescriptionsByName.first?.key
    }

    /// 模型输入要求的瓦片尺寸；未约束时用整图尺寸。
    private func inputTileSize(_ model: MLModel,
                               inputName: String,
                               image: CIImage) -> CGSize {
        if let constraint = model.modelDescription
            .inputDescriptionsByName[inputName]?.imageConstraint,
           constraint.pixelsWide > 0, constraint.pixelsHigh > 0 {
            return CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
        }
        // 未约束：整图单瓦片（限制到 1024 避免超大）
        let w = min(image.extent.width, 1024)
        let h = min(image.extent.height, 1024)
        return CGSize(width: w, height: h)
    }

    // MARK: - Model loading

    private func loadModel(id: String) -> MLModel? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = modelCache[id] { return cached }

        guard let url = Bundle.main.url(forResource: id, withExtension: "mlmodelc") else {
            return nil
        }
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

    // MARK: - Tile buffers

    private func makeTileBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &pb)
        guard status == kCVReturnSuccess else { return nil }
        return pb
    }
}

// MARK: - MLMultiArray -> CIImage (best effort)

enum CIImageHelper {
    static func image(from array: MLMultiArray, context: CIContext) -> CIImage? {
        // 支持 [1,C,H,W] / [C,H,W]，C 通常为 3。
        let shape = array.shape.map { $0.intValue }
        guard let (c, h, w) = dims(shape) else { return nil }

        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pb)
        guard let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        let isFloat16 = array.dataType == .float16
        let isFloat32 = array.dataType == .float32
        guard isFloat16 || isFloat32 else { return nil }

        for yy in 0..<h {
            let row = base.advanced(by: yy * bytesPerRow)
            let px = row.assumingMemoryBound(to: UInt8.self)
            for xx in 0..<w {
                let r = value(array, c, h, w, channel: 0, y: yy, x: xx, fp16: isFloat16)
                let g = value(array, c, h, w, channel: 1, y: yy, x: xx, fp16: isFloat16)
                let b = value(array, c, h, w, channel: 2, y: yy, x: xx, fp16: isFloat16)
                px[xx * 4 + 0] = UInt8(clamping: Int(max(0, min(1, b)) * 255))
                px[xx * 4 + 1] = UInt8(clamping: Int(max(0, min(1, g)) * 255))
                px[xx * 4 + 2] = UInt8(clamping: Int(max(0, min(1, r)) * 255))
                px[xx * 4 + 3] = 255
            }
        }
        return CIImage(cvPixelBuffer: buffer)
    }

    private static func dims(_ shape: [Int]) -> (Int, Int, Int)? {
        if shape.count == 4 {
            return (shape[1], shape[2], shape[3])
        }
        if shape.count == 3 {
            return (shape[0], shape[1], shape[2])
        }
        return nil
    }

    private static func value(_ a: MLMultiArray,
                              _ c: Int, _ h: Int, _ w: Int,
                              channel: Int, y: Int, x: Int,
                              fp16: Bool) -> Float {
        if fp16 {
            // Float16 存储
            let idx = (channel * h + y) * w + x
            let pointer = a.dataPointer.assumingMemoryBound(to: UInt16.self)
            return Float(Float16(bitPattern: pointer[idx]))
        } else {
            let pointer = a.dataPointer.assumingMemoryBound(to: Float.self)
            let idx = (channel * h + y) * w + x
            return pointer[idx]
        }
    }
}
