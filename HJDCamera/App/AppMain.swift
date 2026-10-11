import SwiftUI

@main
struct HJDCameraApp: App {
    @StateObject private var camera = CameraManager()
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(camera)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .statusBar(hidden: false)
        }
    }
}

/// 顶层路由：相机 / 相册 / AI 编辑
struct RootView: View {
    @EnvironmentObject var camera: CameraManager
    @State private var tab: RootTab = .camera

    enum RootTab { case camera, gallery, editor }

    var body: some View {
        ZStack {
            switch camera.appScreen {
            case .camera:
                ContentView()
            case .gallery:
                GalleryView()
            case .aiEditor:
                if camera.editorImage != nil {
                    AIEditorView()
                } else {
                    ContentView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.appScreen)
    }
}
