import Foundation
import UIKit
import ImageIO
import CoreGraphics
import Photos
import UniformTypeIdentifiers

// MARK: - EXIF 存储（本机 / 自定义）

final class EXIFStore {
    enum Mode { case native, custom }
    var mode: Mode = .native

    // 自定义字段
    var manufacturer = "Apple"
    var model = "iPhone 16 Pro Max"
    var software = "iOS 27"
    var brand = "HJD"
    var lens = "24-12000mm f/1.78"
}

enum EXIFWriter {

    /// 写入 EXIF 元数据的图像文件
    static func write(_ image: UIImage,
                      format: PhotoFileFormat = .heif,
                      store: EXIFStore,
                      capture: CaptureMetadata? = nil) -> URL? {
        guard let cg = image.cgImage else { return nil }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hjd_img_\(UUID().uuidString)")
        let url: URL
        let uti: CFString
        switch format {
        case .jpg:
            url = tmp.appendingPathExtension("jpg"); uti = UTType.jpeg.identifier as CFString
        case .png:
            url = tmp.appendingPathExtension("png"); uti = UTType.png.identifier as CFString
        case .tiff:
            url = tmp.appendingPathExtension("tiff"); uti = UTType.tiff.identifier as CFString
        default:
            url = tmp.appendingPathExtension("heic"); uti = UTType.heic.identifier as CFString
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti, 1, nil) else {
            return nil
        }

        let now = Date()
        var exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: Self.dateFormatter.string(from: now),
            kCGImagePropertyExifColorSpace: 1,
        ]
        if let c = capture {
            exif[kCGImagePropertyExifFocalLength] = c.focalLength
            exif[kCGImagePropertyExifISOSpeedRatings] = [c.iso]
            exif[kCGImagePropertyExifExposureTime] = c.exposureTime
            exif[kCGImagePropertyExifFNumber] = c.fNumber
        }

        var tiff: [CFString: Any] = [:]
        if store.mode == .custom {
            tiff[kCGImagePropertyTIFFMake] = store.manufacturer
            tiff[kCGImagePropertyTIFFModel] = store.model
            exif[kCGImagePropertyExifLensModel] = store.lens
            tiff[kCGImagePropertyTIFFSoftware] = store.software
        }

        let meta: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImagePropertyOrientation: cg.imageOrientation.rawValue,
        ]
        CGImageDestinationAddImage(dest, cg, meta as CFDictionary)
        if CGImageDestinationFinalize(dest) {
            return url
        }
        return nil
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
}

struct CaptureMetadata {
    let focalLength: Double
    let iso: Int
    let exposureTime: Double
    let fNumber: Double
}
