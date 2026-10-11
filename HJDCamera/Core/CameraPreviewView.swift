import SwiftUI
import AVFoundation
import UIKit

// MARK: - 相机预览视图（画面随方向旋转）

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var digitalScale: CGFloat
    let orientation: UIDeviceOrientation

    func makeUIView(context: Context) -> PreviewContainer {
        let view = PreviewContainer()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.connection?.videoOrientation = Self.map(orientation)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewContainer, context: Context) {
        // 数字裁切（高倍）
        let s = max(1, digitalScale)
        view.previewLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        view.previewLayer.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        // 方向
        if let conn = view.previewLayer.connection, conn.isVideoOrientationSupported {
            let target = Self.map(orientation)
            if conn.videoOrientation != target {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.25)
                conn.videoOrientation = target
                CATransaction.commit()
            }
        }
    }

    static func map(_ o: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch o {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default:
            // 退回当前界面方向
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                switch scene.interfaceOrientation {
                case .landscapeLeft: return .landscapeLeft
                case .landscapeRight: return .landscapeRight
                case .portraitUpsideDown: return .portraitUpsideDown
                default: return .portrait
                }
            }
            return .portrait
        }
    }
}

final class PreviewContainer: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
