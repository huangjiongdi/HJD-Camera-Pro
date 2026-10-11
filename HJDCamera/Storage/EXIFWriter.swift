//
//  EXIFWriter.swift
//  HJD Camera Pro
//
//  Writes EXIF / TIFF / GPS metadata into JPEG / HEVC images via ImageIO,
//  preserving lens, focal length, ISO, shutter and AI processing records.
//

import Foundation
import ImageIO
import CoreGraphics
import UIKit

struct EXIFMetadata {
    var lensModel: String?
    var focalLength: Double?          // mm
    var focalLength35mm: Double?      // 35mm equivalent
    var iso: Int?
    var shutterSpeed: Double?         // seconds
    var aperture: Double?              // f-number
    var whiteBalance: Int?
    var exposureBias: Double?
    var aiProcessingRecord: String?   // e.g. "超分 2x, 降噪"
    var captureMode: String?
    var dateTime: Date = Date()
}

final class EXIFWriter {
    static let shared = EXIFWriter()

    private init() {}

    // MARK: - Write into existing image data

    /// Takes an existing image file and rewrites it with the provided metadata.
    /// Preserves orientation and color space of the original source.
    func writeMetadata(to sourceURL: URL, destinationURL: URL, metadata: EXIFMetadata) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw NSError(domain: "EXIFWriter", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Cannot read source image"])
        }

        let uti = CGImageSourceGetType(source) ?? "public.jpeg" as CFString
        guard let dest = CGImageDestinationCreateWithURL(destinationURL as CFURL, uti, 1, nil) else {
            throw NSError(domain: "EXIFWriter", code: -2,
                           userInfo: [NSLocalizedDescriptionKey: "Cannot create destination"])
        }

        _ = buildProperties(from: metadata)
        // Copy each image from source into destination with merged properties.
        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            // Preserve original properties and overlay EXIF additions.
            var props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] ?? [:]
            props[kCGImagePropertyExifDictionary] = exifDictionary(from: metadata)
            props[kCGImagePropertyTIFFDictionary] = tiffDictionary(from: metadata)
            if let record = metadata.aiProcessingRecord {
                props[kCGImagePropertyIPTCDictionary] = [
                    "ProcessingRecord": record
                ] as CFDictionary
            }
            CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        }

        if !CGImageDestinationFinalize(dest) {
            throw NSError(domain: "EXIFWriter", code: -3,
                           userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image"])
        }
    }

    // MARK: - Build dictionaries

    private func buildProperties(from meta: EXIFMetadata) -> [CFString: Any] {
        var dict: [CFString: Any] = [:]
        dict[kCGImagePropertyExifDictionary] = exifDictionary(from: meta)
        dict[kCGImagePropertyTIFFDictionary] = tiffDictionary(from: meta)
        return dict
    }

    private func exifDictionary(from meta: EXIFMetadata) -> [CFString: Any] {
        var dict: [CFString: Any] = [:]
        if let focal = meta.focalLength {
            dict[kCGImagePropertyExifFocalLength] = focal
        }
        if let focal35 = meta.focalLength35mm {
            dict[kCGImagePropertyExifFocalLenIn35mmFilm] = focal35
        }
        if let iso = meta.iso {
            dict[kCGImagePropertyExifISOSpeedRatings] = [iso]
        }
        if let shutter = meta.shutterSpeed, shutter > 0 {
            dict[kCGImagePropertyExifExposureTime] = shutter
            dict[kCGImagePropertyExifShutterSpeedValue] = log2(1.0 / shutter)
        }
        if let aperture = meta.aperture {
            dict[kCGImagePropertyExifFNumber] = aperture
            dict[kCGImagePropertyExifApertureValue] = log2(aperture * aperture)
        }
        if let bias = meta.exposureBias {
            dict[kCGImagePropertyExifExposureBiasValue] = bias
        }
        if let wb = meta.whiteBalance {
            dict[kCGImagePropertyExifWhiteBalance] = wb == 0 ? 0 : 1
        }
        if let lensModel = meta.lensModel {
            dict[kCGImagePropertyExifLensModel] = lensModel
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        dict[kCGImagePropertyExifDateTimeOriginal] = formatter.string(from: meta.dateTime)
        return dict
    }

    private func tiffDictionary(from meta: EXIFMetadata) -> [CFString: Any] {
        var dict: [CFString: Any] = [:]
        dict[kCGImagePropertyTIFFSoftware] = "HJD Camera Pro"
        return dict
    }
}
