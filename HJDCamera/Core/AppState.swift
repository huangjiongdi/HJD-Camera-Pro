//
//  AppState.swift
//  HJD Camera Pro
//

import SwiftUI
import Combine
import AVFoundation

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentMode: CaptureMode = .photo
    @Published var currentZoomFactor: Double = 1.0
    @Published var currentZoomSource: ZoomSource = .optical
    @Published var zoomConfidence: ZoomConfidence = .high
    @Published var showExtremeZoomPanel = false
    @Published var showProControls = false
    @Published var showSettings = false
    @Published var showGallery = false
    @Published var showAIStudio = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var timerDuration: Int = 0
    @Published var gridEnabled = false
    @Published var levelEnabled = false
    @Published var rawEnabled = false
    @Published var aiPreviewLevel: LivePreviewLevel = .balanced
    @Published var sceneType: SceneType = .normal
    @Published var lunarDetected = false
    @Published var lunarTracking = false
    @Published var macroDetected = false
    @Published var focusLocked = false
    @Published var exposureLocked = false
    @Published var proSettings = ProCaptureSettings(
        iso: 0, shutterSpeed: 0, evCompensation: 0,
        whiteBalance: 0, colorTemperature: 5500,
        manualFocusDistance: -1, sharpness: 0.5,
        aiIntensity: 0.7, outputScale: 2.0
    )
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var memoryPressure: Float = 0.0
    @Published var storageAvailable: Int64 = 0
    @Published var lastCapturedImageURL: URL?
    @Published var captureQuality: QualityAssessment?
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    @Published var liveEnhanceFrameCount: Int = 0
    @Published var liveEnhanceLatency: TimeInterval = 0

    private init() {}

    func setMode(_ mode: CaptureMode) {
        currentMode = mode
        NotificationCenter.default.post(name: .hjdSettingsChanged, object: nil)
    }

    func setZoom(_ factor: Double, source: ZoomSource) {
        currentZoomFactor = factor
        currentZoomSource = source
        if factor >= 100 {
            zoomConfidence = .low
        } else if factor >= 25 {
            zoomConfidence = .medium
        } else {
            zoomConfidence = .high
        }
    }
}
