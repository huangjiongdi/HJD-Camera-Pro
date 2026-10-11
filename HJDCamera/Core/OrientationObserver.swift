import SwiftUI
import UIKit
import Combine

// MARK: - 设备方向观察器

final class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = .portrait

    private var cancellable: AnyCancellable?

    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        cancellable = NotificationCenter.default
            .publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                let o = UIDevice.current.orientation
                if o.isLandscape || o == .portrait {
                    self?.orientation = o
                }
            }
    }
}

// MARK: - 预览尺寸辅助

enum PreviewGeometry {
    /// 视频预览按画面比例显示的尺寸（用于照片 4:3 / 视频 16:9）
    static func previewSize(in container: CGSize, aspect: CGFloat,
                            isLandscape: Bool) -> CGSize {
        if isLandscape {
            return CGSize(width: container.width, height: container.height)
        }
        // 照片：按比例展示，上下留黑
        let w = container.width
        let h = w / aspect
        return CGSize(width: w, height: min(h, container.height))
    }
}
