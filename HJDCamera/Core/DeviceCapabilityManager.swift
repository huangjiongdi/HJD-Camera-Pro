//
//  DeviceCapabilityManager.swift
//  HJD Camera Pro
//

import AVFoundation
import UIKit

final class DeviceCapabilityManager {
    static let shared = DeviceCapabilityManager()

    private init() {}

    // MARK: - Camera Devices

    var defaultVideoDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    var virtualDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            ?? defaultVideoDevice
    }

    var frontCamera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    var hasTelephoto: Bool {
        AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil
    }

    var hasUltraWide: Bool {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
    }

    var hasLiDAR: Bool {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
    }

    var maxZoomFactor: CGFloat {
        virtualDevice?.activeFormat.videoMaxZoomFactor ?? 10
    }

    var switchOverFactors: [CGFloat] {
        virtualDevice?.virtualDeviceSwitchOverVideoZoomFactors ?? []
    }

    // MARK: - Video Formats

    func availableVideoFormats(for device: AVCaptureDevice?) -> [AVCaptureDevice.Format] {
        guard let device = device else { return [] }
        return device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width >= 1920
        }
    }

    func maxFrameRate(for resolution: String, device: AVCaptureDevice?) -> Int {
        guard let device = device else { return 30 }
        var maxRate: Double = 30
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let resString = resolutionString(width: Int(dims.width), height: Int(dims.height))
            if resString == resolution {
                for range in format.videoSupportedFrameRateRanges {
                    maxRate = max(maxRate, range.maxFrameRate)
                }
            }
        }
        return Int(maxRate)
    }

    func supports4K240(device: AVCaptureDevice?) -> Bool {
        maxFrameRate(for: "4K", device: device) >= 240
    }

    func supports8K(device: AVCaptureDevice?) -> Bool {
        guard let device = device else { return false }
        return device.formats.contains { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width >= 7680
        }
    }

    func supportsProRes() -> Bool {
        // ProRes support depends on device and iOS version
        if #available(iOS 17.0, *) {
            return true
        }
        return false
    }

    func supportsHDR(device: AVCaptureDevice?) -> Bool {
        guard let device = device else { return false }
        return device.activeFormat.isVideoHDRSupported
    }

    // MARK: - Photo Capabilities

    var supportsRAW: Bool {
        defaultVideoDevice?.activeFormat.isVideoHDRSupported ?? false
    }

    var maxPhotoResolution: Int {
        guard let device = defaultVideoDevice else { return 12 }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let megapixels = (Int(dims.width) * Int(dims.height)) / 1_000_000
        return max(megapixels, 12)
    }

    // MARK: - Helpers

    private func resolutionString(width: Int, height: Int) -> String {
        if width >= 7680 { return "8K" }
        if width >= 3840 { return "4K" }
        if width >= 1920 { return "1080p" }
        if width >= 1280 { return "720p" }
        return "480p"
    }

    func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    func compatibilityReport() -> [String: Any] {
        return [
            "device": deviceModelName(),
            "hasTelephoto": hasTelephoto,
            "hasUltraWide": hasUltraWide,
            "hasLiDAR": hasLiDAR,
            "maxZoom": maxZoomFactor,
            "supports4K240": supports4K240(device: virtualDevice),
            "supports8K": supports8K(device: virtualDevice),
            "supportsProRes": supportsProRes(),
            "supportsHDR": supportsHDR(device: virtualDevice),
            "maxPhotoMP": maxPhotoResolution,
            "switchOverFactors": switchOverFactors.map { $0.doubleValue },
            "iOS": UIDevice.current.systemVersion,
        ]
    }
}
