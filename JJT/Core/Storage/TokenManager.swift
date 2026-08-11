import Foundation

/// 登录态 Token 管理（Keychain 持久化，对应安卓 TokenManager）
final class TokenManager {

    static let shared = TokenManager()

    private let kAccessToken = "jjt.access_token"
    private let kRefreshToken = "jjt.refresh_token"
    private let kUserId = "jjt.user_id"

    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private(set) var userId: Int64?

    var isLoggedIn: Bool { accessToken != nil }

    private init() {
        accessToken = KeychainHelper.load(kAccessToken)
        refreshToken = KeychainHelper.load(kRefreshToken)
        if let s = KeychainHelper.load(kUserId) { userId = Int64(s) }
    }

    func save(accessToken: String, refreshToken: String, userId: Int64) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        KeychainHelper.save(accessToken, for: kAccessToken)
        KeychainHelper.save(refreshToken, for: kRefreshToken)
        KeychainHelper.save(String(userId), for: kUserId)
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        userId = nil
        KeychainHelper.delete(kAccessToken)
        KeychainHelper.delete(kRefreshToken)
        KeychainHelper.delete(kUserId)
    }
}
