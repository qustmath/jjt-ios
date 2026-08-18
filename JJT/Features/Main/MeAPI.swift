import Foundation

// MARK: - 模型（对齐安卓 UserDtos.kt / TaskApi.kt / BadgeApi.kt 子集）

/// 会员等级（外显段位；未付费用户为 nil）
struct UserLevelInfo: Decodable {
    let tier: Int?
    let levelInTier: Int?
    let name: String?
    let color: String?
    let avatarFrame: String?
}

struct StoreMemberInfo: Decodable {
    let storeName: String?
    let balance: FlexibleDecimal?
    let memberNo: String?
}

/// 后端 BigDecimal 可能序列化为数字或字符串，统一兜住
struct FlexibleDecimal: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; return }
        if let d = try? c.decode(Double.self) { value = String(format: "%.2f", d); return }
        value = "0.00"
    }
}

struct UserInfoResp: Decodable {
    let id: Int64
    let nickname: String?
    let avatar: String?
    let avatarFrame: String?
    let avatarFrameScale: Double?
    let profileBg: String?
    let name: String?
    let mobile: String?
    let sex: Int?
    let areaId: Int?
    let areaName: String?
    let mark: String?
    let point: Int?
    let experience: Int?
    let level: UserLevelInfo?
    let postCount: Int?
    let followCount: Int?
    let fansCount: Int?
    let freeCoin: Int?
    let giftCoin: Int?
    let earnings: FlexibleDecimal?
    let storeMember: StoreMemberInfo?
    let realnameStatus: Int?       // 1=已通过（对齐安卓页面行为）
    let realName: String?          // 已认证时服务端返回脱敏姓名
    let idCardMasked: String?      // 已认证时服务端返回脱敏身份证
}

struct UpdateUserReq: Encodable {
    var nickname: String? = nil
    var avatar: String? = nil
    var mark: String? = nil
    var profileBg: String? = nil
    var avatarFrame: String? = nil
}

struct TaskItem: Decodable {
    let taskId: Int64
    let name: String?
    let type: String?          // DAILY / NEWBIE / ACHIEVEMENT
    let currentCount: Int?
    let threshold: Int?
    let status: String?        // IN_PROGRESS / CLAIMABLE / CLAIMED
}

struct BadgeHallItem: Decodable {
    let id: Int64
    let name: String?
    let icon: String?          // URL 或 lucide:图标名
}

struct AchievementHallResp: Decodable {
    let litStages: Int?
    let totalStages: Int?
    let mountedIds: [Int64]?
    let badges: [BadgeHallItem]?
}

// MARK: - API

enum UserAPI {
    /// 个人信息（我的页）
    static func getUserInfo() async throws -> UserInfoResp {
        try await APIClient.shared.get("app-api/member/user/get")
    }

    /// 批量获取用户信息（聊天头像框/段位补全等）
    static func getUserInfoList(ids: [Int64]) async throws -> [UserInfoResp] {
        let joined = ids.map(String.init).joined(separator: ",")
        return try await APIClient.shared.get("app-api/member/user/list", query: ["ids": joined])
    }

    /// 更新资料（昵称/头像/签名）
    static func updateUserInfo(_ req: UpdateUserReq) async throws -> Bool {
        try await APIClient.shared.put("app-api/member/user/update", body: req)
    }
}

enum TaskAPI {
    static func taskList() async throws -> [TaskItem] {
        try await APIClient.shared.get("app-api/member/task/list")
    }
}

enum BadgeAPI {
    static func achievementHall() async throws -> AchievementHallResp {
        try await APIClient.shared.get("app-api/member/badge/hall")
    }
}
