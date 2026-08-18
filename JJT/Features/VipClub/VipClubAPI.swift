import Foundation

// MARK: - 蜜兔会 API（对齐安卓 VipClubApi）

struct VipClubInfo: Decodable {
    let minLevel: Int?
    let description: String?
    let questionsJson: String?
}

struct VipClubMember: Decodable, Identifiable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let sex: Int?
    let age: Int?
    let areaId: Int?
    let hasViewPermission: Bool?
    let coverUrl: String?
    let wantToMeet: String?
    let purpose: String?
    let bio: String?

    var id: Int64 { userId }
}

struct VipClubMemberPageResult: Decodable {
    let total: Int64?
    let list: [VipClubMember]?
}

struct VipClubMemberDetail: Decodable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let sex: Int?
    let age: Int?
    let areaId: Int?
    let isOwner: Bool?
    let requesterIsMember: Bool?
    let hasViewPermission: Bool?
    let background: String?
    let clubAvatar: String?
    let photoAlbum: [String]?
    let wantToMeet: String?
    let purpose: String?
    let bio: String?
}

struct VipClubStatus: Decodable {
    /// non_member / applied / member
    let status: String?
}

struct VipClubApplyReq: Encodable {
    var answersJson: String? = nil
    var wantToMeet: String? = nil
    var purpose: String? = nil
    var photoUrls: String? = nil
}

struct VipClubProfileUpdateReq: Encodable {
    var background: String? = nil
    var clubAvatar: String? = nil
    var photoAlbum: String? = nil
    var wantToMeet: String? = nil
    var purpose: String? = nil
    var bio: String? = nil
}

struct VipClubViewRequest: Decodable, Identifiable {
    let requestId: Int64
    let requesterId: Int64
    let nickname: String?
    let avatar: String?
    let createTime: String?

    var id: Int64 { requestId }

    private enum CodingKeys: String, CodingKey {
        case requestId, requesterId, nickname, avatar, createTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(Int64.self, forKey: .requestId)
        requesterId = try c.decode(Int64.self, forKey: .requesterId)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        createTime = try c.decodeLenientString(forKey: .createTime)
    }
}

struct VipClubViewRequestPageResult: Decodable {
    let total: Int64?
    let list: [VipClubViewRequest]?
}

enum VipClubAPI {

    static func info() async throws -> VipClubInfo {
        try await APIClient.shared.get("app-api/member/vip-club/info")
    }

    static func members(pageNo: Int = 1, pageSize: Int = 50) async throws -> VipClubMemberPageResult {
        try await APIClient.shared.get("app-api/member/vip-club/members", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    static func memberDetail(userId: Int64) async throws -> VipClubMemberDetail {
        try await APIClient.shared.get("app-api/member/vip-club/member-detail", query: ["userId": String(userId)])
    }

    static func myStatus() async throws -> VipClubStatus {
        try await APIClient.shared.get("app-api/member/vip-club/my-status")
    }

    static func apply(_ req: VipClubApplyReq) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/vip-club/apply", body: req)
    }

    static func myProfile() async throws -> VipClubMemberDetail {
        try await APIClient.shared.get("app-api/member/vip-club/my-profile")
    }

    static func updateMyProfile(_ req: VipClubProfileUpdateReq) async throws -> Bool {
        try await APIClient.shared.put("app-api/member/vip-club/my-profile", body: req)
    }

    static func requestView(targetUserId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/vip-club/view-request", query: ["targetUserId": String(targetUserId)])
    }

    static func incomingViewRequests(pageNo: Int = 1, pageSize: Int = 20) async throws -> VipClubViewRequestPageResult {
        try await APIClient.shared.get("app-api/member/vip-club/incoming-view-requests", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    static func handleViewRequest(requestId: Int64, approved: Bool) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/vip-club/handle-view-request", query: [
            "requestId": String(requestId), "approved": String(approved)
        ])
    }
}

/// 申请问卷题（questionsJson 数组元素，对齐安卓 QuestionItem）
struct VipClubQuestion {
    let index: Int
    let question: String
    let required: Bool

    static func parse(_ json: String?) -> [VipClubQuestion] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.enumerated().map { i, obj in
            VipClubQuestion(index: i,
                            question: obj["question"] as? String ?? "",
                            required: obj["required"] as? Bool ?? true)
        }
    }
}
