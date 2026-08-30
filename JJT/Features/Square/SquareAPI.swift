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

/// 举报请求（对齐安卓 PostReportReq：reason 为预设原因编码 porn/harassment/ad/illegal/other）
struct PostReportReq: Encodable {
    let postId: Int64
    let reason: String
    let detail: String?
}

enum SocialAPI {

    /// 帖子流（tab: recommend/newest/follow；推荐 tab 已授权定位时带浏览者经纬度做同城加分，ADR 0013；mediaType=video 只取视频帖）
    static func postList(pageNo: Int, pageSize: Int = 20, tab: String, latitude: Double? = nil, longitude: Double? = nil, mediaType: String? = nil) async throws -> PageResult<PostInfo> {
        var query = ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)", "tab": tab]
        if let latitude { query["latitude"] = "\(latitude)" }
        if let longitude { query["longitude"] = "\(longitude)" }
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

    /// 删除自己的评论
    static func deleteComment(id: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/social/post/comment/delete", query: ["id": "\(id)"])
    }

    /// 付费解锁帖子（支付密码；解锁后永久可看）
    static func unlock(postId: Int64, payPassword: String) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/unlock", query: ["postId": "\(postId)", "payPassword": payPassword])
    }

    /// 分享上报：分享成功回调后调用，每次成功分享计一次（重复分享重复计）；取消/失败不上报
    static func share(postId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/share", query: ["postId": "\(postId)"])
    }

    /// 我的帖子收藏列表
    static func favoritePage(pageNo: Int, pageSize: Int = 20) async throws -> PageResult<PostInfo> {
        try await APIClient.shared.get("app-api/social/post/favorite/page", query: ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)"])
    }

    /// 我的点赞帖子列表
    static func likePage(pageNo: Int, pageSize: Int = 20) async throws -> PageResult<PostInfo> {
        try await APIClient.shared.get("app-api/social/post/like/page", query: ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)"])
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

    /// 组局城市列表（cityCode ↔ 城市名映射）
    static func eventCities() async throws -> [EventCityInfo] {
        try await APIClient.shared.get("app-api/social/store/event-cities")
    }

    /// 不感兴趣：负反馈，确认后该帖在本人广场所有 tab 硬隐藏；幂等（重复提交不报错）；v1 无撤销
    static func notInterested(postId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/not-interested", query: ["postId": "\(postId)"])
    }

    /// 曝光批量上报：卡片进入广场可视区后凑批（或退出 feed 时）上报；按 (会员, 帖子) 去重，幂等；仅登录态调用
    static func reportImpressions(_ postIds: [Int64]) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/impression:batch", body: postIds)
    }

    /// 举报帖子：预设原因 + 可选补充说明，提交后进待审由运营审核；按 (会员, 帖子) 唯一，重复举报幂等
    static func report(postId: Int64, reason: String, detail: String?) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/post/report", body: PostReportReq(postId: postId, reason: reason, detail: detail))
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
