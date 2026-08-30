import SwiftUI

/// 广场 — 暗夜奢华风（对齐安卓 SquareScreen.kt）
/// 结构：头部（标题+搜索胶囊+分类 tab+鎏金发丝线）→ 双列瀑布流 → 同城提示条
/// 三 tab：推荐/最新/关注（同城不单设 tab，距离作为推荐算法加分项，CONTEXT.md）；
/// 卡片菜单：不感兴趣（二次确认硬隐藏）/ 举报（预设原因+补充说明）；卡片进可视区记曝光
struct SquareView: View {

    @StateObject private var vm = SquareViewModel()
    @State private var toast: String?
    @State private var detailPostId: Int64?
    @State private var videoFeedPostId: Int64?
    /// 卡片菜单「不感兴趣」：待二次确认的帖子
    @State private var postToHide: PostInfo?
    /// 卡片菜单「举报」：待填原因提交的帖子
    @State private var postToReport: PostInfo?
    /// 彩蛋「逆行之鳞」：逛到底部后重新回到顶部（对齐安卓 reachedBottom）
    @State private var reachedBottom = false

    private static let tabs: [(key: String, label: String)] = [
        ("recommend", "推荐"), ("newest", "最新"), ("follow", "关注"),
    ]

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                // 三 tab 分页容器：左右滑跟手切换（对齐安卓 HorizontalPager）
                TabView(selection: $vm.tab) {
                    ForEach(Self.tabs, id: \.key) { t in
                        feedView(t.key).tag(t.key)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Noir.noir3.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 100)
                        .transition(.opacity)
                }
            }
        }
        .onAppear { vm.switchTab(vm.tab) }
        // 分页滑动直接改 vm.tab（绑定），这里补触发数据加载
        .onChange(of: vm.tab) { _, new in vm.switchTab(new) }
        // 已授权定位时解析浏览者坐标传入推荐流（同城加分；未授权静默降级）
        .task {
            if let c = await CityLocator.shared.currentCoordinate() {
                vm.setViewerLocation(latitude: c.latitude, longitude: c.longitude)
            }
        }
        // 退出广场时把未满批的曝光补报掉
        .onDisappear { vm.flushImpressions() }
        // 发帖成功 → 刷新当前 tab
        .onReceive(NotificationCenter.default.publisher(for: .jjtPostCreated)) { _ in
            vm.refresh(vm.tab)
        }
        // 「不感兴趣」二次确认：确认后上报并从本地列表移除（服务端已对本人硬隐藏，无撤销）
        .alert("不感兴趣", isPresented: Binding(
            get: { postToHide != nil },
            set: { if !$0 { postToHide = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("不再推荐", role: .destructive) {
                if let post = postToHide { vm.notInterested(postId: post.id) }
            }
        } message: {
            Text("确认后将减少此类内容推荐")
        }
        // 「举报」提交弹层：预设原因单选 + 可选补充说明；提交后进平台待审（不移除帖子，接口幂等）
        .sheet(item: $postToReport) { post in
            ReportSheet { reason, detail in
                vm.report(postId: post.id, reason: reason, detail: detail)
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: Binding(
            get: { detailPostId != nil },
            set: { if !$0 { detailPostId = nil } }
        )) {
            if let id = detailPostId {
                PostDetailView(postId: id)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoFeedPostId != nil },
            set: { if !$0 { videoFeedPostId = nil } }
        )) {
            if let id = videoFeedPostId {
                VideoFeedView(initialPostId: id, tab: vm.tab)
            }
        }
    }

    /// 卡片点击：视频帖进竖滑视频流，普通帖进详情（对齐安卓）
    private func openPost(_ post: PostInfo) {
        if post.mediaType == "video" {
            videoFeedPostId = post.id
        } else {
            detailPostId = post.id
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: - 头部：标题 + 搜索胶囊 + 分类 tab + 鎏金发丝线

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("广场")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .tracking(3.6)
                    .foregroundStyle(Noir.goldText)
                // 搜索胶囊（对标设计稿，功能待后端就绪）
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("搜索暗夜同好 / 穿搭 / 派对")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                .onTapGesture {
                    // 彩蛋「失物招领」：在广场使用一次搜索（对齐安卓）
                    EggTrigger.report("search")
                    showToast("搜索功能敬请期待")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 分类 tab（绯红下划线渐变）
            HStack(spacing: 20) {
                ForEach(Self.tabs, id: \.key) { t in
                    let selected = vm.tab == t.key
                    VStack(spacing: 4) {
                        Text(t.label)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Noir.crimsonHot : Color.white.opacity(0.4))
                        Capsule()
                            .fill(selected
                                  ? LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 20, height: 2.5)
                    }
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.switchTab(t.key) }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            // 鎏金发丝线
            Rectangle()
                .fill(Noir.goldLine)
                .frame(height: 1)
                .opacity(0.4)
        }
    }

    // MARK: - 瀑布流

    private func feedView(_ tab: String) -> some View {
        let feed = vm.feeds[tab] ?? SquareViewModel.TabFeed()
        return ScrollView {
            if feed.isLoading {
                ProgressView()
                    .tint(Noir.crimson)
                    .scaleEffect(1.4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
            } else if feed.posts.isEmpty {
                emptyHint
            } else {
                waterfall(feed.posts)

                // 同城提示条：取首条带定位的帖子
                if let location = feed.posts.first(where: { !($0.location ?? "").isEmpty })?.location {
                    cityHint(location)
                }

                // 加载更多哨兵 / 到底提示
                if feed.isLoadingMore {
                    ProgressView().tint(Noir.crimson).frame(maxWidth: .infinity).padding(16)
                } else if !feed.hasMore {
                    Text("NO MORE · 到底啦")
                        .font(.system(size: 10, design: .serif).italic())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .onAppear { reachedBottom = true }
                } else {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { vm.loadMore(tab) }
                }
            }
        }
        .refreshable { vm.refresh(tab) }
    }

    /// 卡片进入可视区：曝光埋点 + 彩蛋「逆行之鳞」（逛到底部后首卡再次入镜视为回到顶部）
    private func cardVisible(_ post: PostInfo, firstId: Int64?) {
        vm.onPostVisible(post.id)
        if reachedBottom, post.id == firstId {
            reachedBottom = false
            EggTrigger.report("scroll-top")
        }
    }

    /// 双列瀑布流（按估算高度分配到较短列；列宽写死，图片无权撑爆布局）
    private func waterfall(_ posts: [PostInfo]) -> some View {
        let firstId = posts.first?.id
        let colW = (JJTMetrics.screenWidth - 20 - 10) / 2
        var col0: [PostInfo] = []
        var col1: [PostInfo] = []
        var h0: CGFloat = 0
        var h1: CGFloat = 0
        for p in posts {
            let aspect: CGFloat = p.id % 2 == 0 ? 0.75 : 1.0
            let est = colW / aspect + 100
            if h0 <= h1 { col0.append(p); h0 += est + 10 } else { col1.append(p); h1 += est + 10 }
        }
        return HStack(alignment: .top, spacing: 10) {
            LazyVStack(spacing: 10) {
                ForEach(col0) {
                    PostCard(post: $0, width: colW, onTap: openPost,
                             onVisible: { cardVisible($0, firstId: firstId) },
                             onNotInterested: { postToHide = $0 },
                             onReport: { postToReport = $0 })
                }
            }
            LazyVStack(spacing: 10) {
                ForEach(col1) {
                    PostCard(post: $0, width: colW, onTap: openPost,
                             onVisible: { cardVisible($0, firstId: firstId) },
                             onNotInterested: { postToHide = $0 },
                             onReport: { postToReport = $0 })
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Text("NO MOMENTS YET")
                .font(.system(size: 10, design: .serif).italic())
                .tracking(2)
                .foregroundStyle(Noir.gold.opacity(0.6))
            Text("暂无动态，来发布第一条吧")
                .font(.system(size: 13))
                .foregroundStyle(Noir.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func cityHint(_ location: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin")
                .font(.system(size: 13))
                .foregroundStyle(Noir.crimsonHot)
            Text("\(location) · 同城暗夜派对等你赴约")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

// MARK: - 瀑布流卡片（对齐安卓 PostCard）

private struct PostCard: View {
    let post: PostInfo
    let width: CGFloat
    let onTap: (PostInfo) -> Void
    /// 卡片进入可视区回调（曝光埋点，对齐安卓 onPostsVisible）
    var onVisible: ((PostInfo) -> Void)? = nil
    /// 卡片菜单「不感兴趣」回调（空则不显示菜单项，对齐安卓可空参）
    var onNotInterested: ((PostInfo) -> Void)? = nil
    /// 卡片菜单「举报」回调
    var onReport: ((PostInfo) -> Void)? = nil

    private var coverURL: URL? {
        if post.mediaType == "video" { return webImageURL(post.videoCover) }
        return webImageURL(post.images?.first)
    }

    /// 封面宽高比：3:4 与 1:1 交错（对齐安卓按 id 奇偶）
    private var aspect: CGFloat { post.id % 2 == 0 ? 0.75 : 1.0 }

    var body: some View {
        VStack(spacing: 0) {
            // 封面
            ZStack {
                if let url = coverURL {
                    // WebImage：带内存缓存 + 占位底座，滚动复用不丢图（AsyncImage 在瀑布流快速滚动会不出图）
                    WebImage(url: url) { Noir.noir3 }
                        .frame(width: width, height: width / aspect)
                        .blur(radius: post.isPaidLocked ? 12 : 0)
                } else if !(post.content ?? "").isEmpty {
                    // 纯文字帖：媒体区展示正文摘要（对齐安卓 PostCard）
                    Noir.noir3
                        .frame(width: width, height: width / aspect)
                        .overlay(alignment: .topLeading) {
                            Text(post.content ?? "")
                                .font(.system(size: 12))
                                .lineSpacing(6)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(7)
                                .padding(12)
                        }
                } else {
                    Noir.noir3
                        .frame(width: width, height: width / aspect)
                        .overlay(Text("暂无图片").font(.system(size: 11)).foregroundStyle(Noir.textFaint))
                }

                // 底部暗渐变
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 56)
                }
                .allowsHitTesting(false)

                // 视频角标
                if post.mediaType == "video" {
                    VStack {
                        Spacer()
                        HStack {
                            HStack(spacing: 2) {
                                Image(systemName: "play.fill").font(.system(size: 10))
                                Text("视频").font(.system(size: 9))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                            Spacer()
                        }
                    }
                }

                // 审核中（仅作者本人可见）
                if post.auditStatus == 0 {
                    VStack {
                        HStack {
                            Text("审核中")
                                .font(.system(size: 9))
                                .foregroundStyle(Noir.gold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Noir.gold.opacity(0.6), lineWidth: 1))
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // 付费未解锁：锁定叠加层
                if post.isPaidLocked {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Noir.goldPale)
                                Text("付费内容")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // 付费角标（鎏金胶囊）
                if (post.paidPrice ?? 0) > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text(post.unlocked == true ? "已解锁" : "付费")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing)))
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                // 右下角：阅读量 + 点赞数
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "eye").font(.system(size: 10))
                            Text(Self.formatCount(post.viewCount ?? 0)).font(.system(size: 10))
                            Spacer().frame(width: 5)
                            Image(systemName: post.liked == true ? "heart.fill" : "heart")
                                .font(.system(size: 10))
                                .foregroundStyle(post.liked == true ? Noir.crimsonHot : .white.opacity(0.85))
                            Text(Self.formatCount(post.likeCount ?? 0)).font(.system(size: 10))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: width, height: width / aspect)

            // 标题（最多两行）
            if !post.displayTitle.isEmpty {
                Text(post.displayTitle)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            // 底部行：头像（含头像框）+ 昵称/等级 + 卡片菜单（不感兴趣/举报）
            HStack(spacing: 10) {
                AppAvatar(url: post.avatar, size: 34,
                          frameURL: post.avatarFrame, frameScale: CGFloat(post.avatarFrameScale ?? 1.25))
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text(post.nickname ?? "用户\(post.userId ?? 0)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let vip = post.vipLevel {
                        let c = Noir.tierColor(post.vipLevelColor)
                        HStack(spacing: 3) {
                            Image(systemName: "crown")
                                .font(.system(size: 9))
                            Text("\(vip) · Lv.\(post.levelInTier ?? 1)")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(c)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.9))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(c.opacity(0.55), lineWidth: 1))
                    } else {
                        Text("普通兔友")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)

                // 卡片菜单（竖向三点，窄尺寸给等级徽章让位，对齐安卓 MoreVert）
                if onNotInterested != nil || onReport != nil {
                    Menu {
                        if let onNotInterested {
                            Button("不感兴趣") { onNotInterested(post) }
                        }
                        if let onReport {
                            Button("举报") { onReport(post) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(90))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 14, height: 24)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onTap(post) }
        // 卡片进入可视区 → 记一次曝光（会话级去重与凑批由 ViewModel 承担）
        .onAppear { onVisible?(post) }
    }

    private static func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - 举报弹层：预设原因单选 + 可选补充说明（提交后运营在管理端审核成立/驳回）

private struct ReportSheet: View {

    /// 举报预设原因（code 对齐服务端 ReportReasonEnum 与安卓 REPORT_REASONS）
    private static let reasons: [(code: String, label: String)] = [
        ("porn", "色情低俗"),
        ("harassment", "骚扰辱骂"),
        ("ad", "广告营销"),
        ("illegal", "违法犯罪"),
        ("other", "其他"),
    ]

    let onConfirm: (_ reason: String, _ detail: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected = Self.reasons[0].code
    @State private var detail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.textDim)
                Spacer()
                Text("举报帖子")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Button("提交") {
                    onConfirm(selected, detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail)
                    dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Noir.crimsonHot)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(Noir.goldLine).frame(height: 1).opacity(0.4)

            // 预设原因单选
            ForEach(Self.reasons, id: \.code) { r in
                let checked = selected == r.code
                HStack {
                    Text(r.label)
                        .font(.system(size: 14))
                        .foregroundStyle(Noir.ivory)
                    Spacer()
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(checked ? Noir.crimsonHot : Color.white.opacity(0.25))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { selected = r.code }
            }

            // 可选补充说明
            TextField("补充说明（选填）", text: $detail, axis: .vertical)
                .font(.system(size: 13))
                .foregroundStyle(Noir.ivory)
                .lineLimit(3...)
                .padding(12)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.hairlineGold, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Spacer()
        }
        .padding(.top, 8)
        .background(Noir.noir.ignoresSafeArea())
    }
}

#Preview {
    SquareView()
}
