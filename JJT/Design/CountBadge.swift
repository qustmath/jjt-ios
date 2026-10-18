import SwiftUI

/// 正圆数字角标（密语未读 / 票夹 / 我的订单 / 优惠券共用，对齐安卓 CountBadge）。
/// >99 显示 99+；圆随位数 16/18/20pt 放大一档保持正圆；0 不渲染。
struct CountBadge: View {

    let count: Int

    var body: some View {
        if count > 0 {
            let text = count > 99 ? "99+" : "\(count)"
            let diameter: CGFloat = text.count >= 3 ? 20 : (text.count == 2 ? 18 : 16)
            Text(text)
                .font(.system(size: text.count >= 3 ? 8 : 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Noir.crimsonHot))
                .accessibilityLabel("未读\(count)条")
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        CountBadge(count: 1)
        CountBadge(count: 30)
        CountBadge(count: 128)
        CountBadge(count: 0)
    }
    .padding(40)
    .background(Noir.bg)
}
