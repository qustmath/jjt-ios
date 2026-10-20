import SwiftUI

/// 该桌当前状态能否直入（仅 free——落座即成桌主；有人桌改审批制，走拼桌申请）；
/// 与后端 validateTableSeatableFor + 容量门槛同口径
func lobbySeatableFor(_ st: LobbyTableStatus, full: Bool) -> Bool {
    st == .free && !full
}

/// 剩余分钟（epoch 毫秒差；null/已过期 → 0）；勿扰在途单倒计时共用
func lobbyRemainingMinutes(_ expireTime: Int64?) -> Int {
    guard let expireTime else { return 0 }
    let diff = expireTime - Int64(Date().timeIntervalSince1970 * 1000)
    if diff <= 0 { return 0 }
    return Int((diff + 59_999) / 60_000)
}

/// 点桌抽屉（六态全操作，对齐安卓 LobbyTableDrawer）。
///
/// 两条判据决定渲染哪组操作：
/// ① 是不是我的桌（我在本桌入座）：我的桌走桌主/成员操作，别人的桌走入座/申请/解锁；
/// ② 桌态：free/occupied 直入、sharing 审批、dnd 付费、reserved 只看、grouping 本期不可达。
///
/// 所有写操作只做入口显隐，合法性由服务端判定（桌主身份、桌态流转、容量、门槛）。
struct LobbyTableDrawerView: View {

    let table: LobbyTable
    let spectate: LobbyTableSpectate?
    /// 我的坐席态（nil=未入座）：桌号命中即「我的桌」，hostUserId 命中即桌主
    let seat: LobbySeatState?
    let myUserId: Int64
    let hostApplies: [LobbyShareApply]
    let hostOrders: [LobbyDndUnlockOrder]
    let myApply: LobbyShareApply?
    let myOrders: [LobbyDndUnlockOrder]

    let onDismiss: () -> Void
    let onCheckIn: () -> Void
    let onSwitch: () -> Void
    let onLeave: () -> Void
    let onApplyShare: () -> Void
    let onUnlock: () -> Void
    let onGiftToTable: () -> Void
    let onMemberClick: (LobbySpectateMember) -> Void
    let onTransfer: (Int64) -> Void
    let onRemove: (Int64) -> Void
    let onInvite: (Int64) -> Void
    let onShout: (String?) -> Void
    let onStopShout: () -> Void
    let onEnableDnd: (String?, Bool, Int64?) -> Void
    let onCancelDnd: () -> Void
    let onApproveApply: (LobbyShareApply) -> Void
    let onRejectApply: (LobbyShareApply) -> Void
    let onAcceptOrder: (LobbyDndUnlockOrder) -> Void
    let onRejectOrder: (LobbyDndUnlockOrder) -> Void

    // 弹层状态（抽屉内的选择/输入）
    @State private var memberOpsFor: LobbySpectateMember?
    @State private var shoutOpen = false
    @State private var shoutNote = ""
    @State private var dndOpen = false
    @State private var dndNote = ""
    @State private var dndSilent = false
    // 解锁价输入（普通勿扰档；桌主自定义解锁价）
    @State private var dndPrice = ""
    @State private var dndPriceError: String?
    @State private var inviteOpen = false

    private var status: LobbyTableStatus { LobbyTableStatus.of(table.status) }
    /// 人数/容量取围观接口的实时值，回退平面图快照（围观失败时抽屉仍可用）
    private var cur: Int { spectate?.currentCount ?? table.currentCount ?? 0 }
    private var capRaw: Int? { spectate?.capacity ?? table.capacity }
    private var full: Bool {
        guard let capRaw else { return false }
        return cur >= capRaw
    }
    private var isMine: Bool { seat?.state == "seated" && seat?.tableId == table.id }
    private var isHost: Bool { isMine && table.hostUserId == myUserId }
    private var members: [LobbySpectateMember] { spectate?.members ?? [] }
    /// 我对本桌的在途申请（未过期）：有则不重复给申请入口
    private var pendingMine: LobbyShareApply? {
        guard let a = myApply, a.tableId == table.id, a.status == "pending", a.expired != true else { return nil }
        return a
    }

