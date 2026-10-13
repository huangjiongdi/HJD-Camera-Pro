//
//  FilmLab.swift
//  HJD Camera Pro
//
//  Film Lab color workflow: organizes LUT application, film simulation,
//  grain, and color grading into a single processing pipeline.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

class FilmLab: ObservableObject {
    static let shared = FilmLab()

    @Published var currentLUTName: String = "None"
    @Published var intensity: Double = 1.0
    @Published var grainIntensity: Double = 0.1
    @Published var filmSimulation: String = "None"
    @Published var saturation: Double = 1.0
    @Published var contrast: Double = 1.0
    @Published var temperature: Double = 0.0

    private let lutApplier = LUTApplier()

    private init() {}

    // MARK: - Pipeline

    func process(image: CIImage) -> CIImage {
        var result = image

        // 1. Apply LUT
        if currentLUTName != "None" {
            result = lutApplier.applyLUT(named: currentLUTName, to: result, intensity: intensity)
        }

        // 2. Film simulation
        if filmSimulation != "None" {
            result = applyFilmSimulation(result)
        }

        // 3. Color grading
        result = applyColorGrading(result)

        // 4. Grain
        if grainIntensity > 0 {
            result = applyGrain(result)
        }

        return result
    }

    private func applyFilmSimulation(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = Float(saturation * 1.1)
        filter.contrast = Float(contrast * 1.05)
        return filter.outputImage ?? image
    }

    private func applyColorGrading(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = Float(saturation)
        filter.contrast = Float(contrast)
        filter.brightness = 0
        return filter.outputImage ?? image
    }

    private func applyGrain(_ image: CIImage) -> CIImage {
        let noise = CIFilter.randomGenerator()
        guard let noiseImage = noise.outputImage?.cropped(to: image.extent) else {
            return image
        }
        let blend = CIFilter.overlayBlendMode()
        blend.inputImage = noiseImage
        blend.backgroundImage = image
        return blend.outputImage ?? image
    }

    // MARK: - Presets

    func loadPreset(_ name: String) {
        let presets: [String: (lut: String, grain: Double, sat: Double, con: Double)] = [
            "胶片5207": (lut: "Kodak 5207", grain: 0.15, sat: 1.1, con: 1.05),
            "电影级": (lut: "Cinematic", grain: 0.08, sat: 0.95, con: 1.1),
            "黑白": (lut: "B&W", grain: 0.2, sat: 0.0, con: 1.2),
            "富士Provia": (lut: "Fuji Provia", grain: 0.05, sat: 1.05, con: 1.0),
        ]
        if let p = presets[name] {
            currentLUTName = p.lut
            grainIntensity = p.grain
            saturation = p.sat
            contrast = p.con
        }
    }
}

#Preview {
    Text("FilmLab")
}
