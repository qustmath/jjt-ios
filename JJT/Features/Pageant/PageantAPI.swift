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
    let myCarrotUsed: Int?
    let myRabbitUsed: Int?
    let myShareEarned: Int?
    let myShareUsed: Int?
    let carrotBalance: Int64?
    let rabbitBalance: Int64?
    let myEntryId: Int64?
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
}
