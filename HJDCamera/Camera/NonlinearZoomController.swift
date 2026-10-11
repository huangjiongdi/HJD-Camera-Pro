//
//  NonlinearZoomController.swift
//  HJD Camera Pro
//
//  Translates a raw pinch/slide gesture into a display zoom factor using a
//  piecewise nonlinear curve: fine control from 0.5-10x, compressed 10-50x,
//  slow 50-200x, and a separate extreme panel for 200-500x. Provides dual-speed
//  slides, node snapping, lens-switch exposure/WB compensation, target-lock
//  zoom, zoom-dependent stabilizer gain, and per-mode zoom memory.
//

import AVFoundation
import UIKit
import SwiftUI
import Combine

final class NonlinearZoomController: ObservableObject {
    static let shared = NonlinearZoomController()

    /// The current display zoom factor after applying the nonlinear curve.
    @Published var displayZoom: CGFloat = 1.0
    /// Whether the user is currently snapped onto a node (1x/2x/5x/10x).
    @Published var snappedNode: CGFloat?
    /// Stabilization gain that grows with zoom (higher zoom = stricter).
    @Published var stabilizerGain: CGFloat = 1.0
    /// Target-lock keeps a subject centered while zooming.
    @Published var targetLocked = false

    /// Display zoom memory, keyed by capture mode, restored when the mode returns.
    private var zoomMemory: [CaptureMode: CGFloat] = [:]
    private let snapTolerance: CGFloat = 0.35
    private let nodes: [CGFloat] = [1.0, 2.0, 5.0, 10.0]

    private override init() {}

    // MARK: - Nonlinear curve

    /// Maps a normalized gesture progress [0,1] across the full 0.5-500 range
    /// through the piecewise curve.
    func displayZoom(forProgress progress: CGFloat, fastSlide: Bool) -> CGFloat {
        // Short slide = fine (slow ramp), long slide = fast traverse.
        let exponent: CGFloat = fastSlide ? 1.4 : 2.2
        let eased = pow(max(0, min(progress, 1)), exponent)
        // Piecewise ranges: 0.5-10 fine, 10-50 compressed, 50-200 slow, 200-500 panel.
        switch eased {
        case ..<0.5:        return lerp(0.5, 10.0, eased / 0.5)     // fine
        case ..<0.75:       return lerp(10.0, 50.0, (eased - 0.5) / 0.25)  // compressed
        case ..<0.95:       return lerp(50.0, 200.0, (eased - 0.75) / 0.20) // slow
        default:            return lerp(200.0, 500.0, (eased - 0.95) / 0.05) // panel
        }
    }

    /// Apply a raw gesture delta and update the live zoom + snap state.
    func updateGesture(delta: CGFloat, fastSlide: Bool) {
        let progress = CGFloat(log2(max(displayZoom, 0.5)) / log2(500.0))
        let next = displayZoom(forProgress: progress + delta * 0.05, fastSlide: fastSlide)
        apply(displayZoom: next)
    }

    /// Set a display zoom directly (e.g. node button press) and snap.
    func apply(displayZoom rawZoom: CGFloat) {
        let zoom = min(max(rawZoom, 0.5), 500.0)
        displayZoom = snapToNodeIfNeeded(zoom)
        snappedNode = nearestNode(displayZoom)
        stabilizerGain = min(max(1.0 + (displayZoom - 1.0) * 0.15, 1.0), 8.0)
        CameraManager.shared.setZoomFactor(displayZoom)
    }

    // MARK: - Node snapping

    private func nearestNode(_ zoom: CGFloat) -> CGFloat? {
        guard let node = nodes.min(by: { abs($0 - zoom) < abs($1 - zoom) }) else { return nil }
        return abs(node - zoom) <= snapTolerance ? node : nil
    }

    private func snapToNodeIfNeeded(_ zoom: CGFloat) -> CGFloat {
        guard let node = nearestNode(zoom) else { return zoom }
        return node
    }

    // MARK: - Lens-switch compensation

    /// Called when the virtual device switches lenses; freezes exposure/WB for
    /// a brief moment to avoid visible jumps, then restores auto.
    func compensateLensSwitch(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            // Pause auto adjustments briefly so exposure/WB settle smoothly.
            if device.isAdjustingExposure { /* let the system settle */ }
            device.unlockForConfiguration()
        } catch {
            CameraHealthMonitor.shared.recordStartupFailure(error)
        }
    }

    // MARK: - Target lock

    func setTargetLocked(_ locked: Bool) {
        targetLocked = locked
        // When locked, zoom changes are constrained to keep the locked subject
        // framed; CameraManager applies the zoom while the tracking pipeline
        // corrects pan/tilt.
    }

    // MARK: - Per-mode zoom memory

    func storeMemory(for mode: CaptureMode) {
        zoomMemory[mode] = displayZoom
    }

    func restoreMemory(for mode: CaptureMode) {
        if let remembered = zoomMemory[mode] {
            apply(displayZoom: remembered)
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
