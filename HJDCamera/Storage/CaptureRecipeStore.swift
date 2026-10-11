//
//  CaptureRecipeStore.swift
//  HJD Camera Pro
//
//  Persists, loads, deletes and shares CaptureRecipe presets.
//

import Foundation
import UniformTypeIdentifiers

final class CaptureRecipeStore: ObservableObject {
    static let shared = CaptureRecipeStore()

    @Published private(set) var recipes: [CaptureRecipe] = []

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storeURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("HJDRecipes", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recipes.json")
    }

    private init() {
        load()
    }

    // MARK: - Load / Save

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else {
            recipes = []
            return
        }
        do {
            recipes = try decoder.decode([CaptureRecipe].self, from: data)
        } catch {
            DiagnosticLogger.shared.error("Failed to load recipes: \(error.localizedDescription)")
            recipes = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(recipes)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            DiagnosticLogger.shared.error("Failed to persist recipes: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    func save(_ recipe: CaptureRecipe) {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        persist()
    }

    func recipe(named name: String) -> CaptureRecipe? {
        recipes.first { $0.name == name }
    }

    func delete(id: UUID) {
        recipes.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        recipes.removeAll()
        persist()
    }

    // MARK: - Share

    /// Exports a recipe to a JSON file that can be shared via the system sheet.
    func shareData(for recipe: CaptureRecipe) -> Data? {
        try? encoder.encode(recipe)
    }

    /// Imports a recipe from shared JSON data.
    @discardableResult
    func `import`(data: Data) -> CaptureRecipe? {
        do {
            var recipe = try decoder.decode(CaptureRecipe.self, from: data)
            recipe = CaptureRecipe(
                id: UUID(),
                name: recipe.name,
                mode: recipe.mode,
                lens: recipe.lens,
                zoomFactor: recipe.zoomFactor,
                iso: recipe.iso,
                shutterSpeed: recipe.shutterSpeed,
                ev: recipe.ev,
                whiteBalance: recipe.whiteBalance,
                modelName: recipe.modelName,
                lutName: recipe.lutName,
                aiIntensity: recipe.aiIntensity,
                createdAt: Date()
            )
            save(recipe)
            return recipe
        } catch {
            DiagnosticLogger.shared.error("Failed to import recipe: \(error.localizedDescription)")
            return nil
        }
    }
}
