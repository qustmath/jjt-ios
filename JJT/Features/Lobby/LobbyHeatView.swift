import SwiftUI

/// 门店热力榜（对齐安卓 LobbyHeatScreen；数据与计分在后端：送礼 1 兔币 = 1 热力、拼桌被通过 = 50）。
///
/// 三 tab 同构：总榜 / 周榜（周一 0 点重置）/ 实时榜（当日），前三领奖台（第 2 | 第 1 | 第 3），
/// 其余按名次列表；点人进资料卡（复用票 19 组件）。
///
/// 榜单是跨会话投影：榜上的人不一定正在大厅（没有 table/seat 上下文），故资料卡按「大厅常客」呈现，
/// 且不带举报入口（举报以公屏消息 msgId 为凭据，榜单没有消息可举报）。
struct LobbyHeatView: View {

    let storeId: Int64
    let storeName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var tab: HeatTab = .total
    @State private var board: LobbyHeatBoard?
    @State private var loading = true
    @State private var error: String?
    @State private var cardUser: LobbyHeatItem?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var giftNav: NightLobbyView.LobbyNavTarget?
    @State private var chatNav: NightLobbyView.LobbyNavTarget?

    /// 榜单类型（后端 /heat/board?type=）
    enum HeatTab: String, CaseIterable {
        case total, week, realtime

        var label: String {
            switch self {
            case .total: return "总榜"
            case .week: return "周榜"
            case .realtime: return "实时榜"
            }
        }

        var hint: String {
            switch self {
            case .total: return "历史累计"
            case .week: return "周一重置"
            case .realtime: return "当日"
            }
        }
    }

