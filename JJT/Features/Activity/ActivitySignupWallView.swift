import SwiftUI

// MARK: - 穿搭墙（对齐安卓 ActivitySignupWallScreen）
// 双列瀑布流 = 全部审核通过者 + 本人待审置顶（mine 标记）；点赞乐观更新 + 服务端幂等；
// 标题/装饰/主题色按 ActivityTheme 令牌注入，代码不写死活动皮肤。

/// 会员段位胶囊（皇冠 + 「段位 · Lv.N」，Noir.tierColor 容错解析；单行不换行）
struct ActivityVipChip: View {
    let vipLevel: String?
    let vipLevelColor: String?
    let levelInTier: Int?
    var fontSize: CGFloat = 8

    var body: some View {
        if let vipLevel, !vipLevel.isEmpty {
            HStack(spacing: 2) {
                Image(systemName: "crown.fill")
                    .font(.system(size: fontSize * 0.95))
                    .foregroundStyle(tier)
                Text("\(vipLevel) · Lv.\(levelInTier ?? 1)")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(tier)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x10 / 255).opacity(0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tier.opacity(0.55), lineWidth: 1))
        }
    }

    private var tier: Color { Noir.tierColor(vipLevelColor) }
}

// MARK: - 墙数据模型

@MainActor
final class ActivitySignupWallModel: ObservableObject {
    @Published var loading = true
    @Published var activity: ActivityInfo?
    @Published var items: [WallItem] = []
    @Published var hasMore = false
    /// 本地点赞乐观态：signupId → (liked, likes)
    @Published var likedOverrides: [Int64: (Bool, Int64)] = [:]

    private var page = 1
    private let pageSize = 20

    func load(activityId: Int64) async {
        do {
            let detail = try await ActivityAPI.get(id: activityId)
            let wall = try await ActivityAPI.signupWall(id: activityId, pageNo: 1, pageSize: pageSize)
            activity = detail
            items = wall.list ?? []
            page = 1
            hasMore = (wall.list?.count ?? 0) >= pageSize
            likedOverrides = [:]
        } catch {
            jjtShowToast(error.localizedDescription)
        }
        loading = false
    }

    /// 返回墙时静默刷新点赞态（与详情页计数同步），不打断浏览；深翻页时不重置已加载列表
    func refreshLikesSilently(activityId: Int64) async {
        guard !loading, page == 1 else { return }
        guard let wall = try? await ActivityAPI.signupWall(id: activityId, pageNo: 1, pageSize: pageSize) else { return }
        items = wall.list ?? []
        likedOverrides = [:]
    }

    func loadMore(activityId: Int64) async {
        guard !loading, hasMore else { return }
        do {
            let wall = try await ActivityAPI.signupWall(id: activityId, pageNo: page + 1, pageSize: pageSize)
            let list = wall.list ?? []
            items += list
            page += 1
            hasMore = list.count >= pageSize
        } catch {
            // 翻页失败静默（下拉重试即可）
        }
    }

    /// 点赞：乐观更新 + 服务端幂等；已点赞的条目本地互斥（不重复计数），失败回滚乐观态
    func like(_ item: WallItem) async {
        let (liked, likes) = display(item)
        if liked { return }
        likedOverrides[item.id] = (true, likes + 1)
        do {
            try await ActivityAPI.signupLike(signupId: item.id)
        } catch {
            likedOverrides.removeValue(forKey: item.id)
            jjtShowToast(error.localizedDescription)
        }
    }

    /// 点赞显示态：本地乐观覆盖优先（连点不错乱）
    func display(_ item: WallItem) -> (Bool, Int64) {
        likedOverrides[item.id] ?? (item.liked == true, item.likes ?? 0)
    }
}

// MARK: - 墙页

struct ActivitySignupWallView: View {
    let activityId: Int64
    var onBack: (() -> Void)? = nil
    /// 「去报名/我的报名」→ 返回活动页（报名入口在活动页三态区）
    var onJoin: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ActivitySignupWallModel()
    @State private var detailTarget: WallDetailTarget?

