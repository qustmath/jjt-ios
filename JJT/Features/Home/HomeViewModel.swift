import Foundation

/// 首页状态（对齐安卓 HomeViewModel；IM 未读红点待 IM SDK 接入后补）
@MainActor
final class HomeViewModel: ObservableObject {

    @Published var banners: [BannerInfo] = []
    @Published var latestPosts: [PostInfo] = []
    @Published var hotGroupEvents: [GroupEventInfo] = []
    @Published var isLoading = false

    private var loaded = false

    /// 首次/回到首页时加载；单项失败静默，不影响其余（对齐安卓并行 launchCatching）
    func load(force: Bool = false) {
        if isLoading || (loaded && !force) { return }
        isLoading = true
        Task {
            async let b: () = loadBanners()
            async let p: () = loadPosts()
            async let e: () = loadEvents()
            _ = await (b, p, e)
            isLoading = false
            loaded = true
        }
    }

    private func loadBanners() async {
        if let r = try? await HomeAPI.banners() { banners = r }
    }

    private func loadPosts() async {
        if let r = try? await HomeAPI.latestPosts() { latestPosts = r.list ?? [] }
    }

    private func loadEvents() async {
        if let r = try? await HomeAPI.hotGroupEvents() { hotGroupEvents = r.list ?? [] }
    }
}