    @ObservedObject private var cardStore = MemberCardStore.shared
    /// 围观视角提示（别人的桌「围观」动作）
    @State private var spectating = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 抓手
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                header
                if let note = tableNote {
                    Text(status == .dnd ? "勿扰：\(note)" : "「\(note)」")
                        .font(.system(size: 11))
                        .foregroundStyle(LobbyColors.goldLight.opacity(0.8))
                        .padding(.top, 6)
                }
                if let reserve = table.reserveText, !reserve.isEmpty {
                    Text("预定：\(reserve)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 0x63/255, green: 0xB4/255, blue: 0xDD/255))
                        .padding(.top, 4)
                }

                // ── 桌主卡（v75 口径：自己的桌也单独一行；成员宫格不再挂桌主标） ──
                hostCard

                // ── 桌主：待审批拼桌申请（拼桌中 / 有人桌审批制） ──

                // ── 桌主：待审批拼桌申请（拼桌中 / 有人桌审批制） ──
                if isHost && (status == .sharing || status == .occupied) {
                    sectionLabel("待审批申请", count: hostApplies.count)
                    if hostApplies.isEmpty {
                        emptyHint("暂无待审批申请 · 申请人会在 30 分钟内等结果")
                    } else {
                        ForEach(hostApplies) { a in
                            ApplyRow(apply: a,
                                     onApprove: { onApproveApply(a) },
                                     onReject: { onRejectApply(a) })
                                .padding(.bottom, 8)
                        }
                    }
                }

                // ── 桌主：待响应解锁订单（勿扰中） ──
                if isHost && status == .dnd {
                    sectionLabel("待响应解锁", count: hostOrders.count)
                    if hostOrders.isEmpty {
                        emptyHint("暂无解锁申请 · 有人付费打扰时会出现在这里")
                    } else {
                        ForEach(hostOrders) { o in
                            UnlockOrderRow(order: o,
                                           onAccept: { onAcceptOrder(o) },
                                           onReject: { onRejectOrder(o) })
                                .padding(.bottom, 8)
                        }
                    }
                }

                // ── 申请人：我的拼桌申请状态（别人的桌 · 拼桌中/有人桌审批制） ──
                if !isMine && (status == .sharing || status == .occupied) {
                    let mine = myApply.flatMap { $0.tableId == table.id ? $0 : nil }
                    if pendingMine != nil {
                        StatusCard(text: "已申请拼桌 · 等桌主审批（30 分钟窗口）", dim: false)
                            .padding(.top, 12)
                    } else if mine?.status == "rejected" {
                        StatusCard(text: "桌主已拒绝该次申请 · 可再试一次", dim: true)
                            .padding(.top, 12)
                    }
                }

                // ── 行动区 ──
                actionArea
                    .padding(.top, 16)

                Text(footerNote)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 10)

