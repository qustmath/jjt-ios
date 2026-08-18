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

/// 发帖请求（对齐安卓 CreatePostReq；nil 字段不编码）
struct CreatePostReq: Encodable {
    let mediaType: String
    let images: [String]?
    let video: String?
    let videoCover: String?
    let content: String
    let topics: [String]?
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let cityCode: String?
    let cityName: String?
    let paidPrice: Int?
    let previewSeconds: Int?
}

/// 编辑帖子请求（对齐安卓 UpdatePostReq：字段同 CreatePostReq + id）
struct UpdatePostReq: Encodable {
    let id: Int64
    let mediaType: String
    let images: [String]?
    let video: String?
    let videoCover: String?
    let content: String
    let topics: [String]?
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let cityCode: String?
    let cityName: String?
    let paidPrice: Int?
    let previewSeconds: Int?
}

/// 发帖成功通知（广场列表收到后刷新）
extension Notification.Name {
    static let jjtPostCreated = Notification.Name("jjtPostCreated")
}

enum SocialAPI {

    /// 帖子流（tab: recommend/newest/nearby/follow；同城需带 cityCode；mediaType=video 只取视频帖）
    static func postList(pageNo: Int, pageSize: Int = 20, tab: String, cityCode: String? = nil, mediaType: String? = nil) async throws -> PageResult<PostInfo> {
        var query = ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)", "tab": tab]
        if let cityCode { query["cityCode"] = cityCode }
        if let mediaType { query["mediaType"] = mediaType }
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

    /// 发布帖子
    static func createPost(_ req: CreatePostReq) async throws -> PostInfo {
        try await APIClient.shared.post("app-api/social/post/create", body: req)
    }

    /// 编辑自己的帖子（body 同 CreatePostReq + id）
    static func updatePost(_ req: UpdatePostReq) async throws -> PostInfo {
        try await APIClient.shared.post("app-api/social/post/update", body: req)
    }

    /// 删除自己的帖子
    static func deletePost(id: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/social/post/delete", query: ["id": "\(id)"])
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

    /// 好友关系状态：none / pending_out / pending_in / friend / self
    static func friendStatus(userId: Int64) async throws -> String {
        try await APIClient.shared.get("app-api/member/friend-apply/status", query: ["targetUserId": "\(userId)"])
    }

    /// 发起好友申请（pending_in 时调用即互关）
    static func friendApply(userId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/friend-apply/apply", query: ["targetUserId": "\(userId)"])
    }
}
