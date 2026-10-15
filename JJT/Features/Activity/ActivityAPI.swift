import Foundation

// MARK: - 活动/票夹 API（对齐安卓 ActivityApi）

struct ActivityInfo: Decodable {
    let id: Int64
    let name: String?
    let nameEn: String?
    let subtitle: String?
    let cover: String?
    let rules: String?
    let footerText: String?
    let actionType: String?
    /// before未开始 / claim领票中 / open验票中 / expired已落幕（服务端时间判定）
    let phase: String?
    let canClaim: Bool?
    let canRedeem: Bool?
    let claimStart: Int64?
    let claimEnd: Int64?
    let redeemStart: Int64?
    let redeemEnd: Int64?
    let rewardBadgeId: Int64?
    let rewardBadgeName: String?
    let rewardBadgeIcon: String?
    let rewardCoin: Int?
    let myTicket: TicketInfo?
    /// 报名模式：photo=报名审核制（SIGNUP_PHOTO），其余 null（v1 安卓对齐）
    let signupMode: String?
    /// 我的报名（含被拒，未报名 null）
    let mySignup: SignupInfo?
    /// 主题令牌 JSON 原样（App 容错解析，可空）
    let theme: String?
    /// 穿搭墙是否开放（报名制活动恒 true）
    let wallEnabled: Bool?
}

struct TicketInfo: Decodable, Identifiable {
    let id: Int64
    let activityId: Int64
    let activityName: String?
    let activityNameEn: String?
    let activityCover: String?
    let ticketNo: String?
    /// 0待使用 1已核销 2已失效
    let status: Int?
    let claimTime: Int64?
    let useTime: Int64?
    let canRedeem: Bool?
}

/// 我的报名（对齐安卓 SignupInfo）
struct SignupInfo: Decodable {
    let id: Int64
    /// 主图（=穿搭照首张）
    let img: String?
    /// 穿搭照列表（1~6 张）
    let imgs: [String]?
    let look: String?
    /// 0待审 1通过 2拒绝
    let status: Int?
    let rejectReason: String?
    let likes: Int64?
    /// 凭证码（status=1 时）
    let ticketNo: String?
}

/// 提交报名请求（仅图片，1~6 张，首张为主图）
struct SignupReq: Encodable {
    let id: Int64
    let imgs: [String]
    let look: String?
}

/// 穿搭墙条目（详情接口同构，点赞数实时；对齐安卓 WallItem）
struct WallItem: Decodable, Identifiable {
    let id: Int64
    /// 主图（=穿搭照首张，墙卡用）
    let img: String?
    /// 穿搭照列表（详情页多图查看用）
    let imgs: [String]?
    let look: String?
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    /// 佩戴头像框（会员等级外观，空=无框）
    let avatarFrame: String?
    let avatarFrameScale: Double?
    /// 外显段位名/色 + 段内等级（空=未达到任何段位）
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?
    let likes: Int64?
    let liked: Bool?
    /// 是否本人报名
    let mine: Bool?
    /// 是否待审（仅本人待审条目出现在墙里）
    let pending: Bool?
    let createTime: Int64?
}

enum ActivityAPI {
    static func get(id: Int64) async throws -> ActivityInfo {
        try await APIClient.shared.get("app-api/member/activity/get", query: ["id": String(id)])
    }

    static func claim(id: Int64) async throws -> TicketInfo {
        try await APIClient.shared.post("app-api/member/activity/claim", query: ["id": String(id)])
    }

    static func redeem(id: Int64) async throws -> ActivityInfo {
        try await APIClient.shared.post("app-api/member/activity/redeem", query: ["id": String(id)])
    }

    static func ticketPage(pageNo: Int = 1, pageSize: Int = 50) async throws -> PageResult<TicketInfo> {
        try await APIClient.shared.get("app-api/member/activity/ticket/page", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    // MARK: - 报名审核制（SIGNUP_PHOTO）

    static func signup(id: Int64, imgs: [String], look: String?) async throws -> SignupInfo {
        try await APIClient.shared.post(
            "app-api/member/activity/signup",
            body: SignupReq(id: id, imgs: imgs, look: look)
        )
    }

    static func signupWall(id: Int64, pageNo: Int = 1, pageSize: Int = 20) async throws -> PageResult<WallItem> {
        try await APIClient.shared.get("app-api/member/activity/signup/wall", query: [
            "id": String(id), "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    static func signupGet(signupId: Int64) async throws -> WallItem {
        try await APIClient.shared.get("app-api/member/activity/signup/get", query: [
            "signupId": String(signupId)
        ])
    }

    @discardableResult
    static func signupLike(signupId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/activity/signup/like", query: [
            "signupId": String(signupId)
        ])
    }
}

/// 时间戳（毫秒）→ "M月d日"（对齐安卓 fmtDay）
func fmtActivityDay(_ ts: Int64?) -> String {
    guard let ts else { return "-" }
    let d = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
    let f = DateFormatter()
    f.dateFormat = "M月d日"
    return f.string(from: d)
}
