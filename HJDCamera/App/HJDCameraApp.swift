//
//  HJDCameraApp.swift
//  HJD Camera Pro
//

import SwiftUI

@main
struct HJDCameraApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var settingsStore = AppSettingsStore.shared
    @StateObject private var hapticEngine = HapticEngine.shared
    @StateObject private var aiModelRegistry = AIModelRegistry.shared
    @StateObject private var aiProcessingQueue = AIProcessingQueue.shared
    @StateObject private var storageManager = StorageManager.shared
    @StateObject private var diagnosticLogger = DiagnosticLogger.shared
    @StateObject private var lutManager = LUTManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(cameraManager)
                .environmentObject(settingsStore)
                .environmentObject(hapticEngine)
                .environmentObject(aiModelRegistry)
                .environmentObject(aiProcessingQueue)
                .environmentObject(storageManager)
                .environmentObject(diagnosticLogger)
                .environmentObject(lutManager)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .onAppear {
                    diagnosticLogger.log("App launched", category: .app)
                    aiModelRegistry.loadBundledModels()
                    cameraManager.startSession()
                }
        }
    }
}
