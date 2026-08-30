import UIKit

/// 全局右滑返回（iOS 通用交互）：本 App 页面均为 fullScreenCover/sheet 模态呈现，
/// 没有系统导航栈，左边缘右滑返回手势由这里统一补上——dismiss 最顶层模态页。
/// 仅在确实存在模态页时手势才开始识别，不干扰主 Tab 横滑翻页与系统告警。
enum JJTSwipeBack {

    static func install() {
        DispatchQueue.main.async { attach(retries: 3) }
    }

    private static func attach(retries: Int) {
        if let window = keyWindow() {
            let pan = UIScreenEdgePanGestureRecognizer(target: Handler.shared, action: #selector(Handler.handle(_:)))
            pan.edges = .left
            pan.delegate = Handler.shared
            window.addGestureRecognizer(pan)
        } else if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { attach(retries: retries - 1) }
        }
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
        }
        return scenes.first?.windows.first
    }

    /// 最顶层模态页控制器；根页面 / 系统告警（必须显式选择，不允许手势吞掉）返回 nil
    static func topModal() -> UIViewController? {
        guard let window = keyWindow(), let root = window.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        guard top !== root, !(top is UIAlertController) else { return nil }
        return top
    }

    private final class Handler: NSObject, UIGestureRecognizerDelegate {
        static let shared = Handler()
        private var triggered = false

        @objc func handle(_ g: UIScreenEdgePanGestureRecognizer) {
            switch g.state {
            case .began:
                triggered = false
            case .changed:
                guard !triggered else { return }
                let t = g.translation(in: g.view)
                // 明显横向右滑才触发，避免边缘上下滚动误触
                guard t.x > 60, t.x > abs(t.y) * 1.5 else { return }
                triggered = true
                JJTSwipeBack.topModal()?.dismiss(animated: true)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            JJTSwipeBack.topModal() != nil
        }

        /// 与页面内的横滑列表（banner、收礼人头像行等）共存：同时识别失败时让给边缘返回
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
