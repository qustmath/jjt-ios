import SwiftUI

/// 勿扰付费解锁面板（对齐安卓 LobbyDndUnlockSheet；资金流全部在后端）。
///
/// 三档并列呈现，互不重复：
/// 1. 送礼档——走礼物体系（scene=lobby_dnd，收礼即解锁，达阈值发通行证），本面板只做入口；
/// 2. 订单档——本面板下单：敬全场 / 通行券（同价），验支付密码 → 扣兔币 → 桌主 10 分钟内接受或原路退款；
/// 3. 完全静音档——不可解锁（桌主可设静音），面板只标注该档存在，不给入口。
///
/// 价格口径：订单档展示价 = 平面图回显的桌主定价（table.dndUnlockPrice，存量无价回退 300，与服务端扣款同规则）；
/// 送礼档阈值 660 兔币为服务端常量。真实扣款金额以服务端建单为准。
/// 在途防重：同一人同一桌只能有一笔 pending（服务端唯一键兜底），面板据此关闭下单按钮。
struct LobbyDndUnlockSheet: View {

    let table: LobbyTable
    let hostNickname: String?
    let myOrders: [LobbyDndUnlockOrder]
    let onDismiss: () -> Void
    /// 送礼档入口（转礼物面板 lobby_dnd 场景）
    let onGiftTier: () -> Void
    /// 订单支付成功回调
    let onOrderPlaced: () -> Void
    /// 在途单刷新（面板打开期间 5s 轮询用）
    var onRefreshOrders: () -> Void = {}
    /// 在途单出结果（桌主接受/拒绝/超时退款）：文案给调用方 toast 并收面板
    var onResolved: (String) -> Void = { _ in }


    @StateObject private var payGuard = PayPasswordGuard()
    @State private var level: LobbyDndUnlockLevel = LobbyDndUnlockSheet.loadLastLevel()
    @State private var busy = false
    @State private var showPaySettings = false
    @State private var showRecharge = false

