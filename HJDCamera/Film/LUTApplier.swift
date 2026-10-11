//
//  LUTApplier.swift
//  HJD Camera Pro
//
//  LUT application engine using CoreImage. Applies 3D LUT (.cube) or built-in
//  color transforms to CIImage with adjustable intensity.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import UIKit
import simd

class LUTApplier: ObservableObject {
    static let shared = LUTApplier()

    private var context: CIContext
    private var metalDevice: MTLDevice?

    init() {
        metalDevice = MTLCreateSystemDefaultDevice()
        if let device = metalDevice {
            context = CIContext(mtlDevice: device)
        } else {
            context = CIContext()
        }
    }

    // MARK: - Apply LUT

    func applyLUT(named name: String, to image: CIImage, intensity: Double) -> CIImage {
        guard name != "None", intensity > 0 else { return image }

        // Try to load custom .cube LUT first
        if let url = Bundle.main.url(forResource: name, withExtension: "cube"),
           let (dimension, cubeData) = parseCube(at: url) {
            return applyColorCube(image: image,
                                  dimension: dimension,
                                  cubeData: cubeData,
                                  intensity: intensity)
        }

        // Fallback: built-in color transform
        return applyBuiltinTransform(image: image, name: name, intensity: intensity)
    }

    // MARK: - .cube LUT parsing

    /// Parse a .cube file into (dimension, RGBA float32 cube data). CIColorCube
    /// expects red to vary fastest, then green, then blue — the same order used
    /// by standard .cube files.
    private func parseCube(at url: URL) -> (Int, Data)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var size = 2
        var entries: [SIMD3<Float>] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            let header = trimmed.uppercased()
            if header.hasPrefix("LUT_3D_SIZE") {
                size = Int(trimmed.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }.last ?? "2") ?? 2
                continue
            }
            if header.hasPrefix("LUT_") { continue } // skip LUT_1D_SIZE / DOMAIN_MIN etc.
            let parts = trimmed.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            if parts.count == 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                entries.append(SIMD3<Float>(r, g, b))
            }
        }

        guard entries.count == size * size * size else { return nil }

        var cubeData = Data()
        cubeData.reserveCapacity(entries.count * 16)
        for entry in entries {
            var rgba = SIMD4<Float>(entry.x, entry.y, entry.z, 1.0)
            cubeData.append(UnsafeBufferPointer(start: &rgba, count: 1))
        }
        return (size, cubeData)
    }

    private func applyColorCube(image: CIImage,
                                dimension: Int,
                                cubeData: Data,
                                intensity: Double) -> CIImage {
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeData = cubeData
        filter.cubeDimension = Float(dimension)
        filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let lutImage = filter.outputImage else { return image }

        // Full strength
        if intensity >= 1.0 { return lutImage }

        // Partial strength: crossfade between the LUT result and the original
        // using a constant mask.
        let mask = CIImage(color: CIColor(red: intensity,
                                          green: intensity,
                                          blue: intensity))
            .cropped(to: image.extent)
        return lutImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ])
    }

    // MARK: - Built-in Transforms

    private func applyBuiltinTransform(image: CIImage, name: String, intensity: Double) -> CIImage {
        var result = image

        // Color controls
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.saturation = Float(1.0 + (intensity - 1.0) * 0.2)
        colorControls.contrast = Float(1.0 + (intensity - 1.0) * 0.15)
        if let output = colorControls.outputImage {
            result = output
        }

        // Color monochrome for B&W
        if name.contains("B&W") || name.contains("黑白") {
            let mono = CIFilter.colorMonochrome()
            mono.inputImage = result
            mono.color = CIColor(red: 0.5, green: 0.5, blue: 0.5)
            mono.intensity = Float(intensity)
            if let output = mono.outputImage { result = output }
        }

        // Temperature shift
        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = result
        temp.neutral = CIVector(x: 6500, y: 0)
        if name.contains("Warm") || name.contains("Film") {
            temp.targetNeutral = CIVector(x: 5500, y: 0)
        } else if name.contains("Cool") || name.contains("Cinematic") {
            temp.targetNeutral = CIVector(x: 7500, y: 0)
        } else {
            temp.targetNeutral = CIVector(x: 6500, y: 0)
        }
        if let output = temp.outputImage { result = output }

        return result
    }

    // MARK: - Render

    func render(image: CIImage, to size: CGSize) -> UIImage? {
        let sx = size.width / image.extent.width
        let sy = size.height / image.extent.height
        let scaled = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
