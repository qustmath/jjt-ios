import SwiftUI

/// 礼物面板上下文（对齐安卓 LobbyGiftContext）：一次开面板所需的全部参数
struct LobbyGiftContext: Identifiable {
    let tableId: Int64
    var tableNo: String?
    /// `lobby` 三级广播 / `lobby_dnd` 勿扰送礼档
    var scene: String
    var receivers: [GiftReceiver]
    var toName: String

    var id: String { "\(tableId)-\(scene)-\(toName)" }
}

/// 三级广播档（对齐安卓 GiftTier = social_gift.broadcast_scope）。
/// matches 把「未配置/未知档」并入同桌心意——与后端 normalizeScope 同口径（未知一律不扇出）。
enum LobbyGiftTier: String, CaseIterable {
    case table
    case store
    case all

    var label: String {
        switch self {
        case .table: return "同桌心意"
        case .store: return "本店广播"
        case .all: return "全门店广播"
        }
    }

    var caption: String {
        switch self {
        case .table: return "只送给本桌这位 · 不广播到公屏"
        case .store: return "特效消息播报到本店公屏 · 须达本店档门槛价"
        case .all: return "播报到全部启用门店群 + 全城聚合群 · 高价档，未达门槛会被服务端拒绝"
        }
    }

    func matches(_ scope: String?) -> Bool {
        if self == .table { return scope == nil || scope?.isEmpty == true || scope == rawValue }
        return scope == rawValue
    }
}

/// 门店大厅礼物面板（三级广播；对齐安卓 LobbyGiftSheet）。
///
/// 三级广播分组 = 服务端权威分档：每个礼物在后台配置 broadcast_scope（table/store/all），
/// 面板按它分组渲染三个 tab，用户选礼物即选定广播范围。门槛值不下发客户端，不硬编码，
/// 真实放行/拒绝由服务端判定，拒绝文案在支付密码弹窗内原样展示。
///
/// 两个场景：
/// - `scene=lobby`：三级广播送礼，接收人必填且须正入座该桌（服务端校验），面板强制先选人；
/// - `scene=lobby_dnd`：勿扰桌「送礼档」解锁，接收方由服务端定为该桌当前桌主，无需选人。
struct LobbyGiftSheet: View {

    let tableId: Int64
    let tableNo: String?
    var scene: String = "lobby"
    /// 本桌入座成员（scene=lobby 必填一位；lobby_dnd 传空——服务端定人）
    var receivers: [GiftReceiver] = []
    /// 收礼人/桌主展示名（lobby_dnd 传桌主昵称）
    var toName: String = ""
    let onClose: () -> Void
    /// 送出回调（页面刷新平面图 + 我的解锁订单）
    var onSent: (GiftItem) -> Void = { _ in }

    @StateObject private var payGuard = PayPasswordGuard()
    @State private var gifts: [GiftItem] = []
    @State private var balance: Int64?
    @State private var tier: LobbyGiftTier = .table
    @State private var sel: GiftItem?
    @State private var chosen: GiftReceiver?
    @State private var receiverRows: [GiftReceiver] = []
    @State private var combo = 0
    @State private var busy = false
    @State private var showPaySettings = false
    @State private var showRecharge = false

