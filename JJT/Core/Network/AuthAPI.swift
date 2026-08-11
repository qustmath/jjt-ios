import Foundation

// MARK: - 请求（与安卓 AuthDtos.kt 对齐）

struct SendSmsCodeReq: Encodable {
    let mobile: String
    let scene: Int = 1 // MEMBER_LOGIN
}

struct RegisterReq: Encodable {
    let mobile: String
    let code: String
    let agreementAccepted: Bool = true
}

struct SmsLoginReq: Encodable {
    let mobile: String
    let code: String
}

struct LoginReq: Encodable {
    let mobile: String
    let password: String
}

// MARK: - 响应

struct LoginResp: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let userId: Int64?
    let expiresTime: Int64?
}

// MARK: - 认证 API

enum AuthAPI {

    /// 手机号+密码登录
    static func login(mobile: String, password: String) async throws -> LoginResp {
        try await APIClient.shared.post("app-api/member/auth/login", body: LoginReq(mobile: mobile, password: password))
    }

    /// 短信验证码登录
    static func smsLogin(mobile: String, code: String) async throws -> LoginResp {
        try await APIClient.shared.post("app-api/member/auth/sms-login", body: SmsLoginReq(mobile: mobile, code: code))
    }

    /// 发送短信验证码（scene=1 登录）
    static func sendSmsCode(mobile: String) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/auth/send-sms-code", body: SendSmsCodeReq(mobile: mobile))
    }

    /// 退出登录（失败也清本地态，忽略错误）
    static func logout() async {
        _ = try? await APIClient.shared.post("app-api/member/auth/logout", body: EmptyBody()) as EmptyData
    }

    private struct EmptyBody: Encodable {}
}
