import SwiftUI

/// 窗口级全屏覆盖层：把内容挂到主窗口的最上层 subview，
/// 盖在包括 sheet / fullScreenCover 在内的所有页面之上，用于送礼动效这类全屏瞬时效果。
/// 不用独立 UIWindow（避免 keyWindow/level/场景时序问题），渲染路径与主页面完全一致。
@MainActor
enum JJTWindowOverlay {

    private static var host: UIHostingController<AnyView>?

    /// 展示覆盖层（重复调用先关旧的）
    static func show<Content: View>(_ content: Content) {
        dismiss()
        guard let window = mainWindow() else { return }
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        host.view.frame = window.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(host.view)
        self.host = host
    }

    static func dismiss() {
        host?.view.removeFromSuperview()
        host = nil
    }

    /// 主窗口（有 rootViewController 的那个；跳过键盘/特效等系统窗口）
    private static func mainWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            if let w = scene.windows.first(where: { $0.rootViewController != nil && $0.isKeyWindow }) { return w }
            if let w = scene.windows.first(where: { $0.rootViewController != nil }) { return w }
        }
        return scenes.first?.windows.first(where: { $0.rootViewController != nil })
    }
}
