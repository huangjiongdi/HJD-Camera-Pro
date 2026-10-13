//
//  FaceIdentityGuard.swift
//  HJD Camera Pro
//
//  身份特征保护：防止 AI 超分改变脸型、五官比例，保持人物识别度。
//

import Foundation
import CoreImage
import Vision

final class FaceIdentityGuard {

    static let shared = FaceIdentityGuard()

    struct IdentityReport {
        var identityPreserved: Bool
        var landmarkDeviation: Double  // 五官关键点偏移量
        var suggestion: String
    }

    private init() {}

    /// 对比原图与处理后图像，检测五官是否变形。
    func check(original: CIImage, processed: CIImage) -> IdentityReport {
        // 提取两张图的面部特征点
        let origLandmarks = extractLandmarks(original)
        let procLandmarks = extractLandmarks(processed)

        guard !origLandmarks.isEmpty, !procLandmarks.isEmpty else {
            return IdentityReport(identityPreserved: true,
                                 landmarkDeviation: 0,
                                 suggestion: "无法检测面部特征，默认保留")
        }

        // 计算特征点平均偏移
        var totalDeviation: Double = 0
        let count = min(origLandmarks.count, procLandmarks.count)
        for i in 0..<count {
            let dx = origLandmarks[i].x - procLandmarks[i].x
            let dy = origLandmarks[i].y - procLandmarks[i].y
            totalDeviation += sqrt(dx*dx + dy*dy)
        }
        let avgDeviation = totalDeviation / Double(count)
        let normalizedDeviation = min(1.0, avgDeviation * 100.0)

        let preserved = normalizedDeviation < 0.3
        let suggestion = preserved ? "面部身份特征保持良好" : "检测到面部变形，建议降低增强强度"

        return IdentityReport(
            identityPreserved: preserved,
            landmarkDeviation: normalizedDeviation,
            suggestion: suggestion
        )
    }

    private func extractLandmarks(_ image: CIImage) -> [CGPoint] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first else { return [] }
            var points: [CGPoint] = []
            if let leftEye = face.landmarks?.leftEye {
                points.append(contentsOf: leftEye.normalizedPoints)
            }
            if let rightEye = face.landmarks?.rightEye {
                points.append(contentsOf: rightEye.normalizedPoints)
            }
            if let nose = face.landmarks?.nose {
                points.append(contentsOf: nose.normalizedPoints)
            }
            if let mouth = face.landmarks?.outerLips {
                points.append(contentsOf: mouth.normalizedPoints)
            }
            return points
        } catch {
            return []
        }
    }
}
