import SwiftUI

/// 组局列表 — 暗夜奢华风（对齐安卓 GroupEventListScreen）
/// mode: "all" = 热门/最新/全部；"my" = 我发起的/我参与的/筹备中
struct GroupEventListView: View {

    var mode: String = "all"
    var initialTab: String? = nil
    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = GroupEventListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var detailEventId: Int64?
    @State private var showCreate = false

    private struct EventTab {
        let key: String
        let label: String
    }

    private static let TABS_ALL = [EventTab(key: "hot", label: "热门"), EventTab(key: "latest", label: "最新"), EventTab(key: "all", label: "全部")]
    private static let TABS_MY = [EventTab(key: "mine_created", label: "我发起的"), EventTab(key: "mine_joined", label: "我参与的"), EventTab(key: "preparing", label: "筹备中")]

    private var tabs: [EventTab] { mode == "my" ? Self.TABS_MY : Self.TABS_ALL }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Text("与同好在暗夜里真实相遇 · 报名后主办方审核入局")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                tabBar
                content
            }
        }
        .onAppear { vm.setup(tab: initialTab ?? (mode == "my" ? "mine_created" : "hot")) }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        .fullScreenCover(isPresented: Binding(
            get: { detailEventId != nil },
            set: { if !$0 { detailEventId = nil } }
        ), onDismiss: { vm.refresh() }) {
            if let id = detailEventId {
                GroupEventDetailView(eventId: id)
            }
        }
        .fullScreenCover(isPresented: $showCreate, onDismiss: { vm.refresh() }) {
            CreateGroupEventView()
        }
        .jjtPageGestures()
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                Spacer()
                Text(mode == "my" ? "我的组局" : "组局 · 暗夜召集")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Spacer()
                if mode == "all" {
                    Button { showCreate = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 13))
                            Text("发起")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    // MARK: - Tab 栏

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(tabs, id: \.key) { t in
                    let selected = vm.tab == t.key
                    Button { vm.switchTab(t.key) } label: {
                        VStack(spacing: 6) {
                            Text(t.label)
                                .font(.system(size: 14, weight: selected ? .bold : .regular))
                                .foregroundStyle(selected ? Noir.ivory : Color.white.opacity(0.35))
                            Rectangle()
                                .fill(selected ? Noir.crimsonHot : .clear)
                                .frame(width: 24, height: 2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 内容（左右滑动切 tab，数据各 tab 独立）

    private var content: some View {
        TabView(selection: Binding(
            get: { vm.tab },
            set: { vm.switchTab($0) }
        )) {
            ForEach(tabs, id: \.key) { t in
                feedPage(t.key)
                    .tag(t.key)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func feedPage(_ tab: String) -> some View {
        let feed = vm.feeds[tab] ?? GroupEventListViewModel.EventFeed()
        return Group {
            if !feed.loaded, feed.isLoading {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if feed.loaded, feed.events.isEmpty {
                Text("暂无组局")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !feed.loaded {
                ProgressView().tint(Noir.crimson).scaleEffect(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(feed.events) { event in
                            GroupEventCard(event: event) { detailEventId = event.id }
                        }
                        if feed.isLoadingMore {
                            ProgressView().tint(Noir.crimson).scaleEffect(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        } else if feed.hasMore {
                            Color.clear.frame(height: 1)
                                .onAppear { vm.loadMore() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .refreshable { vm.refresh() }
            }
        }
    }
}

// MARK: - 组局卡片（对齐安卓 GroupEventCard）

struct GroupEventCard: View {
    let event: GroupEventInfo
    let onTap: () -> Void

    private var full: Bool { (event.currentCount ?? 0) >= (event.participantLimit ?? Int.max) }
    private var joined: Bool { event.joined == true }
    private var started: Bool { Self.isEventStarted(event.eventTime) }

    var body: some View {
        VStack(spacing: 0) {
            cover
            infoSection
        }
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = event.coverImage, !img.isEmpty, let url = URL(string: img) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            coverFallback
                        }
                    }
                } else {
                    coverFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 144)
            .clipped()

            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.2), location: 0.55),
                .init(color: .black.opacity(0.85), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 144)

            // 价格标签
            HStack {
                Spacer()
                Text((event.rabbitCoinPrice ?? 0) == 0 ? "免费" : "\(event.rabbitCoinPrice ?? 0) 兔币")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Noir.goldText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)

            // 标题 + 标签
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title ?? "未命名活动")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
                let chips = chipsOf()
                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: 144)
    }

    private var coverFallback: some View {
        LinearGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func chipsOf() -> [String] {
        var chips: [String] = []
        if event.isOrganizer == true { chips.append("我发起的") }
        if joined { chips.append("已参与") }
        if event.allowQuit == 0 { chips.append("不可退出") }
        if event.hasGroup == true { chips.append("有群聊") }
        return chips
    }

    private var infoSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.crimsonHot)
                Text(event.eventTime ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer().frame(width: 12)
                Image(systemName: "mappin")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.crimsonHot)
                Text(event.location ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.gold)
                Text("\(event.organizerName ?? "神秘人") 主办")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer().frame(width: 8)
                Image(systemName: "person.2")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                Text("\(event.currentCount ?? 0)/\(event.participantLimit ?? 0) 人")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 10)

                // 报名按钮：自己发起的、已开始且未报名的，不渲染
                if event.isOrganizer != true, !(started && !joined) {
                    Text(joined ? "已报名" : (full ? "已满员" : "报名入局"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(joined ? Color.white.opacity(0.55) : full ? Color.white.opacity(0.25) : Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(buttonBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(joined ? Noir.hairlineGold : .clear, lineWidth: 1))
                }
            }
        }
        .padding(14)
    }

    private var buttonBackground: some ShapeStyle {
        if joined || full {
            return AnyShapeStyle(Color.white.opacity(0.04))
        }
        return AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// 组局是否已开始（eventTime 早于当前时间）；解析失败回退 false
    static func isEventStarted(_ eventTime: String?) -> Bool {
        guard let eventTime, !eventTime.isEmpty else { return false }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            if let date = f.date(from: String(eventTime.prefix(format.count > eventTime.count ? eventTime.count : format.count))) {
                return date.timeIntervalSince1970 <= Date().timeIntervalSince1970
            }
        }
        return false
    }
}

// MARK: - ViewModel（对齐安卓 GroupEventListViewModel：每 tab 数据独立）

@MainActor
final class GroupEventListViewModel: ObservableObject {

    struct EventFeed {
        var events: [GroupEventInfo] = []
        var isLoading = false
        var isRefreshing = false
        var isLoadingMore = false
        var hasMore = true
        var page = 1
        var loaded = false
    }

    @Published var tab = "hot"
    @Published var feeds: [String: EventFeed] = [:]
    @Published var error: String?

    private var didSetup = false

    func setup(tab: String) {
        guard !didSetup else { return }
        didSetup = true
        self.tab = tab
        ensureLoaded(tab)
    }

    func switchTab(_ tab: String) {
        guard tab != self.tab else { return }
        self.tab = tab
        ensureLoaded(tab)
    }

    private func ensureLoaded(_ tab: String) {
        let feed = feeds[tab]
        if feed != nil, feed!.loaded || feed!.isLoading { return }
        load(tab, refresh: true)
    }

    func refresh() { load(tab, refresh: true) }

    func loadMore() {
        guard let feed = feeds[tab], !feed.isLoadingMore, !feed.isRefreshing, feed.hasMore else { return }
        load(tab, refresh: false)
    }

    private func load(_ tab: String, refresh: Bool) {
        var feed = feeds[tab] ?? EventFeed()
        let page = refresh ? 1 : feed.page + 1
        feed.isLoading = refresh && feed.events.isEmpty
        feed.isRefreshing = refresh
        feed.isLoadingMore = !refresh
        feed.page = page
        feeds[tab] = feed

        Task {
            do {
                let result = try await GroupEventAPI.list(pageNo: page, tab: tab)
                let list = result.list ?? []
                var f = feeds[tab] ?? EventFeed()
                f.events = refresh ? list : f.events + list
                f.hasMore = list.count >= 20
                f.isLoading = false
                f.isRefreshing = false
                f.isLoadingMore = false
                f.loaded = true
                feeds[tab] = f
            } catch {
                var f = feeds[tab] ?? EventFeed()
                f.isLoading = false
                f.isRefreshing = false
                f.isLoadingMore = false
                feeds[tab] = f
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