    var body: some View {
        ZStack {
            LobbyColors.bg.ignoresSafeArea()
            // 顶部酒红晕染（无门店封面：榜单页不依赖门店素材）
            LinearGradient(
                colors: [Color(red: 0xC4/255, green: 0x12/255, blue: 0x30/255).opacity(0.35), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                tabs

                let items = board?.list ?? []
                if loading && items.isEmpty {
                    ZStack {
                        ProgressView().tint(LobbyColors.gold)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if error != nil && items.isEmpty {
                    ZStack {
                        LobbyLoadFailed(message: error ?? "", onRetry: { load() })
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    VStack(spacing: 0) {
                        Text("本店暂无热力记录 · 送礼、拼桌通过即可上榜 ✨")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        myRankFooter
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        let topThree = Array(items.prefix(3))
                        let rest = items.dropFirst(3)
                        VStack(spacing: 8) {
                            Podium(items: topThree) { cardUser = $0 }
                            Spacer().frame(height: 18)
                            ForEach(rest) { row in
                                HeatRow(item: row) { cardUser = row }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }
                    myRankFooter
                }
            }

            if let t = toast { LobbyToastView(text: t) }

            // 资料卡（榜单无消息上下文，不带举报入口）
            if let u = cardUser {
                LobbyUserCard(
                    userId: u.userId ?? -1,
                    nickname: u.nickname ?? "大厅用户",
                    avatar: u.avatar,
                    tableNo: nil,
                    seated: false,
                    isSelf: (u.userId ?? -1) == (TokenManager.shared.userId ?? -2),
                    stateText: "大厅常客 · 第 \(u.rank ?? 0) 名 · \(u.score ?? 0) 热力",
                    onDismiss: { cardUser = nil },
                    onGift: {
                        cardUser = nil
                        giftNav = .init(userId: u.userId ?? -1, nickname: u.nickname)
                    },
                    onChat: {
                        cardUser = nil
                        chatNav = .init(userId: u.userId ?? -1, nickname: u.nickname)
                    },
                    onFollow: {
                        cardUser = nil
                        guard let uid = u.userId else { return }
                        Task {
                            do {
                                _ = try await FollowAPI.friendApply(userId: uid)
                                showToast("好友申请已发送")
                            } catch {
                                showToast(error.localizedDescription)
                            }
                        }
                    },
                    onInviteShare: {
                        cardUser = nil
                        showToast("邀请拼桌请到门店大厅「我的桌」里发起")
                    },
                    onDrink: {
                        cardUser = nil
                        giftNav = .init(userId: u.userId ?? -1, nickname: u.nickname)
                    },
                    onReport: nil
                )
            }
        }
        .onChange(of: tab) { _, _ in
            // 切 tab 先清榜：避免「实时榜」标签下短暂显示上一 tab 的名单
            board = nil
            load()
        }
        .task { load() }
        .fullScreenCover(item: $giftNav) { nav in
            GiftCenterView(receiverId: nav.userId, receiverName: nav.nickname)
        }
        .fullScreenCover(item: $chatNav) { nav in
            ChatView(peerId: String(nav.userId), isGroup: false, title: nav.nickname)
        }
    }

    private func load() {
        loading = true
        Task {
            do {
                board = try await LobbyAPI.heatBoard(storeId: storeId, type: tab.rawValue, limit: 50)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toast = msg
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.05))
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(storeName ?? "门店") · 热力榜")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
                Text("送礼 1 兔币 = 1 热力 · 拼桌被通过 +50（平台可配）")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 17))
                .foregroundStyle(LobbyColors.goldLight)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 三 tab

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(HeatTab.allCases, id: \.rawValue) { t in
                VStack(spacing: 1) {
                    Text(t.label)
                        .font(.system(size: 11.5, weight: t == tab ? .semibold : .regular))
                        .foregroundStyle(t == tab ? .white : .white.opacity(0.45))
                    Text(t.hint)
                        .font(.system(size: 7.5))
                        .foregroundStyle(t == tab ? .white.opacity(0.65) : .white.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if t == tab {
                        Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                    }
                }
                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture { tab = t }
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.4))
        .overlay(Capsule().stroke(Noir.gold.opacity(0.25), lineWidth: 1))
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - 我的排名页脚（榜上/未上榜都给一句）

    @ViewBuilder
    private var myRankFooter: some View {
        let mine = board?.myRank
        HStack {
            Text("我的排名")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(mine?.ranked == true ? "第 \(mine?.rank ?? 0) 名 · \(mine?.score ?? 0) 热力" : "未上榜 · 送礼或拼桌即可进榜")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(mine?.ranked == true ? LobbyColors.goldLight : .white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0x14/255, green: 0x10/255, blue: 0x0A/255).opacity(0.8))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

/// 前三领奖台：第 2 | 第 1 | 第 3（第 1 更高更亮），缺失的位置不占位
private struct Podium: View {
    let items: [LobbyHeatItem]
    let onClick: (LobbyHeatItem) -> Void

    var body: some View {
        if !items.isEmpty {
            let byRank = items.sorted { ($0.rank ?? 99) < ($1.rank ?? 99) }
            HStack(alignment: .bottom) {
                podiumColumn(byRank.count > 1 ? byRank[1] : nil)
                podiumColumn(byRank.first)
                podiumColumn(byRank.count > 2 ? byRank[2] : nil)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func podiumColumn(_ item: LobbyHeatItem?) -> some View {
        if let item {
            let first = item.rank == 1
            VStack(spacing: 0) {
                if first {
                    Text("👑").font(.system(size: 14))
                    Spacer().frame(height: 2)
                }
                LobbyMemberAvatar(userId: item.userId, fallbackAvatar: item.avatar, size: first ? 62 : 50, ringWhenNoFrame: true, ringColor: first ? LobbyColors.goldLight : LobbyColors.gold.opacity(0.5))
                Spacer().frame(height: 6)
                Text(item.nickname ?? "")
                    .font(.system(size: first ? 12 : 11, weight: first ? .bold : .regular))
                    .foregroundStyle(first ? LobbyColors.goldPale : LobbyColors.ivory)
                    .lineLimit(1)
                    .frame(width: first ? 84 : 76)
                Spacer().frame(height: 2)
                Text("\(item.score ?? 0) 热力")
                    .font(.system(size: 10))
                    .foregroundStyle(first ? LobbyColors.goldLight : .white.opacity(0.5))
                Spacer().frame(height: 6)
                // 台阶高度区分名次
                Text("\(item.rank ?? 0)")
                    .font(.system(size: first ? 18 : 15, weight: .bold))
                    .foregroundStyle(first ? LobbyColors.goldPale : LobbyColors.ivory.opacity(0.8))
                    .frame(width: first ? 84 : 74, height: first ? 34 : 22)
                    .background(
                        LinearGradient(
                            colors: first
                                ? [LobbyColors.gold.opacity(0.5), .clear]
                                : [LobbyColors.crimson.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { onClick(item) }
        } else {
            // 缺位占位，保持 2-1-3 排布
            Color.clear.frame(width: 90, height: 1)
        }
    }
}

/// 第 4 名起的列表行
private struct HeatRow: View {
    let item: LobbyHeatItem
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(item.rank ?? 0)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 26, alignment: .leading)
            LobbyMemberAvatar(userId: item.userId, fallbackAvatar: item.avatar, size: 34, ringWhenNoFrame: true)
            Text(item.nickname ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(LobbyColors.ivory)
                .lineLimit(1)
            Spacer()
            Text("\(item.score ?? 0) 热力")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(LobbyColors.goldLight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
    }
}
