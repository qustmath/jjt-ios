import SwiftUI
import Bugly

@main
struct JJTApp: App {

    @StateObject private var appState = AppState()

    init() {
        // 用户展示信息缓存回填（会话/聊天头像框即时显示）
        UserDisplayCache.load()
        // Bugly 崩溃上报（App ID 为空则跳过；对齐安卓 initBugly）
        if !Config.buglyAppID.isEmpty {
            let config = BuglyConfig()
            #if DEBUG
            config.debugMode = true
            #endif
            Bugly.start(withAppId: Config.buglyAppID, config: config)
            // 崩溃按用户标记
            if let uid = TokenManager.shared.userId, uid > 0 {
                Bugly.setUserIdentifier(String(uid))
            }
            // 上次解析 3D 模型途中崩溃 → 上报具体模型名
            Gift3DView.reportPendingCrashMarker()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isLoggedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.dark)
            // 回前台 → IM 数据刷新信号（对齐安卓 notifyForeground）
            .onReceive(NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)) { _ in
                Task { @MainActor in ImManager.shared.notifyForeground() }
            }
        }
    }
}
