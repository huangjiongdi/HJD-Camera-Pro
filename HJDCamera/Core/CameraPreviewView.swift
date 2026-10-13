//
//  CameraPreviewView.swift
//  HJD Camera Pro
//
//  SwiftUI wrapper around AVCaptureVideoPreviewLayer. Keeps the live preview
//  rotation in sync with OrientationObserver and exposes a double-tap gesture
//  that jumps to a 2x "focus check" zoom so the user can inspect focus.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Called with the tap location (in view coordinates) for tap-to-focus/expose.
    var onTapAt: ((CGPoint) -> Void)?
    /// Called when the user double-taps; toggles a focus-check zoom.
    var onDoubleTap: (() -> Void)?

    @ObservedObject private var orientation = OrientationObserver.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // Expose the live layer for rotation/metadata inspection. 硬件上限
        // 以上的数字裁切（>100× 到 500×）由 CameraPreviewContainer 的
        // .scaleEffect 驱动，不再直接改 layer.transform。
        DispatchQueue.main.async {
            CameraManager.shared.previewLayer = view.videoPreviewLayer
        }

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        context.coordinator.previewView = view
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.updateRotation(angle: orientation.videoRotationAngle)
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: CameraPreviewView
        weak var previewView: PreviewContainerView?

        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            parent.onTapAt?(point)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap?()
        }
    }

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        func updateRotation(angle: CGFloat) {
            guard let connection = videoPreviewLayer.connection,
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
