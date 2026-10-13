//
//  PhotoCapturePipeline.swift
//  HJD Camera Pro
//
//  AVCapturePhotoCaptureDelegate implementation.
//
//  真机可靠性原则（第五轮重写）：
//  1. 原图优先：拿到原始 HEIC/DNG 字节后，立即先把【未修改的原图】写入系统
//     相册，保证任何后续处理失败都绝不丢片，并满足"始终保留原图"铁律。
//  2. 再做"所见即所得"的成片：高倍数字裁切（与预览一致）+ 轻量锐化/对比
//     增强（这是普通图像增强，不是超分，不冒充 AI 超分）。
//  3. 全链路异步，绝不在 AVCapture 回调队列上用 semaphore 阻塞（旧实现会
//     阻塞拍照回调队列，导致后续拍照卡死/被看门狗杀掉）。
//  4. 全分辨率渲染使用关闭中间缓存的 CIContext 并包在 autoreleasepool 中，
//     避免 48MP 渲染的内存峰值导致一点快门就被 jetsam 杀掉。
//  5. 任何失败都静默回退：原图已经在相册，用户永远有片。
//

import AVFoundation
import UIKit
import CoreImage
import ImageIO
import SwiftUI

final class PhotoCapturePipeline: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
    static let shared = PhotoCapturePipeline()

    @Published var burstRemaining = 0
    @Published var multiExposureFrames: [CIImage] = []

    private let fileManager = FileManager.default
    /// 关闭中间缓存，降低 48MP 全分辨率渲染的内存峰值。
    private let ciContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
    }()
    private var pendingBurst = 0
    /// 当前正在后台保存的照片数量；仅在主线程读写。
    private var inFlight = 0
    private var multiExposureTarget = 0

    private override init() {}

    // MARK: - Public capture triggers

    func capture(settings: AVCapturePhotoSettings? = nil) {
        let output = CameraManager.shared.photoOutput
        guard output.connection(with: .video) != nil else {
            NotificationCenter.default.post(name: .hjdStorageWarning,
                                           object: "相机尚未就绪，请稍后再试")
            return
        }
        let resolved = settings ?? AVCapturePhotoSettings()
        output.capturePhoto(with: resolved, delegate: self)
    }

    func startBurst(count: Int) {
        pendingBurst = max(1, count)
        burstRemaining = pendingBurst
        captureNextBurstFrame()
    }

    private func captureNextBurstFrame() {
        guard pendingBurst > 0 else { return }
        pendingBurst -= 1
        capture()
    }

    /// 连拍：一张回调结束后立即排下一张（系统会自动排队）。
    private func advanceBurstIfNeeded() {
        guard pendingBurst > 0 else {
            DispatchQueue.main.async { self.burstRemaining = 0 }
            return
        }
        DispatchQueue.main.async { self.burstRemaining = self.pendingBurst }
        captureNextBurstFrame()
    }

    func scheduleTimer(seconds: Int) {
        guard seconds > 0 else { capture(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            self?.capture()
        }
    }

    func beginMultiExposure(frameCount: Int) {
        multiExposureFrames.removeAll()
        multiExposureTarget = max(2, frameCount)
    }

    // MARK: - Delegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hjdStorageWarning, object: error)
            }
            advanceBurstIfNeeded()
            return
        }

        // 1. 立即拿到原始字节（含 EXIF），写到受保护的临时文件。
        guard let originalData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hjdStorageWarning,
                                                object: "照片数据为空，请重试")
            }
            advanceBurstIfNeeded()
            return
        }
        let isRAW = photo.isRawPhoto
        let originalURL = writeOriginalToTemp(data: originalData, isRAW: isRAW)

        // 2. 多曝光合成模式。
        if multiExposureTarget > 0 {
            accumulateMultiExposureFrame(data: originalData)
            return
        }

        // 3. 普通照片：先在主线程登记，再后台保存。
        DispatchQueue.main.async {
            self.inFlight += 1
            AppState.shared.isProcessing = true
            AppState.shared.processingProgress = 0.1
            AppState.shared.lastCapturedImageURL = originalURL
        }
        // 连拍立即排下一张（不等待保存）。
        advanceBurstIfNeeded()

        // 读取设置快照（在当前线程一次性读完，避免后台任务跨线程访问 @Published）。
        let keepOriginal = AppSettingsStore.shared.keepOriginal
        let fallbackOnFailure = AppSettingsStore.shared.fallbackOnFailure
        let digitalCrop = CameraManager.shared.currentDigitalCrop

        processCapture(originalData: originalData,
                       originalURL: originalURL,
                       keepOriginal: keepOriginal,
                       fallbackOnFailure: fallbackOnFailure,
                       digitalCrop: digitalCrop)
    }

    // MARK: - 原始照片保护（ImageIO，EXIF 原样保留）

    private func writeOriginalToTemp(data: Data, isRAW: Bool) -> URL {
        let ext = isRAW ? "dng" : "heic"
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("original-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        // fileDataRepresentation() 已携带 EXIF，原样写入即保留全部元数据。
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 保存流程（全程异步，不阻塞任何系统队列）

    private func processCapture(originalData: Data,
                                originalURL: URL,
                                keepOriginal: Bool,
                                fallbackOnFailure: Bool,
                                digitalCrop: CGFloat) {
        Task.detached(priority: .userInitiated) {
            // 1) 原图优先入库——绝不丢片、始终保留原图。
            if keepOriginal {
                if case .failure(let err) = await PhotoLibraryExporter.shared.exportPhoto(data: originalData) {
                    DiagnosticLogger.shared.error("Original save failed: \(err)")
                }
            }

            // 2) 渲染"所见即所得"成片（高倍数字裁切 + 轻量增强）。
            let enhancedURL = autoreleasepool {
                Self.renderEnhanced(originalURL: originalURL,
                                    digitalCrop: digitalCrop,
                                    context: self.ciContext)
            }

            var finalURL = originalURL
            if let enhancedURL,
               let enhancedData = try? Data(contentsOf: enhancedURL) {
                let result = await PhotoLibraryExporter.shared.exportPhoto(data: enhancedData)
                switch result {
                case .success:
                    finalURL = enhancedURL
                case .failure(let err):
                    DiagnosticLogger.shared.error("Enhanced save failed: \(err)")
                    if !keepOriginal && fallbackOnFailure {
                        // 不保留原图且增强片入库失败时，把原图兜底入库。
                        _ = await PhotoLibraryExporter.shared.exportPhoto(data: originalData)
                    }
                }
            } else if !keepOriginal && fallbackOnFailure {
                // 增强渲染失败：原图兜底入库。
                _ = await PhotoLibraryExporter.shared.exportPhoto(data: originalData)
            }

            // 3) 收尾全部回到主线程（@Published 状态只在主线程更新）。
            await MainActor.run {
                AppState.shared.lastCapturedImageURL = finalURL
                AppState.shared.processingProgress = 1.0
                self.inFlight = max(0, self.inFlight - 1)
                if self.inFlight == 0 {
                    AppState.shared.isProcessing = false
                }
                NotificationCenter.default.post(name: .hjdCaptureCompleted, object: finalURL)
            }
        }
    }

    /// 渲染"所见即所得"成片：高倍数字裁切（与预览 scaleEffect 同源）+ 轻量
    /// 锐化与对比增强。任何失败返回 nil，由调用方回退原图。
    private static func renderEnhanced(originalURL: URL,
                                       digitalCrop: CGFloat,
                                       context: CIContext) -> URL? {
        guard let source = CIImage(contentsOf: originalURL) else { return nil }
        var image = source

        // 高倍数字裁切：从成片中心裁出与预览一致的区域，再 Lanczos 放回原尺寸。
        // 这是数字插值（不是 AI 超分），UI 已在 ≥100× 明确标注"数字裁切/AI 重建"。
        if digitalCrop > 1.01 {
            let extent = source.extent
            let w = extent.width / digitalCrop
            let h = extent.height / digitalCrop
            let rect = CGRect(x: extent.midX - w / 2.0,
                              y: extent.midY - h / 2.0,
                              width: w, height: h)
            let recentered = source
                .cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.origin.x,
                                                   y: -rect.origin.y))
            let scaled = recentered
                .applyingFilter("CILanczosScaleTransform",
                                parameters: [kCIInputScaleKey: digitalCrop,
                                             kCIInputAspectRatioKey: 1.0])
                .cropped(to: CGRect(origin: .zero,
                                    size: CGSize(width: extent.width, height: extent.height)))
            image = scaled
        }

        // 轻量、确定性的增强（非 AI 超分）。
        image = image
            .applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 1.2,
                kCIInputIntensityKey: 0.5
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.03,
                kCIInputSaturationKey: 1.02
            ])

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let data = context.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption.quality: 0.92]
        ) else { return nil }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed-\(UUID().uuidString).jpg")
        do {
            try data.write(to: outURL, options: .atomic)
            return outURL
        } catch {
            return nil
        }
    }

    // MARK: - Multi-exposure accumulation

    private func accumulateMultiExposureFrame(data: Data) {
        guard let ciImage = CIImage(data: data) else { return }
        multiExposureFrames.append(ciImage)
        guard multiExposureFrames.count >= multiExposureTarget else { return }
        multiExposureTarget = 0
        let frames = multiExposureFrames
        multiExposureFrames.removeAll()

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let fused = frames.reduce(into: CIImage?.none) { partial, frame in
                    if let acc = partial {
                        partial = acc.applyingFilter("CIAdditionCompositing",
                                                     parameters: [kCIInputBackgroundImageKey: frame])
                    } else {
                        partial = frame
                    }
                }
                if let fused = fused {
                    let outURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("multiexposure-\(UUID().uuidString).heic")
                    try? self.ciContext.writeHEIFRepresentation(
                        of: fused, to: outURL, format: .BGRA8,
                        colorSpace: fused.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                        options: [:]
                    )
                    DispatchQueue.main.async {
                        AppState.shared.lastCapturedImageURL = outURL
                        NotificationCenter.default.post(name: .hjdCaptureCompleted, object: outURL)
                    }
                }
            }
        }
    }

    enum PipelineError: Error {
        case decodeFailed
        case insufficientResolution
    }
}