                // ── 同桌成员（v75 口径：放在最底部，四列宫格） ──
                HStack(spacing: 0) {
                    Text("同桌成员")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer().frame(width: 6)
                    Text(capRaw.map { "\(cur)/\($0)" } ?? "\(cur)")
                        .font(.lobbyNumber(9))
                        .foregroundStyle(LobbyColors.goldLight)
                    if isHost {
                        Spacer()
                        Text("长按可转让/移出")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
                .padding(.top, 16)
                MemberLane(
                    members: members,
                    emptySeats: capRaw.map { max($0 - cur, 0) },
                    myUserId: myUserId,
                    hostUserId: table.hostUserId,
                    canHostAct: isHost,
                    onClick: { onMemberClick($0) },
                    onHostAction: { memberOpsFor = $0 }
                )
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        // ── 抽屉内浮层：成员管理 / 喊人 / 勿扰设置 / 好友补位 ──
        .confirmationDialog(
            memberOpsFor?.nickname ?? "该成员",
            isPresented: Binding(get: { memberOpsFor != nil }, set: { if !$0 { memberOpsFor = nil } }),
            titleVisibility: .visible
        ) {
            Button("查看资料卡") { if let m = memberOpsFor { memberOpsFor = nil; onMemberClick(m) } }
            Button("转让桌主给 TA") { if let m = memberOpsFor { memberOpsFor = nil; onTransfer(m.userId) } }
            Button("移出本桌（回罚站）", role: .destructive) { if let m = memberOpsFor { memberOpsFor = nil; onRemove(m.userId) } }
            Button("取消", role: .cancel) { memberOpsFor = nil }
        }
        .alert("喊人拼桌", isPresented: $shoutOpen) {
            TextField("还差 2 位，来会玩骰子的", text: $shoutNote)
            Button("喊人") { onShout(shoutNote.isEmpty ? nil : shoutNote) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("喊人文案（选填，≤50 字，随滚动条展示）")
        }
        .sheet(isPresented: $dndOpen) {
            dndSetupSheet
                .presentationDetents([.medium])
                .presentationBackground(LobbyColors.panel)
        }
        .sheet(isPresented: $inviteOpen) {
            LobbyFriendPickerSheet(
                onDismiss: { inviteOpen = false },
                onPick: { u in
                    inviteOpen = false
                    onInvite(u.userId)
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(LobbyColors.panel)
        }
    }

    /// 三列动作宫格（2026-10-18 用户口径）
    private func drawerActionGrid(_ actions: [DrawerSpec]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(actions) { a in
                drawerAction(a)
            }
        }
    }

    private func drawerAction(_ a: DrawerSpec) -> some View {
        VStack(spacing: 4) {
            Image(systemName: a.icon)
                .font(.system(size: 15))
            Text(a.label)
                .font(.system(size: 9.5))
                .lineLimit(1)
        }
        .foregroundStyle(a.gold ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255)
                            : (a.primary ? .white : LobbyColors.ivory))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background {
            if a.gold {
                RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [LobbyColors.goldPale, LobbyColors.gold], startPoint: .leading, endPoint: .trailing))
            } else if a.primary {
                RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
            } else {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05))
            }
        }
        .overlay {
            if !a.gold && !a.primary {
                RoundedRectangle(cornerRadius: 14).stroke(LobbyColors.gold.opacity(0.3), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { a.action() }
    }

    private var tableNote: String? {
        let s = spectate?.note
        if let s, !s.isEmpty { return s }
        if let n = table.note, !n.isEmpty { return n }
        return nil
    }

    private var footerNote: String {
        if isMine && isHost {
            return "桌主动作由服务端复核（身份/桌态/容量）；有人桌才能转拼桌或勿扰"
        }
        if isMine {
            return "同桌成员可送礼与离桌；桌主管理动作仅桌主可见"
        }
        if lobbySeatableFor(status, full: full) {
            return "入座核验在服务端：入座码时效 + 门店围栏 + 实名"
        }
        if status == .sharing || status == .occupied {
            return "入座走桌主审批：申请后等 30 分钟窗口，通过即入桌"
        }
        if status == .dnd {
            return "勿扰桌：付费解锁（送礼档 / 订单档）或先围观；完全静音档不可解锁"
        }
        return "该桌当前无可执行动作"
    }

    // MARK: - 桌头

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("\(table.tableNo ?? "?") 桌")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                Spacer().frame(width: 10)
                HStack(spacing: 2) {
                    if status == .dnd {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(LobbyTableStyle.color(status))
                    }
                    Text(status.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LobbyTableStyle.color(status))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(LobbyTableStyle.glow(status))
                .overlay(Capsule().stroke(LobbyTableStyle.color(status), lineWidth: 1))
                .clipShape(Capsule())
                Spacer().frame(width: 8)
                // 容量未知时不显示 "n/0 人"
                Text(capRaw.map { "\(cur)/\($0) 人" } ?? "\(cur) 人")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                if isMine {
                    Spacer()
                    Text(isHost ? "我的桌 · 我是桌主" : "我的桌")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isHost ? .white : Color(red: 0x1A/255, green: 0x14/255, blue: 0x08/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(isHost ? LobbyColors.crimson : LobbyColors.gold.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - 桌主卡（v75：自己的桌也单独一行）

    @ViewBuilder
    private var hostCard: some View {
        let host = members.first { $0.userId == table.hostUserId }
            ?? members.first { $0.host == true }
            ?? members.first
        if let host {
            let card = cardStore.card(host.userId)
            let hostIsMe = host.userId == myUserId
            HStack(spacing: 10) {
                LobbyMemberAvatar(userId: host.userId, fallbackAvatar: host.avatar, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(hostIsMe ? "我" : memberDisplayName(card, host.nickname))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LobbyColors.ivory)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("桌主")
                            .font(.system(size: 9))
                            .foregroundStyle(LobbyColors.gold)
                        if card?.vipName?.isEmpty == false {
                            Spacer().frame(width: 6)
                            LobbyVipChip(vipName: card?.vipName, vipColor: card?.vipColor, levelInTier: card?.levelInTier)
                        }
                    }
                    Text(hostIsMe
                         ? (capRaw.map { "你是桌主 · 本桌 \(cur)/\($0) 人" } ?? "你是桌主 · 本桌 \(cur) 人")
                         : (capRaw.map { "本桌桌主 · 本桌 \(cur)/\($0) 人" } ?? "本桌桌主 · 本桌 \(cur) 人"))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(LobbyColors.gold.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LobbyColors.gold.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture { onMemberClick(host) }
            .padding(.top, 12)
            .task(id: host.userId) { MemberCardStore.shared.fetchMissing([host.userId]) }
        }
    }

    // MARK: - 行动区

    @ViewBuilder
    private var actionArea: some View {
        if isMine {
            // 我的桌：三列动作宫格（2026-10-18 用户口径）
            if !isHost {
                Text("桌主可喊人拼桌 / 设置勿扰 / 邀请补位 / 转让与移出成员")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                switch status {
                case .free:
                    HintActionRow(label: "开桌后再喊人拼桌（先入座成为有人桌）")
                case .grouping, .reserved:
                    HintActionRow(label: "该桌当前不可发起拼桌/勿扰")
                default:
                    EmptyView()
                }
            }
            drawerActionGrid(myTableActions)
        } else {
            othersActions
            if spectating {
                StatusCard(text: "当前为围观视角 · 对方看不到你", dim: true)
                    .padding(.top, 8)
            }
        }
    }

    /// 我的桌动作（桌主按桌态追加，送礼/离桌始终有）
    private var myTableActions: [DrawerSpec] {
        var list: [DrawerSpec] = []
        if isHost {
            switch status {
            case .sharing:
                list.append(DrawerSpec(label: "停止拼桌", icon: "person.3", primary: true) { onStopShout() })
                list.append(DrawerSpec(label: "邀请补位", icon: "person.badge.plus") { inviteOpen = true })
            case .dnd:
                list.append(DrawerSpec(label: "取消勿扰", icon: "lock", primary: true) { onCancelDnd() })
            case .occupied:
                list.append(DrawerSpec(label: "喊人拼桌", icon: "person.3", primary: true) { shoutNote = ""; shoutOpen = true })
                list.append(DrawerSpec(label: "勿扰设置", icon: "lock") { dndNote = ""; dndSilent = false; dndPrice = ""; dndPriceError = nil; dndOpen = true })
                list.append(DrawerSpec(label: "邀请补位", icon: "person.badge.plus") { inviteOpen = true })
            case .free:
                list.append(DrawerSpec(label: "邀请补位", icon: "person.badge.plus") { inviteOpen = true })
            default:
                break
            }
        }
        list.append(DrawerSpec(label: "送礼", icon: "gift.fill", gold: true) { onGiftToTable() })
        list.append(DrawerSpec(label: "离桌", icon: "rectangle.portrait.and.arrow.right") { onLeave() })
        return list
    }

    @ViewBuilder
    private var othersActions: some View {
        // 入座后取消自由换桌（2026-10-16 用户口径）：要换桌先去我的桌主动离桌
        if lobbySeatableFor(status, full: full) && seat?.state == "seated" {
            HintActionRow(label: "已入座本店 · 换桌请先离桌")
        } else if lobbySeatableFor(status, full: full) {
            SeatActionButton(label: "扫码入座 \(table.tableNo ?? "") 桌", icon: "qrcode") { onCheckIn() }
        } else if (status == .sharing || status == .occupied) && full {
            HintActionRow(label: "该桌已满员 · 等有人离桌后再申请")
        } else if (status == .sharing || status == .occupied) && pendingMine != nil {
            // 已有在途申请：不再给按钮（服务端也会拒重复申请），避免无谓请求与错误提示
            HintActionRow(label: "已申请 · 等桌主审批（30 分钟窗口）")
        } else if status == .sharing || status == .occupied {
            // v75 三连动作：申请 / 敬全场（送礼给全桌）/ 围观 并排等宽
            HStack(spacing: 8) {
                drawerAction(DrawerSpec(label: "申请拼桌", icon: "person.3", primary: true) { onApplyShare() })
                    .frame(maxWidth: .infinity)
                drawerAction(DrawerSpec(label: "敬全场", icon: "gift.fill", gold: true) { onGiftToTable() })
                    .frame(maxWidth: .infinity)
                drawerAction(DrawerSpec(label: "围观", icon: "eye") { spectating = true })
                    .frame(maxWidth: .infinity)
            }
        } else if status == .dnd {
            // 勿扰：付费解锁（送礼档/订单档）；持证者给扫码入口（走与空闲桌同一套扫码核销链路）；
            // 无证才给付费按钮——持证者付费会被服务端拦，入口直接分流
            if myOrders.contains(where: { $0.tableId == table.id && $0.holdsPass }) {
                SeatActionButton(label: "凭通行证扫码入座 \(table.tableNo ?? "") 桌", icon: "qrcode") { onCheckIn() }
                HintActionRow(label: "通行证一次性核销 · 无需重复付费")
                    .padding(.top, 6)
            } else if table.dndLevel == "silent" {
                // 完全静音不可付费解锁（此前按钮照画、点击吃服务端 400）；
                // dndLevel 为 nil（旧后端）按可解锁勿扰对待，保持旧表现
                HintActionRow(label: "完全静音中 · 不可付费解锁打扰")
            } else {
                // 解锁入口显桌主定价（nil=服务端默认 300，不编数）
                SeatActionButton(label: table.dndUnlockPrice.map { "付费 \($0) 兔币解锁打扰" } ?? "付费解锁打扰", icon: "lock") { onUnlock() }
            }
        } else if status == .reserved {
            HintActionRow(label: "已预定 · \(table.reserveText ?? "到点后开放")")
        } else {
            HintActionRow(label: "组局态本期不可达（组局弱关联）")
        }
    }

    // MARK: - 勿扰设置弹层（桌主）

    private var dndSetupSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置本桌勿扰")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LobbyColors.ivory)
            Text("勿扰后外人不能申请入桌，只能付费解锁打扰或围观。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 6)
            TextField("熟人局，勿扰", text: $dndNote)
                .font(.system(size: 12))
                .foregroundStyle(LobbyColors.textBody)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 12)
                .onChange(of: dndNote) { _, v in
                    if v.count > 50 { dndNote = String(v.prefix(50)) }
                }
            HStack(spacing: 8) {
                DndTierChip(title: "普通勿扰", sub: "可付费解锁", selected: !dndSilent) { dndSilent = false }
                DndTierChip(title: "完全静音", sub: "不可付费解锁", selected: dndSilent) { dndSilent = true }
            }
            .padding(.top, 12)
            if !dndSilent {
                // 解锁价：桌主指定兔币金额（解锁者按此价付费，50% 分账桌主）
                VStack(alignment: .leading, spacing: 4) {
                    Text("解锁价（兔币，必填）")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("如 300", text: $dndPrice)
                        .font(.system(size: 12))
                        .keyboardType(.numberPad)
                        .foregroundStyle(LobbyColors.textBody)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                            dndPriceError == nil ? Noir.gold.opacity(0.3) : LobbyColors.crimson, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: dndPrice) { _, v in
                            // ≤7 位纯数字（对齐安卓）
                            if v.count > 7 || v.contains(where: { !$0.isNumber }) {
                                dndPrice = String(v.prefix(7)).filter(\.isNumber)
                            }
                            dndPriceError = nil
                        }
                    if let err = dndPriceError {
                        Text(err)
                            .font(.system(size: 9.5))
                            .foregroundStyle(LobbyColors.crimson)
                    } else {
                        Text("他人付费此价申请解锁打扰 · 50% 分账给你")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.top, 10)
            }
            HStack(spacing: 12) {
                Button {
                    dndOpen = false
                } label: {
                    Text("取消")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.05))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    let amount = Int64(dndPrice)
                    if !dndSilent, amount == nil || amount! < 1 {
                        dndPriceError = "请设置解锁价（至少 1 兔币）"
                        return
                    }
                    // 上限与服务端 @Max 同口径（超限本地拦，别等服务端 400 回打）
                    if !dndSilent, let amount, amount > lobbyAmountMax {
                        dndPriceError = "解锁价过大（上限 100 万兔币）"
                        return
                    }
                    dndOpen = false
                    onEnableDnd(dndNote.isEmpty ? nil : dndNote, dndSilent, dndSilent ? nil : amount)
                } label: {
                    Text("设为勿扰")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - 小组件

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LobbyColors.ivory)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(LobbyColors.crimson)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(.white.opacity(0.3))
    }
}

// MARK: - 成员区

/// 成员头像行 + 虚位占位：短按 = 资料卡（所有人）；桌主长按 = 转让桌主/移出成员
private struct MemberLane: View {
    let members: [LobbySpectateMember]
    let emptySeats: Int?
    let myUserId: Int64
    let hostUserId: Int64?
    let canHostAct: Bool
    let onClick: (LobbySpectateMember) -> Void
    let onHostAction: (LobbySpectateMember) -> Void

    @ObservedObject private var cardStore = MemberCardStore.shared

    /// 桌主标只信平面图快照的 hostUserId（随播报/轮询实时刷新）——宫格内不再挂桌主标（v75：桌主有单独大卡）
    var body: some View {
        let empty = max(emptySeats ?? 0, 0)
        if members.isEmpty && empty == 0 {
            Text("暂无人入座")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        } else {
            let cells: [MemberCellItem] = {
                var list: [MemberCellItem] = members.map { .member($0) }
                for _ in 0..<empty { list.append(.empty) }
                return list
            }()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .member(let m):
                        memberCell(m)
                    case .empty:
                        emptySeatCell
                    }
                }
            }
            .task(id: members.map(\.userId)) {
                MemberCardStore.shared.fetchMissing(members.map(\.userId))
            }
        }
    }

    private enum MemberCellItem {
        case member(LobbySpectateMember)
        case empty
    }

    private func memberCell(_ m: LobbySpectateMember) -> some View {
        let card = cardStore.card(m.userId)
        let isSelf = m.userId == myUserId
        return VStack(spacing: 4) {
            LobbyMemberAvatar(userId: m.userId, fallbackAvatar: m.avatar, size: 50)
                .contentShape(Circle())
                .onTapGesture { onClick(m) }
                .simultaneousGesture(
                    LongPressGesture().onEnded { _ in
                        if canHostAct && !isSelf { onHostAction(m) }
                    }
                )
            Text(isSelf ? "我" : memberDisplayName(card, m.nickname))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
            if card?.vipName?.isEmpty == false {
                LobbyVipChip(vipName: card?.vipName, vipColor: card?.vipColor, levelInTier: card?.levelInTier, fontSize: 7.5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 虚位：金色虚线圆（v75）
    private var emptySeatCell: some View {
        VStack(spacing: 4) {
            Circle()
                .stroke(LobbyColors.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .frame(width: 50, height: 50)
                .overlay(
                    Text("虚")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.18))
                )
            Text("虚位")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
    }
}

/// 抽屉动作（图标在上文字在下；primary 酒红 / gold 鎏金 / 常态描边）
struct DrawerSpec: Identifiable {
    let label: String
    let icon: String
    var primary = false
    var gold = false
    let action: () -> Void

    var id: String { label }
}

// MARK: - 审批 / 订单行

private struct ApplyRow: View {
    let apply: LobbyShareApply
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LobbyMemberAvatar(userId: apply.userId, fallbackAvatar: apply.userAvatar, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(apply.userNickname ?? "申请人")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
                Text(apply.expired == true ? "申请已过期（审批窗口 30 分钟）" : "申请加入本桌 · 差你点头")
                    .font(.system(size: 9))
                    .foregroundStyle(apply.expired == true ? .white.opacity(0.3) : .white.opacity(0.45))
            }
            Spacer()
            if apply.expired == true {
                Text("已过期")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                DrawerSmallButton(label: "拒绝", primary: false, onClick: onReject)
                DrawerSmallButton(label: "同意", primary: true, onClick: onApprove)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// 解锁订单行：剩余响应时间（服务端 10 分钟窗口；已过期时服务端会拒绝接受，这里只作展示）
private struct UnlockOrderRow: View {
    let order: LobbyDndUnlockOrder
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let leftMin = lobbyRemainingMinutes(order.expireTime)
            HStack(spacing: 10) {
                LobbyMemberAvatar(userId: order.userId, fallbackAvatar: order.userAvatar, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.userNickname ?? "解锁方")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LobbyColors.ivory)
                        .lineLimit(1)
                    Text(
                        (order.isGift ? "送礼解锁" : (LobbyDndUnlockLevel(rawValue: order.unlockLevel ?? "")?.label ?? "解锁"))
                            + " · \(order.amount ?? 0) 兔币 · 剩 \(leftMin) 分钟"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(LobbyColors.goldLight.opacity(0.75))
                }
                Spacer()
                DrawerSmallButton(label: "拒绝", primary: false, onClick: onReject)
                DrawerSmallButton(label: "接受", primary: true, onClick: onAccept)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(LobbyColors.crimson.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LobbyColors.crimson.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// 抽屉内小按钮（同意/拒绝）
private struct DrawerSmallButton: View {
    let label: String
    let primary: Bool
    let onClick: () -> Void

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(primary ? .white : LobbyColors.goldLight)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                } else {
                    Capsule().fill(.white.opacity(0.05))
                        .overlay(Capsule().stroke(Noir.gold.opacity(0.35), lineWidth: 1))
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { onClick() }
    }
}

/// 申请人/持证状态卡
struct StatusCard: View {
    let text: String
    let dim: Bool

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(dim ? .white.opacity(0.4) : LobbyColors.goldLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 抽屉内的主行动按钮；primary = false 时用描边弱化（离桌等退出类动作）
struct SeatActionButton: View {
    let label: String
    let icon: String
    var primary = true
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(primary ? .white : LobbyColors.goldLight)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primary ? .white : LobbyColors.goldLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background {
            if primary {
                Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
            } else {
                Capsule().fill(.white.opacity(0.04))
                    .overlay(Capsule().stroke(LobbyColors.goldLight.opacity(0.5), lineWidth: 1))
            }
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { onClick() }
    }
}

/// 纯提示行动条（无实际操作：桌态不可执行时给原因）
struct HintActionRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundStyle(LobbyColors.goldLight)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LobbyColors.goldLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.04))
        .overlay(Capsule().stroke(Noir.gold.opacity(0.25), lineWidth: 1))
        .clipShape(Capsule())
    }
}

/// 勿扰档位 chip（普通勿扰 / 完全静音）
private struct DndTierChip: View {
    let title: String
    let sub: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? LobbyColors.ivory : .white.opacity(0.6))
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(selected ? LobbyColors.crimson.opacity(0.14) : .white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? LobbyColors.crimson.opacity(0.6) : .white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
    }
}

/// 好友选择（「邀请好友补位」入口）：一次拉 20 位好友，点选即发邀请（一桌对一人一条）。
/// 失败静默空态，不弹错打断选人。
struct LobbyFriendPickerSheet: View {
    var title = "邀请好友补位"
    let onDismiss: () -> Void
    let onPick: (FollowUser) -> Void

    @State private var friends: [FollowUser] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LobbyColors.ivory)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if loading {
                        Text("加载好友中…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    } else if friends.isEmpty {
                        Text("暂无好友可邀请 · 先去广场加几位好友吧")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(friends) { u in
                            HStack(spacing: 10) {
                                LobbyMemberAvatar(userId: u.userId, fallbackAvatar: u.avatar, size: 32)
                                Text(u.nickname ?? "好友")
                                    .font(.system(size: 12))
                                    .foregroundStyle(LobbyColors.ivory)
                                    .lineLimit(1)
                                Spacer()
                                Text("邀请")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(LobbyColors.crimson)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(u) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .task {
            friends = (try? await FollowAPI.friends().list) ?? []
            loading = false
        }
    }
}