    private var theme: ActivityTheme { parseActivityTheme(model.activity?.theme) }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            // 背景装饰（theme.deco，缺省无）
            if !theme.deco.isEmpty {
                Text(theme.deco)
                    .font(.system(size: 90))
                    .foregroundStyle(.white.opacity(0.05))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 80)
                    .allowsHitTesting(false)
                Text(theme.deco)
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.04))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar
                infoStrip
                if model.loading {
                    Spacer()
                    ProgressView().tint(theme.accent)
                    Spacer()
                } else if model.items.isEmpty {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("还没有人晒出穿搭")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("第一个报名，登上穿搭墙吧")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Spacer()
                } else {
                    grid
                }
            }
        }
        .task { await model.load(activityId: activityId) }
        .fullScreenCover(item: $detailTarget) { target in
            ActivitySignupDetailView(signupId: target.id, activityId: activityId)
        }
        .onChange(of: detailTarget) { _, new in
            // 从详情页返回时静默刷新点赞态（对齐安卓 ON_RESUME）
            if new == nil {
                Task { await model.refreshLikesSilently(activityId: activityId) }
            }
        }
        .jjtPageGestures()
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            VStack(spacing: 1) {
                Text(theme.resolvedWallTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Noir.ivory)
                Text(theme.wallTitleEn)
                    .font(.system(size: 8, design: .serif))
                    .italic()
                    .tracking(3)
                    .foregroundStyle(theme.accent.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            Button(action: onJoin) {
                Text(joinLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.accent.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var joinLabel: String {
        if let my = model.activity?.mySignup, my.status != SignupStatus.rejected { return "我的报名" }
        return "去报名"
    }

    /// 说明条：本墙仅展示已通过审核的会员穿搭（v74 原型；装饰字符按主题令牌）
    private var infoStrip: some View {
        Text((theme.deco.isEmpty ? "" : theme.deco + " ") + "本墙仅展示报名成功并通过审核的会员穿搭")
            .font(.system(size: 9))
            .foregroundStyle(theme.accent.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(0.07))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(theme.accent.opacity(0.25), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    // MARK: 双列瀑布流

    private var grid: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(columns.left, id: \.item.id) { entry in
                        card(entry)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(columns.right, id: \.item.id) { entry in
                        card(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)

            Text("—— \(model.activity?.name ?? "") · 穿搭墙 ——")
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.vertical, 16)
        }
    }

    private struct IndexedItem: Identifiable {
        let index: Int
        let item: WallItem
        var id: Int64 { item.id }
    }

    /// 双列分配：按估算高度把每张卡放进较矮的一列（近似安卓 staggered grid）
    private var columns: (left: [IndexedItem], right: [IndexedItem]) {
        var left: [IndexedItem] = []
        var right: [IndexedItem] = []
        var lh: CGFloat = 0
        var rh: CGFloat = 0
        for (i, item) in model.items.enumerated() {
            let h = 1 / cardRatio(item)
            if lh <= rh {
                left.append(IndexedItem(index: i, item: item))
                lh += h
            } else {
                right.append(IndexedItem(index: i, item: item))
                rh += h
            }
        }
        return (left, right)
    }

    private func card(_ entry: IndexedItem) -> some View {
        WallCardView(
            item: entry.item,
            theme: theme,
            ratio: cardRatio(entry.item),
            liked: model.display(entry.item),
            onLike: { Task { await model.like(entry.item) } },
            onTap: { detailTarget = WallDetailTarget(id: entry.item.id) }
        )
        .onAppear {
            if entry.index >= model.items.count - 4 {
                Task { await model.loadMore(activityId: activityId) }
            }
        }
    }

    /// 瀑布流错落高度：与安卓同口径（id%3）
    private func cardRatio(_ item: WallItem) -> CGFloat {
        if item.id % 3 == 0 { return 1.25 }
        if item.id % 3 == 1 { return 0.8 }
        return 1
    }
}

/// fullScreenCover(item:) 目标（Int64 非 Identifiable，包一层）
struct WallDetailTarget: Identifiable, Equatable {
    let id: Int64
}

// MARK: - 墙卡

private struct WallCardView: View {
    let item: WallItem
    let theme: ActivityTheme
    let ratio: CGFloat
    let liked: (Bool, Int64)
    let onLike: () -> Void
    let onTap: () -> Void

    private var isMine: Bool { item.mine == true }

    var body: some View {
        ZStack {
            // 图片填满整卡，信息与点赞全部叠加在图上
            WebImage(url: webImageURL(item.img), contentMode: .fill) { Color.white.opacity(0.05) }
            // 底部渐变（保信息可读）
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
            }
            // 信息行：头像（带框）+ 昵称 + 造型名（end 66 避让点赞胶囊）
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 8) {
                    AppAvatar(
                        url: item.avatar,
                        size: 28,
                        frameURL: item.avatarFrame,
                        frameScale: CGFloat(item.avatarFrameScale ?? 1.2)
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.nickname ?? "")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let look = item.look, !look.isEmpty {
                            Text("「\(look)」")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .padding(.trailing, 66)
                .padding(.bottom, 10)
            }
            // 点赞：右下角压暗胶囊（叠加图上）
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onLike) {
                        HStack(spacing: 4) {
                            Image(systemName: liked.0 ? "heart.fill" : "heart")
                                .font(.system(size: 11))
                                .foregroundStyle(liked.0 ? theme.accent : .white.opacity(0.75))
                            Text("\(liked.1)")
                                .font(.system(size: 10))
                                .foregroundStyle(liked.0 ? theme.accent : .white.opacity(0.75))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
                }
            }
            // 角标：我的报名 / 审核中
            VStack {
                HStack {
                    Spacer()
                    if isMine {
                        WallBadgeView(text: "我的报名",
                                      gradient: LinearGradient(colors: [theme.accent, theme.accent2],
                                                                startPoint: .leading, endPoint: .trailing))
                    } else if item.pending == true {
                        WallBadgeView(text: "审核中",
                                      gradient: LinearGradient(colors: [Noir.crimsonDeep, Noir.crimson],
                                                                startPoint: .leading, endPoint: .trailing))
                    }
                }
                Spacer()
            }
            .padding(8)
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isMine ? theme.accent.opacity(0.7) : Color.white.opacity(0.1),
                        lineWidth: isMine ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(onTap)
    }
}

private struct WallBadgeView: View {
    let text: String
    let gradient: LinearGradient

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(gradient)
            .clipShape(Capsule())
    }
}
