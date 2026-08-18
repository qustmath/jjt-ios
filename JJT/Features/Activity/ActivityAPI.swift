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
}

/// 时间戳（毫秒）→ "M月d日"（对齐安卓 fmtDay）
func fmtActivityDay(_ ts: Int64?) -> String {
    guard let ts else { return "-" }
    let d = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
    let f = DateFormatter()
    f.dateFormat = "M月d日"
    return f.string(from: d)
}
