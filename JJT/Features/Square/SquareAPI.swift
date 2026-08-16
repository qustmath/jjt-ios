import Foundation

// MARK: - 广场相关 API（对齐安卓 SocialApi / GroupEventApi 的城市接口）

struct EventCityInfo: Decodable {
    let cityCode: Int
    let cityName: String
}

enum SocialAPI {

    /// 帖子流（tab: recommend/newest/nearby/follow；同城需带 cityCode）
    static func postList(pageNo: Int, pageSize: Int = 20, tab: String, cityCode: String? = nil) async throws -> PageResult<PostInfo> {
        var query = ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)", "tab": tab]
        if let cityCode { query["cityCode"] = cityCode }
        return try await APIClient.shared.get("app-api/social/post/list", query: query)
    }

    /// 组局城市列表（cityCode ↔ 城市名映射，同城 tab 定位后反查 cityCode 用）
    static func eventCities() async throws -> [EventCityInfo] {
        try await APIClient.shared.get("app-api/social/store/event-cities")
    }
}
