import SwiftUI

/// 群送礼候选收礼人（对齐安卓 GiftReceiver）
struct GiftReceiver: Identifiable {
    let id: Int64
    let name: String
    let avatar: String?
}

/// 赠礼底部弹层 + 全屏赠送动效（对齐安卓 GiftPanelSheet）
/// 用法：GiftPanelSheet(receiverId: 作者id, toName: 昵称, onClose: ...)
/// 群聊：传 receivers（候选收礼人），面板内头像行切换收礼人，送出走 onSentTo
/// 帖子挂帖：传 scene="post" + sceneId=帖子ID（服务端据此刻意分账给发帖人并计礼物热度）
struct GiftPanelSheet: View {

    let receiverId: Int64
    let toName: String
    let onClose: () -> Void
    var onSent: (GiftItem) -> Void = { _ in }
    /// 群送礼候选收礼人（非空即群模式：必须主动选择收礼人才能送出）
    var receivers: [GiftReceiver]? = nil
    /// 群模式送出回调（含选中的收礼人）
    var onSentTo: (GiftItem, GiftReceiver) -> Void = { _, _ in }
    /// 赠送场景：post=帖子挂帖；nil=按面板形态推断（群=group，否则 profile）
    var scene: String? = nil
    /// 场景ID（scene=post 时为帖子ID）
    var sceneId: Int64? = nil

    @StateObject private var payGuard = PayPasswordGuard()
    @State private var gifts: [GiftItem] = []
    @State private var sel: GiftItem?
    @State private var combo = 0
    @State private var sending = false
    @State private var busy = false
    @State private var balance: Int64?
    @State private var error: String?
    @State private var showPaySettings = false
    @State private var showRecharge = false
    /// 群模式：当前选中的收礼人（默认不选，需用户主动点选）
    @State private var selectedReceiver: GiftReceiver?

    private var curReceiverId: Int64 { selectedReceiver?.id ?? receiverId }
    private var curToName: String { selectedReceiver?.name ?? toName }

    /// 只展示 2D 礼物（3D/GLB 已在 iOS 下线，不再解析）
    private var list: [GiftItem] {
        gifts.filter { giftRenderKindOf(giftDisplayIcon($0.icon, $0.animationUrl)).map { giftKindGroupOf($0.0) } == "2d" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            header
            // 群模式：收礼人选择行（头像横滑，选中金边）
            if let receivers {
                receiverRow(receivers)
            }
            giftRow
            sendBar
                .padding(.top, 10)
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.crimsonHot)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 28)
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
        .overlay {
            if sending, let sel {
                GiftSendOverlay(gift: sel, combo: combo) { sending = false }
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("赠礼 · ")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text(curToName.isEmpty ? "请选择" : curToName)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [Noir.crimsonHot, Noir.crimson], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .lineLimit(1)
                }
                Text("以礼寄意，暗夜传情")
                    .font(.system(size: 11))
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
            .padding(.trailing, 10)
            Button { if !busy { onClose() } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - 礼物横排

    private var giftRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(list) { gift in
                    let selected = sel?.id == gift.id
                    VStack(spacing: 2) {
                        GiftIconView(
                            icon: giftDisplayIcon(gift.icon, gift.animationUrl),
                            size: 56,
                            scale: CGFloat(gift.iconScale ?? 100) / 100
                        )
                        .frame(height: 64)
                        Text(gift.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        Text("\(gift.priceRabbit ?? 0) 币")
                            .font(.system(size: 10))
                            .foregroundStyle(Noir.goldText)
                    }
                    .frame(width: 64)
                    .padding(.vertical, 8)
                    .background(selected ? Noir.crimson.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                        selected ? Noir.crimson.opacity(0.6) : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { if !busy { sel = gift } }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
    }

    // MARK: - 选中说明 + 赠送按钮

    private var sendBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(sel?.name ?? "")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Noir.ivory)
                    if let sel {
                        let kind = giftRenderKindOf(giftDisplayIcon(sel.icon, sel.animationUrl))?.0
                        Text(giftKindGroupOf(kind) == "3d" ? "3D 动效" : "2D 动效")
                            .font(.system(size: 9))
                            .foregroundStyle(Noir.gold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                    }
                }
                Text(sel?.description ?? "")
                    .font(.system(size: 11))
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
                            .font(.system(size: 14))
                        Text("赠送")
                    }
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    busy
                        ? AnyShapeStyle(Color.gray.opacity(0.4))
                        : AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy || sending || sel == nil)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 群收礼人选择行

    private func receiverRow(_ receivers: [GiftReceiver]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(receivers) { r in
                    let selected = selectedReceiver?.id == r.id
                    VStack(spacing: 3) {
                        AppAvatar(url: r.avatar, size: 38)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(selected ? Noir.gold : Color.white.opacity(0.12), lineWidth: 1.5))
                        Text(r.name)
                            .font(.system(size: 10))
                            .foregroundStyle(selected ? Noir.gold : .white.opacity(0.5))
                            .lineLimit(1)
                            .frame(width: 52)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !busy { selectedReceiver = r } }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
    }

    // MARK: - 逻辑

    private func load() {
        Task {
            gifts = (try? await GiftAPI.giftList()) ?? []
            if sel == nil || !(list.contains { $0.id == sel?.id }) {
                sel = list.first
            }
        }
        refreshBalance()
    }

    private func refreshBalance() {
        Task {
            balance = try await WalletAPI.getWallet("rabbit_coin").availableAmount
        }
    }

    private func send() {
        guard let gift = sel, !busy else { return }
        // 群模式必须先选收礼人
        guard receivers == nil || selectedReceiver != nil else {
            error = "请先选择收礼人"
            return
        }
        let price = Int64(gift.priceRabbit ?? 0)
        if let balance, balance < price {
            showRecharge = true
            return
        }
        error = nil
        payGuard.require { pwd in
            busy = true
            defer { busy = false }
            // 余额不足/未设密码由守卫统一处理（充值引导/去设置）
            // scene 缺省按形态推断：群=group，单聊/主页=profile；帖子挂帖由调用方显式传 post + sceneId
            _ = try await GiftAPI.send(SendGiftReq(
                giftId: gift.id, receiverId: curReceiverId, quantity: 1,
                scene: scene ?? (receivers != nil ? "group" : "profile"), sceneId: sceneId, payPassword: pwd))
            balance = (balance ?? 0) - price
            combo += 1
            sending = true
            // 彩蛋「借火的人」：送出一件礼物（对齐安卓）
            EggTrigger.report("gift")
            onSent(gift)
            if let selectedReceiver { onSentTo(gift, selectedReceiver) }
        }
    }
}
