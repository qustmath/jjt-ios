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
    let nickname: String?
    let avatar: String?
    let content: String?
    let images: [String]?
    let likeCount: Int?
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
