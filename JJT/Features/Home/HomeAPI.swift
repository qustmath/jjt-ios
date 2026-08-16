import Foundation

// MARK: - 模型（字段对齐安卓 BannerInfo / PostInfo / GroupEventInfo，首页只用子集）

struct BannerInfo: Decodable {
    let id: Int64?
    let imageUrl: String?
    let linkTarget: String?
    let title: String?
}

struct PostInfo: Decodable, Identifiable {
    let id: Int64
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?
    let avatarFrame: String?
    let avatarFrameScale: Double?
    let mediaType: String?
    let title: String?
    let content: String?
    let images: [String]?
    let video: String?
    let videoCover: String?
    let topics: [String]?
    let location: String?
    let cityName: String?
    let likeCount: Int?
    let commentCount: Int?
    let favoriteCount: Int?
    let viewCount: Int?
    let liked: Bool?
    let favorited: Bool?
    let unlocked: Bool?
    let paidPrice: Int?
    let auditStatus: Int?
    let createTime: Int64?

    /// 卡片标题：无 title 时取 content 首行（对齐安卓 PostCard）
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let c = content ?? ""
        if let nl = c.firstIndex(of: "\n") { return String(c[..<nl]) }
        return c
    }

    /// 付费未解锁（对齐安卓 isPaidLocked）
    var isPaidLocked: Bool { (paidPrice ?? 0) > 0 && unlocked != true }
}

struct GroupEventInfo: Decodable, Identifiable {
    let id: Int64
    let title: String?
    let eventTime: String?
    let location: String?
    let participantLimit: Int?
    let currentCount: Int?
    let rabbitCoinPrice: Int?
}

/// 通用分页壳
struct PageResult<T: Decodable>: Decodable {
    let list: [T]?
    let total: Int64?
}

// MARK: - 首页相关 API（对齐安卓 BannerApi / SocialApi / GroupEventApi）

enum HomeAPI {

    /// 轮播图（position=1 首页）
    static func banners() async throws -> [BannerInfo] {
        try await APIClient.shared.get("app-api/system/banner/list", query: ["position": "1"])
    }

    /// 广场最新帖子
    static func latestPosts() async throws -> PageResult<PostInfo> {
        try await APIClient.shared.get("app-api/social/post/list", query: ["pageNo": "1", "pageSize": "10", "tab": "newest"])
    }

    /// 热门组局
    static func hotGroupEvents() async throws -> PageResult<GroupEventInfo> {
        try await APIClient.shared.get("app-api/social/group-event/list", query: ["pageNo": "1", "pageSize": "4", "tab": "hot"])
    }
}
