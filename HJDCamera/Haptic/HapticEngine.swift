import Foundation
import UIKit
import CoreHaptics
import AudioToolbox

// MARK: - 触感事件

enum HapticEvent {
    case shutter
    case focusLocked
    case zoomStep
    case aiMomentFound
    case superResolutionFinished
    case superMoonLocked
    case telephotoLocked
    case recordingStart
    case exportFinished
    case error
}

/// 相机触感引擎（统一触感语言，模拟真实相机）
final class HapticEngine {

    static let shared = HapticEngine()
    private init() {}

    private var engine: CHHapticEngine?

    private func ensureEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine = try? CHHapticEngine()
        try? engine?.start()
        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
        }
        self.engine = engine
        return engine
    }

    // 系统触感（即时反馈，更强烈）
    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle,
                        intensity: CGFloat = 1.0) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred(intensity: intensity)
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: 播放

    func play(_ event: HapticEvent) {
        // 关键操作：系统触感（快、稳、强）
        switch event {
        case .shutter:
            impact(.rigid, intensity: 0.9)
        case .focusLocked:
            impact(.medium, intensity: 0.7)
        case .zoomStep:
            impact(.light, intensity: 0.6)
        case .aiMomentFound:
            impact(.medium, intensity: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.impact(.medium, intensity: 0.8)
            }
        case .superResolutionFinished:
            impact(.medium, intensity: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.impact(.heavy, intensity: 0.7)
            }
        case .superMoonLocked:
            notify(.success)
        case .telephotoLocked:
            impact(.heavy, intensity: 0.9)
        case .recordingStart:
            notify(.success)
        case .exportFinished:
            notify(.success)
        case .error:
            notify(.error)
        }
    }
}

/// 快门声（系统快门音）
enum ShutterSound {
    static func play() {
        // 使用系统拍照音（PhotoShutter）
        if let url = URL(fileURLWithPath:
            "/System/Library/Audio/UISounds/photoShutter.caf") as URL? {
            var id: SystemSoundID = 1108
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            AudioServicesPlaySystemSound(id)
        } else {
            AudioServicesPlaySystemSound(1108)
        }
    }
}
