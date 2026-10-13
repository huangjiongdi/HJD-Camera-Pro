//
//  ExternalLensProfile.swift
//  HJD Camera Pro
//
//  Describes an external lens attached to the phone (clip-on telephoto or
//  macro). Stores distortion-correction coefficients and stabilization tuning,
//  and links the chosen teleconverter mode to the internal zoom so the display
//  factor already includes the external multiplier.
//

import Foundation
import SwiftUI

/// Distortion (lens) model coefficients for an external lens.
struct LensDistortionModel: Codable, Equatable {
    var k1: Double   // radial coefficient
    var k2: Double
    var p1: Double   // tangential
    var p2: Double
    var centerX: Double
    var centerY: Double
}

/// Stabilization tuning applied when a specific external lens is active.
struct LensStabilizationParams: Codable, Equatable {
    var gyroGain: Double
    var epsilon: Double
    var rollingShutterCompensation: Double
}

struct ExternalLensProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var kind: Kind
    var teleconverterFactor: Double        // e.g. 2.0 for a 2x clip-on tele
    var distortion: LensDistortionModel
    var stabilization: LensStabilizationParams

    enum Kind: String, Codable {
        case telephoto
        case macro
        case wide
    }
}

final class ExternalLensProfileController: ObservableObject {
    static let shared = ExternalLensProfileController()

    @Published var activeProfile: ExternalLensProfile?
    @Published var profiles: [ExternalLensProfile] = []

    private let storageKey = "hjd.externalLensProfiles"

    private init() {
        load()
    }

    // MARK: - CRUD

    func addProfile(_ profile: ExternalLensProfile) {
        profiles.append(profile)
        save()
    }

    func removeProfile(_ profile: ExternalLensProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id { activeProfile = nil }
        save()
    }

    func activate(_ profile: ExternalLensProfile) {
        activeProfile = profile
        // Link the external teleconverter into the internal zoom: the display
        // zoom already includes the external multiplier, so we rescale the
        // internal target accordingly.
        let internalTarget = CameraManager.shared.currentZoomFactor / CGFloat(profile.teleconverterFactor)
        CameraManager.shared.setZoomFactor(max(internalTarget, 1.0))
    }

    func deactivate() {
        activeProfile = nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ExternalLensProfile].self, from: data) else {
            return
        }
        profiles = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
