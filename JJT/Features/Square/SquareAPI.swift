import Foundation

// MARK: - 广场相关 API（对齐安卓 SocialApi / GroupEventApi 的城市接口）

struct EventCityInfo: Decodable {
    let cityCode: Int
    let cityName: String
}

// MARK: - 评论模型（对齐安卓 CommentInfo / CommentReq）

struct CommentInfo: Decodable, Identifiable {
    let id: Int64
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?
    let avatarFrame: String?
    let avatarFrameScale: Double?
    let content: String
    let parentId: Int64?
    let createTime: Int64?
}

struct CommentReq: Encodable {
    let postId: Int64
    let parentId: Int64?
    let content: String
}

enum SocialAPI {

    /// 帖子流（tab: recommend/newest/nearby/follow；同城需带 cityCode）
    static func postList(pageNo: Int, pageSize: Int = 20, tab: String, cityCode: String? = nil) async throws -> PageResult<PostInfo> {
        var query = ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)", "tab": tab]
        if let cityCode { query["cityCode"] = cityCode }
        return try await APIClient.shared.get("app-api/social/post/list", query: query)
    }

    /// 帖子详情
    static func postDetail(id: Int64) async throws -> PostInfo {
        try await APIClient.shared.get("app-api/social/post/detail", query: ["id": "\(id)"])
    }

    /// 点赞/取消点赞（切换）
    static func like(postId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/like", query: ["postId": "\(postId)"])
    }

    /// 收藏/取消收藏（切换）
    static func favorite(postId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/favorite", query: ["postId": "\(postId)"])
    }

    /// 评论列表
    static func comments(postId: Int64) async throws -> [CommentInfo] {
        try await APIClient.shared.get("app-api/social/post/comments", query: ["postId": "\(postId)"])
    }

    /// 发评论（parentId 非空为回复）
    static func addComment(postId: Int64, parentId: Int64?, content: String) async throws -> CommentInfo {
        try await APIClient.shared.post("app-api/social/post/comment", body: CommentReq(postId: postId, parentId: parentId, content: content))
    }

    /// 组局城市列表（cityCode ↔ 城市名映射，同城 tab 定位后反查 cityCode 用）
    static func eventCities() async throws -> [EventCityInfo] {
        try await APIClient.shared.get("app-api/social/store/event-cities")
    }
}

// MARK: - 关注（对齐安卓 FollowApi）

private struct FollowBody: Encodable { let followUserId: Int64 }

enum FollowAPI {
    static func check(userId: Int64) async throws -> Bool {
        try await APIClient.shared.get("app-api/member/follow/check", query: ["followUserId": "\(userId)"])
    }

    static func follow(userId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/follow/follow", body: FollowBody(followUserId: userId))
    }

    static func unfollow(userId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/follow/unfollow", body: FollowBody(followUserId: userId))
    }
}
