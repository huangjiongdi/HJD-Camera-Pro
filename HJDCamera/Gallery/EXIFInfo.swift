//
//  EXIFInfo.swift
//  HJD Camera Pro
//
//  Lightroom 式照片信息面板：从 PHAsset 读取 EXIF/TIFF/GPS/尺寸。
//

import Photos
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

struct EXIFInfo {
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64
    let cameraModel: String?
    let lensModel: String?
    let focalLength: String?
    let fNumber: String?
    let iso: [Int]?
    let shutterSpeed: String?
    let exposureBias: String?
    let whiteBalance: String?
    let date: Date?
    let location: CLLocation?
    let fileType: String?

    var megapixels: String {
        String(format: "%.1f MP", Double(pixelWidth * pixelHeight) / 1_000_000.0)
    }

    var resolution: String { "\(pixelWidth) × \(pixelHeight)" }

    var formattedDate: String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return f.string(from: date)
    }

    var exposureLine: String? {
        var parts: [String] = []
        if let fNumber { parts.append("f/\(fNumber)") }
        if let shutterSpeed { parts.append("\(shutterSpeed)s") }
        if let iso = iso?.first { parts.append("ISO \(iso)") }
        if let focalLength { parts.append("\(focalLength)mm") }
        if let ev = exposureBias, ev != "0" { parts.append("EV \(ev)") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// 异步读取 PHAsset 的原图数据并解析 EXIF。
    static func load(asset: PHAsset, completion: @escaping (EXIFInfo?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.version = .current
        let manager = PHCachingImageManager()
        manager.requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard let data, !cancelled else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let parsed = parse(data: data, asset: asset, uti: uti)
            DispatchQueue.main.async { completion(parsed) }
        }
    }

    private static func parse(data: Data, asset: PHAsset, uti: String?) -> EXIFInfo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let index = 0
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? asset.pixelWidth
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? asset.pixelHeight

        let model = (tiff[kCGImagePropertyTIFFModel] as? String)
        let lens = (exif[kCGImagePropertyExifLensModel] as? String)
        let focal: Double? = num(exif[kCGImagePropertyExifFocalLength])
        let fnum: Double? = num(exif[kCGImagePropertyExifFNumber])
        let isoNums = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int]
        let bias = num(exif[kCGImagePropertyExifExposureBiasValue])
        let wb = num(exif[kCGImagePropertyExifWhiteBalance])

        var shutter: String?
        if let et = exif[kCGImagePropertyExifExposureTime] as? Double, et > 0 {
            if et >= 1 {
                shutter = String(format: "%.1f", et)
            } else {
                shutter = "1/\(Int((1.0 / et).rounded()))"
            }
        }

        var fileType: String?
        if let uti {
            fileType = EXIFInfo.preferredFileExtension(uti: uti)
        }

        return EXIFInfo(
            pixelWidth: w,
            pixelHeight: h,
            fileSize: Int64(data.count),
            cameraModel: model,
            lensModel: lens,
            focalLength: focal.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) },
            fNumber: fnum.map { String(format: $0 == $0.rounded() ? "%.0f" : "%.1f", $0) },
            iso: isoNums,
            shutterSpeed: shutter,
            exposureBias: bias.map { String(format: "%.1f", $0) },
            whiteBalance: wb.map { $0 == 0 ? "自动" : "手动" },
            date: asset.creationDate,
            location: asset.location,
            fileType: fileType
        )
    }

    private static func num(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func preferredFileExtension(uti: String) -> String? {
        let map: [String: String] = [
            "public.heic": "HEIC",
            "public.heif": "HEIF",
            "public.jpeg": "JPEG",
            "public.png": "PNG",
            "public.tiff": "TIFF",
            "public.mpeg-4": "MP4",
            "com.apple.quicktime-movie": "MOV",
            "public.3gpp": "3GP",
            "public.avi": "AVI",
            "com.adobe.raw-image": "DNG",
            "com.canon.cr2-raw-image": "CR2",
            "com.canon.cr3-raw-image": "CR3",
            "com.nikon.raw-image": "NEF",
            "com.sony.raw-image": "ARW",
            "com.apple.photos.raw": "RAW",
            "public.dng": "DNG"
        ]
        if let v = map[uti] { return v }
        // 兜底：UTI 末段（如 public.jpeg -> JPEG）。
        let tail = uti.split(separator: ".").last.map { $0.uppercased() }
        return tail
    }
}
