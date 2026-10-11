import Foundation
import AVFoundation
import UIKit
import CoreImage
import CoreMotion

// MARK: - 对焦 / AE-AF 锁定 / 数据输出

extension CameraManager {

    // MARK: 点击对焦 + 测光

    func setFocus(point: CGPoint, previewSize: CGSize) {
        let devX = point.x / previewSize.width
        let devY = point.y / previewSize.height
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: devX, y: devY)
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: devX, y: devY)
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async {
                self.focusPoint = CGPoint(x: devX, y: devY)
                HapticEngine.shared.play(.focusLocked)
            }
        }
    }

    // MARK: 长按锁定 AE/AF

    func lockFocusExposure(point: CGPoint, previewSize: CGSize) {
        let devX = point.x / previewSize.width
        let devY = point.y / previewSize.height
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: devX, y: devY)
                    device.focusMode = .locked
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: devX, y: devY)
                    device.exposureMode = .locked
                }
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async {
                self.afAeLocked = true
                self.lockPoint = CGPoint(x: devX, y: devY)
                self.focusPoint = CGPoint(x: devX, y: devY)
                HapticEngine.shared.play(.focusLocked)
            }
            self.startUnlockMotionWatcher()
        }
    }

    func unlockFocusExposure() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.exposureMode = .continuousAutoExposure
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async {
                self.afAeLocked = false
                self.lockPoint = nil
            }
        }
        stopUnlockMotionWatcher()
    }

    private func startUnlockMotionWatcher() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, self.afAeLocked, let motion = motion else { return }
            let a = motion.userAcceleration
            let mag = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
            if mag > 1.4 {
                self.unlockFocusExposure()
            }
        }
    }

    private func stopUnlockMotionWatcher() {
        if motionManager.isDeviceMotionActive { motionManager.stopDeviceMotionUpdates() }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 峰值对焦（专业模式）
        if shootingMode == .pro {
            updatePeaking(pixelBuffer: pixelBuffer)
        }
        // 直方图（轻量抽样）
        if Int.random(in: 0..<6) == 0 {
            updateHistogram(pixelBuffer: pixelBuffer)
        }
    }

    private func updatePeaking(pixelBuffer: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let edges = ci.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 4.0])
        // 绿色高亮边缘（峰值）
        let colored = edges.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputColor1": CIColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        ])
        let small = colored.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        if let cg = sharedCIContext.createCGImage(small, from: small.extent) {
            let img = UIImage(cgImage: cg)
            DispatchQueue.main.async { self.peakingImage = img }
        }
    }

    private func updateHistogram(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var bins = [Float](repeating: 0, count: 256)
        var count: Float = 0
        let step = 12
        for y in stride(from: 0, to: h, by: step) {
            let row = base.advanced(by: y * bpr)
            for x in stride(from: 0, to: w, by: step) {
                let p = row.advanced(by: x * 4)
                // BGRA -> luminance
                let b = p.load(as: UInt8.self)
                let g = p.advanced(by: 1).load(as: UInt8.self)
                let r = p.advanced(by: 2).load(as: UInt8.self)
                let lum = (0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b))
                let idx = min(255, Int(lum))
                bins[idx] += 1
                count += 1
            }
        }
        if count > 0 {
            let norm = bins.map { $0 / count }
            DispatchQueue.main.async {
                self.histogramData = norm
            }
        }
    }
}
