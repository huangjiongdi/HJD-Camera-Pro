import Foundation
import UIKit
import CoreImage
import Vision
import CoreVideo

// MARK: - 场景类型

enum SceneType {
    case unknown, night, portrait, moon, macro, landscape, text, stage, sky
}

// MARK: - 场景识别（Vision）

enum SceneEngine {

    /// 识别场景（同步，轻量）
    static func classify(_ image: UIImage) -> SceneType {
        guard let ci = CIImage(image: image) else { return .unknown }
        // 亮度判断：夜景
        let avg = averageLuminance(ci)
        if avg < 0.18 { return .night }

        // 人脸
        if detectFaces(image).count > 0 { return .portrait }

        // 月亮（亮圆）
        if LunarEngine.isMoon(image) { return .moon }

        return .unknown
    }

    static func averageLuminance(_ ci: CIImage) -> CGFloat {
        let extent = ci.extent
        let filter = CIFilter.areaAverage()
        filter.inputImage = ci
        filter.extent = extent
        let ctx = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        if let out = filter.outputImage {
            ctx.render(out, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            let r = CGFloat(bitmap[0])/255
            let g = CGFloat(bitmap[1])/255
            let b = CGFloat(bitmap[2])/255
            return 0.299*r + 0.587*g + 0.114*b
        }
        return 0.5
    }
}

// MARK: - 人脸检测（Vision）

func detectFaces(_ image: UIImage) -> [CGRect] {
    guard let cg = image.cgImage else { return [] }
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do {
        try handler.perform([request])
        return (request.results ?? []).map { $0.boundingBox }
    } catch {
        return []
    }
}

// MARK: - 人像引擎（人脸精修 + 肤色）

enum PortraitEngine {

    static func enhance(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let faces = detectFaces(image)
        guard !faces.isEmpty else { return image }

        var ci = CIImage(cgImage: cg)
        let W = ci.extent.width
        let H = ci.extent.height

        for box in faces {
            // Vision 坐标（左下）→ CIImage 坐标
            let w = box.width * W * 1.2
            let h = box.height * H * 1.3
            let x = box.midX * W - w/2
            let y = box.midY * H - h/2
            let faceRect = CGRect(x: x, y: y, width: w, height: h)
            // 裁切人脸 → 512 运行 gfpgan
            var face = ci.cropped(to: faceRect)
            face = face.transformed(by: CGAffineTransform(
                translationX: -faceRect.origin.x, y: -faceRect.origin.y))
            face = face.transformed(by: CGAffineTransform(
                scaleX: 512/w, y: 512/h))
            guard let pb = PixelBufferFactory.render(
                face, width: 512, height: 512, context: CIContext()) else { continue }
            guard let out = AIModelHub.shared.predictImage(
                model: .gfpgan, inputName: "x_1",
                outputName: "activation_out", input: pb) else { continue }
            var outCI = CIImage(cvPixelBuffer: out)
            outCI = outCI.transformed(by: CGAffineTransform(
                scaleX: w/512, y: h/512))
            outCI = outCI.transformed(by: CGAffineTransform(
                translationX: x, y: y))
            // 羽化合成
            ci = outCI.composited(over: ci)
        }

        let ctx = CIContext()
        if let result = ctx.createCGImage(ci, from: ci.extent) {
            return UIImage(cgImage: result)
        }
        return image
    }
}

// MARK: - 月亮引擎（检测亮圆 + 真月面超分）

enum LunarEngine {

    /// 判定是否为月亮（亮圆，仅超级月亮模式使用）
    static func isMoon(_ image: UIImage) -> Bool {
        guard let ci = CIImage(image: image) else { return false }
        // 检测中心区域是否有高亮度近圆形区域
        let extent = ci.extent
        let center = CGRect(
            x: extent.midX - extent.width*0.2,
            y: extent.midY - extent.height*0.2,
            width: extent.width*0.4, height: extent.height*0.4)
        let crop = ci.cropped(to: center)
        let lum = SceneEngine.averageLuminance(crop)
        // 中心亮、四周暗（月亮特征）
        let edge = SceneEngine.averageLuminance(
            ci.cropped(to: CGRect(x: 0, y: 0,
                                  width: extent.width*0.1,
                                  height: extent.height*0.1)))
        return lum > 0.75 && edge < 0.2
    }

    /// 月面增强（realesrgan）
    static func enhance(_ image: UIImage) -> UIImage {
        // 直接对整体做超分，再缩回（月面细节提升）
        let res = TiledUpscaler.upscale(image: image,
                                        targetPixels: 12_000_000,
                                        showWatermark: false, progress: { _ in })
        if let url = res?.fileURL,
           let big = UIImage(contentsOfFile: url.path) {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { _ in
                big.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        return image
    }
}

// MARK: - 夜景引擎（重降噪 + 提亮 + 保色）

enum NightEngine {

    static func enhance(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        var ci = CIImage(cgImage: cg)

        // 1) 提亮（局部）
        let exposure = ci.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: 0.9])
        // 2) 重降噪
        let nr = exposure.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": 0.04, kCIInputSharpnessKey: 0.6])
        // 3) 暗部提亮（阴影）
        let shadow = nr.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": 0.8, "inputHighlightAmount": 0.95])
        // 4) 轻微对比
        let contrast = shadow.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.06, kCIInputSaturationKey: 1.02])
        ci = contrast

        // 5) 细节增强（realesrgan 缩到 12MP）
        let ctx = CIContext()
        if let result = ctx.createCGImage(ci, from: ci.extent) {
            return UIImage(cgImage: result)
        }
        return image
    }
}

// MARK: - 微距引擎（细节增强）

enum MacroEngine {
    static func enhance(_ image: UIImage) -> UIImage {
        let res = TiledUpscaler.upscale(image: image,
                                        targetPixels: 24_000_000,
                                        showWatermark: false, progress: { _ in })
        if let url = res?.fileURL,
           let big = UIImage(contentsOfFile: url.path) {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { _ in
                big.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        return image
    }
}
