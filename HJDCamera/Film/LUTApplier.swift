//
//  LUTApplier.swift
//  HJD Camera Pro
//
//  LUT application engine using Metal/CIFilter. Applies 3D LUT (.cube) or
//  built-in color transforms to CIImage with adjustable intensity.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import UIKit

class LUTApplier: ObservableObject {
    static let shared = LUTApplier()

    private var context: CIContext
    private var metalDevice: MTLDevice?

    private init() {
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
        if let cubeImage = loadCubeLUT(named: name) {
            return applyColorCube(image: image, cube: cubeImage, intensity: intensity)
        }

        // Fallback: built-in color transform
        return applyBuiltinTransform(image: image, name: name, intensity: intensity)
    }

    // MARK: - .cube LUT via CIColorCube

    private func loadCubeLUT(named name: String) -> CIImage? {
        // Look for bundled .cube file
        guard let url = Bundle.main.url(forResource: name, withExtension: "cube") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return parseCubeData(data)
        } catch {
            return nil
        }
    }

    private func parseCubeData(_ data: Data) -> CIImage? {
        // Simplified .cube parser: extracts size and data points
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var size = 2
        var entries: [simd_float3] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                size = Int(trimmed.components(separatedBy: " ").last ?? "2") ?? 2
                continue
            }
            let parts = trimmed.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            if parts.count == 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                entries.append(simd_float3(r, g, b))
            }
        }

        guard entries.count == size * size * size else { return nil }

        // Build data provider for CIColorCube
        var cubeData = Data()
        for entry in entries {
            var r = entry.x; var g = entry.y; var b = entry.z
            cubeData.append(Data(bytes: &r, count: 4))
            cubeData.append(Data(bytes: &g, count: 4))
            cubeData.append(Data(bytes: &b, count: 4))
        }

        let dataProvider = CGDataProvider(data: cubeData as CFData)!
        let colorspace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = CGImage(
            width: size * size,
            height: size,
            bitsPerComponent: 32,
            bitsPerPixel: 96,
            bytesPerRow: size * size * 12,
            space: colorspace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return CIImage(cgImage: cgImage)
    }

    private func applyColorCube(image: CIImage, cube: CIImage, intensity: Double) -> CIImage {
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeData = cube
        filter.intensity = Float(intensity)
        return filter.outputImage ?? image
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
        let scaled = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width,
                                                            y: size.height / image.extent.height))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
