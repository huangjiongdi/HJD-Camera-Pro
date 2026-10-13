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
import UniformTypeIdentifiers
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

    // MARK: - 星轨/光轨/多曝光序列
    private let trailLock = NSLock()
    private var trailState: TrailState?

    private final class TrailState {
        var target: Int
        var count: Int = 0
        var accumulator: CIImage?
        let lighten: Bool
        let tap: Int
        init(target: Int, lighten: Bool, tap: Int) {
            self.target = target
            self.lighten = lighten
            self.tap = tap
        }
    }

    private override init() {}

    // MARK: - 星轨 / 光轨 / 多曝光

    var isTrailActive: Bool {
        trailLock.lock(); defer { trailLock.unlock() }
        return trailState != nil
    }

    /// 开始多帧序列：lighten=true 取每像素最亮（星轨/光轨），false 叠加（多曝光）。
    func beginTrail(frameCount: Int, lighten: Bool, tap: Int) {
        trailLock.lock()
        trailState = TrailState(target: max(2, frameCount), lighten: lighten, tap: tap)
        trailLock.unlock()
        DispatchQueue.main.async {
            AppState.shared.isProcessing = true
            AppState.shared.processingProgress = 0.03
        }
        ShutterTrace.mark(tap, "多帧序列开始",
                          extra: "帧数=\(frameCount) 混合=\(lighten ? "lighten" : "add")")
        captureTrailFrame()
    }

    private func captureTrailFrame() {
        let output = CameraManager.shared.photoOutput
        let tap = ShutterTrace.lastTap
        guard output.connection(with: .video) != nil else {
            ShutterTrace.mark(tap, "序列拍摄中止：无连接")
            abortTrail(message: "相机尚未就绪")
            return
        }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        // 序列帧优先速度，保证连排间隔短、星点/光斑不断。
        if AVCapturePhotoOutput.QualityPrioritization.speed.rawValue
            <= output.maxPhotoQualityPrioritization.rawValue {
            settings.photoQualityPrioritization = .speed
        } else {
            settings.photoQualityPrioritization = .balanced
        }
        ShutterTrace.mark(tap, "序列帧 capturePhoto 提交")
        output.capturePhoto(with: settings, delegate: self)
    }

    private func handleTrailFrame(data: Data, tap: Int) {
        trailLock.lock()
        guard let state = trailState else {
            trailLock.unlock()
            return
        }
        // 解码并方向转正（不做 LUT/AI，保持夜空暗场）。
        let frame: CIImage? = {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4032
            ] as [CFString: Any] as CFDictionary
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else { return nil }
            return CIImage(cgImage: cg)
        }()

        if let f = frame {
            if let acc = state.accumulator {
                state.accumulator = state.lighten
                    ? f.applyingFilter("CILightenBlendMode", parameters: [kCIInputBackgroundImageKey: acc])
                    : f.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: acc])
            } else {
                state.accumulator = f
            }
            state.count += 1
        }

        let done = state.count >= state.target
        let progress = Double(state.count) / Double(state.target)
        if done { trailState = nil }
        trailLock.unlock()

        DispatchQueue.main.async {
            AppState.shared.processingProgress = 0.1 + 0.8 * progress
        }

        if done {
            ShutterTrace.mark(tap, "多帧序列融合中", extra: "帧数=\(state.count)")
            finalizeTrail(state: state)
        } else {
            // 立即排下一张。
            captureTrailFrame()
        }
    }

    private func abortTrail(message: String) {
        trailLock.lock()
        trailState = nil
        trailLock.unlock()
        DispatchQueue.main.async {
            AppState.shared.isProcessing = false
            AppState.shared.processingProgress = 0
            NotificationCenter.default.post(name: .hjdStorageWarning, object: message)
        }
    }

    private func finalizeTrail(state: TrailState) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                guard let fused = state.accumulator,
                      let cg = self.ciContext.createCGImage(fused, from: fused.extent) else {
                    ShutterTrace.mark(state.tap, "多帧序列融合失败：无图像")
                    DispatchQueue.main.async {
                        AppState.shared.isProcessing = false
                        AppState.shared.processingProgress = 0
                        NotificationCenter.default.post(name: .hjdStorageWarning,
                                                        object: "多帧合成失败，请重试")
                    }
                    return
                }
                let image = UIImage(cgImage: cg)
                guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
                    DispatchQueue.main.async {
                        AppState.shared.isProcessing = false
                        NotificationCenter.default.post(name: .hjdStorageWarning,
                                                        object: "多帧合成失败，请重试")
                    }
                    return
                }
                let outURL = self.fileManager.temporaryDirectory
                    .appendingPathComponent("trail-\(UUID().uuidString).jpg")
                try? jpeg.write(to: outURL, options: .atomic)

                DispatchQueue.main.async {
                    AppState.shared.lastCapturedImageURL = outURL
                    AppState.shared.processingProgress = 1.0
                    AppState.shared.isProcessing = false
                }

                Task {
                    let result = await PhotoLibraryExporter.shared.exportPhoto(data: jpeg)
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            ShutterTrace.mark(state.tap, "多帧序列完成，已保存相册")
                            NotificationCenter.default.post(name: .hjdCaptureCompleted, object: outURL)
                            HapticEngine.shared.trigger(.exportComplete)
                        case .failure(let e):
                            ShutterTrace.mark(state.tap, "多帧序列保存失败", extra: "\(e)")
                            NotificationCenter.default.post(name: .hjdStorageWarning, object: e.description)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Public capture triggers

    func capture(settings: AVCapturePhotoSettings? = nil) {
        let output = CameraManager.shared.photoOutput
        let tap = ShutterTrace.lastTap
        guard output.connection(with: .video) != nil else {
            ShutterTrace.mark(tap, "连拍/定时拍照中止：无连接")
            NotificationCenter.default.post(name: .hjdStorageWarning,
                                           object: "相机尚未就绪，请稍后再试")
            return
        }
        let resolved: AVCapturePhotoSettings
        if let settings = settings {
            resolved = settings
        } else {
            // 连拍/定时路径同样要做闪光灯白名单，避免同样的 NSException。
            let normal = AVCapturePhotoSettings()
            let wanted = AppState.shared.flashMode
            if Set(output.supportedFlashModes).contains(wanted) {
                normal.flashMode = wanted
            } else {
                normal.flashMode = .off
            }
            normal.photoQualityPrioritization = .balanced
            resolved = normal
        }
        ShutterTrace.mark(tap, "连拍/定时 capturePhoto 提交")
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

    /// 系统已开始拍照（曝光设置就绪）。
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let tap = ShutterTrace.lastTap
        ShutterTrace.mark(tap, "delegate willBeginCapture",
                          extra: "uniqueID=\(resolvedSettings.uniqueID) 尺寸=\(resolvedSettings.photoDimensions.width)x\(resolvedSettings.photoDimensions.height)")
    }

    /// 拍照即将发生（快门动画时机）。
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        ShutterTrace.mark(ShutterTrace.lastTap, "delegate willCapturePhoto（快门动画）")
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let tap = ShutterTrace.lastTap
        if let error = error {
            ShutterTrace.mark(tap, "delegate didFinishProcessingPhoto 报错",
                              extra: "\(error.localizedDescription)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hjdStorageWarning, object: error)
            }
            advanceBurstIfNeeded()
            return
        }

        // 1. 立即拿到原始字节（含 EXIF），写到受保护的临时文件。
        ShutterTrace.mark(tap, "delegate 收到照片，开始读取原始字节")
        guard let originalData = photo.fileDataRepresentation() else {
            ShutterTrace.mark(tap, "fileDataRepresentation 返回 nil（无照片数据）")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hjdStorageWarning,
                                                object: "照片数据为空，请重试")
            }
            advanceBurstIfNeeded()
            return
        }
        let isRAW = photo.isRawPhoto
        ShutterTrace.mark(tap, "原始字节就绪",
                          extra: "RAW=\(isRAW) 字节=\(originalData.count)")
        let originalURL = writeOriginalToTemp(data: originalData, isRAW: isRAW)
        ShutterTrace.mark(tap, "原始临时文件已写", extra: originalURL.lastPathComponent)

        // 2. 星轨/光轨/多曝光序列：单帧不入相册，直接进入融合链路。
        if isTrailActive {
            ShutterTrace.mark(tap, "序列帧到达")
            handleTrailFrame(data: originalData, tap: tap)
            return
        }

        // 2b. 旧多曝光骨架（保留兼容，实际走 beginTrail）。
        if multiExposureTarget > 0 {
            ShutterTrace.mark(tap, "进入多曝光合成")
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
        let lutName = LUTManager.shared.activeLUTName
        let lutIntensity = LUTManager.shared.intensity
        let sharpness = AppState.shared.proSettings.sharpness
        ShutterTrace.mark(tap, "开始后台保存",
                          extra: "保留原图=\(keepOriginal) 数字裁切=\(String(format: "%.3f", Double(digitalCrop))) LUT=\(lutName)")

        processCapture(originalData: originalData,
                       originalURL: originalURL,
                       keepOriginal: keepOriginal,
                       fallbackOnFailure: fallbackOnFailure,
                       digitalCrop: digitalCrop,
                       lutName: lutName,
                       lutIntensity: lutIntensity,
                       sharpness: sharpness,
                       tap: tap)
    }

    /// 拍照回调链全部结束（无论成败）。
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        let tap = ShutterTrace.lastTap
        if let error = error {
            ShutterTrace.mark(tap, "delegate didFinishCapture 报错",
                              extra: "\(error.localizedDescription)")
        } else {
            ShutterTrace.mark(tap, "delegate didFinishCapture 成功（系统回调链完成）")
        }
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
                                digitalCrop: CGFloat,
                                lutName: String,
                                lutIntensity: Double,
                                sharpness: Double,
                                tap: Int) {
        Task.detached(priority: .userInitiated) {
            // 1) 原图优先入库——绝不丢片、始终保留原图。
            if keepOriginal {
                ShutterTrace.mark(tap, "原图写入相册开始")
                let originalResult = await PhotoLibraryExporter.shared.exportPhoto(data: originalData)
                if case .failure(let err) = originalResult {
                    DiagnosticLogger.shared.error("Original save failed: \(err)")
                    ShutterTrace.mark(tap, "原图写入相册失败", extra: "\(err)")
                } else {
                    ShutterTrace.mark(tap, "原图已写入相册")
                }
            }

            // 2) 渲染"所见即所得"成片（高倍数字裁切 + 轻量增强 + 选中的 LUT）。
            ShutterTrace.mark(tap, "开始渲染所见即所得成片")
            let enhancedURL = autoreleasepool {
                Self.renderEnhanced(originalURL: originalURL,
                                    digitalCrop: digitalCrop,
                                    lutName: lutName,
                                    lutIntensity: lutIntensity,
                                    sharpness: sharpness,
                                    context: self.ciContext)
            }
            ShutterTrace.mark(tap, enhancedURL == nil ? "成片渲染失败（将回退原图）" : "成片渲染完成")

            var finalURL = originalURL
            if let enhancedURL,
               let enhancedData = try? Data(contentsOf: enhancedURL) {
                ShutterTrace.mark(tap, "成片写入相册开始", extra: "字节=\(enhancedData.count)")
                let result = await PhotoLibraryExporter.shared.exportPhoto(data: enhancedData)
                switch result {
                case .success:
                    finalURL = enhancedURL
                    ShutterTrace.mark(tap, "成片已写入相册")
                case .failure(let err):
                    DiagnosticLogger.shared.error("Enhanced save failed: \(err)")
                    ShutterTrace.mark(tap, "成片写入相册失败", extra: "\(err)")
                    if !keepOriginal && fallbackOnFailure {
                        // 不保留原图且增强片入库失败时，把原图兜底入库。
                        _ = await PhotoLibraryExporter.shared.exportPhoto(data: originalData)
                    }
                }
            } else if !keepOriginal && fallbackOnFailure {
                // 增强渲染失败：原图兜底入库。
                ShutterTrace.mark(tap, "增强失败，原图兜底入库")
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
            ShutterTrace.mark(tap, "拍照流程结束")
            // 本次拍照成功，清除上次崩溃的置顶提示。
            ShutterTrace.clearCrashReport()
        }
    }

    /// 渲染"所见即所得"成片：高倍数字裁切（与预览 scaleEffect 同源）+ 轻量
    /// 锐化与对比增强。任何失败返回 nil，由调用方回退原图。
    private static func renderEnhanced(originalURL: URL,
                                       digitalCrop: CGFloat,
                                       lutName: String,
                                       lutIntensity: Double,
                                       sharpness: Double,
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

        // 轻量、确定性的增强（非 AI 超分）。锐化强度由 Pro 面板的"锐化"控制。
        let sharpenIntensity = max(0.0, min(1.0, sharpness)) * 0.9
        if sharpenIntensity > 0.02 {
            image = image.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 1.2,
                kCIInputIntensityKey: sharpenIntensity
            ])
        }
        image = image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.03,
                kCIInputSaturationKey: 1.02
            ])

        // 真实 LUT（徕卡/胶片/电影等，HALD 64³ 或 .cube）。任何失败都回退原片。
        if lutName != "None", lutIntensity > 0 {
            let extent = image.extent
            let lutResult = LUTApplier.shared.applyLUT(
                named: lutName, to: image, intensity: lutIntensity)
            image = lutResult.cropped(to: extent)
        }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // 经 CGImageDestination 输出 JPEG 并指定压缩质量（CIContext 的
        // jpegRepresentation 不暴露 Swift 可见的 quality 键）。
        guard let cgImage = context.createCGImage(image, from: image.extent,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpace) else {
            return nil
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed-\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else { return nil }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return outURL
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
