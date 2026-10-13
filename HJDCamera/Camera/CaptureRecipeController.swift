//
//  CaptureRecipeController.swift
//  HJD Camera Pro
//
//  Records and reproduces capture "recipes" — the full lens / exposure / zoom /
//  AI-model / LUT / processing state that produced a great shot. Recipes are
//  persisted as Codable CaptureRecipe entries and can be re-applied in one tap.
//

import Foundation
import SwiftUI

final class CaptureRecipeController: ObservableObject {
    static let shared = CaptureRecipeController()

    @Published var recipes: [CaptureRecipe] = []

    private let storageKey = "hjd.captureRecipes"

    private init() {
        load()
    }

    // MARK: - Record

    /// Build a recipe from the current live camera state.
    func recordCurrentRecipe(name: String, modelName: String, lutName: String) {
        let app = AppState.shared
        let recipe = CaptureRecipe(
            id: UUID(),
            name: name,
            mode: app.currentMode.rawValue,
            lens: CameraManager.shared.currentDevice?.localizedName ?? "Back",
            zoomFactor: Double(CameraManager.shared.currentZoomFactor),
            iso: app.proSettings.iso,
            shutterSpeed: app.proSettings.shutterSpeed,
            ev: app.proSettings.evCompensation,
            whiteBalance: app.proSettings.whiteBalance,
            modelName: modelName,
            lutName: lutName,
            aiIntensity: app.proSettings.aiIntensity,
            createdAt: Date()
        )
        recipes.insert(recipe, at: 0)
        save()
    }

    // MARK: - Reproduce

    /// Re-apply a recipe to the live camera.
    func apply(_ recipe: CaptureRecipe) {
        let app = AppState.shared
        if let mode = CaptureMode(rawValue: recipe.mode) {
            app.setMode(mode)
        }
        CameraManager.shared.setZoomFactor(CGFloat(recipe.zoomFactor))
        app.proSettings.iso = recipe.iso
        app.proSettings.shutterSpeed = recipe.shutterSpeed
        app.proSettings.evCompensation = recipe.ev
        app.proSettings.whiteBalance = recipe.whiteBalance
        app.proSettings.aiIntensity = recipe.aiIntensity
    }

    // MARK: - Management

    func deleteRecipe(_ recipe: CaptureRecipe) {
        recipes.removeAll { $0.id == recipe.id }
        save()
    }

    func renameRecipe(_ recipe: CaptureRecipe, to name: String) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].name = name
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CaptureRecipe].self, from: data) else {
            return
        }
        recipes = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recipes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
