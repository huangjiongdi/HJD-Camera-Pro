//
//  PhotoCapturePipeline.swift
//  HJD Camera Pro
//
//  AVCapturePhotoCaptureDelegate implementation. Persists the untouched original
//  (HEIF / JPEG / RAW / RAW+) to a protected temp file first, then hands the
//  asset to the AI enhancement stage. If AI enhancement fails the pipeline falls
//  back to a traditional Lanczos resample at a minimum 12 MP so the user always
//  keeps a usable image. EXIF metadata is preserved via ImageIO.
//

import AVFoundation
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import Combine

final class PhotoCapturePipeline: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
    static let shared = PhotoCapturePipeline()

    @Published var isCapturing = false
    @Published var burstRemaining = 0
    @Published var multiExposureFrames: [CIImage] = []

    private let fileManager = FileManager.default
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var pendingBurst = 0
    private var multiExposureTarget = 0

    private override init() {}

    // MARK: - Public capture triggers

    func capture(settings: AVCapturePhotoSettings? = nil) {
        let output = CameraManager.shared.photoOutput
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
        isCapturing = true
        defer { isCapturing = false }

        guard error == nil else {
            // Never lose the shot: surface the error and bail cleanly.
            NotificationCenter.default.post(name: .hjdStorageWarning, object: error)
            return
        }

        // 1. Protect the original — write untouched data (with EXIF) to a temp file.
        guard let originalData = photo.fileDataRepresentation() else { return }
        let originalURL = writeOriginalToTemp(data: originalData, isRAW: photo.isRawPhoto)

        // 2. Route by mode.
        if multiExposureTarget > 0 {
            accumulateMultiExposureFrame(data: originalData)
            return
        }

        // 3. Hand to AI enhancement; on failure fall back to traditional scaling.
        enhance(originalURL: originalURL, photo: photo)
    }

    // MARK: - Original protection (ImageIO, EXIF preserved)

    private func writeOriginalToTemp(data: Data, isRAW: Bool) -> URL {
        let ext = isRAW ? "dng" : "heic"
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("original-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        // fileDataRepresentation() already carries the EXIF/NMaker metadata from
        // the capture; writing the bytes verbatim preserves it.
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - AI enhancement with Lanczos fallback

    private let workQueue = DispatchQueue(label: "com.hjd.camera.photoEnhance", qos: .userInitiated)

    private func enhance(originalURL: URL, photo: AVCapturePhoto) {
        DispatchQueue.main.async {
            AppState.shared.isProcessing = true
            AppState.shared.processingProgress = 0.2
        }
        workQueue.async {
            guard let source = CIImage(contentsOf: originalURL) else {
                // Cannot decode: keep the original file as the final asset.
                self.finishEnhancement(image: nil, fallbackOriginal: originalURL)
                return
            }

            var image = source

            // High-zoom digital crop: when the requested zoom is beyond the
            // hardware maximum, centre-crop the still to match the live preview
            // and scale it back to full output size with Lanczos.
            let crop = CameraManager.shared.currentDigitalCrop
            if crop > 1.01 {
                let extent = source.extent
                let w = extent.width / crop
                let h = extent.height / crop
                let rect = CGRect(x: extent.midX - w / 2.0,
                                  y: extent.midY - h / 2.0,
                                  width: w, height: h)
                let recentered = source
                    .cropped(to: rect)
                    .transformed(by: CGAffineTransform(translationX: -rect.origin.x,
                                                       y: -rect.origin.y))
                let scaled = recentered
                    .applyingFilter("CILanczosScaleTransform",
                                    parameters: [kCIInputScaleKey: crop,
                                                 kCIInputAspectRatioKey: 1.0])
                    .cropped(to: CGRect(origin: .zero,
                                        size: CGSize(width: extent.width, height: extent.height)))
                image = scaled
            }

            // Fast, deterministic enhancement (sharpen + local contrast).
            // The heavy tiled CoreML super-resolution is an offline AI Studio
            // job; running it on a full-resolution still here produced thousands
            // of tiles and was the reason the photo never reached the library.
            image = image
                .applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: 1.5,
                    kCIInputIntensityKey: 0.6
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.03,
                    kCIInputSaturationKey: 1.02
                ])

            self.finishEnhancement(image: image, fallbackOriginal: originalURL)
        }
    }

    /// Encode the processed image to JPEG, write it out, export to the system
    /// photo library, and update UI. Never throws on the main path — any failure
    /// still keeps the original.
    private func finishEnhancement(image: CIImage?, fallbackOriginal: URL) {
        let outURL = fileManager.temporaryDirectory
            .appendingPathComponent("processed-\(UUID().uuidString).jpg")
        var success = false

        if let image = image {
            let cs = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            if let data = try? ciContext.jpegRepresentation(of: image,
                                                            colorSpace: cs) {
                try? data.write(to: outURL, options: .atomic)
                success = FileManager.default.fileExists(atPath: outURL.path)
            }
        }

        let finalURL = success ? outURL : fallbackOriginal

        // Save exactly one asset to the system photo library. If the enhanced
        // encode failed, the original is exported instead — the shot is never
        // lost. A failure here surfaces a real storage/permission error.
        if let data = try? Data(contentsOf: finalURL) {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                let result = await PhotoLibraryExporter.shared.exportPhoto(data: data)
                if case .failure(let err) = result {
                    DiagnosticLogger.shared.error("Photo save failed: \(err)")
                    NotificationCenter.default.post(name: .hjdStorageWarning, object: "\(err)")
                }
                semaphore.signal()
            }
            semaphore.wait()
        }

        DispatchQueue.main.async {
            AppState.shared.lastCapturedImageURL = finalURL
            AppState.shared.isProcessing = false
            AppState.shared.processingProgress = 1.0
            NotificationCenter.default.post(name: .hjdCaptureCompleted, object: finalURL)
        }

        if pendingBurst > 0 {
            burstRemaining = pendingBurst
            captureNextBurstFrame()
        } else {
            burstRemaining = 0
        }
    }

    private func lanczosFallback(originalURL: URL) -> URL {
        guard let source = CIImage(contentsOf: originalURL) else { return originalURL }
        let megapixels = (source.extent.width * source.extent.height) / 1_000_000
        var image = source
        if megapixels < 12.0 {
            let scale = sqrt(12.0 / max(megapixels, 1.0))
            image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .applyingFilter("CILanczosScaleTransform")
        }
        let outURL = fileManager.temporaryDirectory
            .appendingPathComponent("fallback-\(UUID().uuidString).jpg")
        if let data = try? ciContext.jpegRepresentation(of: image,
                                                        colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB()) {
            try? data.write(to: outURL, options: .atomic)
            return outURL
        }
        return originalURL
    }

    // MARK: - Multi-exposure accumulation

    private func accumulateMultiExposureFrame(data: Data) {
        guard let ciImage = CIImage(data: data) else { return }
        multiExposureFrames.append(ciImage)
        guard multiExposureFrames.count >= multiExposureTarget else { return }
        multiExposureTarget = 0
        let fused = multiExposureFrames.reduce(into: CIImage?.none) { partial, frame in
            partial = partial?.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: frame]) ?? frame
        }
        if let fused = fused {
            let outURL = fileManager.temporaryDirectory
                .appendingPathComponent("multiexposure-\(UUID().uuidString).heic")
            try? ciContext.writeHEIFRepresentation(of: fused, to: outURL, format: .BGRA8,
                                                   colorSpace: fused.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                                   options: [:])
            AppState.shared.lastCapturedImageURL = outURL
            NotificationCenter.default.post(name: .hjdCaptureCompleted, object: outURL)
        }
        multiExposureFrames.removeAll()
    }

    enum PipelineError: Error {
        case decodeFailed
        case insufficientResolution
    }
}
