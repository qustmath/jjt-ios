import SwiftUI

/// 窗口级全屏覆盖层：独立 UIWindow 盖在包括 sheet / fullScreenCover 在内的所有页面之上，
/// 用于送礼动效这类需要全屏呈现的瞬时效果。不改变 keyWindow（不影响键盘），关闭即回收。
@MainActor
enum JJTWindowOverlay {

    private static var overlayWindow: UIWindow?

    /// 展示覆盖层（重复调用先关旧的）
    static func show<Content: View>(_ content: Content) {
        dismiss()
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        overlayWindow = window
    }

    static func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }
}
