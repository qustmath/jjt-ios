import PhotosUI
import SwiftUI

/// 门店大厅（对齐安卓 StoreLobbyScreen，原型 /lobby/store/:id）：
/// 视频区 / 热力榜横幅 / 座位平面图（六态桌位）/ 图例 / 公屏四路发言 + 桌位抽屉全操作
/// + 表演区语音房（房间列表/开房/进房，对齐安卓票 20）。
struct StoreLobbyView: View {

    let storeId: Int64
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = StoreLobbyViewModel()
    @ObservedObject private var seatSession = LobbySeatSession.shared
    @ObservedObject private var imSession = LobbyImSession.shared
    @ObservedObject private var voiceSession = VoiceRoomSession.shared

    // 楼层/聊天显隐
    @State private var floorIdx = 0
    @State private var showChat = true
    @State private var highlight: Int64 = -1
    @State private var drawerTable: LobbyTable?
    @State private var spectate: LobbyTableSpectate?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var leaveConfirmFor: LobbyTable?
    // 桌态高亮自动熄灭
    @State private var highlightTask: Task<Void, Never>?
    // sys=seat 播报防抖
    @State private var seatEventTask: Task<Void, Never>?
    // 用户点「忽略」的邀请：本会话不再横幅展示（重进页面恢复，服务端到期自然消失）
    @State private var dismissedInviteIds: Set<Int64> = []
    // 公屏：点人资料卡、举报目标、发送中
    @State private var cardUser: LobbyCardTarget?
    @State private var reportTarget: LobbyChatMessage?
    @State private var sending = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    // 票 21/23 浮层：勿扰解锁面板、礼物面板（本桌成员 / 勿扰送礼档 / 单人）
    @State private var unlockFor: LobbyTable?
    @State private var giftCtx: LobbyGiftContext?
    // 未入座时的送礼入口：先选桌（收礼人须正入座某桌），再进礼物面板
    @State private var giftPickOpen = false
    // 表演区（语音房）：房间列表 / 开房 / 进房
    @State private var roomListOpen = false
    @State private var createRoomOpen = false
    @State private var voiceRoomNav: VoiceRoomNav?
    struct VoiceRoomNav: Identifiable {
        let roomId: Int64
        var id: Int64 { roomId }
    }
    // 入座扫码（扫平板入座码）：待入座的桌位 id
    @State private var scanForTableId: Int64?
    // 资料卡动作跳转
    @State private var giftNav: NightLobbyView.LobbyNavTarget?
    @State private var chatNav: NightLobbyView.LobbyNavTarget?
    @State private var showHeat = false

