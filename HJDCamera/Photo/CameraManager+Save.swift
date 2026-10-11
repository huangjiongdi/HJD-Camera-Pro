import Foundation
import UIKit
import CoreImage
import Photos
import ImageIO

// MARK: - 归一化 / 文件写入 / 保存

extension CameraManager {

    /// 方向归一化
    func normalizedUpImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let out = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        return out
    }

    /// 写入文件（含 EXIF）
    func writeImageFile(_ image: UIImage, exif: EXIFStore) -> URL? {
        let fmt: PhotoFileFormat
        switch fileFormat {
        case .jpg: fmt = .jpg
        case .png: fmt = .png
        case .tiff: fmt = .tiff
        case .raw: fmt = .jpg
        default: fmt = .heif
        }
        return EXIFWriter.write(image, format: fmt, store: exif)
    }

    /// 保存文件到相册
    func saveImageFileToLibrary(_ url: URL, thumbnail: UIImage?) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard status == .authorized || status == .limited else {
                self?.postMessage("需要相册权限")
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                let resType = PHAssetResourceType.photo
                req.addResource(with: resType, fileURL: url, options: options)
            } completionHandler: { success, _ in
                self?.postMessage(success ? "照片已保存" : "照片保存失败")
            }
        }
    }

    /// 直接保存 UIImage 到相册（兜底）
    func saveToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard status == .authorized || status == .limited else {
                self?.postMessage("需要相册权限"); return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                self?.postMessage(success ? "照片已保存" : "照片保存失败")
            }
        }
    }

    /// 保证最少像素（绝不存小图）
    func guaranteeMinPixels(_ image: UIImage, minPixels: Int) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let cur = cg.width * cg.height
        if cur >= minPixels { return image }
        let scale = sqrt(CGFloat(minPixels) / CGFloat(cur))
        let newSize = CGSize(width: CGFloat(cg.width) * scale,
                             height: CGFloat(cg.height) * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: 消息提示

    func postMessage(_ text: String) {
        DispatchQueue.main.async {
            self.saveMessage = text
            self.clearMessageAfter()
        }
    }

    func clearMessageAfter() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            if self.saveMessage != "处理中…" {
                self.saveMessage = ""
            }
        }
    }
}
