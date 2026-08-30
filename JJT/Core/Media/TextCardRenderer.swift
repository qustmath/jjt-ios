import UIKit

/// 纯文字帖文字卡片渲染（对齐安卓 TextCardRenderer）：
/// 把标题+正文绘制到渐变背景上，生成 1080x1440（3:4）封面图。
/// 类似小红书「发文字」的文字卡片——本地渲染，零成本，走普通图片上传通道。
enum TextCardRenderer {

    static let width: CGFloat = 1080
    static let height: CGFloat = 1440

    /// 背景模板（暗夜系渐变，与 App 风格一致）
    struct CardStyle {
        let name: String
        let startColor: UIColor
        let endColor: UIColor
        let accent: UIColor
    }

    static let styles: [CardStyle] = [
        CardStyle(name: "鎏金", startColor: UIColor(hex: 0x3D2B0E), endColor: UIColor(hex: 0x120A14), accent: UIColor(hex: 0xD4AF6A)),
        CardStyle(name: "绯红", startColor: UIColor(hex: 0x4A0E1E), endColor: UIColor(hex: 0x14060A), accent: UIColor(hex: 0xE91E63)),
        CardStyle(name: "墨蓝", startColor: UIColor(hex: 0x0E1E3A), endColor: UIColor(hex: 0x060A14), accent: UIColor(hex: 0x7DB8E8)),
        CardStyle(name: "苔原", startColor: UIColor(hex: 0x0E2E1E), endColor: UIColor(hex: 0x060F0A), accent: UIColor(hex: 0x7DB8A8)),
    ]

    /// 渲染文字卡片。fullContent 为「标题\n正文」合并文本（首行即标题）
    static func render(_ fullContent: String, styleIndex: Int) -> UIImage {
        let style = styles[max(0, min(styleIndex, styles.count - 1))]
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cg = ctx.cgContext

            // 背景：对角渐变
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [style.startColor.cgColor, style.endColor.cgColor] as CFArray,
                                      locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])

            // 左上角装饰引号（淡淡的，营造卡片感）
            let quoteAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 220),
                .foregroundColor: style.accent.withAlphaComponent(40.0 / 255),
            ]
            "“".draw(at: CGPoint(x: 70, y: 300 - 220 * 0.82), withAttributes: quoteAttr)

            // 拆标题/正文
            let trimmed = fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let nl = trimmed.firstIndex(of: "\n")
            let title = nl.map { String(trimmed[..<$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            let body = nl.map { String(trimmed[trimmed.index(after: $0)...]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed

            let margin: CGFloat = 100
            let contentWidth = width - margin * 2

            // 标题（如有）：粗体 84px，最多 3 行
            var titleLayout: TextBlock?
            if !title.isEmpty {
                titleLayout = TextBlock(text: title,
                                        font: UIFont.boldSystemFont(ofSize: 84),
                                        color: .white, kern: 84 * 0.02,
                                        width: contentWidth, maxLines: 3, lineHeightMultiple: 1.5)
            }
            // 正文：60px，行距 1.5，最多 13 行
            var bodyLayout: TextBlock?
            if !body.isEmpty {
                bodyLayout = TextBlock(text: body,
                                       font: UIFont.systemFont(ofSize: 60),
                                       color: .white.withAlphaComponent(230.0 / 255), kern: 60 * 0.01,
                                       width: contentWidth, maxLines: 13, lineHeightMultiple: 1.5)
            }

            // 内容总高：标题块（标题 + 金色短划线及间距）+ 正文
            var contentHeight: CGFloat = 0
            if let t = titleLayout { contentHeight += t.height + 36 + 60 }
            if let b = bodyLayout { contentHeight += b.height }

            // 起始 y：内容不足一页时上下居中（底部预留水印区）；内容较高时保持顶部起点
            let topStart: CGFloat = 240
            let bottomReserve: CGFloat = 180
            var y = topStart
            if topStart + contentHeight + bottomReserve < height {
                y = (height - contentHeight) / 2
            }

            if let t = titleLayout {
                t.draw(at: CGPoint(x: margin, y: y))
                y += t.height + 36
                // 标题下金色短划线
                cg.setFillColor(style.accent.cgColor)
                cg.fill(CGRect(x: margin, y: y, width: 90, height: 5))
                y += 60
            }

            bodyLayout?.draw(at: CGPoint(x: margin, y: y))

            // 底部品牌水印
            let brandAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30),
                .foregroundColor: style.accent.withAlphaComponent(130.0 / 255),
                .kern: 30 * 0.3 * 10, // letterSpacing 0.3em 视觉近似
            ]
            "J I N G J I T U".draw(at: CGPoint(x: margin, y: height - 80 - 30), withAttributes: brandAttr)
        }
    }

    /// 定宽多行文本块（对齐安卓 StaticLayout：定宽自动换行 + maxLines 截断 + 行距倍数）。
    /// 用 TextKit（NSTextStorage/NSLayoutManager/NSTextContainer，UILabel 同款排版管线），
    /// NSStringDrawing 的 truncatesLastVisibleLine 实测存在不换行场景，故以 TextKit 为准。
    private struct TextBlock {
        private let layoutManager = NSLayoutManager()
        private let textContainer: NSTextContainer

        init(text: String, font: UIFont, color: UIColor, kern: CGFloat, width: CGFloat, maxLines: Int, lineHeightMultiple: CGFloat) {
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = lineHeightMultiple
            para.lineBreakMode = .byTruncatingTail
            let storage = NSTextStorage(string: text, attributes: [
                .font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: para,
            ])
            textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            textContainer.lineFragmentPadding = 0
            textContainer.maximumNumberOfLines = maxLines
            textContainer.lineBreakMode = .byTruncatingTail
            layoutManager.addTextContainer(textContainer)
            storage.addLayoutManager(layoutManager)
        }

        /// 排版后的实际高度（已按 maxLines 截断）
        var height: CGFloat {
            layoutManager.ensureLayout(for: textContainer)
            return layoutManager.usedRect(for: textContainer).height
        }

        func draw(at point: CGPoint) {
            let glyphs = layoutManager.glyphRange(for: textContainer)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: point)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
