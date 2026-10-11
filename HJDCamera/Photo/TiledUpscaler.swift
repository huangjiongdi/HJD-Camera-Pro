import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

// MARK: - 分块超分结果

struct UpscaleResult {
    let fileURL: URL
    let thumbnail: UIImage
}

// MARK: - TiledUpscaler
//
// 用内嵌 RealESRGAN 模型对分块执行 512→2048（×4）增强，
// 羽化拼接为目标总像素的大图，写入 JPEG（含 EXIF）。
enum TiledUpscaler {

    private static let ci = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB()])

    private static let tileSrc: CGFloat = 400
    private static let marginSrc: CGFloat = 40
    private static let overlap: CGFloat = 0.75

    static func upscale(image: UIImage,
                        targetPixels: Int,
                        showWatermark: Bool,
                        progress: (Double) -> Void) -> UpscaleResult? {
        guard let src = image.cgImage else { return nil }

        let W = CGFloat(src.width)
        let H = CGFloat(src.height)
        let s = sqrt(CGFloat(targetPixels) / (W * H))
        let outW = Int((W * s).rounded())
        let outH = Int((H * s).rounded())

        // 输出画布（大 bitmap context，4 bytes/px）
        let bytesPerRow = outW * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let data = calloc(outH * outW, 4),
              let ctx = CGContext(data: data,
                                  width: outW, height: outH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // 输出坐标翻转（CG 坐标系 y 向上）
        ctx.translateBy(x: 0, y: CGFloat(outH))
        ctx.scaleBy(x: 1, y: -1)

        // 分块中心网格
        let step = tileSrc * overlap
        let regionSrc = tileSrc + marginSrc * 2   // 480
        let regionOut = Int((regionSrc * s).rounded())

        var centersX: [CGFloat] = []
        var cx = regionSrc / 2
        while cx < W - regionSrc/2 { centersX.append(cx); cx += step }
        centersX.append(W - regionSrc/2)

        var centersY: [CGFloat] = []
        var cy = regionSrc / 2
        while cy < H - regionSrc/2 { centersY.append(cy); cy += step }
        centersY.append(H - regionSrc/2)

        let total = centersX.count * centersY.count
        var done = 0

        for py in centersY {
            for px in centersX {
                autoreleasepool {
                    if let tile = runTile(src: src,
                                          center: CGPoint(x: px, y: py),
                                          region: regionSrc,
                                          regionOut: regionOut,
                                          scale: s,
                                          canvasH: outH) {
                        // 放置中心
                        let cxOut = px * s
                        let cyOut = py * s
                        let dx = (cxOut - CGFloat(regionOut)/2)
                        let dy = (cyOut - CGFloat(regionOut)/2)
                        ctx.draw(tile, in: CGRect(x: dx, y: dy,
                                                  width: CGFloat(regionOut),
                                                  height: CGFloat(regionOut)))
                    }
                }
                done += 1
                progress(Double(done)/Double(total))
            }
        }

        // 裁剪到精确尺寸（已是精确尺寸，直接取图）
        guard let finalCG = ctx.makeImage() else {
            free(data); return nil
        }

        // 写入 JPEG
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hjd_sr_\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            free(data); return nil
        }
        let meta: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifColorSpace: 1,
            ]
        ]
        CGImageDestinationAddImage(dest, finalCG, meta as CFDictionary)
        let ok = CGImageDestinationFinalize(dest)
        free(data)
        if !ok { return nil }

        // 缩略图（256px）
        let thumbSize = 256
        let thumb = UIImage(cgImage: finalCG)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: thumbSize, height: thumbSize))
        let thumbOut = renderer.image { _ in
            thumb.draw(in: CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize))
        }

        return UpscaleResult(fileURL: outURL, thumbnail: thumbOut)
    }

    // MARK: 单块：裁切 → 512 → 模型 → 2048 → regionOut（羽化）

    private static func runTile(src: CGImage,
                                center: CGPoint,
                                region: CGFloat,
                                regionOut: Int,
                                scale: CGFloat,
                                canvasH: Int) -> CGImage? {
        let W = CGFloat(src.width)
        let H = CGFloat(src.height)
        let cropRect = CGRect(x: center.x - region/2,
                              y: center.y - region/2,
                              width: region, height: region)
        // 边界保护
        let clamped = cropRect.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard let cropped = src.cropping(to: clamped) else { return nil }

        var tileCI = CIImage(cgImage: cropped)
        // 统一缩放为 512×512
        let scaleX = 512 / tileCI.extent.width
        let scaleY = 512 / tileCI.extent.height
        tileCI = tileCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        tileCI = tileCI.cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))

        guard let pb = PixelBufferFactory.render(tileCI, width: 512, height: 512,
                                                context: ci) else { return nil }
        guard let outPB = AIModelHub.shared.predictImage(
            model: .realesrgan,
            inputName: "input",
            outputName: "activation_out",
            input: pb) else {
            // 兜底：bicubic ×4
            let big = tileCI.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
            if let cg = ci.createCGImage(big, from: CGRect(x:0,y:0,width:2048,height:2048)) {
                return cg
            }
            return nil
        }

        var outCI = CIImage(cvPixelBuffer: outPB)
        // 缩放到 regionOut
        let k = CGFloat(regionOut) / outCI.extent.width
        outCI = outCI.transformed(by: CGAffineTransform(scaleX: k, y: k))
        outCI = outCI.cropped(to: CGRect(x: 0, y: 0,
                                         width: regionOut, height: regionOut))

        // 羽化遮罩（拼接去缝）
        let feather = CGFloat(marginSrc) * scale
        // 径向羽化
        let radial = CIFilter.radialGradient()
        radial.center = CGPoint(x: CGFloat(regionOut)/2, y: CGFloat(regionOut)/2)
        radial.radius0 = Float(CGFloat(regionOut)/2 - feather)
        radial.radius1 = Float(CGFloat(regionOut)/2)
        radial.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        radial.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        let masked = outCI.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: radial.outputImage ?? CIImage()
        ])

        return ci.createCGImage(masked, from: CGRect(
            x: 0, y: 0, width: regionOut, height: regionOut))
    }
}
