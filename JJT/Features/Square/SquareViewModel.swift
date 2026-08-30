import Foundation

/// 广场状态（对齐安卓 SquareViewModel：每 tab 数据/分页/加载态独立；
/// 推荐 tab 携带浏览者经纬度做同城加分；曝光按 (会员, 帖子) 会话级去重凑批上报）
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

    // ===== 推荐 tab 浏览者定位（同城距离加分项；ADR 0013 第 5 条） =====
    private var viewerLatitude: Double?
    private var viewerLongitude: Double?

    var currentFeed: TabFeed { feeds[tab] ?? TabFeed() }

    /// 切 tab：确保该页数据已加载
    func switchTab(_ t: String) {
        tab = t
        let f = feeds[t]
        if f == nil || (!f!.loaded && !f!.isLoading) { refresh(t) }
    }

    func refresh(_ t: String) { load(t, page: 1, isRefresh: true) }

    /// 静默刷新：不打扰用户（用于定位就绪后让同城加分生效等自动触发场景）
    func refreshSilent(_ t: String) { load(t, page: 1, isRefresh: true) }

    func loadMore(_ t: String) {
        guard let f = feeds[t], !f.isLoading, !f.isLoadingMore, f.hasMore, !f.posts.isEmpty else { return }
        load(t, page: f.page + 1, isRefresh: false)
    }

    /// 设置浏览者定位（已授权定位时由页面解析后传入；未授权不调用，请求不带经纬度）。
    /// 推荐流已加载过时静默重刷一次，让同城加分生效（服务端 pageNo=1 重算快照）。
    func setViewerLocation(latitude: Double, longitude: Double) {
        if viewerLatitude == latitude && viewerLongitude == longitude { return }
        viewerLatitude = latitude
        viewerLongitude = longitude
        if feeds["recommend"]?.loaded == true { refreshSilent("recommend") }
    }

    private func load(_ t: String, page: Int, isRefresh: Bool) {
        // 推荐 tab：按定位授权情况携带浏览者经纬度（未授权/未获取为 nil，请求不带，同城项计 0）
        let latitude = t == "recommend" ? viewerLatitude : nil
        let longitude = t == "recommend" ? viewerLongitude : nil
        updateFeed(t) { $0.isLoading = isRefresh && $0.posts.isEmpty; $0.isLoadingMore = !isRefresh }
        Task {
            let resp = try? await SocialAPI.postList(pageNo: page, tab: t, latitude: latitude, longitude: longitude)
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

    // ===== 负反馈（对齐安卓：不感兴趣硬隐藏本人全部 tab；举报进平台待审不移除） =====

    /// 不感兴趣：上报成功后从所有 tab 的本地列表移除该帖（服务端已对本人硬隐藏，接口幂等可重试）
    func notInterested(postId: Int64) {
        Task {
            guard (try? await SocialAPI.notInterested(postId: postId)) == true else { return }
            for t in feeds.keys {
                updateFeed(t) { feed in feed.posts.removeAll { $0.id == postId } }
            }
            jjtShowToast("已减少此类内容推荐")
        }
    }

    /// 举报：提交后进入平台待审（接口幂等可重试）；帖子不从列表移除，审核成立与否由运营判定
    func report(postId: Int64, reason: String, detail: String?) {
        Task {
            guard (try? await SocialAPI.report(postId: postId, reason: reason, detail: detail)) == true else { return }
            jjtShowToast("举报已提交，平台将尽快审核")
        }
    }

    // ===== 曝光上报（按 (会员, 帖子) 去重，仅登录会员；负反馈率 15% 硬规则的分母数据源） =====

    /// 本 Session 已见过的曝光帖子：同一会话内重复露出（切 tab/回刷）不重复上报
    private var seenImpressions = Set<Int64>()
    /// 待上报队列：凑够批次阈值或退出 feed 时批量上报
    private var pendingImpressions: [Int64] = []

    static let impressionBatchSize = 10

    /// 卡片进入可视区 → 记一次曝光（本 Session 内去重；凑批即上报，静默失败不打扰用户）
    func onPostVisible(_ id: Int64) {
        guard TokenManager.shared.isLoggedIn else { return } // 仅登录会员上报（曝光按会员计），游客不留口
        guard seenImpressions.insert(id).inserted else { return }
        pendingImpressions.append(id)
        if pendingImpressions.count >= Self.impressionBatchSize { flushImpressions() }
    }

    /// 批量上报待上报队列；失败回补队列随下一批重试（服务端幂等，重复上报无副作用）
    func flushImpressions() {
        guard !pendingImpressions.isEmpty, TokenManager.shared.isLoggedIn else { return }
        let batch = pendingImpressions
        pendingImpressions.removeAll()
        Task {
            if (try? await SocialAPI.reportImpressions(batch)) != true {
                pendingImpressions.insert(contentsOf: batch, at: 0)
            }
        }
    }

    private func updateFeed(_ t: String, _ transform: (inout TabFeed) -> Void) {
        var f = feeds[t] ?? TabFeed()
        transform(&f)
        feeds[t] = f
    }
}
