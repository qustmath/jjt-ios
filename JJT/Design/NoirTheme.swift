import SwiftUI

/// Noir 黑金主题（对齐安卓 ui/theme）
enum Noir {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.055)   // #0B0B0E
    static let card = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let gold = Color(red: 0.831, green: 0.686, blue: 0.322)          // #D4AF52
    static let goldDim = Color(red: 0.55, green: 0.45, blue: 0.24)
    static let crimson = Color(red: 0.851, green: 0.016, blue: 0.161)       // #D90429
    static let wine = Color(red: 0.35, green: 0.05, blue: 0.10)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = Color.white.opacity(0.28)

    static let goldText = LinearGradient(
        colors: [Color(red: 0.96, green: 0.85, blue: 0.55), gold, Color(red: 0.72, green: 0.56, blue: 0.25)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let primaryButton = LinearGradient(
        colors: [crimson, Color(red: 0.62, green: 0.02, blue: 0.10), wine],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let hairline = Color.white.opacity(0.06)
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
