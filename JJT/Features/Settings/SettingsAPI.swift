import Foundation

// MARK: - 账号安全 API（对齐安卓 AccountSecurityApi）

enum AccountSecurityAPI {

    /// 短信验证码。scene: 2=修改手机号 3=修改密码（对齐安卓）
    static func sendSmsCode(mobile: String, scene: Int) async throws -> Bool {
        struct Req: Encodable { let mobile: String; let scene: Int }
        return try await APIClient.shared.post("app-api/member/auth/send-sms-code", body: Req(mobile: mobile, scene: scene))
    }

    static func updatePassword(password: String, code: String) async throws -> Bool {
        struct Req: Encodable { let password: String; let code: String }
        return try await APIClient.shared.put("app-api/member/user/update-password", body: Req(password: password, code: code))
    }

    /// oldCode：第一步验证旧手机的验证码（换绑必带）
    static func updateMobile(mobile: String, code: String, oldCode: String?) async throws -> Bool {
        struct Req: Encodable { let mobile: String; let code: String; let oldCode: String? }
        return try await APIClient.shared.put("app-api/member/user/update-mobile", body: Req(mobile: mobile, code: code, oldCode: oldCode))
    }
}

// MARK: - 实名认证 API（对齐安卓 VerificationApi）

struct VerifyResp: Decodable {
    let passed: Bool
    let status: Int?
    let message: String?
}

enum VerificationAPI {
    static func verify(realName: String, idCard: String) async throws -> VerifyResp {
        struct Req: Encodable { let realName: String; let idCard: String }
        return try await APIClient.shared.post("app-api/member/user/realname-verify", body: Req(realName: realName, idCard: idCard))
    }
}

/// 手机号脱敏（对齐安卓 maskPhone）
func maskPhone(_ phone: String) -> String {
    guard phone.count >= 7 else { return phone }
    return "\(phone.prefix(3))****\(phone.suffix(4))"
}
