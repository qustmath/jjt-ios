import Foundation

// MARK: - 暗夜选美 API（对齐安卓 PageantApi）

struct PageantActivity: Decodable {
    let id: Int64
    let name: String?
    let nameEn: String?
    let seasonTag: String?
    let cover: String?
    let rules: String?
    /// 开始时间（epoch 毫秒；nil 不限）
    let startTime: Int64?
    /// 落幕时间（epoch 毫秒）
    let endTime: Int64?
    let rewardText: String?
    let carrotPrice: Int64?
    let rabbitPrice: Int64?
    let carrotDaily: Int?
    let rabbitDaily: Int?
    let shareDailyCap: Int?
    /// 免费票每日限次（0=渠道关闭）
    let freeDaily: Int?
    let myCarrotUsed: Int?
    let myRabbitUsed: Int?
    let myFreeUsed: Int?
    let myShareEarned: Int?
    let myShareUsed: Int?
    let carrotBalance: Int64?
    let rabbitBalance: Int64?
    let myEntryId: Int64?
    // ---- 票池（购票入库后统一投票；对齐安卓 PageantActivity pool 字段） ----
    /// 免费票剩余（每日重置）
    let freeLeft: Int?
    /// 分享票剩余（分享得机会，每日重置）
    let shareChances: Int?
    /// 萝贝票库存（购票累计，跨日持久）
    let carrotTickets: Int?
    /// 兔币票库存
    let rabbitTickets: Int?
    /// 票池总票数 = 免费 + 分享 + 萝贝 + 兔币
    let totalTickets: Int?
    /// 今日该渠道还可购票张数（受每日次数与库存约束）
    let carrotPurchaseLeft: Int?
    let rabbitPurchaseLeft: Int?
}

struct PageantEntry: Decodable, Identifiable {
    let id: Int64
    /// 参赛号（活动内序号，展示如 006）
    let entryNo: Int?
    let userId: Int64
    let nickname: String?
    let avatar: String?
    /// 头像框（会员当前佩戴）
    let avatarFrame: String?
    let avatarFrameScale: Double?
    /// 段位名/色值/段内等级（未付费为 nil）
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?
    let images: [String]?
    let video: String?
    let videoCover: String?
    let line: String?
    let votes: Int64?
    let mine: Bool?
    let auditStatus: Int?
    let auditRemark: String?
}

struct PageantEntryDetail: Decodable {
    let id: Int64
    let entryNo: Int?
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let avatarFrame: String?
    let avatarFrameScale: Double?
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?
    let images: [String]?
    let video: String?
    let videoCover: String?
    let line: String?
    let votes: Int64?
    let mine: Bool?
    let rank: Int?
    let gapVotes: Int64?
    let recentVoters: [Voter]?

    struct Voter: Decodable {
        let nickname: String?
        let avatar: String?
        let avatarFrame: String?
        let avatarFrameScale: Double?
        let vipLevel: String?
        let vipLevelColor: String?
        let levelInTier: Int?
        let votes: Int?
        let timeText: String?
    }
}

struct PageantFeedItem: Decodable {
    let voterNickname: String?
    let ownerNickname: String?
    let votes: Int?
    let timeText: String?
}

struct PageantEntrySaveReq: Encodable {
    let images: [String]
    let video: String?
    let videoCover: String?
    let line: String
}

/// voteType: carrot / rabbit / share；rabbit 需 payPassword
struct PageantVoteReq: Encodable {
    let entryId: Int64
    let voteType: String
    let votes: Int
    let payPassword: String?
}

/// 购票：type=rabbit/carrot，count=张数；兔币需支付密码；扣钱包后进入票池
struct PageantTicketPurchaseReq: Encodable {
    let type: String
    let count: Int
    let payPassword: String?
}

/// 票池投票：服务端按 免费→分享→萝贝→兔币 顺序扣票
struct PageantPoolVoteReq: Encodable {
    let entryId: Int64
    let votes: Int
}

/// 购票后的票池快照
struct PageantTicketPool: Decodable {
    let freeLeft: Int?
    let shareChances: Int?
    let carrotTickets: Int?
    let rabbitTickets: Int?
    let totalTickets: Int?
    let carrotPurchaseLeft: Int?
    let rabbitPurchaseLeft: Int?
}

enum PageantAPI {
    static func activity() async throws -> PageantActivity {
        try await APIClient.shared.get("app-api/member/pageant/activity")
    }

    static func entries() async throws -> [PageantEntry] {
        try await APIClient.shared.get("app-api/member/pageant/entries")
    }

    static func entryDetail(id: Int64) async throws -> PageantEntryDetail {
        try await APIClient.shared.get("app-api/member/pageant/entry", query: ["id": "\(id)"])
    }

    static func myEntry() async throws -> PageantEntry? {
        try await APIClient.shared.get("app-api/member/pageant/my-entry")
    }

    static func feed() async throws -> [PageantFeedItem] {
        try await APIClient.shared.get("app-api/member/pageant/feed")
    }

    static func join(_ body: PageantEntrySaveReq) async throws -> PageantEntry {
        try await APIClient.shared.post("app-api/member/pageant/join", body: body)
    }

    static func updateEntry(_ body: PageantEntrySaveReq) async throws -> PageantEntry {
        try await APIClient.shared.put("app-api/member/pageant/entry", body: body)
    }

    static func deleteEntry() async throws -> Bool {
        try await APIClient.shared.delete("app-api/member/pageant/entry")
    }

    static func vote(_ body: PageantVoteReq) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/pageant/vote", body: body)
    }

    static func shareEarn(entryId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/pageant/share-earn", query: ["entryId": "\(entryId)"])
    }

    /// 购票入池（扣兔币/萝贝钱包），返回最新票池
    static func purchaseTicket(_ body: PageantTicketPurchaseReq) async throws -> PageantTicketPool {
        try await APIClient.shared.post("app-api/member/pageant/ticket/purchase", body: body)
    }

    /// 票池投票（免费→分享→萝贝→兔币 顺序扣票）
    static func votePool(_ body: PageantPoolVoteReq) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/pageant/ticket/vote", body: body)
    }
}
