import Foundation

/// 地理位置（对齐安卓 GeoApi：后端转发腾讯 WebService——逆地理 + POI 搜索）
enum GeoAPI {

    /// 逆地理：坐标 → 城市
    static func reverse(latitude: Double, longitude: Double) async throws -> ReverseGeo {
        try await APIClient.shared.get("app-api/social/geo/reverse", query: [
            "latitude": "\(latitude)", "longitude": "\(longitude)",
        ])
    }

    /// POI 关键词搜索（城市限定 + 定位排序）
    static func searchPoi(keyword: String, cityName: String? = nil, latitude: Double? = nil, longitude: Double? = nil) async throws -> [PoiInfo] {
        var query = ["keyword": keyword]
        if let cityName { query["cityName"] = cityName }
        if let latitude { query["latitude"] = "\(latitude)" }
        if let longitude { query["longitude"] = "\(longitude)" }
        return try await APIClient.shared.get("app-api/social/geo/poi", query: query)
    }

    /// 周边 POI（距定位点由近及远）
    static func nearbyPois(latitude: Double, longitude: Double) async throws -> [PoiInfo] {
        try await APIClient.shared.get("app-api/social/geo/nearby-pois", query: [
            "latitude": "\(latitude)", "longitude": "\(longitude)",
        ])
    }
}

struct ReverseGeo: Decodable {
    let cityCode: String?
    let cityName: String?
}

struct PoiInfo: Decodable, Identifiable {
    let title: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let cityCode: String?
    let cityName: String?
    /// 距定位点距离（米，仅周边列表返回）
    let distance: Int?

    var id: String { "\(title ?? "")_\(address ?? "")_\(latitude ?? 0)_\(longitude ?? 0)" }
}
