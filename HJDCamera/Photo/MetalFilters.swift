//
//  MetalFilters.swift
//  HJD Camera Pro
//
//  Metal-backed real-time preview enhancement filters. Uses a Metal-backed
//  CIContext for GPU-accelerated rendering and exposes a small set of
//  enhancement operations that map to shader-based kernels.
//

import Foundation
import CoreImage
import Metal
import UIKit

final class MetalFilters: ObservableObject {
    static let shared = MetalFilters()

    let device: MTLDevice?
    let ciContext: CIContext?

    @Published var enhancementIntensity: Double = 0.5
    @Published var isEnabled = true

    private init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.device = metalDevice
        if let metalDevice = metalDevice {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB()
            ])
        } else {
            self.ciContext = nil
        }
    }

    var isMetalAvailable: Bool { device != nil }

    // MARK: - Real-time preview enhancement

    /// Applies a lightweight, real-time enhancement to a preview frame.
    /// Combines brightness, contrast and a mild saturation boost — all executed
    /// on the GPU via Metal-backed CIFilters.
    func enhancePreview(_ image: CIImage) -> CIImage {
        guard isEnabled else { return image }

        var output = image

        // Mild tone curve lift (highlights / shadows).
        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(output, forKey: kCIInputImageKey)
            colorControls.setValue(1.0 + enhancementIntensity * 0.1, forKey: kCIInputSaturationKey)
            colorControls.setValue(0.05 * enhancementIntensity, forKey: kCIInputBrightnessKey)
            colorControls.setValue(1.0 + enhancementIntensity * 0.15, forKey: kCIInputContrastKey)
            output = colorControls.outputImage ?? output
        }

        // Local contrast / sharpening.
        if let sharp = CIFilter(name: "CISharpenLuminance") {
            sharp.setValue(output, forKey: kCIInputImageKey)
            sharp.setValue(0.2 * enhancementIntensity, forKey: kCIInputSharpnessKey)
            output = sharp.outputImage ?? output
        }

        return output
    }

    // MARK: - Render

    func render(_ image: CIImage) -> CGImage? {
        guard let context = ciContext else { return nil }
        return context.createCGImage(image, from: image.extent)
    }
}
