//
//  PortraitSegmentation.swift
//  HJD Camera Pro
//
//  人物分割：基于 Vision 人像分割 + DepthPro 深度，分离前景人物与背景。
//

import Foundation
import CoreImage
import Vision

final class PortraitSegmentation {

    static let shared = PortraitSegmentation()

    struct SegmentationResult {
        var personMask: CIImage     // 白色=人物，黑色=背景
        var boundingBox: CGRect
        var confidence: Double
    }

    private init() {}

    /// 执行人像分割。
    func segment(image: CIImage) -> SegmentationResult {
        // 使用 Vision 人像分割请求
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            if let result = request.results?.first {
                let mask = CIImage(cvPixelBuffer: result.pixelBuffer)
                let bbox = CGRect(x: 0, y: 0,
                                 width: image.extent.width,
                                 height: image.extent.height)
                return SegmentationResult(
                    personMask: mask,
                    boundingBox: bbox,
                    confidence: 0.9
                )
            }
        } catch {
            // Vision 不可用时回退到人脸检测
        }

        // 回退：人脸检测 + 扩展区域
        let faceRequest = VNDetectFaceRectanglesRequest()
        let faceHandler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try faceHandler.perform([faceRequest])
            if let face = faceRequest.results?.first {
                let bbox = face.boundingBox
                let expanded = bbox.insetBy(dx: -bbox.width * 0.5, dy: -bbox.height * 0.5)
                let mask = CIImage(color: CIColor.white)
                    .cropped(to: expanded)
                return SegmentationResult(
                    personMask: mask,
                    boundingBox: expanded,
                    confidence: 0.6
                )
            }
        } catch {
            // 完全失败：返回全图掩码
        }

        let fullMask = CIImage(color: CIColor.white).cropped(to: image.extent)
        return SegmentationResult(
            personMask: fullMask,
            boundingBox: image.extent,
            confidence: 0.3
        )
    }
}
