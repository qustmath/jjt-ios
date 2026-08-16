import Foundation

/// 广场状态（对齐安卓 SquareViewModel：每 tab 数据/分页/加载态独立）
@MainActor
final class SquareViewModel: ObservableObject {

    /// 单个 tab 的 feed（对齐安卓 TabFeed）
    struct TabFeed {
        var posts: [PostInfo] = []
        var isLoading = false
        var isLoadingMore = false
        var hasMore = true
        var page = 1
        var loaded = false
    }

    @Published var tab = "recommend"
    @Published var feeds: [String: TabFeed] = [:]

    // 同城 tab 定位状态
    @Published var nearbyCityCode: String?
    @Published var nearbyCityName: String?
    @Published var nearbyLocating = false
    @Published var nearbyDenied = false

    var currentFeed: TabFeed { feeds[tab] ?? TabFeed() }

    /// 切 tab：确保该页数据已加载
    func switchTab(_ t: String) {
        tab = t
        let f = feeds[t]
        if f == nil || (!f!.loaded && !f!.isLoading) { refresh(t) }
    }

    func refresh(_ t: String) { load(t, page: 1, isRefresh: true) }

    func loadMore(_ t: String) {
        guard let f = feeds[t], !f.isLoading, !f.isLoadingMore, f.hasMore, !f.posts.isEmpty else { return }
        load(t, page: f.page + 1, isRefresh: false)
    }

    private func load(_ t: String, page: Int, isRefresh: Bool) {
        // 同城 tab：未定位到城市时不发请求（UI 由定位引导态接管）
        var cityCode: String?
        if t == "nearby" {
            guard let c = nearbyCityCode else { return }
            cityCode = c
        }
        updateFeed(t) { $0.isLoading = isRefresh && $0.posts.isEmpty; $0.isLoadingMore = !isRefresh }
        Task {
            let resp = try? await SocialAPI.postList(pageNo: page, tab: t, cityCode: cityCode)
            updateFeed(t) { f in
                f.isLoading = false
                f.isLoadingMore = false
                guard let resp else { return }
                let list = resp.list ?? []
                if isRefresh {
                    f.posts = list
                } else {
                    // 分页去重：翻页间隙新帖插入会导致 id 重复
                    var seen = Set(f.posts.map(\.id))
                    f.posts += list.filter { seen.insert($0.id).inserted }
                }
                f.hasMore = list.count >= 20
                f.page = page
                f.loaded = true
            }
        }
    }

    /// 同城定位：城市名 → event-cities 反查 cityCode（iOS CLGeocoder 拿不到 adcode）
    func locateNearby() {
        nearbyLocating = true
        nearbyDenied = false
        Task {
            defer { nearbyLocating = false }
            guard let name = await CityLocator.shared.currentCity(),
                  let cities = try? await SocialAPI.eventCities(),
                  let match = cities.first(where: { name.contains($0.cityName) || $0.cityName.contains(name) }) else {
                nearbyDenied = true
                return
            }
            nearbyCityCode = String(match.cityCode)
            nearbyCityName = match.cityName
            nearbyDenied = false
            refresh("nearby")
        }
    }

    private func updateFeed(_ t: String, _ transform: (inout TabFeed) -> Void) {
        var f = feeds[t] ?? TabFeed()
        transform(&f)
        feeds[t] = f
    }
}
