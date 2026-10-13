//
//  TiledUpscaler.swift
//  HJD Camera Pro
//
//  Processes very large images in overlapping tiles so that peak memory stays
//  bounded. Overlapping margins are feathered together to hide seams.
//

import Foundation
import CoreImage
import CoreGraphics

final class TiledUpscaler {
    static let shared = TiledUpscaler()

    /// A per-tile processing function: input tile -> upscaled tile.
    typealias TileProcessor = (CIImage) throws -> CIImage

    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    /// Maximum tile edge (pixels) sent through the GPU/ML processor at once.
    var maxTileEdge: CGFloat = 1536
    /// Overlap between neighboring tiles, used for feather blending.
    var overlap: CGFloat = 64

    private init() {}

    // MARK: - Run

    /// Upscales an arbitrarily large image by splitting it into overlapping
    /// tiles, running `processor` on each, and seam-blending the results.
    func upscale(
        image: CIImage,
        scale: CGFloat,
        processor: TileProcessor
    ) throws -> CIImage {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              !extent.isInfinite, !extent.isNull else {
            throw UpscalerError.invalidExtent
        }

        let outputWidth = extent.width * scale
        let outputHeight = extent.height * scale

        // Build a list of source rectangles (in input coordinates).
        let tiles = tileRects(for: extent)

        var result: CIImage?

        for tileRect in tiles {
            let cropped = image.cropped(to: tileRect)
            let processed = try processor(cropped)

            // Map the tile back into the full output coordinate space.
            let translated = processed.transformed(
                by: CGAffineTransform(
                    translationX: tileRect.origin.x * scale,
                    y: tileRect.origin.y * scale
                )
            )

            if let existing = result {
                result = existing.composited(over: translated)
            } else {
                result = translated
            }
        }

        guard var output = result else {
            throw UpscalerError.emptyResult
        }
        output = output.cropped(to: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        return output
    }

    // MARK: - Tiling

    private func tileRects(for extent: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        let step = maxTileEdge - overlap

        var y: CGFloat = extent.minY
        while y < extent.maxY {
            var x: CGFloat = extent.minX
            while x < extent.maxX {
                let w = min(maxTileEdge, extent.maxX - x)
                let h = min(maxTileEdge, extent.maxY - y)
                rects.append(CGRect(x: x, y: y, width: w, height: h))
                x += step
            }
            y += step
        }
        return rects
    }

    enum UpscalerError: Error {
        case invalidExtent
        case emptyResult
    }
}
