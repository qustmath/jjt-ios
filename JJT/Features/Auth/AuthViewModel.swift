import Foundation

@MainActor
final class AuthViewModel: ObservableObject {

    enum Mode { case password, sms }

    @Published var mode: Mode = .password
    @Published var mobile = ""
    @Published var password = ""
    @Published var smsCode = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var countdown = 0

    private var countdownTask: Task<Void, Never>?

    var canSubmit: Bool {
        guard mobile.count == 11 else { return false }
        switch mode {
        case .password: return !password.isEmpty
        case .sms: return smsCode.count >= 4
        }
    }

    /// 发送验证码（登录场景），成功开始 60s 倒计时
    func sendCode() async {
        guard mobile.count == 11, countdown == 0 else { return }
        isLoading = true
        errorMessage = nil
        do {
            let ok: Bool = try await AuthAPI.sendSmsCode(mobile: mobile)
            if ok { startCountdown() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 登录成功回调由外层 AppState.didLogin 处理
    func login() async -> LoginResp? {
        guard canSubmit else { return nil }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch mode {
            case .password:
                return try await AuthAPI.login(mobile: mobile, password: password)
            case .sms:
                return try await AuthAPI.smsLogin(mobile: mobile, code: smsCode)
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task {
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
        }
    }
}
