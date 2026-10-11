//
//  OrientationObserver.swift
//  HJD Camera Pro
//
//  Observes physical device orientation and exposes the matching video rotation
//  angle used by AVCaptureVideoPreviewLayer and capture connections. All
//  consumers (preview layer, photo output, movie output) read from this single
//  source of truth so rotation stays consistent across the app.
//

import SwiftUI
import Combine
import UIKit

final class OrientationObserver: ObservableObject {
    static let shared = OrientationObserver()

    /// Current physical device orientation (only valid interface orientations are published).
    @Published var deviceOrientation: UIDeviceOrientation = .portrait

    /// Rotation angle (degrees) to apply to a back-camera capture connection in portrait-facing capture.
    @Published var videoRotationAngle: CGFloat = 90

    private var cancellables = Set<AnyCancellable>()

    private init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .compactMap { _ in UIDevice.current.orientation }
            .filter { $0.isValidInterfaceOrientation }
            .sink { [weak self] orientation in
                guard let self = self else { return }
                self.deviceOrientation = orientation
                self.videoRotationAngle = self.rotationAngle(for: orientation)
            }
            .store(in: &cancellables)
    }

    /// Maps a physical device orientation to the rotation angle required by a
    /// back-facing camera connection so recorded/captured media is upright.
    func rotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:            return 90
        case .portraitUpsideDown:  return 270
        case .landscapeRight:      return 0    // device rotated clockwise, home button on the right
        case .landscapeLeft:       return 180  // device rotated counter-clockwise, home button on the left
        default:                   return 90
        }
    }

    /// Convenience used by still-image orientation metadata.
    var imageOrientation: CGImagePropertyOrientation {
        switch deviceOrientation {
        case .portrait:           return .right
        case .portraitUpsideDown: return .left
        case .landscapeRight:     return .up
        case .landscapeLeft:      return .down
        default:                  return .right
        }
    }
}
