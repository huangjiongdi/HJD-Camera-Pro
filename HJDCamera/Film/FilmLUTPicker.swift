import SwiftUI

// MARK: - 胶片 / LUT 选择器

struct FilmLUTPicker: View {
    @EnvironmentObject var camera: CameraManager
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $tab) {
                    Text("胶片").tag(0)
                    Text("内置 LUT").tag(1)
                    Text("导入 .cube").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if tab == 0 {
                    filmGrid
                } else if tab == 1 {
                    lutGrid
                } else {
                    importCube
                }
            }
            .navigationTitle("胶片 / LUT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var filmGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))],
                      spacing: 12) {
                Button {
                    camera.filmLook = nil
                    dismiss()
                } label: { pickerTile("原片", selected: camera.filmLook == nil) }

                ForEach(FilmLab.styles, id: \.self) { s in
                    Button {
                        camera.filmLook = s
                        dismiss()
                    } label: {
                        pickerTile(s, selected: camera.filmLook == s)
                    }
                }
            }
            .padding()
        }
    }

    private var lutGrid: some View {
        let luts = LUTManager.shared.availableLUTs()
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))],
                      spacing: 12) {
                Button {
                    camera.activeLUT = nil
                    dismiss()
                } label: { pickerTile("无 LUT", selected: camera.activeLUT == nil) }
                ForEach(luts, id: \.self) { s in
                    Button {
                        camera.activeLUT = s
                        dismiss()
                    } label: {
                        pickerTile(s, selected: camera.activeLUT == s)
                    }
                }
            }
            .padding()
        }
    }

    private var importCube: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 44))
                .foregroundColor(.yellow)
            Text("将 .cube 文件放入 App 文档目录，或通过「文件」导入。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("内置已包含 69 个 LUT，可直接使用。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func pickerTile(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: selected ? .bold : .medium))
            .foregroundColor(selected ? .black : .white)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.yellow : Color.white.opacity(0.12)))
    }
}
