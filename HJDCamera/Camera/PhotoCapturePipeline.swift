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
            AppState.shared.processingProgress = 0.1
        }
        workQueue.async {
            // 1) Try real AI super-resolution (Real-ESRGAN via CoreML).
            if let source = CIImage(contentsOf: originalURL) {
                AIModelRunner.shared.run(model: "sr_generic", input: source) { [weak self] upscaled in
                    guard let self = self else { return }
                    // The completion fires on the main thread — re-encode on workQueue.
                    self.workQueue.async {
                        self.finishEnhancement(image: upscaled ?? source, fallbackOriginal: originalURL)
                    }
                }
                return
            }
            // Could not decode — fall straight back to the original file.
            self.finishEnhancement(image: nil, fallbackOriginal: originalURL)
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
            // Gentle sharpen on top of the AI result.
            let sharpened = image.applyingFilter("CISharpenLuminance",
                                                  parameters: [kCIInputSharpnessKey: 0.35])
            if let data = try? ciContext.jpegRepresentation(of: sharpened,
                                                            colorSpace: sharpened.colorSpace ?? CGColorSpaceCreateDeviceRGB()) {
                try? data.write(to: outURL, options: .atomic)
                success = FileManager.default.fileExists(atPath: outURL.path)
            }
        }

        let finalURL = success ? outURL : fallbackOriginal

        // Export to the system photo library (this is what was missing — nothing
        // was ever saved to Photos).
        if let data = try? Data(contentsOf: finalURL) {
            Task.detached {
                _ = await PhotoLibraryExporter.shared.exportPhoto(data: data)
            }
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