    /// 本桌在途单（同人同桌唯一 pending）：有则在途卡片取代下单按钮
    private var pending: LobbyDndUnlockOrder? {
        myOrders.first { $0.tableId == table.id && $0.status == "pending" }
    }
    /// 最近一笔已结果订单（接受/拒绝/退款）：给「上次结果」提示，避免用户重复下单
    private var lastDone: LobbyDndUnlockOrder? {
        myOrders.first { $0.tableId == table.id && $0.status != "pending" }
    }
    /// 持证态：服务端会拦（且已前置到验密之前），但入口处就该告知，别让人走到密码那步
    private var holdsPass: Bool {
        myOrders.contains { $0.tableId == table.id && $0.holdsPass }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(LobbyColors.crimson)
                        .frame(width: 30, height: 30)
                        .background(LobbyColors.crimson.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("勿扰解锁 · \(table.tableNo ?? "该桌") 桌")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(LobbyColors.ivory)
                        Text(hostNickname.map { "桌主：\($0) · 解锁后到店即可入座" } ?? "解锁后到店即可入座")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                if holdsPass {
                    StatusCard(text: "你已持有本桌通行证 · 到桌边扫桌码核销入座（一次性），无需重复付费", dim: false)
                        .padding(.top, 10)
                }
                if let note = table.note, !note.isEmpty {
                    Text("「\(note)」")
                        .font(.system(size: 11))
                        .foregroundStyle(LobbyColors.goldLight.opacity(0.8))
                        .padding(.top, 8)
                }

                // ── 在途订单：替代下单按钮（服务端仍有唯一键兜底） ──
                if let pending {
                    PendingOrderCard(order: pending)
                        .padding(.top, 16)
                }

                // ── 档位①：送礼档（走礼物体系）；在途申请/持证时关闭入口 ──
                if pending == nil && !holdsPass {
                    tierCard
                        .padding(.top, 16)
                } else {
                    StatusCard(
                        text: holdsPass
                            ? "你已持有本桌通行证 · 扫桌码核销入座即可，无需再送解锁礼物"
                            : "已有解锁申请待桌主确认（\(pending.map { lobbyRemainingMinutes($0.expireTime) } ?? 10) 分钟窗口）· 期间不能再送解锁礼物",
                        dim: true)
                        .padding(.top, 16)
                }

                // ── 档位②：订单档（敬全场 / 通行券） ──
                orderTier
                    .padding(.top, 12)

                // ── 档位③：完全静音（不可解锁） ──
                silentTier
                    .padding(.top, 12)

                if let lastDone {
                    Text("上次结果：\(lastDone.isGift ? lobbyDndGiftOrderStatusLabel(lastDone.status) : lobbyDndOrderStatusLabel(lastDone.status))（\(lastDone.amount ?? 0) 兔币）")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 12)
                }

                Text("桌主同意后，同店在座会自动入桌；未入座到店后扫该桌入座码核销通行证（一次性）")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .payPasswordGuard(payGuard) { showPaySettings = true }
        .task(id: pending?.id) {
            // 在途单轮询：桌主响应后服务端不会推（无 C2C），面板开着就 5s 拉一次我的订单
            guard pending != nil else { return }
            lastPendingStatus = "pending"
            while !Task.isCancelled, pending != nil {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, pending != nil else { break }
                onRefreshOrders()
            }
        }
        .onChange(of: pending?.status ?? "none") { oldValue, newValue in
            guard oldValue == "pending" else { return }
            let text: String?
            switch newValue {
            case "accepted": text = "桌主已接受解锁 · 通行证已发放（同店在座自动入桌，未入座到店扫该桌入座码）"
            case "rejected": text = "桌主已拒绝 · 款项已原路退回"
            case "timeout_refund": text = "桌主未响应 · 款项已自动原路退回"
            case "refunded": text = "桌主已取消勿扰 · 款项已原路退回"
            default: text = nil
            }
            if let text { onResolved(text) }
        }
        .fullScreenCover(isPresented: $showPaySettings) {
            PayPasswordSettingsView()
        }
        .fullScreenCover(isPresented: $showRecharge, onDismiss: {}) {
            CoinRechargeView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jjtInsufficientBalance)) { _ in
            showRecharge = true
        }
    }

    // MARK: - 档位①：送礼档

    private var tierCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("档位一 · ")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(LobbyColors.goldLight)
                Text("送礼档 · 收礼即解锁")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
            }
            Text("送 660 兔币以上礼物发起解锁申请，桌主确认后解锁（礼物照收）；含 50% 分账与礼物广播")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)
            HStack(spacing: 5) {
                Image(systemName: "storefront")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0x1A/255, green: 0x14/255, blue: 0x08/255))
                Text("选礼物送出")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0x1A/255, green: 0x14/255, blue: 0x08/255))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(LinearGradient(colors: [LobbyColors.gold, LobbyColors.deepGold], startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { onGiftTier() }
            .padding(.top, 10)
        }
        .padding(14)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 档位②：订单档

    private var orderTier: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("档位二 · 订单档")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                Text("\(table.dndUnlockPrice ?? 300) 兔币 · 桌主定价")
                    .font(.system(size: 9.5))
                    .foregroundStyle(LobbyColors.goldLight)
            }
            Text("支付后桌主 10 分钟内响应：接受则收益分账，拒绝或超时原路退款")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(LobbyDndUnlockLevel.allCases, id: \.rawValue) { lv in
                    levelChip(lv)
                }
            }
            .padding(.top, 10)
            // 支付入口：验支付密码（未设置给引导、余额不足给充值引导、错误在弹窗内提示）
            Button { placeOrder() } label: {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    }
                    Text(pending != nil ? "已有一笔在途订单" : "支付 \(table.dndUnlockPrice ?? 300) 兔币 · \(level.label)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if pending != nil || busy {
                        Capsule().fill(LinearGradient(colors: [Color(red: 0x5A/255, green: 0x5A/255, blue: 0x62/255), Color(red: 0x3A/255, green: 0x3A/255, blue: 0x42/255)], startPoint: .leading, endPoint: .trailing))
                    } else {
                        Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                    }
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(pending != nil || busy)
            .padding(.top, 12)
        }
        .padding(14)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LobbyColors.crimson.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func levelChip(_ lv: LobbyDndUnlockLevel) -> some View {
        let selected = level == lv
        return VStack(alignment: .leading, spacing: 2) {
            Text(lv.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? LobbyColors.ivory : .white.opacity(0.6))
            Text(lv.desc)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(selected ? LobbyColors.crimson.opacity(0.16) : .white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? LobbyColors.crimson.opacity(0.6) : .white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { level = lv }
    }

    // MARK: - 档位③：完全静音

    private var silentTier: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("档位三 · 完全静音（不可解锁）")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("桌主设为完全静音的桌不接受任何付费打扰，仅可围观桌况。是否静音由服务端判定，尝试付费会被拒绝。")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .background(.white.opacity(0.02))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 逻辑

    private func placeOrder() {
        guard pending == nil, !busy else { return }
        payGuard.require { pwd in
            busy = true
            defer { busy = false }
            _ = try await LobbyAPI.dndCreateOrder(tableId: table.id, level: level.rawValue, payPassword: pwd)
            Self.saveLastLevel(level)
            onOrderPlaced()
        }
    }

    // MARK: - 「记住上次选择」本地记忆（UserDefaults 对齐安卓 SharedPreferences）

    private static let lastLevelKey = "lobby_dnd_last_unlock_level"

    /// 读上次档位（缺省通行券）；脏值/未知档位回退默认，不让本地记忆把面板卡死
    private static func loadLastLevel() -> LobbyDndUnlockLevel {
        guard let raw = UserDefaults.standard.string(forKey: lastLevelKey) else { return .passTicket }
        return LobbyDndUnlockLevel(rawValue: raw) ?? .passTicket
    }

    private static func saveLastLevel(_ level: LobbyDndUnlockLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: lastLevelKey)
    }
}

/// 在途订单卡片：剩余响应时间（服务端 10 分钟窗口，超时自动原路退款）
private struct PendingOrderCard: View {
    let order: LobbyDndUnlockOrder

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let leftMin = lobbyRemainingMinutes(order.expireTime)
            VStack(alignment: .leading, spacing: 3) {
                Text("已下单 · 等桌主响应")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LobbyColors.goldLight)
                Text(detailText(leftMin: leftMin))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(LobbyColors.standing.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func detailText(leftMin: Int) -> String {
        if order.isGift {
            let tail = leftMin > 0 ? "剩 \(leftMin) 分钟未确认即失效" : "窗口已到 · 失效由服务端收口"
            return "送礼解锁 · 随 \(order.amount ?? 0) 兔币礼物申请 · \(tail)"
        }
        let tail = leftMin > 0 ? "剩 \(leftMin) 分钟自动退款" : "窗口已到 · 退款由服务端收口"
        let lv = LobbyDndUnlockLevel(rawValue: order.unlockLevel ?? "")?.label ?? "解锁"
        return "\(lv) · 已支付 \(order.amount ?? 0) 兔币 · \(tail)"
    }
}
