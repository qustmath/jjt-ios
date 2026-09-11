import Foundation

// MARK: - 图文 API（对齐安卓 ArticleApi）

/// 图文详情（v1 仅经轮播图/弹窗/扫码 DeepLink 直达，与帖子严格隔离：不进广场、无互动）
struct ArticleInfo: Decodable {
    let id: Int64?
    let title: String?
    /// 封面图 URL（列表/分享预留，v1 详情页不渲染）
    let coverUrl: String?
    /// 正文 JSON 块数组：[{"type":"text","value"},{"type":"image","url"}]
    let content: String?
    /// 发布时间（epoch millis，与帖子 createTime 序列化口径一致）
    let publishTime: Int64?
    /// 浏览次数（本次访问已由服务端计入）
    let browseCount: Int?
}

enum ArticleAPI {

    /// 图文详情（仅启用态可见；服务端内部浏览次数 +1，App 不单独上报）；
    /// 禁用/不存在返回 code=1002017000（"图文不存在或已下架"）
    static func get(id: Int64) async throws -> ArticleInfo {
        try await APIClient.shared.get("app-api/system/article/get", query: ["id": String(id)])
    }
}