    /// scene=lobby 按广播档过滤；lobby_dnd（解锁送礼档）不按广播档过滤：
    /// 解锁阈值是「单价 ≥660 兔币」，与广播范围无关
    private var list: [GiftItem] {
        if scene == "lobby" {
            return gifts.filter { tier.matches($0.broadcastScope) }
        }
        return gifts
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                header

                // ── 收礼人（scene=lobby 必选：服务端要求接收人正入座该桌） ──
                if scene == "lobby" {
                    receiverSection
                    tierTabs
                }

                // ── 礼物横排（当前档位） ──
                giftRow

                // ── 已选礼物 + 赠送 ──
                sendBar
                if scene == "lobby" && chosen == nil && !receiverRows.isEmpty {
                    Text("先选一位收礼人")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 6)
                }
                Text(scene == "lobby_dnd"
                     ? "送礼达门槛即视为解锁，桌主收礼后你可在到店时入座"
                     : "广播档位由平台按礼物配置，未达档位门槛的礼物会被服务端拒绝")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: .jjtInsufficientBalance)) { _ in
            showRecharge = true
        }
        .payPasswordGuard(payGuard) { showPaySettings = true }
        .fullScreenCover(isPresented: $showPaySettings) {
            PayPasswordSettingsView()
        }
        .fullScreenCover(isPresented: $showRecharge, onDismiss: { refreshBalance() }) {
            CoinRechargeView()
        }
        // 全屏赠送动效（窗口级覆盖：sheet 内的 overlay 只有半屏）
        .onChange(of: combo) { _, newValue in
            guard newValue > 0, let gift = sel else { return }
            let c = newValue
            let g = gift
            JJTWindowOverlay.show(GiftSendOverlay(gift: g, combo: c) { JJTWindowOverlay.dismiss() })
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("赠礼 · ")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(LobbyColors.ivory)
                    Text((chosen?.name ?? toName).isEmpty ? "本桌" : (chosen?.name ?? toName))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [Noir.crimsonHot, Noir.crimson], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .lineLimit(1)
                }
                Text(scene == "lobby_dnd"
                     ? "勿扰解锁 · 送礼档（随礼申请，桌主确认后解锁）"
                     : "\(tableNo ?? "本桌") · 三级广播：只送本桌 / 本店 / 全城")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            // 余额胶囊
            HStack(spacing: 5) {
                Image(systemName: "gem")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.gold)
                Text(balance.map { "\($0)" } ?? "--")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
            Button { if !busy { onClose() } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 收礼人

    @ViewBuilder
    private var receiverSection: some View {
        if receiverRows.isEmpty {
            Text("本桌还没有人入座 · 收礼人须正在该桌就座")
                .font(.system(size: 10.5))
                .foregroundStyle(LobbyColors.goldLight.opacity(0.6))
                .padding(.top, 12)
        } else {
            Text("选收礼人（须正在本桌就座）")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(receiverRows) { r in
                        let selected = chosen?.id == r.id
                        VStack(spacing: 3) {
                            AppAvatar(url: r.avatar, size: 38)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(selected ? LobbyColors.gold : .white.opacity(0.12), lineWidth: 1.5))
                            Text(r.name)
                                .font(.system(size: 10))
                                .foregroundStyle(selected ? LobbyColors.gold : .white.opacity(0.45))
                                .lineLimit(1)
                                .frame(width: 56)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if !busy { chosen = r } }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - 三级广播档位 tab

    private var tierTabs: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(LobbyGiftTier.allCases, id: \.rawValue) { t in
                    Text(t.label)
                        .font(.system(size: 11, weight: t == tier ? .semibold : .regular))
                        .foregroundStyle(t == tier ? .white : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if t == tier {
                                Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                            }
                        }
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !busy { tier = t; combo = 0 }
                        }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.45))
            .overlay(Capsule().stroke(Noir.gold.opacity(0.25), lineWidth: 1))
            .clipShape(Capsule())

            Text(tier.caption)
                .font(.system(size: 9.5))
                .foregroundStyle(tier == .all ? LobbyColors.goldLight.opacity(0.8) : .white.opacity(0.35))
        }
        .padding(.top, 12)
    }

    // MARK: - 礼物横排

    @ViewBuilder
    private var giftRow: some View {
        if list.isEmpty {
            Text(scene == "lobby_dnd"
                 ? "平台尚未配置可解锁的礼物档（后台可配）"
                 : "「\(tier.label)」档暂无礼物 · 平台在后台按档位配置")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, 10)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list) { gift in
                        let selected = sel?.id == gift.id
                        VStack(spacing: 2) {
                            GiftIconView(
                                icon: giftDisplayIcon(gift.icon, gift.animationUrl),
                                size: 54,
                                scale: CGFloat(gift.iconScale ?? 100) / 100
                            )
                            .frame(height: 60)
                            Text(gift.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                            Text("\(gift.priceRabbit ?? 0) 兔币")
                                .font(.system(size: 10))
                                .foregroundStyle(LobbyColors.goldLight)
                        }
                        .frame(width: 66)
                        .padding(.vertical, 8)
                        .background(selected ? LobbyColors.crimson.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? LobbyColors.crimson.opacity(0.6) : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { if !busy { sel = gift } }
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - 已选礼物 + 赠送

    private var sendBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sel?.name ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(LobbyColors.ivory)
                Text(sel?.description ?? "")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer()
            Button { send() } label: {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView().tint(.white).scaleEffect(0.7)
                        Text("赠送中…")
                    } else {
                        Image(systemName: "paperplane")
                            .font(.system(size: 13))
                        Text("赠送")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background {
                    if busy {
                        Capsule().fill(Color(red: 0x5A/255, green: 0x5A/255, blue: 0x62/255))
                    } else {
                        Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                    }
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy || sel == nil || (scene == "lobby" && chosen == nil))
        }
        .padding(.top, 12)
    }

    // MARK: - 逻辑

    private func load() {
        receiverRows = receivers
        Task {
            gifts = (try? await GiftAPI.giftList()) ?? []
            // 默认落第一个有货的档：本店/全门店档未配置礼物时不至于开面板即空页
            tier = LobbyGiftTier.allCases.first { t in gifts.contains { t.matches($0.broadcastScope) } } ?? .table
            // 收礼人现拉一次（服务端按「正入座该桌」校验，抽屉里的快照可能已过期）；
            // 拉不到就沿用调用方传入的快照，由服务端最终把关
            if scene == "lobby" {
                if let live = try? await LobbyAPI.spectateTable(tableId: tableId) {
                    let me = TokenManager.shared.userId ?? -1
                    receiverRows = (live.members ?? [])
                        .filter { $0.userId != me }
                        .map { GiftReceiver(id: $0.userId, name: $0.nickname ?? "本桌用户", avatar: $0.avatar) }
                }
            }
            if sel == nil || !list.contains(where: { $0.id == sel?.id }) {
                sel = list.first
            }
        }
        refreshBalance()
    }

    private func refreshBalance() {
        Task {
            balance = try? await WalletAPI.getWallet("rabbit_coin").availableAmount
        }
    }

    private func send() {
        guard let gift = sel, !busy else { return }
        // 只有一位候选时自动选中：从「资料卡 → 送礼」这类单人入口进来不需要再点一次
        if scene == "lobby", chosen == nil, receiverRows.count == 1 {
            chosen = receiverRows.first
        }
        guard scene != "lobby" || chosen != nil else { return }
        let price = Int64(gift.priceRabbit ?? 0)
        if let balance, balance < price {
            // 兔币不足 → 充值引导（与礼物中心同路径）
            showRecharge = true
            return
        }
        payGuard.require { pwd in
            busy = true
            defer { busy = false }
            // lobby_dnd 由服务端定为该桌桌主，receiverId 传 nil 即可（客户端值被忽略）
            _ = try await GiftAPI.send(SendGiftReq(
                giftId: gift.id,
                receiverId: scene == "lobby" ? chosen?.id : nil,
                quantity: 1,
                scene: scene,
                sceneId: tableId,
                payPassword: pwd))
            balance = (balance ?? 0) - price
            combo += 1
            // 彩蛋「借火的人」：送出一件礼物（对齐安卓）
            EggTrigger.report("gift")
            onSent(gift)
        }
    }
}

/// 收礼人桌位选择（未入座送礼入口）：从本店「有人入座的桌」里挑一张再进面板——
/// 后端口径是「送方不必入座/到店，接收人须正入座该桌」（围观可送礼）。
struct LobbyGiftTargetSheet: View {
    let tables: [LobbyTable]
    let onDismiss: () -> Void
    let onPick: (LobbyTable) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)
                Text("选一张桌送礼")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                Text("收礼人须正在该桌就座；围观也可送礼（不必入座）")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
                if tables.isEmpty {
                    Text("本店暂无有人入座的桌 · 等有人入座后再送礼")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 14)
                } else {
                    ForEach(tables) { t in
                        HStack(spacing: 8) {
                            Text("\(t.tableNo ?? "?") 桌")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LobbyColors.ivory)
                            Text("\(LobbyTableStatus.of(t.status).label) · \(t.currentCount ?? 0) 人")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            Text("送礼")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LobbyColors.crimson)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                        .onTapGesture { onPick(t) }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - 礼物广播接收端补播（对齐安卓 LobbyGiftBroadcastOverlay）

/// 监听 .jjtLobbyGiftEvent：命中 listenGroupId 且非本人发送的特效副本，直接用载荷素材播同款全屏动效
/// （素材 animation_url 优先、icon 兜底；不拉礼物详情）。发送者本地已播过，按 senderId 跳过防双播。
/// 挂载：门店大厅听门店群、暗夜大厅听聚合群。
struct LobbyGiftBroadcastOverlay: View {
    let listenGroupId: String?
    let myUserId: Int64

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .jjtLobbyGiftEvent)) { note in
                guard let e = note.object as? LobbyGiftEvent,
                      e.groupId == listenGroupId,
                      e.senderId != myUserId else { return }
                JJTWindowOverlay.show(
                    GiftSendOverlay(gift: syntheticGift(e), combo: max(e.quantity, 1)) {
                        JJTWindowOverlay.dismiss()
                    }
                )
            }
    }

    private func syntheticGift(_ e: LobbyGiftEvent) -> GiftItem {
        GiftItem(id: 0, name: e.giftName, description: nil, icon: e.icon,
                 categoryId: nil, categoryName: nil, priceRabbit: nil,
                 animationUrl: e.animationUrl.isEmpty ? nil : e.animationUrl,
                 iconScale: e.iconScale ?? 100, broadcastScope: e.scope)
    }
}
