import SwiftUI

/// 广场 — 暗夜奢华风（对齐安卓 SquareScreen.kt）
/// 结构：头部（标题+搜索胶囊+分类 tab+鎏金发丝线）→ 双列瀑布流 → 同城提示条
/// v1 范围：浏览/切 tab/分页/下拉刷新/同城定位；帖子详情与点赞评论后续迁移
struct SquareView: View {

    @StateObject private var vm = SquareViewModel()
    @State private var toast: String?

    private static let tabs: [(key: String, label: String)] = [
        ("recommend", "推荐"), ("newest", "最新"), ("nearby", "同城"), ("follow", "关注"),
    ]

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if vm.tab == "nearby" && vm.nearbyCityCode == nil {
                    nearbyGate
                } else {
                    feedView
                }
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
                .onTapGesture { showToast("搜索功能敬请期待") }
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

    // MARK: - 同城定位引导态

    private var nearbyGate: some View {
        VStack(spacing: 0) {
            Spacer()
            if vm.nearbyLocating {
                ProgressView()
                    .tint(Noir.crimson)
                    .scaleEffect(1.2)
                Spacer().frame(height: 14)
                Text("正在定位当前城市…")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.textDim)
            } else {
                Image(systemName: "mappin")
                    .font(.system(size: 34))
                    .foregroundStyle(Noir.gold)
                Spacer().frame(height: 14)
                Text(vm.nearbyDenied ? "定位失败或未授权，再试一次？" : "开启定位，发现同城同好")
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.ivory)
                Spacer().frame(height: 6)
                Text("仅使用城市级位置，不会暴露精确坐标")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer().frame(height: 20)
                Button { vm.locateNearby() } label: {
                    Text(vm.nearbyDenied ? "重新定位" : "开启定位")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 瀑布流

    private var feedView: some View {
        let feed = vm.currentFeed
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
                } else {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { vm.loadMore(vm.tab) }
                }
            }
        }
        .refreshable { vm.refresh(vm.tab) }
    }

    /// 双列瀑布流（按估算高度分配到较短列；列宽写死，图片无权撑爆布局）
    private func waterfall(_ posts: [PostInfo]) -> some View {
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
                ForEach(col0) { PostCard(post: $0, width: colW, onTap: { showToast("帖子详情敬请期待") }) }
            }
            LazyVStack(spacing: 10) {
                ForEach(col1) { PostCard(post: $0, width: colW, onTap: { showToast("帖子详情敬请期待") }) }
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
            Text(vm.tab == "nearby"
                 ? "「\(vm.nearbyCityName ?? "同城")」还没有帖子，来发第一条吧"
                 : "暂无动态，来发布第一条吧")
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
    let onTap: () -> Void

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
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Noir.noir3
                        }
                    }
                    .frame(width: width, height: width / aspect)
                    .clipped()
                    .blur(radius: post.isPaidLocked ? 12 : 0)
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

            // 底部行：头像 + 昵称/等级
            HStack(spacing: 10) {
                AsyncImage(url: webImageURL(post.avatar)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Noir.gold.opacity(0.4))
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(post.nickname ?? "用户\(post.userId ?? 0)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if let vip = post.vipLevel {
                        let c = Noir.tierColor(post.vipLevelColor)
                        HStack(spacing: 3) {
                            Image(systemName: "crown")
                                .font(.system(size: 9))
                            Text("\(vip) · Lv.\(post.levelInTier ?? 1)")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
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
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private static func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

#Preview {
    SquareView()
}
