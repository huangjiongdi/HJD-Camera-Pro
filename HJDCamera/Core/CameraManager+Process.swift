import Foundation
import AVFoundation
import UIKit
import CoreImage
import Photos
import ImageIO
import UniformTypeIdentifiers

// MARK: - 拍照 / 录像完成回调

extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            print("[HJD] photo error:", error)
            return
        }
        // 快门触感 + 声音
        HapticEngine.shared.play(.shutter)
        ShutterSound.play()

        // 取图像
        if let data = photo.fileDataRepresentation(),
           let img = UIImage(data: data) {
            self.processAndSave(img)
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // 校验文件大小
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard let unwrapped = size, unwrapped > 1000, error == nil else {
            DispatchQueue.main.async { self.saveMessage = "录像失败" }
            return
        }
        // 保存到相册
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.saveMessage = "需要相册权限" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                req.addResource(with: .video, fileURL: fileURL, options: options)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    self.saveMessage = success ? "视频已保存" : "视频保存失败"
                    self.clearMessageAfter()
                }
            }
        }
    }
}

// MARK: - 处理与保存

extension CameraManager {

    func processAndSave(_ image: UIImage) {
        // 1) 方向归一化
        var processed = normalizedUpImage(image)
        // 数字中心裁切（高倍真实视野）
        processed = centerCropForDigitalZoom(processed)

        // 2) 场景专用 AI 增强
        switch shootingMode {
        case .night:
            processed = NightEngine.enhance(processed)
        case .moon:
            processed = LunarEngine.enhance(processed)
        case .portrait:
            processed = PortraitEngine.enhance(processed)
        case .macro:
            processed = MacroEngine.enhance(processed)
        default:
            break
        }

        // 3) 胶片 / LOG LUT
        if let film = filmLook {
            if let ci = CIImage(image: processed) {
                let r = FilmLab.apply(styleName: film, to: ci)
                processed = FilmLab.render(r) ?? processed
            }
        }
        if let lut = activeLUT {
            processed = LUTManager.shared.applyLUT(named: lut, to: processed) ?? processed
        }

        // 4) 滤镜/LUT 后降噪（锐化前）
        if filmLook != nil || activeLUT != nil {
            if let ci = CIImage(image: processed) {
                let nr = ci.applyingFilter("CINoiseReduction", parameters: [
                    "inputNoiseLevel": 0.22, kCIInputSharpnessKey: 0.72])
                if let cg = sharedCIContext.createCGImage(nr, from: ci.extent) {
                    processed = UIImage(cgImage: cg)
                }
            }
        }

        // 5) 锐化
        if sharpness > 0 {
            processed = applySharpness(processed, amount: sharpness)
        }

        // 6) 像素约束
        let isNight = shootingMode == .night
        let effective = PixelConstraints.clampPreset(resolutionPreset,
                                                     zoom: zoomFactor,
                                                     isNight: isNight)

        // 7) 12MP：文件写入 + EXIF
        if effective == .mp12 {
            var toSave = processed
            lastPhoto = toSave
            if let url = writeImageFile(toSave, exif: exifStore) {
                saveImageFileToLibrary(url, thumbnail: toSave)
            } else {
                saveToPhotoLibrary(toSave)
            }
            return
        }

        // 8) 高像素：分块超分
        isProcessing = true
        let exif = exifStore
        processingQueue.async {
            let out = TiledUpscaler.upscale(
                image: processed,
                targetPixels: effective.targetPixels,
                showWatermark: false,
                progress: { _ in })
            DispatchQueue.main.async {
                self.isProcessing = false
                if let out {
                    self.lastPhoto = out.thumbnail
                    self.saveImageFileToLibrary(out.fileURL, thumbnail: nil)
                } else {
                    // 兜底：绝不存小图
                    let safe = self.guaranteeMinPixels(processed, minPixels: 12_000_000)
                    self.lastPhoto = safe
                    if let url = self.writeImageFile(safe, exif: exif) {
                        self.saveImageFileToLibrary(url, thumbnail: nil)
                    } else {
                        self.saveToPhotoLibrary(safe)
                    }
                }
            }
        }
    }

    // 数字中心裁切（高倍）
    func centerCropForDigitalZoom(_ image: UIImage) -> UIImage {
        let scale = digitalCropScale
        guard scale > 1.01, let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width) / scale
        let h = CGFloat(cg.height) / scale
        let rect = CGRect(
            x: (CGFloat(cg.width) - w) / 2,
            y: (CGFloat(cg.height) - h) / 2,
            width: w, height: h)
        if let cropped = cg.cropping(to: rect) {
            return UIImage(cgImage: cropped)
        }
        return image
    }

    func applySharpness(_ image: UIImage, amount: Double) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        let r = ci.applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: amount * 0.8])
        if let cg = sharedCIContext.createCGImage(r, from: ci.extent) {
            return UIImage(cgImage: cg)
        }
        return image
    }
}
