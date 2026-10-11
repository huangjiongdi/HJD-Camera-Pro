//
//  ImageProcessingHelper.swift
//  HJD Camera Pro
//
//  CIImage / CGImage helpers: scaling, cropping, rotation, color-space
//  conversion, with a Lanczos resampling fallback when needed.
//

import Foundation
import CoreImage
import UIKit

final class ImageProcessingHelper {
    static let shared = ImageProcessingHelper()

    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    private init() {}

    // MARK: - Scale

    /// Scales a CIImage to the target size. Uses Lanczos resampling via
    /// CILanczosScaleTransform for high-quality down/upscaling.
    func scale(_ image: CIImage, to size: CGSize) -> CIImage {
        let scaleX = size.width / max(image.extent.width, 1)
        let scaleY = size.height / max(image.extent.height, 1)
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else {
            return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }
        lanczos.setValue(image, forKey: kCIInputImageKey)
        lanczos.setValue(scaleX, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return lanczos.outputImage ?? image
    }

    // MARK: - Crop

    func crop(_ image: CIImage, to rect: CGRect) -> CIImage {
        image.cropped(to: rect)
    }

    // MARK: - Rotate

    func rotate(_ image: CIImage, degrees: Double) -> CIImage {
        let radians = degrees * .pi / 180.0
        let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        return image.transformed(
            by: CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: radians)
                .translatedBy(x: -center.x, y: -center.y)
        )
    }

    // MARK: - Color space

    func convert(_ image: CIImage, to colorSpace: CGColorSpace) -> CIImage {
        guard let cg = context.createCGImage(image,
                                             from: image.extent,
                                             format: .RGBA8,
                                             colorSpace: colorSpace) else {
            return image
        }
        return CIImage(cgImage: cg, options: [.colorSpace: colorSpace])
    }

    // MARK: - Render to CGImage

    func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }

    // MARK: - UIImage <-> CIImage

    func uiImage(from image: CIImage) -> UIImage? {
        guard let cg = render(image) else { return nil }
        return UIImage(cgImage: cg)
    }
}
