import SwiftUI

/// 赠礼底部弹层 + 全屏赠送动效（对齐安卓 GiftPanelSheet）
/// 用法：GiftPanelSheet(receiverId: 作者id, toName: 昵称, onClose: ...)
/// 群聊候选收礼人（receivers）留待密语阶段接线
struct GiftPanelSheet: View {

    let receiverId: Int64
    let toName: String
    let onClose: () -> Void
    var onSent: (GiftItem) -> Void = { _ in }

    @StateObject private var payGuard = PayPasswordGuard()
    @State private var gifts: [GiftItem] = []
    @State private var tab = "2d"
    @State private var sel: GiftItem?
    @State private var combo = 0
    @State private var sending = false
    @State private var busy = false
    @State private var balance: Int64?
    @State private var error: String?
    @State private var showPaySettings = false
    @State private var showRecharge = false

    private var list: [GiftItem] {
        gifts.filter { giftRenderKindOf(giftDisplayIcon($0.icon, $0.animationUrl)).map { giftKindGroupOf($0.0) } == tab }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            header
            tabSwitcher
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
                    Text(toName.isEmpty ? "请选择" : toName)
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

    // MARK: - 2D/3D 切换

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            panelTab("平 面 之 礼", active: tab == "2d") { tab = "2d"; combo = 0 }
            panelTab("立 体 之 礼", active: tab == "3d") { tab = "3d"; combo = 0 }
        }
        .padding(3)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func panelTab(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .tracking(1.5)
                .foregroundStyle(active ? .white : .white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(active
                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.clear))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
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
            _ = try await GiftAPI.send(SendGiftReq(
                giftId: gift.id, receiverId: receiverId, quantity: 1,
                scene: "profile", payPassword: pwd))
            balance = (balance ?? 0) - price
            combo += 1
            sending = true
            onSent(gift)
        }
    }
}
