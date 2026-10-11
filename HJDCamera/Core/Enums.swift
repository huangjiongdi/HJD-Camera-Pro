import Foundation
import CoreGraphics
import SwiftUI

// MARK: - 应用界面路由

enum AppScreen {
    case camera
    case gallery
    case aiEditor
}

// MARK: - 拍摄模式

enum ShootingMode: String, CaseIterable, Identifiable {
    case photo      = "照片"
    case portrait   = "人像"
    case video      = "视频"
    case sloMo      = "慢动作"
    case night      = "夜景"
    case moon       = "超级月亮"
    case pro        = "专业"
    case macro      = "长焦微距"
    case timelapse  = "延时"
    case burst      = "连拍"
    case multiExposure = "多重曝光"
    case panorama   = "全景"

    var id: String { rawValue }
    var isVideo: Bool { self == .video || self == .sloMo || self == .timelapse }
}

// MARK: - 曝光模式 P/A/S/M

enum ExposureMode: String, CaseIterable, Identifiable {
    case program    = "P"
    case aperture   = "A"
    case shutter    = "S"
    case manual     = "M"
    var id: String { rawValue }
}

// MARK: - 视频色彩空间

enum VideoColorSpace: String, CaseIterable, Identifiable {
    case sdr      = "SDR"
    case hdr      = "HDR"
    case dolby    = "杜比视界"
    case log      = "LOG"
    var id: String { rawValue }
}

// MARK: - 分辨率

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case mp12  = "12MP"
    case mp24  = "24MP"
    case mp48  = "48MP"
    case mp50  = "50MP"
    case mp100 = "100MP"
    case mp200 = "200MP"
    case mp300 = "300MP"
    case mp400 = "400MP"

    var id: String { rawValue }
    /// 目标总像素数
    var targetPixels: Int {
        switch self {
        case .mp12:  return 12_000_000
        case .mp24:  return 24_000_000
        case .mp48:  return 48_000_000
        case .mp50:  return 50_000_000
        case .mp100: return 100_000_000
        case .mp200: return 200_000_000
        case .mp300: return 300_000_000
        case .mp400: return 400_000_000
        }
    }

    var megapixels: Int {
        let v = rawValue
        return Int(v.prefix(while: { $0.isNumber })) ?? 12
    }
}

/// 像素约束（随焦段/夜景变化）
enum PixelConstraints {
    static func clampPreset(_ preset: ResolutionPreset,
                            zoom: CGFloat,
                            isNight: Bool) -> ResolutionPreset {
        // 50× 以上：最高 50MP
        if zoom > 50 {
            if preset.targetPixels > ResolutionPreset.mp50.targetPixels {
                return .mp50
            }
            return preset
        }
        // 夜景：最高 200MP
        if isNight {
            if preset.targetPixels > ResolutionPreset.mp200.targetPixels {
                return .mp200
            }
        }
        return preset
    }
}

// MARK: - 画面比例

enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case r43    = "4:3"
    case r169   = "16:9"
    case r21    = "2:1"
    case r235   = "2.35:1"
    case r11    = "1:1"

    var id: String { rawValue }
    var ratio: CGFloat {
        switch self {
        case .r43:  return 4.0/3.0
        case .r169: return 16.0/9.0
        case .r21:  return 2.0
        case .r235: return 2.35
        case .r11:  return 1.0
        }
    }
}

// MARK: - 视频分辨率

enum VideoResolution: String, CaseIterable, Identifiable {
    case r480   = "480P"
    case r720   = "720P"
    case r1080  = "1080P"
    case r4k    = "4K"
    case r8k    = "8K"
    var id: String { rawValue }
    var pixelHeight: Int {
        switch self {
        case .r480: return 480
        case .r720: return 720
        case .r1080: return 1080
        case .r4k: return 2160
        case .r8k: return 4320
        }
    }
}

// MARK: - 变焦显示方式

enum ZoomDisplayMode: String, CaseIterable, Identifiable {
    case multiplier   = "倍数"
    case focalLength  = "焦段"
    var id: String { rawValue }
}

// MARK: - 照片格式

enum PhotoFileFormat: String, CaseIterable, Identifiable {
    case heif = "HEIF"
    case jpg  = "JPG"
    case png  = "PNG"
    case raw  = "RAW"
    case tiff = "TIFF"
    var id: String { rawValue }
}

// MARK: - 专业取景覆盖

enum ProOverlayMode {
    case none
    case peaking
    case zebra
    case falseColor
}

// MARK: - 变焦档位（含焦段）

struct ZoomStop: Identifiable {
    let id = UUID()
    let multiplier: CGFloat
    let focal35: CGFloat   // 等效 35mm 焦段（24mm 为广角基准）
    let kind: ZoomKind
}

enum ZoomKind: String {
    case optical = "光学"
    case hybrid  = "混合"
    case digital = "裁切"
    case ai      = "AI"
}

/// 非线性变焦：显示倍数 → 滑动位置
enum NonlinearZoom {
    static let stops: [CGFloat] = [0.5, 1, 2, 5, 10, 25, 50, 100, 200, 400, 500]

    static func position(for factor: CGFloat) -> Double {
        // 用对数映射，让高倍更可控
        let log = log10(factor)
        let lo = log10(0.5)
        let hi = log10(500)
        return Double((log - lo) / (hi - lo))
    }

    static func factor(for position: Double) -> CGFloat {
        let lo = log10(0.5)
        let hi = log10(500)
        let v = lo + CGFloat(position) * (hi - lo)
        return CGFloat(pow(10, v))
    }

    static func nearestStop(to factor: CGFloat) -> CGFloat {
        stops.min(by: { abs($0 - factor) < abs($1 - factor) }) ?? factor
    }
}
