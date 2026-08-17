import Foundation

// MARK: - 模型（对齐安卓 UserProfileApi.kt / FollowApi.kt）

/// 用户主页公开资料
struct UserProfileInfo: Decodable {
    let id: Int64
    let nickname: String?
    let avatar: String?
    let avatarFrame: String?
    let avatarFrameScale: Double?
    let profileBg: String?
    let sex: Int?
    let areaName: String?
    let mark: String?
    let level: UserLevelInfo?
    let postCount: Int?
    let followCount: Int?
    let fansCount: Int?
    let likeCount: Int?
    var isFollowing: Bool?
    let isMutual: Bool?
    let isSelf: Bool?
}

struct FollowUser: Decodable, Identifiable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let mark: String?
    var isMutual: Bool?
    let createTime: String?
    let avatarFrame: String?
    let avatarFrameScale: Double?
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?

    var id: Int64 { userId }
}

struct FollowPage: Decodable {
    let list: [FollowUser]?
    let total: Int64?
}

struct FriendApplyInfo: Decodable, Identifiable {
    let id: Int64
    let peerUserId: Int64
    let nickname: String?
    let avatar: String?
    let createTime: String?
}

struct IntimateRelation: Decodable, Identifiable {
    let id: Int64
    let peerUserId: Int64
    let peerNickname: String?
    let peerAvatar: String?
    let myRole: String?
    let peerRole: String?
    let intimacy: Int?
}

struct IntimateInviteReq: Encodable {
    let peerUserId: Int64
    let role: String
}

// MARK: - SocialAPI 扩展（个人主页帖子/删帖）

extension SocialAPI {
    /// 指定用户的帖子列表
    static func userPostList(userId: Int64, pageNo: Int = 1, pageSize: Int = 20) async throws -> PageResult<PostInfo> {
        try await APIClient.shared.get("app-api/social/post/user-list", query: [
            "userId": String(userId), "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    /// 删除自己的帖子（连带删除云端媒体）
    static func deletePost(id: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/social/post/delete", query: ["id": String(id)])
    }
}

// MARK: - UserAPI 扩展（公开主页资料）

extension UserAPI {
    static func getProfile(userId: Int64) async throws -> UserProfileInfo {
        try await APIClient.shared.get("app-api/member/user/profile", query: ["userId": String(userId)])
    }
}

// MARK: - FollowAPI 扩展（关注/粉丝/好友/好友申请/亲密关系）
// 基础件 check/follow/unfollow/friendStatus/friendApply 在 SquareAPI.swift

extension FollowAPI {
    static func followers(pageNo: Int = 1, pageSize: Int = 20) async throws -> FollowPage {
        try await APIClient.shared.get("app-api/member/follow/followers", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    static func following(pageNo: Int = 1, pageSize: Int = 20) async throws -> FollowPage {
        try await APIClient.shared.get("app-api/member/follow/following", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    /// 好友列表（互关）
    static func friends() async throws -> FollowPage {
        try await APIClient.shared.get("app-api/member/follow/friends")
    }

    // ---- 好友申请 ----

    static func friendApplyReceived() async throws -> [FriendApplyInfo] {
        try await APIClient.shared.get("app-api/member/friend-apply/received")
    }

    static func friendApplySent() async throws -> [FriendApplyInfo] {
        try await APIClient.shared.get("app-api/member/friend-apply/sent")
    }

    static func friendApplyAgree(id: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/friend-apply/agree", query: ["id": String(id)])
    }

    static func friendApplyReject(id: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/friend-apply/reject", query: ["id": String(id)])
    }

    // ---- 亲密关系 ----

    static func intimateInvite(peerUserId: Int64, role: String) async throws -> Int64 {
        try await APIClient.shared.post("app-api/member/intimate/invite", body: IntimateInviteReq(peerUserId: peerUserId, role: role))
    }

    static func intimateAccept(peerUserId: Int64, role: String) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/intimate/accept", body: IntimateInviteReq(peerUserId: peerUserId, role: role))
    }

    static func intimateList() async throws -> [IntimateRelation] {
        try await APIClient.shared.get("app-api/member/intimate/list")
    }

    static func intimatePending() async throws -> [IntimateRelation] {
        try await APIClient.shared.get("app-api/member/intimate/pending")
    }
}
