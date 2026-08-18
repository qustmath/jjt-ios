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

struct TaskItem: Decodable, Identifiable {
    let taskId: Int64
    let name: String?
    let description: String?
    let type: String?          // DAILY / NEWBIE / ACHIEVEMENT
    let checkType: String?     // COUNT / CONDITION
    let currentCount: Int?
    let threshold: Int?
    let status: String?        // IN_PROGRESS / CLAIMABLE / CLAIMED
    let rewardAmount: Int64?
    let rewardBadgeId: Int64?  // 有值表示该任务奖励勋章
    let autoClaim: Bool?

    var id: Int64 { taskId }
}

struct BadgeHallItem: Decodable, Identifiable {
    let id: Int64
    let cat: String?
    let name: String?
    let description: String?
    let icon: String?          // URL 或 lucide:图标名
    let rarity: String?
    let stages: Int?
    let targets: [Int64]?
    let condTemplate: String?
    let score: Int?
    let reward: Int?
    let hidden: Bool?
    let sealed: Bool?
    let stage: Int?            // 已点亮阶数（0=未点亮）
    let stageDates: [String]?
    let progress: Int64?       // 当前行为进度值
    let mounted: Bool?
}

struct BadgeCatStat: Decodable {
    let cat: String
    let name: String?
    let got: Int
    let total: Int
}

struct AchievementHallResp: Decodable {
    let totalScore: Int64?
    let litStages: Int?
    let totalStages: Int?
    let carrotBalance: Int64?
    let mountedIds: [Int64]?
    let cats: [BadgeCatStat]?
    let badges: [BadgeHallItem]?
}

/// 勋章墙项（对齐安卓 BadgeItem）
struct BadgeItem: Decodable, Identifiable {
    let id: Int64
    let name: String
    let description: String?
    let icon: String?
    let rarity: String?        // COMMON / RARE / EPIC / LEGENDARY
    let owned: Bool
    let acquiredAt: String?
    let progress: Int?         // 未获得时有值
    let threshold: Int?
}

/// 隐藏彩蛋解锁结果（对齐安卓 EggUnlockResp）
struct EggUnlockResp: Decodable {
    let id: Int64
    let name: String
    let icon: String?
    let score: Int
    let reward: Int
}

struct SignInResult: Decodable {
    let continuousDays: Int
    let rewardAmount: Int64
    let signDate: String?
}

struct SignInStatus: Decodable {
    let signedToday: Bool
    let continuousDays: Int
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

    /// 获取我的邀请码（历史用户首次取码懒生成兜底）
    static func getInviteCode() async throws -> InviteCodeResp {
        try await APIClient.shared.get("app-api/member/user/invite-code")
    }
}

struct InviteCodeResp: Decodable {
    let inviteCode: String?
}

enum TaskAPI {
    static func taskList() async throws -> [TaskItem] {
        try await APIClient.shared.get("app-api/member/task/list")
    }

    static func claim(taskId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/task/claim", query: ["taskId": String(taskId)])
    }

    static func signIn() async throws -> SignInResult {
        try await APIClient.shared.post("app-api/member/sign-in/do", query: [:])
    }

    static func signInStatus() async throws -> SignInStatus {
        try await APIClient.shared.get("app-api/member/sign-in/status")
    }

    /// 每日活跃上报（App 启动时调用，每日首次生效）
    static func dailyActive() async throws -> Bool {
        try await APIClient.shared.post("app-api/member/sign-in/daily-active", query: [:])
    }
}

enum BadgeAPI {
    static func achievementHall() async throws -> AchievementHallResp {
        try await APIClient.shared.get("app-api/member/badge/hall")
    }

    /// 我的勋章墙（含未获得+进度）
    static func badgeWall() async throws -> [BadgeItem] {
        try await APIClient.shared.get("app-api/member/badge/wall")
    }

    /// 他人勋章墙（仅已获得）
    static func userBadgeWall(userId: Int64) async throws -> [BadgeItem] {
        try await APIClient.shared.get("app-api/member/badge/user-wall", query: ["userId": String(userId)])
    }

    static func mount(badgeId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/badge/mount", query: ["badgeId": String(badgeId)])
    }

    static func unmount(badgeId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/badge/unmount", query: ["badgeId": String(badgeId)])
    }

    /// 尝试解锁隐藏彩蛋（key 精准触发；空则随机掉落兜底）
    static func triggerEgg(key: String? = nil) async throws -> EggUnlockResp? {
        try await APIClient.shared.post("app-api/member/badge/egg/trigger", query: key.map { ["key": $0] } ?? [:])
    }
}
