//
//  HJDCameraApp.swift
//  HJD Camera Pro
//

import SwiftUI
import AVFoundation
import Photos
import CoreLocation

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

    init() {
        // 尽早安装快门崩溃追踪，保证任何阶段闪退都能把原因写进诊断日志。
        ShutterTrace.install()
    }

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
                    requestPermissionsAndStartCamera()
                }
        }
    }

    /// Request all runtime permissions up front, then configure & start the
    /// capture session. Starting the session before camera permission is granted
    /// leaves the preview black until the user flips the camera — so we wait.
    private func requestPermissionsAndStartCamera() {
        Task {
            async let cameraGranted = AVCaptureDevice.requestAccess(for: .video)
            async let micGranted = AVCaptureDevice.requestAccess(for: .audio)
            async let photoGranted = PHPhotoLibrary.requestAuthorization(for: .readWrite)
            _ = await (cameraGranted, micGranted, photoGranted)

            // Location (for EXIF GPS) — best effort.
            let loc = CLLocationManager()
            loc.requestWhenInUseAuthorization()

            await MainActor.run {
                cameraManager.configureSession()
                cameraManager.startSession()
            }
        }
    }
}
