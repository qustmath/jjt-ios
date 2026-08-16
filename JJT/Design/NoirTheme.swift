import SwiftUI

/// Noir 黑金主题（对齐安卓 ui/theme/Noir.kt —— 暗夜奢华风）
/// 黑底 + 酒红 + 鎏金 + 象牙白
enum Noir {
    // — 背景 —
    static let bg    = Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255) // #08080B
    static let noir  = Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0D/255) // #0A0A0D
    static let noir2 = Color(red: 0x12/255, green: 0x12/255, blue: 0x16/255) // #121216
    static let noir3 = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x20/255) // #1A1A20

    // — 酒红 —
    static let crimson     = Color(red: 0xC4/255, green: 0x12/255, blue: 0x30/255) // #C41230
    static let crimsonHot  = Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255) // #E8304F
    static let crimsonDeep = Color(red: 0x8B/255, green: 0x0A/255, blue: 0x1E/255) // #8B0A1E
    static let wine        = Color(red: 0x5C/255, green: 0x0A/255, blue: 0x16/255) // #5C0A16

    // — 鎏金 —
    static let gold      = Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255) // #C9A45C
    static let goldLight = Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255) // #E8CF9A
    static let goldPale  = Color(red: 0xF5/255, green: 0xE3/255, blue: 0xB8/255) // #F5E3B8
    static let goldDeep  = Color(red: 0x8A/255, green: 0x6A/255, blue: 0x2F/255) // #8A6A2F

    // — 文字 —
    static let ivory     = Color(red: 0xEF/255, green: 0xE9/255, blue: 0xDD/255) // #EFE9DD
    static let textDim   = Color.white.opacity(0.4)
    static let textFaint = Color.white.opacity(0.25)

    // — 描边 —
    static let hairlineGold = Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255).opacity(0.22)
    static let hairlineRed  = crimson.opacity(0.35)

    // — 旧别名（登录页等已有代码使用） —
    static let background   = bg
    static let card         = noir3
    static let goldDim      = goldDeep
    static let textPrimary  = ivory
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = textFaint
    static let hairline     = Color.white.opacity(0.06)

    /// 鎏金渐变文字（gold-text，5 段）
    static let goldText = LinearGradient(
        stops: [
            .init(color: Color(red: 0xF5/255, green: 0xE3/255, blue: 0xB8/255), location: 0.00),
            .init(color: gold, location: 0.35),
            .init(color: goldDeep, location: 0.55),
            .init(color: goldLight, location: 0.80),
            .init(color: gold, location: 1.00),
        ],
        startPoint: .leading, endPoint: .trailing)

    /// 酒红渐变（主按钮）
    static let primaryButton = LinearGradient(
        colors: [crimson, Color(red: 0.62, green: 0.02, blue: 0.10), wine],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// 鎏金分隔线（gold-line）
    static let goldLine = LinearGradient(
        colors: [.clear, gold, Color(red: 0xF0/255, green: 0xDB/255, blue: 0xA8/255), gold, .clear],
        startPoint: .leading, endPoint: .trailing)

    /// 后台配置的等级颜色（#RGB/#RRGGBB/#AARRGGBB），空值或解析失败回退鎏金（对齐安卓 tierColor）
    static func tierColor(_ hex: String?) -> Color {
        guard let hex else { return gold }
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v) else { return gold }
        switch s.count {
        case 3: // RGB
            return Color(red: Double((v >> 8) & 0xF) / 15, green: Double((v >> 4) & 0xF) / 15, blue: Double(v & 0xF) / 15)
        case 6: // RRGGBB
            return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        case 8: // AARRGGBB
            return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
                .opacity(Double((v >> 24) & 0xFF) / 255)
        default:
            return gold
        }
    }
}

/// 屏幕宽（竖屏锁定；图片/卡片写死宽度用，防止内容反向撑爆布局）
enum JJTMetrics {
    static var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390
    }
}

/// 取景框四角（L 形角标），设计稿标志性元素
struct CornerFrameModifier: ViewModifier {
    var color: Color
    var margin: CGFloat = 12
    var arm: CGFloat = 16

    func body(content: Content) -> some View {
        content.overlay(
            Canvas { ctx, size in
                let w: CGFloat = 1
                let right = size.width - margin
                let bottom = size.height - margin
                var path = Path()
                // 左上
                path.move(to: CGPoint(x: margin, y: margin + arm)); path.addLine(to: CGPoint(x: margin, y: margin)); path.addLine(to: CGPoint(x: margin + arm, y: margin))
                // 右上
                path.move(to: CGPoint(x: right - arm, y: margin)); path.addLine(to: CGPoint(x: right, y: margin)); path.addLine(to: CGPoint(x: right, y: margin + arm))
                // 左下
                path.move(to: CGPoint(x: margin, y: bottom - arm)); path.addLine(to: CGPoint(x: margin, y: bottom)); path.addLine(to: CGPoint(x: margin + arm, y: bottom))
                // 右下
                path.move(to: CGPoint(x: right - arm, y: bottom)); path.addLine(to: CGPoint(x: right, y: bottom)); path.addLine(to: CGPoint(x: right, y: bottom - arm))
                ctx.stroke(path, with: .color(color), lineWidth: w)
            }
            .allowsHitTesting(false)
        )
    }
}

extension View {
    func cornerFrame(_ color: Color, margin: CGFloat = 12, arm: CGFloat = 16) -> some View {
        modifier(CornerFrameModifier(color: color, margin: margin, arm: arm))
    }
}

/// 主按钮样式（酒红渐变胶囊）
struct NoirPrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(enabled ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(enabled ? Noir.primaryButton : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// 输入框样式（深色底 + 聚焦金边）
struct NoirTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Noir.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairline))
            .foregroundStyle(Noir.textPrimary)
    }
}

extension View {
    func noirField() -> some View { modifier(NoirTextFieldStyle()) }
}
