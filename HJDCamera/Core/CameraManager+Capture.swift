import Foundation
import AVFoundation
import UIKit
import CoreImage
import Photos

// MARK: - 拍照 / 录像 / 模式切换

extension CameraManager {

    // MARK: 快门（拍照 / 录像统一入口）

    func shutter() {
        switch shootingMode {
        case .video, .sloMo, .timelapse:
            if isRecording { stopRecording() } else { startRecording() }
        case .burst:
            captureBurst()
        default:
            capturePhoto()
        }
    }

    // MARK: 拍照

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            // 闪光灯
            if self.photoOutput.supportedFlashModes.contains(self.flashMode) {
                settings.flashMode = self.flashMode
            }
            // 高分辨率优先
            if self.photoOutput.isHighResolutionCaptureEnabled {
                settings.isHighResolutionPhotoEnabled = true
            }
            // RAW
            if self.fileFormat == .raw && self.photoOutput.isAppleProRAWSupported {
                let raw = AVCapturePhotoSettings(
                    rawPixelFormatType: self.photoOutput.availableAppleProRAWPhotoTypes.first!
                        .uint32Value)
                self.photoOutput.capturePhoto(with: raw, delegate: self)
            } else {
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func captureBurst() {
        for _ in 0..<10 {
            capturePhoto()
        }
    }

    // MARK: 录像

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 视频手电筒常亮
            if self.torchOn, let device = self.currentDevice, device.hasTorch {
                try? device.lockForConfiguration()
                device.torchMode = .on
                device.unlockForConfiguration()
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("hjd_\(UUID().uuidString).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.movieOutput.stopRecording()
            if let device = self.currentDevice, device.torchMode == .on {
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            }
            DispatchQueue.main.async { self.isRecording = false }
        }
    }

    // MARK: 闪光灯 / 手电筒

    func toggleTorch() {
        torchOn.toggle()
        if shootingMode.isVideo {
            sessionQueue.async { [weak self] in
                guard let self, let device = self.currentDevice, device.hasTorch else { return }
                try? device.lockForConfiguration()
                device.torchMode = self.torchOn ? .on : .off
                device.unlockForConfiguration()
            }
        }
    }

    func cycleFlash() {
        switch flashMode {
        case .auto: flashMode = .on
        case .on:   flashMode = .off
        case .off:  flashMode = .auto
        @unknown default: flashMode = .auto
        }
    }

    // MARK: 模式切换

    func setMode(_ mode: ShootingMode) {
        DispatchQueue.main.async {
            self.shootingMode = mode
            self.overlayMode = mode == .pro ? .peaking : .none
            // 视频 16:9，拍照 4:3
            self.aspectRatio = mode.isVideo ? .r169 : .r43
        }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            if mode.isVideo {
                if mode == .sloMo {
                    self.configureVideoFormat(device: device, resolution: .r1080, fps: 120)
                } else {
                    self.configureVideoFormat(device: device,
                                              resolution: self.videoResolution,
                                              fps: self.videoFPS)
                }
            } else {
                self.resetToDefaultFormat(device: device)
            }
        }
    }

    // MARK: 视频格式配置（预览帧率跟随）

    func configureVideoFormat(device: AVCaptureDevice,
                              resolution: VideoResolution,
                              fps: Int) {
        let targetH = resolution.pixelHeight
        let desired = fps
        var best: AVCaptureDevice.Format?
        var bestRange: AVFrameRateRange?
        for f in device.formats {
            let desc = f.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            if dims.height >= targetH - 20 && dims.height <= targetH + 120 {
                for r in f.videoSupportedFrameRateRanges {
                    if r.maxFrameRate >= Double(desired) {
                        best = f
                        bestRange = r
                        break
                    }
                }
            }
            if best != nil { break }
        }
        guard let fmt = best, let range = bestRange else {
            print("[HJD] no exact format, fallback")
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = fmt
            let useFPS = min(Double(desired), range.maxFrameRate)
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(useFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(useFPS))
            device.unlockForConfiguration()
        } catch {}
    }

    func resetToDefaultFormat(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.activeFormat = device.formats.first { f in
                let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                return dims.height >= 3000 && dims.height <= 4000
            } ?? device.activeFormat
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 45)
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: 方向

    var currentImageOrientation: CGImagePropertyOrientation {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return .right }
        switch scene.interfaceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        case .unknown: return .right
        @unknown default: return .right
        }
    }

    // MARK: 进入相册 / 编辑器

    func openGallery() { appScreen = .gallery }
    func openEditor(_ image: UIImage) {
        editorImage = image
        appScreen = .aiEditor
    }
    func backToCamera() {
        appScreen = .camera
        editorImage = nil
    }
}
