import UIKit

/// 选美拉票海报生成（对齐安卓 PageantPoster，共用同一模板资源 posters/pageant_poster_bg.jpg 941×1672）：
/// 模板全出血打底（品牌/标题/规则文字已烘焙在模板里）→ 中央椭圆槽放参赛者照片 →
/// 左下「参赛号」旁写真实号码 → 右下二维码槽放投票二维码。
enum PageantPoster {

    private static let W: CGFloat = 941
    private static let H: CGFloat = 1672

    /// 内置模板照片槽（模板像素实测，对齐安卓）
    private static let builtinEllipse = CGRect(x: 209, y: 592, width: 740 - 209, height: 1384 - 592)
    /// 后台自定义底图照片槽（Halloween 模板白色圆角矩形内缘实测）
    private static let customRect = CGRect(x: 162, y: 465, width: 768 - 162, height: 1390 - 465)
    private static let customCorner: CGFloat = 120
    /// 二维码槽内嵌区（居中 124 方形码）
    private static let qrRect = CGRect(x: 730, y: 1331, width: 854 - 730, height: 1455 - 1331)
    /// 号码颜色（与模板「参赛号」文字同色）
    private static let numColor = UIColor(red: 203 / 255, green: 199 / 255, blue: 196 / 255, alpha: 1)

    /// 生成海报。photoUrl 取参赛者第一张图，center-crop 进椭圆槽。返回 UIImage。
    /// 后台配置了 shareImage 时用后台底图（941×1672 同槽位），nil/加载失败回退内置模板。
    static func generate(activity: PageantActivity, detail: PageantEntryDetail, qrContent: String) async -> UIImage? {
        let bg: UIImage
        if let custom = await loadImage(activity.shareImage) {
            bg = custom
        } else if let bundled = bundledPoster() {
            bg = bundled
        } else {
            return nil
        }
        let photo = await loadImage(detail.images?.first)
        let isCustom = activity.shareImage?.isEmpty == false
        // PNG 透明镂空：按 alpha 透明区把照片透出来（形状不用猜）；不透明底图走几何槽
        let hole = isCustom ? alphaHoleRect(bg) : nil
        let photoRect = isCustom ? customRect : builtinEllipse
        let photoPath: UIBezierPath = isCustom
            ? UIBezierPath(roundedRect: photoRect, cornerRadius: customCorner)
            : UIBezierPath(ovalIn: photoRect)
        let qr = qrCodeImage(qrContent, side: qrRect.width * 4) // 4 倍超采样，保证小尺寸可扫
        let noText = String(format: "No.%03d", detail.entryNo ?? Int(detail.id))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
        return renderer.image { ctx in
            if let hole {
                // 先画照片到镂空 bbox，再用底图盖住；透明洞自然露出照片
                if let photo {
                    let bmpW = CGFloat(bg.cgImage?.width ?? Int(bg.size.width))
                    let bmpH = CGFloat(bg.cgImage?.height ?? Int(bg.size.height))
                    let sx = W / max(bmpW, 1)
                    let sy = H / max(bmpH, 1)
                    drawCover(photo, in: CGRect(
                        x: hole.minX * sx, y: hole.minY * sy,
                        width: hole.width * sx, height: hole.height * sy))
                }
                bg.draw(in: CGRect(x: 0, y: 0, width: W, height: H))
            } else {
                // ---- 模板打底 ----
                bg.draw(in: CGRect(x: 0, y: 0, width: W, height: H))
                // ---- 照片槽（center-crop + 椭圆/圆角矩形裁剪） ----
                if let photo {
                    ctx.cgContext.saveGState()
                    ctx.cgContext.addPath(photoPath.cgPath)
                    ctx.cgContext.clip()
                    drawCover(photo, in: photoRect)
                    ctx.cgContext.restoreGState()
                }
            }

            // ---- 参赛号：抹掉模板烘焙的原字（垂直渐变贴合背景），重画「小 label + 大号码」 ----
            let eraseRect = CGRect(x: 75, y: 1350, width: 225 - 75, height: 1405 - 1350)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 50 / 255, green: 47 / 255, blue: 42 / 255, alpha: 1).cgColor,
                UIColor(red: 38 / 255, green: 34 / 255, blue: 31 / 255, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.cgContext.saveGState()
            ctx.cgContext.addRect(eraseRect)
            ctx.cgContext.clip()
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1350), end: CGPoint(x: 0, y: 1405), options: [])
            ctx.cgContext.restoreGState()

            let baseline: CGFloat = 1392
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Times New Roman", size: 17) ?? UIFont.systemFont(ofSize: 17),
                .foregroundColor: numColor,
                .kern: 17 * 0.2,
            ]
            "参赛号".draw(at: CGPoint(x: 83, y: baseline - 22), withAttributes: labelAttr)
            let noAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Times-Bold", size: 52) ?? UIFont.boldSystemFont(ofSize: 52),
                .foregroundColor: numColor,
            ]
            noText.draw(at: CGPoint(x: 155, y: baseline - 62), withAttributes: noAttr)

            // ---- 投票二维码 ----
            if let qr {
                qr.draw(in: qrRect)
            }
        }
    }

    // MARK: - 私有

    /// 内置模板（后台 shareImage 为空/加载失败时兜底）
    private static func bundledPoster() -> UIImage? {
        guard let path = Bundle.main.path(forResource: "pageant_poster_bg", ofType: "jpg", inDirectory: "posters") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }

    /// 自定义底图若为带透明镂空的 PNG，返回透明区 bbox（像素坐标）；不透明返回 nil
    private static func alphaHoleRect(_ image: UIImage) -> CGRect? {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let w = cg.width
        let h = cg.height
        let bpp = cg.bitsPerPixel / 8
        guard bpp >= 4 else { return nil }
        let alphaOffset: Int
        switch cg.alphaInfo {
        case .premultipliedLast, .last: alphaOffset = 3
        case .premultipliedFirst, .first: alphaOffset = 0
        default: return nil
        }
        let bpr = cg.bytesPerRow
        var count = 0
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for y in 0..<h {
            let row = y * bpr
            for x in 0..<w {
                if ptr[row + x * bpp + alphaOffset] < 250 {
                    count += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0, count > w * h / 20 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// cover 模式绘制到目标区域
    private static func drawCover(_ src: UIImage, in dest: CGRect) {
        let scale = max(dest.width / src.size.width, dest.height / src.size.height)
        let w = src.size.width * scale
        let h = src.size.height * scale
        src.draw(in: CGRect(x: dest.minX + (dest.width - w) / 2,
                            y: dest.minY + (dest.height - h) / 2,
                            width: w, height: h))
    }

    private static func loadImage(_ url: String?) async -> UIImage? {
        guard let url, let u = webImageURL(url) else { return nil }
        return try? await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: u) { data, _, error in
                if let data, let img = UIImage(data: data) {
                    cont.resume(returning: img)
                } else {
                    cont.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}
