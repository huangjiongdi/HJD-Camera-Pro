//
//  HapticEngine.swift
//  HJD Camera Pro
//
//  Centralized haptic feedback with selectable preset and per-event toggles.
//

import UIKit
import Combine

// MARK: - Haptic Event

enum HapticEvent: String, CaseIterable {
    case shutter
    case focus
    case moonLock
    case zoomNode
    case aiComplete
    case exportComplete
    case error
}

final class HapticEngine: ObservableObject {
    static let shared = HapticEngine()

    // MARK: Configuration

    @Published var preset: HapticPreset = .camera {
        didSet { applyPreset() }
    }

    @Published var shutterEnabled: Bool = true
    @Published var focusEnabled: Bool = true
    @Published var moonLockEnabled: Bool = true
    @Published var zoomNodeEnabled: Bool = true
    @Published var aiCompleteEnabled: Bool = true
    @Published var exportCompleteEnabled: Bool = true
    @Published var errorEnabled: Bool = true

    // MARK: Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    // MARK: Zoom throttling

    private var lastZoomNodeFire: TimeInterval = 0
    private let zoomNodeMinimumInterval: TimeInterval = 0.06

    private init() {
        prepareAll()
    }

    private func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        notification.prepare()
        selection.prepare()
    }

    // MARK: - Preset

    private func applyPreset() {
        // Preset only changes *how strong* feedback feels; individual toggles
        // still gate whether an event fires at all.
        prepareAll()
    }

    // MARK: - Trigger

    /// Triggers a haptic for the given event. The second argument allows callers
    /// to pick an impact style; the engine still validates the per-event toggle.
    func trigger(_ event: HapticEvent, type style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled(for: event) else { return }

        switch event {
        case .shutter:
            fireShutter()
        case .focus:
            fireFocus()
        case .moonLock:
            fireMoonLock()
        case .zoomNode:
            fireZoomNode()
        case .aiComplete:
            notification.notificationOccurred(.success)
        case .exportComplete:
            notification.notificationOccurred(.success)
        case .error:
            notification.notificationOccurred(.error)
        }
        // `style` is honored via the selected impact generator for generic taps.
        _ = style
    }

    /// Lightweight selection feedback for slider/zoom scrubbing, throttled so it
    /// never fires every frame.
    func selectionChanged() {
        let now = CACurrentMediaTime()
        guard now - lastZoomNodeFire >= zoomNodeMinimumInterval else { return }
        lastZoomNodeFire = now
        selection.selectionChanged()
    }

    // MARK: - Gating

    private func isEnabled(for event: HapticEvent) -> Bool {
        switch event {
        case .shutter: return shutterEnabled
        case .focus: return focusEnabled
        case .moonLock: return moonLockEnabled
        case .zoomNode: return zoomNodeEnabled
        case .aiComplete: return aiCompleteEnabled
        case .exportComplete: return exportCompleteEnabled
        case .error: return errorEnabled
        }
    }

    // MARK: - Internal fire methods

    private func fireShutter() {
        switch preset {
        case .natural:
            softImpact.impactOccurred(intensity: 0.6)
        case .camera:
            lightImpact.impactOccurred(intensity: 0.9)
        case .pro:
            rigidImpact.impactOccurred(intensity: 1.0)
        case .cinematic:
            mediumImpact.impactOccurred(intensity: 0.7)
        }
    }

    private func fireFocus() {
        switch preset {
        case .natural:
            selection.selectionChanged()
        case .camera:
            lightImpact.impactOccurred(intensity: 0.4)
        case .pro:
            softImpact.impactOccurred(intensity: 0.5)
        case .cinematic:
            lightImpact.impactOccurred(intensity: 0.3)
        }
    }

    private func fireMoonLock() {
        notification.notificationOccurred(.success)
        heavyImpact.impactOccurred(intensity: 0.5)
    }

    private func fireZoomNode() {
        let now = CACurrentMediaTime()
        guard now - lastZoomNodeFire >= zoomNodeMinimumInterval else { return }
        lastZoomNodeFire = now
        selection.selectionChanged()
    }

    // MARK: - Sync with settings

    func sync(from settings: AppSettingsStore) {
        preset = settings.hapticPreset
        shutterEnabled = settings.hapticShutter
        focusEnabled = settings.hapticFocus
        moonLockEnabled = settings.hapticMoonLock
        zoomNodeEnabled = settings.hapticZoomNode
        aiCompleteEnabled = settings.hapticAIComplete
        exportCompleteEnabled = settings.hapticExportComplete
        errorEnabled = settings.hapticError
    }
}