    var body: some View {
        ZStack {
            BlurredStoreBackdrop(cover: vm.store?.cover)

            VStack(spacing: 0) {
                topBar
                inviteBanner
                hostPendingBanner
                videosSection
                heatBanner
                planSection
                legendRow
                speechSection
            }

            // 浮层群（ZStack 顶层）
            if let u = cardUser { userCard(u) }
            if let msg = reportTarget { reportSheet(msg) }
            if let t = toast { LobbyToastView(text: t) }

            // 本店/全门店礼物动效接收端补播：门店大厅听本店群
            LobbyGiftBroadcastOverlay(listenGroupId: storeGroupId, myUserId: myUserId)
        }
        .task { await initialLoad() }
        .task { await LobbySeatSession.shared.heartbeatLoop() }
        .task {
            // 桌态轮询兜底（平面图 + 拼桌投影 20s 一拉）：IM 秒级刷新只覆盖坐席类变化（sys=seat 播报）；
            // 勿扰设置/取消、喊人拼桌、预定等桌态变更无系统播报，不轮询则他人视角永不更新
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                await vm.refreshPlan(storeId: storeId)
                await vm.refreshInvites(storeId: storeId)
                refreshHostPendingNow()
            }
        }
        .onAppear { LobbyImSession.shared.start() }
        .onDisappear { LobbyImSession.shared.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .jjtLobbySeatChanged)) { _ in
            // 入座/换桌/离桌后重拉平面图与拼桌投影（桌态、「我的桌」随之更新）
            Task { await vm.refreshPlan(storeId: storeId) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jjtLobbySeatEvent)) { _ in
            onSeatEvent()
        }
        .onChange(of: plansSignature) { _, _ in
            refreshDrawerTable()
        }
        .onChange(of: highlight) { _, newValue in
            // 高亮圈只在抽屉开着时当定位圈：关抽屉 3 秒后自动熄灭，兜住全部关闭路径
            highlightTask?.cancel()
            guard newValue != -1, drawerTable == nil else { return }
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled { highlight = -1 }
            }
        }
        .onChange(of: drawerTable) { _, newValue in
            highlightTask?.cancel()
            if newValue == nil, highlight != -1 {
                highlightTask = Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !Task.isCancelled { highlight = -1 }
                }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            sendPickedImage(item)
        }
        // 点桌抽屉（六态全操作）：用平面图里的最新同 id 桌（动作后 reloadPlan 会回流新桌态）
        .sheet(item: $drawerTable) { snapshot in
            let live = vm.plans.flatMap { $0.tables ?? [] }.first { $0.id == snapshot.id } ?? snapshot
            LobbyTableDrawerView(
                table: live,
                spectate: spectate,
                seat: seatSession.seat,
                myUserId: myUserId,
                hostApplies: vm.hostApplies.filter { $0.tableId == live.id },
                hostOrders: vm.hostOrders.filter { $0.tableId == live.id },
                myApply: vm.myApply,
                myOrders: vm.myOrders,
                onDismiss: { drawerTable = nil; highlight = -1 },
                onCheckIn: { startCheckIn(live) },
                onSwitch: { switchTo(live) },
                onLeave: { leaveConfirmFor = live },
                onApplyShare: { drawerTable = nil; startShareApply(live) },
                onUnlock: { unlockFor = live; Task { await vm.refreshMyOrders() } },
                onGiftToTable: { giftCtx = lobbyGiftContext(live) },
                onMemberClick: { m in cardUser = m.toCardTarget(tableId: live.id, tableNo: live.tableNo) },
                onTransfer: { uid in runDrawerAction(toastOK: "已转让桌主") { try await vm.transferHost(tableId: live.id, targetUserId: uid) } },
                onRemove: { uid in runDrawerAction(toastOK: "已移出该成员 · 对方回到罚站") { try await vm.removeMember(tableId: live.id, targetUserId: uid) } },
                onInvite: { uid in runDrawerAction(toastOK: "已邀请 · 到店核销后入座") { try await vm.invite(tableId: live.id, inviteeId: uid) } },
                onShout: { note in runDrawerAction(toastOK: "已喊人拼桌 · 本店滚动条高亮 3 分钟") { try await vm.shout(tableId: live.id, note: note) } },
                onStopShout: { runDrawerAction(toastOK: "已停止拼桌") { try await vm.stopShout(tableId: live.id) } },
                onEnableDnd: { note, silent, price in
                    runDrawerAction(toastOK: silent ? "已设为完全静音 · 不可付费解锁" : "已设为勿扰桌 · 解锁价 \(price ?? 0) 兔币") {
                        try await vm.enableDnd(tableId: live.id, note: note, silent: silent, unlockPrice: price)
                    }
                },
                onCancelDnd: { runDrawerAction(toastOK: "已取消勿扰") { try await vm.cancelDnd(tableId: live.id) } },
                onApproveApply: { a in runDrawerAction(toastOK: "已同意 \(a.userNickname ?? "该申请人") 入桌") { try await vm.approveApply(applyId: a.id, tableId: live.id) } },
                onRejectApply: { a in runDrawerAction(toastOK: "已拒绝 \(a.userNickname ?? "该申请人")") { try await vm.rejectApply(applyId: a.id, tableId: live.id) } },
                onAcceptOrder: { o in runDrawerAction(toastOK: "已接受解锁 · 收益已分账，对方可在到店后入座") { try await vm.acceptOrder(orderId: o.id) } },
                onRejectOrder: { o in runDrawerAction(toastOK: "已拒绝并原路退款") { try await vm.rejectOrder(orderId: o.id) } }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(LobbyColors.panel)
        }
        // 离桌确认：离桌后回罚站、需重新扫平板码才能再入座，故给一次确认
        .alert(
            "确定要离桌吗？",
            isPresented: Binding(get: { leaveConfirmFor != nil }, set: { if !$0 { leaveConfirmFor = nil } })
        ) {
            Button("离桌", role: .destructive) {
                leaveConfirmFor = nil
                drawerTable = nil
                Task {
                    do {
                        try await LobbySeatSession.shared.leave()
                        showToast("已离桌 · 回到罚站")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("离桌后回到罚站状态，想再入座需重新扫门店平板上的入座码。")
        }
        // 入座扫码（平板入座码）
        .fullScreenCover(item: Binding(
            get: { scanForTableId.map { ScanTarget(tableId: $0) } },
            set: { scanForTableId = $0?.tableId }
        )) { target in
            ScanView(onLobbyEntry: { token in
                scanForTableId = nil
                checkIn(token: token, tableId: target.tableId)
            })
        }
        // 勿扰付费解锁面板（三档并列）
        .sheet(item: $unlockFor) { t in
            LobbyDndUnlockSheet(
                table: t,
                hostNickname: drawerSpectate(t)?.members?.first { $0.host == true || $0.userId == t.hostUserId }?.nickname,
                myOrders: vm.myOrders,
                onDismiss: { unlockFor = nil },
                onGiftTier: {
                    unlockFor = nil
                    let hostName = drawerSpectate(t)?.members?
                        .first { $0.host == true || $0.userId == t.hostUserId }?.nickname
                    giftCtx = LobbyGiftContext(
                        tableId: t.id, tableNo: t.tableNo, scene: "lobby_dnd",
                        receivers: [], toName: hostName ?? "桌主")
                },
                onOrderPlaced: {
                    unlockFor = nil
                    showToast("解锁订单已支付 · 等桌主响应（10 分钟内，超时自动退款）")
                    Task { await vm.refreshMyOrders() }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(LobbyColors.panel)
        }
        // 送桌前先选桌（未入座路径）
        .sheet(isPresented: $giftPickOpen) {
            LobbyGiftTargetSheet(
                tables: vm.plans.flatMap { $0.tables ?? [] }
                    .filter { ($0.currentCount ?? 0) > 0 }
                    .sorted { ($0.currentCount ?? 0) > ($1.currentCount ?? 0) },
                onDismiss: { giftPickOpen = false },
                onPick: { t in
                    giftPickOpen = false
                    Task {
                        spectate = await vm.spectate(tableId: t.id)
                        giftCtx = lobbyGiftContext(t)
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(LobbyColors.panel)
        }
        // 礼物面板（三级广播）
        .sheet(item: $giftCtx) { ctx in
            LobbyGiftSheet(
                tableId: ctx.tableId,
                tableNo: ctx.tableNo,
                scene: ctx.scene,
                receivers: ctx.receivers,
                toName: ctx.toName,
                onClose: { giftCtx = nil },
                onSent: { gift in
                    showToast(ctx.scene == "lobby_dnd" ? "礼物已送出 · 达门槛即解锁" : "\(gift.name) 已送出")
                    // 送礼会改热力榜与桌况：刷新平面图 + 我的订单（勿扰档可能已发通行证）
                    Task {
                        await vm.refreshPlan(storeId: storeId)
                        await vm.refreshMyOrders()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(LobbyColors.panel)
        }
        // 热力榜
        .fullScreenCover(isPresented: $showHeat) {
            LobbyHeatView(storeId: storeId, storeName: vm.store?.name)
        }
        // 表演区房间列表（20s 轮询在 sheet 内）
        .sheet(isPresented: $roomListOpen) {
            VoiceRoomListSheet(
                storeId: storeId,
                rooms: vm.rooms,
                onRefresh: { Task { await vm.refreshRooms(storeId: storeId) } },
                onEnter: { room in
                    roomListOpen = false
                    voiceRoomNav = VoiceRoomNav(roomId: room.id)
                },
                onPreview: {
                    roomListOpen = false
                    voiceRoomNav = VoiceRoomNav(roomId: -1)
                },
                onCreate: {
                    roomListOpen = false
                    createRoomOpen = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(LobbyColors.panel)
        }
        // 开小房间（门槛全在服务端；建成功直接进房）
        .sheet(isPresented: $createRoomOpen) {
            VoiceRoomCreateSheet(
                storeId: storeId,
                onDismiss: { createRoomOpen = false },
                onCreated: { id in
                    createRoomOpen = false
                    Task { await vm.refreshRooms(storeId: storeId) }
                    voiceRoomNav = VoiceRoomNav(roomId: id)
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(LobbyColors.panel)
        }
        // 语音房（LiveKit + IM 群公屏 + 麦位管理）
        .fullScreenCover(item: $voiceRoomNav) { nav in
            VoiceRoomView(storeId: storeId, roomId: nav.roomId, storeName: vm.store?.name)
        }
        // 资料卡动作：礼物中心 / 私信
        .fullScreenCover(item: $giftNav) { nav in
            GiftCenterView(receiverId: nav.userId, receiverName: nav.nickname)
        }
        .fullScreenCover(item: $chatNav) { nav in
            ChatView(peerId: String(nav.userId), isGroup: false, title: nav.nickname)
        }
    }

    struct ScanTarget: Identifiable {
        let tableId: Int64
        var id: Int64 { tableId }
    }

    // MARK: - 派生状态

    private var myUserId: Int64 { TokenManager.shared.userId ?? -1 }

    /// 是否已在本店入座（发言免限频、换桌入口、发言框文案都用它）
    private var seatedHere: Bool {
        seatSession.seat?.state == "seated" && seatSession.seat?.storeId == storeId
    }

    /// 我的桌（入座的桌位）：礼物入口、桌主操作的锚点
    private var myTable: LobbyTable? {
        guard seatedHere, let tableId = seatSession.seat?.tableId else { return nil }
        return vm.plans.flatMap { $0.tables ?? [] }.first { $0.id == tableId }
    }

    private var amHost: Bool {
        myTable?.hostUserId == myUserId
    }

    private var storeGroupId: String? { vm.store?.avchatroomId }

    private var boardMessages: [LobbyChatMessage] {
        guard let gid = storeGroupId, !gid.isEmpty else { return [] }
        return imSession.messages.filter { $0.groupId == gid }
    }

    /// 平面图签名（桌态/人数/桌主变化触发抽屉回填）
    private var plansSignature: String {
        vm.plans.map { plan in
            let tables = (plan.tables ?? []).map { "\($0.id):\($0.status ?? ""):\($0.currentCount ?? 0):\($0.hostUserId ?? 0)" }
            return "\(plan.id)|\(tables.joined(separator: ","))"
        }.joined(separator: ";")
    }

    private var plan: LobbyFloorPlan? {
        let plans = vm.plans
        guard !plans.isEmpty else { return nil }
        return plans[min(floorIdx, plans.count - 1)]
    }

    private var online: Int {
        (plan?.tables ?? []).reduce(0) { $0 + ($1.currentCount ?? 0) }
    }

    // MARK: - 生命周期

    private func initialLoad() async {
        await vm.load(storeId: storeId)
        await vm.refreshInvites(storeId: storeId)
        await LobbySeatSession.shared.refresh()
        // 先补 IM 登录（大厅原本不登 IM，直接发言会 sdk not init），再入本店群；
        // 随后拉最近 50 条公屏历史前插（新用户进店回看，loadHistory 自身幂等）
        await LobbyImSession.shared.ensureImReady()
        LobbyImSession.shared.ensureStoreJoined(storeGroupId)
        await LobbyImSession.shared.loadHistory(storeGroupId)
    }

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toast = msg
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    /// 他人的坐席变化走 IM 系统播报（sys=seat）：收流到达后防抖刷平面图；
    /// 同一防抖里连自己的坐席态一起重拉：拼桌审批入座等远端坐席变化不经过本机动作。
    /// 勿扰开关/喊人/转让/申请等桌属性变更后端也发 sys=seat 播报，同一条流顺带刷桌主待处理。
    private func onSeatEvent() {
        seatEventTask?.cancel()
        seatEventTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await vm.refreshPlan(storeId: storeId)
            await LobbySeatSession.shared.refresh()
            refreshHostPendingNow()
        }
    }

    /// 桌主待处理刷新：申请/解锁确认原本只在打开抽屉时拉，桌主不开抽屉就完全无感知。
    private func refreshHostPendingNow() {
        guard seatSession.isSeated, seatSession.seat?.storeId == storeId,
              let tableId = seatSession.seat?.tableId else { return }
        guard let table = vm.plans.flatMap({ $0.tables ?? [] }).first(where: { $0.id == tableId }) else { return }
        if table.hostUserId == myUserId {
            Task { await vm.loadTableOps(tableId: table.id, status: table.status, isHost: true) }
        }
    }

    /// 抽屉开着时桌面快照要跟平面图刷新走：drawerTable 是开抽屉那刻的旧对象，
    /// 不回填则开着抽屉的一方永远看不到转让桌主等变更。
    private func refreshDrawerTable() {
        guard let current = drawerTable else { return }
        guard let fresh = vm.plans.flatMap({ $0.tables ?? [] }).first(where: { $0.id == current.id }) else { return }
        drawerTable = fresh
        Task {
            if let result = await vm.spectate(tableId: fresh.id) {
                if drawerTable?.id == fresh.id { spectate = result }
            }
            let isHost = seatSession.seat?.tableId == fresh.id && fresh.hostUserId == myUserId
            await vm.loadTableOps(tableId: fresh.id, status: fresh.status, isHost: isHost)
        }
    }

    // MARK: - 入座/换桌/拼桌/邀请

    /// 入座入口：进扫码页（token + 桌位 + GPS 一起提交；GPS 在 checkIn 内采集）
    private func startCheckIn(_ t: LobbyTable) {
        drawerTable = nil
        scanForTableId = t.id
    }

    private func checkIn(token: String, tableId: Int64) {
        Task {
            do {
                try await LobbySeatSession.shared.checkIn(token: token, tableId: tableId)
                showToast("入座成功")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// 同店换桌（服务端原子「离旧+入新」，不重复核验门槛）；跨店由服务端拒绝并提示
    private func switchTo(_ t: LobbyTable) {
        drawerTable = nil
        Task {
            do {
                try await LobbySeatSession.shared.switchTo(tableId: t.id)
                showToast("已换到 \(t.tableNo ?? "该桌") 桌")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// 提交拼桌申请：申请瞬间 GPS 作 3km 围栏证据，服务端复核实名 + 桌态 + 容量 + 一人一申请。
    /// 取不到定位不提交必被拒的请求，直接提示重试（与入座同口径）。
    private func startShareApply(_ t: LobbyTable) {
        Task {
            do {
                guard let fix = await LobbyLocator.shared.currentFix() else {
                    throw APIError.business(code: -1, message: "定位失败：请在开阔处重试（拼桌申请需核验是否在门店 3 公里内）")
                }
                try await LobbyAPI.shareApply(
                    tableId: t.id,
                    longitude: fix.coordinate.longitude,
                    latitude: fix.coordinate.latitude)
                showToast("拼桌申请已提交 · 等桌主审批（30 分钟窗口）")
                await vm.loadTableOps(tableId: t.id, status: LobbyTableStatus.sharing.rawValue, isHost: false)
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    // MARK: - 抽屉动作壳

    /// 桌主动作成功后重拉抽屉的实时桌况（成员入桌/移出后人数与成员列表都变了）
    private func runDrawerAction(toastOK: String? = nil, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                if let toastOK { showToast(toastOK) }
                refreshDrawerSpectate()
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// 围观桌况限定在当前桌（spectate 是单桌快照，防串桌）
    private func drawerSpectate(_ t: LobbyTable) -> LobbyTableSpectate? {
        guard let s = spectate, s.tableId == t.id else { return nil }
        return s
    }

    private func refreshDrawerSpectate() {
        guard let t = drawerTable else { return }
        Task {
            if let r = await vm.spectate(tableId: t.id), drawerTable?.id == t.id {
                spectate = r
            }
        }
    }

    // MARK: - 礼物上下文

    /// 本桌礼物面板上下文：收礼人取抽屉里的围观快照（排除自己）；
    /// 面板打开时会再拉一次围观数据校正——服务端按「发送时正入座该桌」判定，快照过期只影响候选列表。
    private func lobbyGiftContext(_ t: LobbyTable) -> LobbyGiftContext {
        LobbyGiftContext(
            tableId: t.id,
            tableNo: t.tableNo,
            scene: "lobby",
            receivers: (drawerSpectate(t)?.members ?? [])
                .filter { $0.userId != myUserId }
                .map { GiftReceiver(id: $0.userId, name: $0.nickname ?? "本桌用户", avatar: $0.avatar) },
            toName: "\(t.tableNo ?? "本桌") 桌成员")
    }

    /// 单人送礼上下文（资料卡的「送礼 / 请喝一杯」）：收礼人只有卡上这一位，面板会自动选中
    private func singleReceiverContext(tableId: Int64, _ u: LobbyCardTarget) -> LobbyGiftContext {
        LobbyGiftContext(
            tableId: tableId,
            tableNo: u.tableNo,
            scene: "lobby",
            receivers: [GiftReceiver(id: u.userId, name: u.nickname, avatar: u.avatar)],
            toName: u.nickname)
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.05))
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.store?.name ?? "门店大厅")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
                Text("座位图 · 点桌看成员与拼桌")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(LobbyColors.seated).frame(width: 6, height: 6)
                Text("\(online)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                Text("入座")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LobbyColors.gold.opacity(0.06))
            .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
            // 进行中语音房入口：「留在房里」退出页面但未退房时常驻提示，点击直接回房；
            // 退房/解散即消失。只在本店房间显示
            if let p = voiceSession.presence, p.storeId == storeId {
                HStack(spacing: 4) {
                    Circle().fill(LobbyColors.crimson).frame(width: 6, height: 6)
                    Text("在语音房")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(LobbyColors.crimson.opacity(0.95))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(LobbyColors.crimson.opacity(0.14))
                .overlay(Capsule().stroke(LobbyColors.crimson.opacity(0.45), lineWidth: 1))
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture { voiceRoomNav = VoiceRoomNav(roomId: p.roomId) }
            }
            LobbyIconAction(icon: "square.and.arrow.up", tint: .white.opacity(0.6)) {
                showToast("门店分享链接另立票")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 桌位邀请横幅

    @ViewBuilder
    private var inviteBanner: some View {
        if let inv = vm.myInvites.first(where: {
            !dismissedInviteIds.contains($0.id) && !(seatedHere && seatSession.seat?.tableId == $0.tableId)
        }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(inv.inviterNickname ?? "好友") 邀你拼「\(inv.tableNo ?? "")」桌")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(LobbyColors.goldLight)
                        .lineLimit(1)
                    Text("接受直接入座，无需桌位码 · 剩 \(remainingMinutes(inv.expireTime)) 分钟")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Text("忽略")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissedInviteIds.insert(inv.id) }
                Text("接受")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0x24/255, green: 0x1A/255, blue: 0x06/255))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(LobbyColors.gold.opacity(0.92))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { startInviteAccept(inv) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LobbyColors.gold.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(LobbyColors.gold.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    /// 接受邀请：核销瞬间 GPS 作 3km 围栏证据，门槛复核全在服务端
    private func startInviteAccept(_ invite: LobbyTableInvite) {
        Task {
            do {
                guard let fix = await LobbyLocator.shared.currentFix() else {
                    throw APIError.business(code: -1, message: "定位失败：请在开阔处重试（接受邀请需核验是否在门店 3 公里内）")
                }
                try await vm.acceptInvite(
                    invite,
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude)
                showToast("已接受邀请 · 入座「\(invite.tableNo ?? "")」桌")
                // 本机动作不经 IM 播报回环，坐席会话要自己刷（否则金环还画在旧位）
                await LobbySeatSession.shared.refresh()
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// 剩余分钟（向上取整）
    private func remainingMinutes(_ expireTime: Int64?) -> Int {
        guard let expireTime else { return 0 }
        let seconds = expireTime / 1000 - Int64(Date().timeIntervalSince1970)
        return max(1, Int(ceil(Double(seconds) / 60.0)))
    }

    // MARK: - 桌主待处理横幅

    @ViewBuilder
    private var hostPendingBanner: some View {
        if drawerTable == nil, let hostTable = myTable, amHost {
            // 申请适用于拼桌/有人桌，解锁确认只属于勿扰桌——按当前桌态过滤，防上一态的残留计数
            let status = LobbyTableStatus.of(hostTable.status)
            let cues: [String] = [
                (!vm.hostApplies.isEmpty && (status == .sharing || status == .occupied))
                    ? "拼桌申请×\(vm.hostApplies.count)" : nil,
                (!vm.hostOrders.isEmpty && status == .dnd)
                    ? "解锁确认×\(vm.hostOrders.count)" : nil,
            ].compactMap { $0 }
            if !cues.isEmpty {
                HStack {
                    Text("\(cues.joined(separator: "、"))待处理 · 点击打开桌位")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LobbyColors.goldLight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(LobbyColors.gold.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LobbyColors.gold.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { openDrawer(hostTable) }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - 门店视频区（只读列表）

    @ViewBuilder
    private var videosSection: some View {
        if !vm.videos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.videos) { v in
                        VStack(alignment: .leading, spacing: 3) {
                            ZStack {
                                if let cover = v.videoCover, !cover.isEmpty, let url = webImageURL(cover) {
                                    WebImage(url: url) {
                                        Color(red: 0x14/255, green: 0x10/255, blue: 0x18/255)
                                    }
                                } else {
                                    Color(red: 0x14/255, green: 0x10/255, blue: 0x18/255)
                                }
                                LinearGradient(
                                    colors: [Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.1), Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.7)],
                                    startPoint: .top, endPoint: .bottom
                                )
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(LobbyColors.goldLight)
                                VStack {
                                    HStack {
                                        HStack(spacing: 2) {
                                            Image(systemName: "record.circle").font(.system(size: 6)).foregroundStyle(.white)
                                            Text("LIVE").font(.system(size: 6.5, weight: .bold)).foregroundStyle(.white)
                                        }
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(LobbyColors.crimson)
                                        .cornerRadius(3)
                                        Spacer()
                                    }
                                    .padding(4)
                                    Spacer()
                                    if let sec = v.durationSec {
                                        HStack {
                                            Spacer()
                                            Text("\(sec)s")
                                                .font(.system(size: 6.5))
                                                .foregroundStyle(.white.opacity(0.8))
                                                .padding(.horizontal, 3)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(3)
                                                .padding(3)
                                        }
                                    }
                                }
                            }
                            .frame(width: 92, height: 52)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { showToast("视频播放待接入（仅只读列表）") }
                            Text(v.title ?? "")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                        .frame(width: 92)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
        }
    }

    // MARK: - 热力榜横幅

    private var heatBanner: some View {
        Button {
            showHeat = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(LobbyColors.goldPale)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("门店排行榜")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(LobbyColors.ivory)
                        HStack(spacing: 3) {
                            Circle().fill(LobbyColors.seated).frame(width: 4, height: 4)
                            Text("实时")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(LobbyColors.seated)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(LobbyColors.seated.opacity(0.4), lineWidth: 1))
                    }
                    Text("总榜 / 周榜 / 实时热力 · 送礼拼桌组局均可上榜")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                // 前三迷你领奖台（实时榜）
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(vm.heatTop.prefix(3).enumerated()), id: \.element.id) { i, item in
                        AppAvatar(url: item.avatar, size: i == 0 ? 32 : 25)
                            .offset(y: i == 0 ? -4 : 0)
                            .overlay(Circle().stroke(i == 0 ? LobbyColors.goldLight : LobbyColors.gold.opacity(0.5), lineWidth: i == 0 ? 2 : 1))
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(LobbyColors.gold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(LinearGradient(colors: [Color(red: 0x18/255, green: 0x10/255, blue: 0x0A/255).opacity(0.96), Color(red: 0x28/255, green: 0x0C/255, blue: 0x12/255).opacity(0.96)], startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LobbyColors.crimson.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - 主区：座位平面图

    private var planSection: some View {
        ZStack {
            Color(red: 0x0C/255, green: 0x0A/255, blue: 0x0D/255)
                .contentShape(Rectangle())
                .onTapGesture { showChat.toggle() }

            if vm.loading && vm.plans.isEmpty {
                ProgressView().tint(LobbyColors.gold)
            } else if vm.plans.isEmpty, let err = vm.error {
                LobbyLoadFailed(message: err, onRetry: { Task { await vm.load(storeId: storeId) } })
            } else if vm.plans.isEmpty {
                Text("该门店尚未配置平面图")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                planContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var planContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 底图
                if let image = plan?.image, !image.isEmpty, let url = webImageURL(image) {
                    WebImage(url: url) { Color.clear }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.3)

                // 桌位标记（按百分比坐标）
                ForEach(plan?.tables ?? []) { t in
                    let x = min(max((t.posX ?? 0) / 100, 0), 1)
                    let y = min(max((t.posY ?? 0) / 100, 0), 1)
                    LobbyTableMarker(
                        table: t,
                        highlighted: highlight == t.id,
                        mine: seatedHere && seatSession.seat?.tableId == t.id
                    )
                    .position(x: w * x, y: h * y)
                    .onTapGesture { openDrawer(t) }
                }

                // 图内顶部：拼桌/组局滚动条
                VStack {
                    LobbyGapMarquee(gaps: vm.gaps) { gap in
                        // 跨楼层缺口：先从全楼层查桌，定位到桌后再切层 + 开抽屉，一次到位
                        let target = vm.plans.first { p in (p.tables ?? []).contains { $0.id == gap.tableId } }
                        if let target, let t = (target.tables ?? []).first(where: { $0.id == gap.tableId }) {
                            floorIdx = vm.plans.firstIndex(where: { $0.id == target.id }) ?? floorIdx
                            openDrawer(t)
                        } else {
                            showToast("该桌位不在平面图投影内")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    Spacer()
                }

                // 图内左上：楼层切换
                if vm.plans.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(vm.plans.enumerated()), id: \.element.id) { i, f in
                            Text(f.label ?? "F\(i + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(i == floorIdx ? .white : .white.opacity(0.55))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background {
                                    if i == floorIdx {
                                        Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                                    } else {
                                        Capsule().fill(Color(red: 0x10/255, green: 0x07/255, blue: 0x0A/255).opacity(0.6))
                                            .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
                                    }
                                }
                                .contentShape(Capsule())
                                .onTapGesture { floorIdx = i }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 8)
                    .padding(.top, 44)
                }

                // 表演区热点：开启小房间（列表/开房/进房）
                if let p = plan {
                    let sx = min(max((p.stageX ?? 50) / 100, 0), 1)
                    let sy = min(max((p.stageY ?? 50) / 100, 0), 1)
                    VStack(spacing: 4) {
                        LobbyPulsingDot()
                        HStack(spacing: 3) {
                            Image(systemName: "mic")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                            Text("表演区 · 开启小房间")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(LinearGradient(colors: [LobbyColors.crimson.opacity(0.85), LobbyColors.crimsonTail.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().stroke(LobbyColors.goldLight.opacity(0.7), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .position(x: w * sx, y: h * sy)
                    .onTapGesture {
                        Task { await vm.refreshRooms(storeId: storeId) }
                        roomListOpen = true
                    }
                }

                // 图内底部：公屏消息流（点击图面空白显隐）
                if showChat {
                    VStack {
                        Spacer()
                        LobbyChatList(
                            messages: boardMessages,
                            showStorePrefix: false,
                            emptyText: "本店公屏暂无消息 · 说点什么都行 ✨",
                            onUserClick: { cardUser = $0.toCardTarget() },
                            onMessageLongPress: { msg in
                                if msg.canReport(myUserId: myUserId) { reportTarget = msg }
                            }
                        )
                        .frame(height: h * 0.67 - 8)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                } else {
                    VStack {
                        Spacer()
                        HStack {
                            Text("💬 聊天已隐藏 · 点击图面显示")
                                .font(.system(size: 9))
                                .foregroundStyle(LobbyColors.goldLight.opacity(0.75))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0x10/255, green: 0x07/255, blue: 0x0A/255).opacity(0.55))
                        .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                }
            }
        }
    }

    private func openDrawer(_ t: LobbyTable) {
        highlight = t.id
        drawerTable = t
        spectate = nil
        Task {
            if let result = await vm.spectate(tableId: t.id), drawerTable?.id == t.id {
                spectate = result
            }
        }
        let isHost = seatSession.seat?.tableId == t.id && t.hostUserId == myUserId
        Task { await vm.loadTableOps(tableId: t.id, status: t.status, isHost: isHost) }
    }

    // MARK: - 图例

    private var legendRow: some View {
        HStack(spacing: 0) {
            ForEach(LobbyTableStatus.allCases, id: \.rawValue) { s in
                HStack(spacing: 3) {
                    Circle().fill(LobbyTableStyle.color(s)).frame(width: 6, height: 6)
                    Text(s.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.trailing, 10)
            }
            HStack(spacing: 3) {
                Circle()
                    .stroke(LobbyColors.goldLight, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                Text("我的桌")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Text("点击空白显隐聊天")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - 底部发言区

    private var speechSection: some View {
        LobbySpeechInput(
            hint: lobbyInputHint(seatedHere: seatedHere, state: seatSession.seat?.state, tableNo: seatSession.seat?.tableNo),
            sending: sending,
            onSendText: { text in
                sending = true
                Task {
                    let err = await LobbyImSession.shared.sendText(groupId: storeGroupId, text: text, seatedInStore: seatedHere)
                    sending = false
                    if let err { showToast(err) }
                }
            },
            onSendSticker: { pack, name in
                Task {
                    if let err = await LobbyImSession.shared.sendSticker(groupId: storeGroupId, pack: pack, name: name, seatedInStore: seatedHere) {
                        showToast(err)
                    }
                }
            },
            onPickImage: { showPicker = true },
            onGift: {
                // 礼物面板：入座者直接对本桌开面板；未入座引导走选桌（收礼人须正入座某桌）
                if let t = myTable {
                    giftCtx = lobbyGiftContext(t)
                } else {
                    giftPickOpen = true
                }
            },
            onVoiceStop: { result in
                guard let path = result.path else {
                    if let e = result.error { showToast(e) }
                    return
                }
                sending = true
                Task {
                    let err = await LobbyImSession.shared.sendVoice(groupId: storeGroupId, path: path, seconds: result.seconds, seatedInStore: seatedHere)
                    sending = false
                    if let err { showToast(err) }
                }
            },
            onError: { showToast($0) }
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - 发图

    private func sendPickedImage(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let jpeg = ui.jpegData(compressionQuality: 0.85) else {
                showToast("图片读取失败，换一张试试")
                return
            }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("lobby_img_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
            do {
                try jpeg.write(to: file)
            } catch {
                showToast("图片读取失败，换一张试试")
                return
            }
            sending = true
            let err = await LobbyImSession.shared.sendImage(groupId: storeGroupId, path: file.path, seatedInStore: seatedHere)
            sending = false
            if let err { showToast(err) }
        }
    }

    // MARK: - 浮层

    /// 点人资料卡：同桌成员、榜单人物复用同一卡片
    private func userCard(_ u: LobbyCardTarget) -> some View {
        LobbyUserCard(
            nickname: u.nickname,
            avatar: u.avatar,
            tableNo: u.tableNo,
            seated: u.seated,
            isSelf: u.userId == myUserId,
            stateText: u.stateText,
            onDismiss: { cardUser = nil },
            onGift: {
                cardUser = nil
                // 知道对方在哪桌 → 走大厅礼物面板（收礼人须正入座该桌，服务端复核）；
                // 否则退礼物中心（与聊天/帖子同一路径）
                if let tid = u.tableId {
                    giftCtx = singleReceiverContext(tableId: tid, u)
                } else {
                    giftNav = .init(userId: u.userId, nickname: u.nickname)
                }
            },
            onChat: {
                cardUser = nil
                chatNav = .init(userId: u.userId, nickname: u.nickname)
            },
            onFollow: {
                cardUser = nil
                Task {
                    do {
                        _ = try await FollowAPI.friendApply(userId: u.userId)
                        showToast("好友申请已发送")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            },
            onInviteShare: {
                cardUser = nil
                guard amHost, let myTable else {
                    showToast("仅本桌桌主可邀请拼桌")
                    return
                }
                Task {
                    do {
                        try await vm.invite(tableId: myTable.id, inviteeId: u.userId)
                        showToast("已邀请 \(u.nickname) · 到店核销后入座")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            },
            onDrink: {
                // 请喝一杯 = 礼物体系里的饮品礼物（同一面板，不另开路径）
                cardUser = nil
                if let tid = u.tableId {
                    giftCtx = singleReceiverContext(tableId: tid, u)
                } else {
                    giftNav = .init(userId: u.userId, nickname: u.nickname)
                }
            },
            // 举报以公屏消息为凭据：只有聊天消息来源的卡带消息对象
            onReport: u.message.map { msg in
                { cardUser = nil; reportTarget = msg }
            }
        )
    }

    private func reportSheet(_ msg: LobbyChatMessage) -> some View {
        LobbyReportSheet(
            onDismiss: { reportTarget = nil },
            onSubmit: { reason in
                reportTarget = nil
                Task {
                    do {
                        try await LobbyImSession.shared.report(msgId: msg.msgId, reason: reason, detail: nil)
                        showToast("举报已提交，平台会核查处置")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            }
        )
    }
}

// MARK: - 零件

/// 桌位标记：圆角方块 + 六态配色（拼桌脉冲 / 组局呼吸 / 勿扰降透明 + 锁）；`mine` = 我入座的桌
struct LobbyTableMarker: View {
    let table: LobbyTable
    var highlighted: Bool
    var mine: Bool

    private var status: LobbyTableStatus { LobbyTableStatus.of(table.status) }
    @State private var breathe = false
    @State private var pulse = false

    var body: some View {
        let color = LobbyTableStyle.color(status)
        ZStack {
            if highlighted {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 34, height: 34)
            }
            // 我的桌：常显金色双环（入座成功的图面标识）
            if mine {
                Circle()
                    .stroke(LobbyColors.goldLight, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
            }
            HStack(spacing: 2) {
                if status == .dnd {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(color)
                }
                Text(table.tableNo ?? "?")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: 0x06/255, green: 0x05/255, blue: 0x08/255).opacity(0.82))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(markerAlpha), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .scaleEffect(markerScale)
        .onAppear { startAnimationIfNeeded() }
    }

    private var markerAlpha: Double {
        status == .grouping ? (breathe ? 1 : 0.45) : (status == .dnd ? 0.65 : 1)
    }

    private var markerScale: CGFloat {
        status == .sharing ? (pulse ? 1.12 : 1) : 1
    }

    /// 只有需要动画的桌位才启动 repeatForever 动画
    private func startAnimationIfNeeded() {
        switch status {
        case .grouping where !breathe:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
        case .sharing where !pulse:
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                pulse = true
            }
        default:
            break
        }
    }
}

/// 表演区呼吸红点
struct LobbyPulsingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(LobbyColors.crimson.opacity(pulse ? 1 : 0.35))
            .frame(width: 10, height: 10)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// 图内拼桌/组局滚动条（投影；溢出时自动横向滚动，可点定位）
struct LobbyGapMarquee: View {
    let gaps: [LobbyShareGap]
    let onClick: (LobbyShareGap) -> Void

    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        if gaps.isEmpty {
            Text("今夜暂无拼桌，虚位以待你来开局 ✨")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(red: 0x10/255, green: 0x07/255, blue: 0x0A/255).opacity(0.6))
                .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
        } else {
            GeometryReader { geo in
                let overflows = contentWidth > geo.size.width
                HStack(spacing: 20) {
                    ForEach(gaps) { g in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(g.justShouted == true ? LobbyColors.crimson : Color(red: 0xA0/255, green: 0x8B/255, blue: 0xFF/255))
                                .frame(width: 8, height: 8)
                            Text("\(g.tableNo ?? "?")桌")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(LobbyColors.ivory)
                            Text((g.note?.isEmpty == false ? g.note! : "拼桌中") + " · 差\(g.gap ?? 0)位")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color(red: 0xA0/255, green: 0x8B/255, blue: 0xFF/255))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onClick(g) }
                        .fixedSize()
                    }
                }
                .background(
                    // 量内容宽度：超出容器才启用跑马灯
                    GeometryReader { c in
                        Color.clear.onAppear { contentWidth = c.size.width }
                            .onChange(of: c.size.width) { _, newW in contentWidth = newW }
                    }
                )
                .offset(x: overflows ? offset : 0)
                .onChange(of: contentWidth) { _, _ in
                    // 内容宽度就绪后再启动（onAppear 时测量可能还没回来）
                    startMarquee()
                }
                .onAppear {
                    containerWidth = geo.size.width
                    startMarquee()
                }
                .onChange(of: geo.size.width) { _, newW in
                    containerWidth = newW
                }
            }
            .frame(height: 30)
            .background(Color(red: 0x10/255, green: 0x07/255, blue: 0x08/255).opacity(0.28))
            .overlay(Capsule().stroke(LobbyColors.crimson.opacity(0.25), lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    /// 自动横向滚动（约 40pt/s），滚出右缘后回卷；已启动不重复启动
    private func startMarquee() {
        guard offset == 0, contentWidth > 0, contentWidth > containerWidth else { return }
        let distance = contentWidth + 20
        let duration = Double(distance) / 40.0
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}
