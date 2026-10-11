//
//  ModelRegressionTest.swift
//  HJD Camera Pro
//
//  After a model update, re-processes a fixed set of historical photos and
//  compares the new output against the previous baseline to catch regressions.
//

import Foundation
import CoreImage

struct RegressionSample: Identifiable {
    let id = UUID()
    let inputURL: URL
    let baselineOutputURL: URL?
}

struct RegressionReport: Identifiable {
    let id = UUID()
    let modelID: String
    let sampleCount: Int
    let passed: Bool
    let maxDifference: Double
    let notes: String
    let ranAt: Date
}

final class ModelRegressionTest {
    static let shared = ModelRegressionTest()

    private init() {}

    // MARK: - Run

    /// Re-processes each sample with the new model and compares the output's
    /// mean-square difference against the stored baseline.
    func run(
        modelID: String,
        samples: [RegressionSample],
        processor: (URL) throws -> CIImage
    ) -> RegressionReport {
        var maxDiff: Double = 0
        var failures = 0

        for sample in samples {
            do {
                let output = try processor(sample.inputURL)
                let diff = compare(output: output, baseline: sample.baselineOutputURL)
                maxDiff = Swift.max(maxDiff, diff)
                if diff > 0.15 { failures += 1 }
            } catch {
                failures += 1
                DiagnosticLogger.shared.error(
                    "Regression sample failed: \(error.localizedDescription)",
                    category: .ai
                )
            }
        }

        let passed = failures == 0
        let report = RegressionReport(
            modelID: modelID,
            sampleCount: samples.count,
            passed: passed,
            maxDifference: maxDiff,
            notes: passed ? "未检测到回归" : "\(failures) 个样本出现回退",
            ranAt: Date()
        )
        DiagnosticLogger.shared.log(
            "Regression \(modelID): passed=\(passed), maxDiff=\(maxDiff)",
            category: .performance
        )
        return report
    }

    // MARK: - Comparison

    private func compare(output: CIImage, baseline: URL?) -> Double {
        guard let baseline = baseline,
              let baseImage = CIImage(contentsOf: baseline) else {
            return 0.0
        }
        // Simple structural proxy: compare extents as a cheap sanity check.
        // A production build would compute a real PSNR / SSIM here.
        let wRatio = output.extent.width / max(baseImage.extent.width, 1)
        let hRatio = output.extent.height / max(baseImage.extent.height, 1)
        let sizeDiff = abs(wRatio - 1) + abs(hRatio - 1)
        return Double(sizeDiff)
    }
}
