import Foundation
import AVFoundation
import UIKit
import CoreImage
import Photos
import ImageIO
import UniformTypeIdentifiers
import CoreMotion
import Combine

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject {

    // MARK: Session & outputs

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "hjd.camera.session")
    private let videoQueue = DispatchQueue(label: "hjd.camera.video")
    private let processingQueue = DispatchQueue(label: "hjd.camera.processing")

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "hjd.camera.data")

    // MARK: Published state

    @Published var isAuthorized = false
    @Published var isSessionReady = false
    @Published var shootingMode: ShootingMode = .photo
    @Published var exposureMode: ExposureMode = .program
    @Published var colorSpace: VideoColorSpace = .sdr
    @Published var resolutionPreset: ResolutionPreset = .mp12
    @Published var aspectRatio: AspectRatioPreset = .r43
    @Published var videoResolution: VideoResolution = .r4k
    @Published var videoFPS: Int = 30
    @Published var zoomDisplayMode: ZoomDisplayMode = .multiplier
    @Published var fileFormat: PhotoFileFormat = .heif

    @Published var zoomFactor: CGFloat = 1.0
    @Published var isFrontCamera = false
    @Published var isRecording = false

    @Published var focusPoint: CGPoint?
    @Published var afAeLocked = false
    @Published var lockPoint: CGPoint?
    @Published var lastTapLocation: CGPoint = .zero

    @Published var overlayMode: ProOverlayMode = .none
    @Published var peakingImage: UIImage?
    @Published var histogramData: [Float] = Array(repeating: 0, count: 256)

    @Published var isProcessing = false
    @Published var saveMessage: String = ""
    @Published var lastPhoto: UIImage?
    @Published var appScreen: AppScreen = .camera
    @Published var editorImage: UIImage?

    // AI flags
    @Published var aiSnapshot = false
    @Published var filmLook: String?
    @Published var activeLUT: String?

    // 闪光灯 / 手电筒
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var torchOn = false

    // 增距镜
    @Published var teleconverterEnabled = false
    @Published var teleconverterFocal: CGFloat = 2.0   // 倍增系数

    // 手动参数
    @Published var manualISO: Float = 100
    @Published var manualShutter: Double = 1.0/120
    @Published var manualEV: Float = 0
    @Published var manualWBTemp: Float = 5600
    @Published var manualFocus: Float = 1.0
    @Published var sharpness: Double = 0.5

    // MARK: 硬件变焦映射（运行时确定）
    private var switchOverFactors: [CGFloat] = []
    private var hardwareMaxZoom: CGFloat = 16.0
    private var displayToHardwareScale: CGFloat = 2.0

    let exifStore = EXIFStore()

    // 加速度（锁定后移动过快解锁）
    private let motionManager = CMMotionManager()

    // 共享 CIContext
    let sharedCIContext: CIContext = {
        CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()])
    }()

    // MARK: - Init

    override init() {
        super.init()
        // 权限与会话在请求时启动
        checkAndConfigure()
    }

    // MARK: - 权限

    func checkAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.startSession() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    // MARK: - 会话配置

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession(front: false)
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionReady = true
            }
        }
    }

    private func configureSession(front: Bool) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // 移除旧输入
        if let vi = videoInput { session.removeInput(vi) }
        if let ai = audioInput { session.removeInput(ai) }
        session.removeOutput(photoOutput)
        session.removeOutput(movieOutput)
        session.removeOutput(videoDataOutput)

        // 摄像头
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: front
                ? [.builtInWideAngleCamera]
                : [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: front ? .front : .back)

        // 优先使用包含多摄的虚拟设备（多镜头自动切换）
        let device: AVCaptureDevice
        if front {
            guard let d = discovery.devices.first else {
                session.commitConfiguration(); return
            }
            device = d
        } else {
            // 三摄虚拟设备（支持自动切换）
            let tripleDiscovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera],
                mediaType: .video, position: .back)
            device = tripleDiscovery.devices.first ?? discovery.devices.first!
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            }
        } catch {
            session.commitConfiguration(); return
        }

        // 音频输入
        if let mic = AVCaptureDevice.default(for: .audio) {
            do {
                let ai = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(ai) {
                    session.addInput(ai)
                    audioInput = ai
                }
            } catch {}
        }

        // 照片输出
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            if photoOutput.isAppleProRAWSupported {
                photoOutput.isAppleProRAWEnabled = true
            }
        }

        // 视频输出
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        // 视频数据输出（实时增强 / 峰值 / 直方图）
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()

        // 记录硬件变焦映射
        switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map {
            CGFloat(truncating: $0)
        }
        hardwareMaxZoom = min(device.activeFormat.videoMaxZoomFactor, 16.0)
        // 显示倍数 → 硬件倍数：以第一个切换点（通常为 2）为广角
        displayToHardwareScale = switchOverFactors.first ?? 2.0
        print("[HJD] switch=\(switchOverFactors) max=\(hardwareMaxZoom) scale=\(displayToHardwareScale)")

        // 应用初始变焦
        applyHardwareZoom(display: zoomFactor)
    }

    // MARK: - 前后摄像头

    func switchCamera() {
        let newFront = !isFrontCamera
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.configureSession(front: newFront)
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isFrontCamera = newFront
                self.zoomFactor = 1.0
            }
        }
    }

    // MARK: - 变焦（显示倍数 → 硬件 + 数字裁切）

    /// 当前输入设备
    var currentDevice: AVCaptureDevice? {
        videoInput?.device
    }

    func setZoom(_ display: CGFloat) {
        let clamped = max(0.5, min(500, display))
        zoomFactor = clamped
        applyHardwareZoom(display: clamped)
    }

    /// 硬件可支持的最大「显示倍数」
    private var hardwareMaxDisplay: CGFloat {
        hardwareMaxZoom / displayToHardwareScale
    }

    private func applyHardwareZoom(display: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            // 硬件倍数 = 显示倍数 × 比例（仅当硬件范围内）
            let hw = display * self.displayToHardwareScale
            let target = min(hw, self.hardwareMaxZoom)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(1.0, target)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// 数字/AI 裁切的显示倍数（超出硬件范围部分）
    var digitalCropScale: CGFloat {
        let hwMax = hardwareMaxDisplay
        if zoomFactor <= hwMax { return 1.0 }
        // 增距镜
        let tc = teleconverterEnabled ? teleconverterFocal : 1.0
        return zoomFactor / hwMax * tc
    }

    /// 给预览层用的数字裁切（UI 预览）
    var digitalPreviewScale: CGFloat {
        return max(1.0, digitalCropScale)
    }
}
