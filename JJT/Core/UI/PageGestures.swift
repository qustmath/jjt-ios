import SwiftUI

/// 收起系统键盘
func jjtDismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// 模态页通用手势（iOS 常规交互，替代系统导航手势）：
/// 1. 左边缘右滑 → 返回上一级（SwiftUI environment dismiss，binding 状态同步，不绕UIKit）
/// 2. 页面竖向滑动 → 收起键盘（非滚动页的兜底；滚动区由 scrollDismissesKeyboard 联动处理）
/// 3. 滚动区拖动 → 键盘随手势联动收回
///
/// 注意：只能加在 fullScreenCover/sheet 呈现的页面根容器上；
/// 页内浮层（PayPasswordSheet/PrankOverlay 等 ZStack overlay）不要加，否则会误关宿主页面。
private struct PageGesturesModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 14).onEnded { v in
                    let t = v.translation
                    if v.startLocation.x <= 24, t.width > 64, t.width > abs(t.height) * 1.5 {
                        // 左边缘右滑返回上一级
                        dismiss()
                    } else if abs(t.height) > 56, abs(t.height) > abs(t.width) * 1.2 {
                        // 竖向滑动收键盘（上滑/下滑均可）
                        jjtDismissKeyboard()
                    }
                }
            )
    }
}

extension View {
    /// 模态页通用手势：左缘右滑返回 + 滑动收键盘 + 滚动联动收键盘
    func jjtPageGestures() -> some View { modifier(PageGesturesModifier()) }
}
