import SwiftUI

/// 全局应用状态：登录态路由（登录页 ↔ 主界面）
@MainActor
final class AppState: ObservableObject {

    @Published var isLoggedIn: Bool

    init() {
        isLoggedIn = TokenManager.shared.isLoggedIn
        NotificationCenter.default.addObserver(
            forName: .jjtUnauthorized, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isLoggedIn = false }
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
