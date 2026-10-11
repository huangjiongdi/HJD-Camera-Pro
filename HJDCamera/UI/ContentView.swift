import SwiftUI
import AVFoundation
import UIKit

// MARK: - 主相机界面

struct ContentView: View {
    @EnvironmentObject var camera: CameraManager
    @StateObject private var orientation = OrientationObserver()
    @State private var showSettings = false
    @State private var showFilm = false
    @State private var focusSquarePoint: CGPoint?
    @State private var focusLocked = false

    private var isLandscape: Bool {
        orientation.orientation.isLandscape
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black.ignoresSafeArea()

                // 预览
                CameraPreviewView(
                    session: camera.session,
                    digitalScale: Binding(
                        get: { camera.digitalPreviewScale },
                        set: { _ in }),
                    orientation: orientation.orientation)
                    .ignoresSafeArea()

                // 对焦手势
                FocusGestureView(
                    onTap: { p in
                        camera.setFocus(point: p, previewSize: size)
                        showFocus(at: p, locked: false)
                    },
                    onLongPress: { p in
                        camera.lockFocusExposure(point: p, previewSize: size)
                        showFocus(at: p, locked: true)
                    })
                    .ignoresSafeArea()

                // 对焦框
                if let fp = focusSquarePoint {
                    FocusSquare(point: fp, locked: focusLocked)
                        .transition(.opacity)
                }

                // 峰值（左上角小块）
                if camera.shootingMode == .pro, let pk = camera.peakingImage {
                    Image(uiImage: pk)
                        .resizable()
                        .frame(width: 130, height: 98)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .position(x: 78, y: 120)
                }

                // 顶部 + 底部控件
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout(size: size)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showFilm) {
            FilmLUTPicker()
        }
    }

    // MARK: 竖屏布局

    private func portraitLayout(size: CGSize) -> some View {
        VStack {
            // 顶部栏
            HStack {
                // 左侧：闪光灯（视频为手电筒）
                topButton(icon: camera.shootingMode.isVideo
                          ? (camera.torchOn ? "bolt.fill" : "bolt.slash")
                          : flashIcon) {
                    if camera.shootingMode.isVideo {
                        camera.toggleTorch()
                    } else {
                        camera.cycleFlash()
                    }
                }
                Spacer()
                // 右侧：相册 / 切镜头 / 设置
                topButton(icon: "camera.rotate") { camera.switchCamera() }
                topButton(icon: "gearshape") { showSettings = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 参数（左上角，避开闪光灯）
            paramChips
                .padding(.top, 6)

            Spacer()

            // 胶片/LOG 入口
            HStack {
                Button {
                    showFilm = true
                } label: {
                    Label(camera.filmLook ?? "胶片 / LUT",
                          systemImage: "camera.filters")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
                Spacer()
                // 增距镜
                Button {
                    camera.teleconverterEnabled.toggle()
                } label: {
                    Label("增距镜", systemImage: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(camera.teleconverterEnabled ? .black : .white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(
                            camera.teleconverterEnabled ? Color.yellow :
                                Color.black.opacity(0.55)))
                }
            }
            .padding(.horizontal, 16)

            // 专业控制
            ProControls(camera: camera)
                .padding(.horizontal, 10)

            // 变焦轮盘 + 微距花
            ZStack {
                ZoomWheel(
                    factor: Binding(
                        get: { camera.zoomFactor },
                        set: { camera.setZoom($0) }),
                    isMacro: false,
                    onCommit: { camera.setZoom($0) })
                HStack {
                    MacroFlowerButton(
                        enabled: Binding(
                            get: { camera.shootingMode == .macro },
                            set: { _ in
                                camera.setMode(camera.shootingMode == .macro
                                               ? .photo : .macro)
                            })) {
                        camera.setMode(camera.shootingMode == .macro
                                       ? .photo : .macro)
                    }
                    Spacer()
                }
            }
            .padding(.bottom, 4)

            // 模式选择
            ModeSelector(
                mode: Binding(
                    get: { camera.shootingMode },
                    set: { camera.setMode($0) }),
                onSelect: { camera.setMode($0) })

            // 快门行
            shutterRow
                .padding(.bottom, 10)
        }
    }

    // MARK: 横屏布局（简化）

    private var landscapeLayout: some View {
        HStack {
            VStack {
                topButton(icon: "bolt.fill") { camera.toggleTorch() }
                Spacer()
                topButton(icon: "gearshape") { showSettings = true }
            }
            .padding(.leading, 10)
            Spacer()
            VStack {
                Button {
                    camera.shutter()
                } label: {
                    Circle()
                        .fill(camera.shootingMode.isVideo && camera.isRecording
                              ? Color.red : Color.white)
                        .frame(width: 68, height: 68)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                }
                topButton(icon: "camera.rotate") { camera.switchCamera() }
            }
            .padding(.trailing, 16)
        }
    }

    // MARK: 快门行（竖屏）

    private var shutterRow: some View {
        HStack {
            // 左：最近照片 → 相册
            Button {
                camera.openGallery()
            } label: {
                ZStack {
                    if let last = camera.lastPhoto {
                        Image(uiImage: last)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5))
            }

            Spacer()

            // 中：快门
            Button {
                camera.shutter()
            } label: {
                ZStack {
                    if camera.shootingMode.isVideo {
                        Circle()
                            .fill(camera.isRecording ? Color.red : Color.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    }
                }
            }

            Spacer()

            // 右：切镜头
            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: 参数标签（视频：分辨率/帧率/色彩；照片：格式/像素）

    private var paramChips: some View {
        Group {
            if camera.shootingMode.isVideo {
                HStack(spacing: 6) {
                    chip(camera.videoResolution.rawValue) {
                        cycleVideoResolution()
                    }
                    chip(camera.shootingMode == .sloMo
                         ? "240" : "\(camera.videoFPS)") {
                        cycleVideoFPS()
                    }
                    ForEach(VideoColorSpace.allCases) { cs in
                        let sel = camera.colorSpace == cs
                        Text(cs.rawValue)
                            .font(.system(size: 12, weight: sel ? .bold : .medium))
                            .foregroundColor(sel ? .black : .white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Capsule().fill(
                                sel ? Color.yellow : Color.black.opacity(0.5)))
                            .onTapGesture { camera.colorSpace = cs }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    chip(camera.fileFormat.rawValue) {
                        cyclePhotoFormat()
                    }
                    chip(camera.resolutionPreset.rawValue) {
                        cyclePixelPreset()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }

    private var flashIcon: String {
        switch camera.flashMode {
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        @unknown default: return "bolt"
        }
    }

    private func topButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
    }

    // MARK: 对焦框动画

    private func showFocus(at p: CGPoint, locked: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            focusSquarePoint = p
            focusLocked = locked
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if !locked {
                withAnimation(.easeIn(duration: 0.3)) {
                    focusSquarePoint = nil
                }
            }
        }
    }

    // MARK: 循环参数

    private func cycleVideoResolution() {
        let all = VideoResolution.allCases
        if let i = all.firstIndex(of: camera.videoResolution) {
            let next = all[(i+1) % all.count]
            camera.videoResolution = next
            reconfigureVideo()
        }
    }

    private func cycleVideoFPS() {
        let opts = [24, 30, 60, 120, 240]
        if let i = opts.firstIndex(of: camera.videoFPS) {
            camera.videoFPS = opts[(i+1) % opts.count]
            reconfigureVideo()
        }
    }

    private func reconfigureVideo() {
        camera.sessionQueueSafe { device in
            camera.configureVideoFormat(device: device,
                                        resolution: camera.videoResolution,
                                        fps: camera.videoFPS)
        }
    }

    private func cyclePhotoFormat() {
        let all = PhotoFileFormat.allCases
        if let i = all.firstIndex(of: camera.fileFormat) {
            camera.fileFormat = all[(i+1) % all.count]
        }
    }

    private func cyclePixelPreset() {
        let all = ResolutionPreset.allCases
        if let i = all.firstIndex(of: camera.resolutionPreset) {
            camera.resolutionPreset = all[(i+1) % all.count]
        }
    }
}
