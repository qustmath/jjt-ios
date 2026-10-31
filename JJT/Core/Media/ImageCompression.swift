import UIKit

/// 上传前图片压缩（选美 / 广场共用，对齐安卓 ImageCompressor）：
/// 长边压到 2048、JPEG 质量 0.85；原始带透明通道的 PNG 保持 PNG（避免透明底变黑），
/// 其余统一转 JPEG。重绘时顺带把 EXIF 方向摆正（横拍照片否则会躺倒）。
enum ImageCompression {

    /// 长边上限：3x 屏详情大图/九宫格长边显示足够，单图通常 300~600KB
    static let maxEdge: CGFloat = 2048

    /// JPEG 质量
    static let jpegQuality: CGFloat = 0.85

    struct Prepared {
        let data: Data
        let ext: String
        let mime: String
    }

    /// 压缩并编码，返回上传数据与扩展名/MIME；失败返回 nil（调用方回退原图）
    static func prepareForUpload(
        _ image: UIImage,
        maxEdge: CGFloat = maxEdge,
        quality: CGFloat = jpegQuality
    ) -> Prepared? {
        let resized = resize(image, maxEdge: maxEdge)
        // 透明通道按原图判断：JPEG/HEIC 无 alpha；带透明的 PNG 保 PNG，否则转 JPEG
        if hasAlpha(image), let png = resized.pngData() {
            return Prepared(data: png, ext: "png", mime: "image/png")
        }
        if let jpg = resized.jpegData(compressionQuality: quality) {
            return Prepared(data: jpg, ext: "jpg", mime: "image/jpeg")
        }
        return nil
    }

    /// 等比缩到长边 ≤ maxEdge，并转正方向；已足够小且方向正常时原样返回
    static func resize(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return image }
        let scale = min(1, maxEdge / max(w, h))
        if scale >= 1, image.imageOrientation == .up { return image }
        let target = CGSize(
            width: max(1, (w * scale).rounded()),
            height: max(1, (h * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1       // 输出像素尺寸与 target 一致，不乘屏幕倍率
        format.opaque = hasAlpha(image) == false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        switch alpha {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }
}
