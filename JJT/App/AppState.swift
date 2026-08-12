import SwiftUI

/// 全局应用状态：登录态路由（登录页 ↔ 主界面）
@MainActor
final class AppState: ObservableObject {

    @Published var isLoggedIn: Bool

    init() {
        isLoggedIn = TokenManager.shared.isLoggedIn
        // token 失效 → 回登录页（同 actor 隔离，无并发捕获问题）
        Task { @MainActor in
            for await _ in NotificationCenter.default.notifications(named: .jjtUnauthorized) {
                isLoggedIn = false
            }
        }
    }

    func didLogin(_ resp: LoginResp) {
        guard let at = resp.accessToken, let rt = resp.refreshToken, let uid = resp.userId else { return }
        TokenManager.shared.save(accessToken: at, refreshToken: rt, userId: uid)
        isLoggedIn = true
    }

    func logout() {
        Task {
            await AuthAPI.logout()
            TokenManager.shared.clear()
            await MainActor.run { isLoggedIn = false }
        }
    }
}
