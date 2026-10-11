//
//  ModelLicenseRegistry.swift
//  HJD Camera Pro
//
//  Registers every bundled / downloaded model with its license and declares the
//  open-source components used by the app.
//

import Foundation

struct ModelLicense: Identifiable {
    let id: String          // model id
    let name: String
    let license: String     // e.g. "MIT", "Apache-2.0", "CC-BY-NC-4.0"
    let attribution: String
    let source: String
}

struct OpenSourceComponent: Identifiable {
    let id = UUID()
    let name: String
    let license: String
    let text: String
}

final class ModelLicenseRegistry {
    static let shared = ModelLicenseRegistry()

    private(set) var licenses: [ModelLicense] = []
    private(set) var components: [OpenSourceComponent] = []

    private init() {
        registerDefaults()
    }

    // MARK: - Registration

    func register(_ license: ModelLicense) {
        licenses.removeAll { $0.id == license.id }
        licenses.append(license)
    }

    func license(forModelID id: String) -> ModelLicense? {
        licenses.first { $0.id == id }
    }

    // MARK: - Defaults

    private func registerDefaults() {
        licenses = [
            ModelLicense(
                id: "superres-general-v2",
                name: "通用超分 v2",
                license: "Proprietary",
                attribution: "HJD Research",
                source: "Bundled"
            ),
            ModelLicense(
                id: "lunar-surface-v1",
                name: "超级月亮增强 v1",
                license: "Proprietary",
                attribution: "HJD Research",
                source: "Bundled"
            )
        ]

        components = [
            OpenSourceComponent(
                name: "CoreImage",
                license: "Apple SDK",
                text: "System framework, licensed under Apple's SDK terms."
            ),
            OpenSourceComponent(
                name: "Metal Performance Shaders",
                license: "Apple SDK",
                text: "System framework, licensed under Apple's SDK terms."
            )
        ]
    }

    // MARK: - Export

    func fullLicenseAttribution() -> String {
        var lines = ["HJD Camera Pro — Open Source & Model Attributions", ""]
        lines += licenses.map { "• \($0.name) — \($0.license) (\($0.attribution))" }
        lines += ["", "Open Source Components:"]
        lines += components.map { "• \($0.name) — \($0.license)" }
        return lines.joined(separator: "\n")
    }
}
