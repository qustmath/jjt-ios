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
    // 表演区（语音房）：进房
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
    // 全屏公屏（v75 chatFocus）：图内点「展开公屏」进入，返回键/「回到座位图」退出；换店重置
    @State private var chatFocus = false
    @State private var chatFocusInput = false

    // 浮层单宿主：同一视图链上多个 .sheet 会排队（第二个要等第一个收起才弹——
    // 「点送礼 10~20 秒才出面板」的根因）。收敛成一个 item 枚举，切换 case 即换内容：
    // 抽屉→送礼/勿扰解锁、选桌→送礼、房间列表→开房全部零延迟。
    @State private var sheet: LobbySheet?

    private enum LobbySheet: Identifiable {
        case drawer(LobbyTable)      // 桌位抽屉（六态全操作）
        case unlock(LobbyTable)      // 勿扰付费解锁面板
        case giftPick                // 未入座送礼先选桌
        case gift(LobbyGiftContext)  // 礼物面板（本桌成员 / 勿扰送礼档 / 单人）
        case rank                    // 本店热力榜
        case video                   // 店长视频
        case roomList                // 表演区小房间列表
        case createRoom              // 开小房间

        var id: String {
            switch self {
            case .drawer(let t): return "drawer-\(t.id)"
            case .unlock(let t): return "unlock-\(t.id)"
            case .giftPick: return "giftPick"
            case .gift(let c): return "gift-\(c.id)"
            case .rank: return "rank"
            case .video: return "video"
            case .roomList: return "roomList"
            case .createRoom: return "createRoom"
            }
        }
    }

    /// 抽屉桌面快照（只读视图：平面图刷新回填、围观拉取等沿用旧调用点）
    private var drawerTable: LobbyTable? {
        if case .drawer(let t) = sheet { return t }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ① 全屏平面图即页面（场景化）：铺满 + 上下压暗氛围遮罩
                planScene
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                atmosphereDim

                // ② HUD：左上返回 + 右上三按钮（店长视频 / 排行榜 / 小房间）
                backHud
                hudButtons

                // ③ 左缘：楼层切换（竖排）+ 浮动招募卡（v75 游戏任务追踪式）
                if vm.plans.count > 1 {
                    floorRail(topInset: geo.size.height * 0.11)
                }
                if !vm.gaps.isEmpty {
                    recruitmentLayer(topInset: geo.size.height * 0.18)
                }

                // ④ 底部：图内聊天/显隐条 + 邀请/桌主待办 + 店名状态 + 输入（浮在场景上）
                VStack(spacing: 0) {
                    Spacer()
                    if chatFocus {
                        EmptyView()
                    } else if showChat && plan != nil {
                        planChatPanel
                    } else if plan != nil {
                        hiddenChatBar
                    }
                    inviteBanner
                    hostPendingBanner
                    storeStatusLine
                    speechSection
                }

                // 全屏公屏（v75 chatFocus）：不是新页面，是从底部升起的浮层；关闭时向下收起
                if chatFocus {
                    fullScreenChatLayer
                        .transition(.move(edge: .bottom))
                }

                // 浮层群（ZStack 顶层）
                if let u = cardUser { userCard(u) }
                if let msg = reportTarget { reportSheet(msg) }
                if let t = toast { LobbyToastView(text: t) }

                // 本店/全门店礼物动效接收端补播：门店大厅听本店群
                LobbyGiftBroadcastOverlay(listenGroupId: storeGroupId, myUserId: myUserId)
            }
            .animation(.easeOut(duration: 0.28), value: chatFocus)
            .lobbyPageEnter()
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
            guard newValue != -1, sheet == nil else { return }
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled { highlight = -1 }
            }
        }
        .onChange(of: sheet?.id) { _, newValue in
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
        .sheet(item: $sheet) { route in
            switch route {
            case .drawer(let snapshot):
                drawerSheetBuilder(snapshot)
            case .unlock(let t):
                unlockSheetBuilder(t)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(LobbyColors.panel)
            case .giftPick:
                giftTargetSheetBuilder
                    .presentationDetents([.medium])
                    .presentationBackground(LobbyColors.panel)
            case .gift(let ctx):
                giftSheetBuilder(ctx)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(LobbyColors.panel)
            case .rank:
                LobbyRankSheet(storeId: storeId) { item in
                    sheet = nil
                    cardUser = LobbyCardTarget(userId: item.userId ?? 0,
                                               nickname: item.nickname ?? "本店用户",
                                               avatar: item.avatar)
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(LobbyColors.panel)
            case .video:
                LobbyVideoSheet(videos: vm.videos)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(LobbyColors.panel)
            case .roomList:
                roomListSheetBuilder
                    .presentationDetents([.medium, .large])
                    .presentationBackground(LobbyColors.panel)
            case .createRoom:
                createRoomSheetBuilder
                    .presentationDetents([.medium])
                    .presentationBackground(LobbyColors.panel)
            }
        }
        // 离桌确认：离桌后回罚站、需重新扫平板码才能再入座，故给一次确认
        .alert(
            "确定要离桌吗？",
            isPresented: Binding(get: { leaveConfirmFor != nil }, set: { if !$0 { leaveConfirmFor = nil } })
        ) {
            Button("离桌", role: .destructive) {
                leaveConfirmFor = nil
                sheet = nil
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
        sheet = .drawer(fresh)
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
        sheet = nil
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
        sheet = nil
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
                    throw APIError.business(code: -1, message: "定位失败：请在开阔处重试（拼桌申请需核验是否在门店内）")
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
                    throw APIError.business(code: -1, message: "定位失败：请在开阔处重试（接受邀请需核验是否在门店内）")
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

    // MARK: - 场景分层（拆出 body，编译器对超大表达式会超时）

    /// 上下压暗氛围遮罩
    private var atmosphereDim: some View {
        LinearGradient(stops: [
            .init(color: LobbyColors.bg.opacity(0.55), location: 0),
            .init(color: LobbyColors.bg.opacity(0.12), location: 0.22),
            .init(color: LobbyColors.bg.opacity(0.10), location: 0.55),
            .init(color: LobbyColors.bg.opacity(0.88), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .bottom)
    }

    /// 左上返回（全屏公屏开着时先收公屏）
    private var backHud: some View {
        VStack {
            HStack {
                Button {
                    if chatFocus {
                        closeFullScreenChat()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Color(red: 0x0A/255, green: 0x08/255, blue: 0x0B/255).opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 12)
            Spacer()
        }
    }

    /// 右上三 HUD 钮：店长视频 / 排行榜 / 小房间
    private var hudButtons: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HudIconButton(icon: "film", label: "店长视频", badge: !vm.videos.isEmpty ? "LIVE" : nil) {
                        sheet = .video
                    }
                    HudIconButton(icon: "trophy.fill", label: "排行榜", live: !vm.heatTop.isEmpty) {
                        sheet = .rank
                    }
                    HudIconButton(icon: "mic.fill", label: "小房间",
                                  live: voiceSession.presence?.storeId == storeId) {
                        Task { await vm.refreshRooms(storeId: storeId) }
                        sheet = .roomList
                    }
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
            Spacer()
        }
    }

    /// 左缘楼层切换（竖排）
    private func floorRail(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.leading, 10)
        .padding(.top, topInset)
    }

    /// 左缘招募呼吸卡
    private func recruitmentLayer(topInset: CGFloat) -> some View {
        LobbyRecruitmentPanel(
            gaps: vm.gaps,
            plans: vm.plans,
            onLocate: { gap in
                // 跨楼层缺口：先从全楼层查桌，定位到桌后再切层 + 开抽屉，一次到位
                let target = vm.plans.first { p in (p.tables ?? []).contains { $0.id == gap.tableId } }
                if let target, let t = (target.tables ?? []).first(where: { $0.id == gap.tableId }) {
                    floorIdx = vm.plans.firstIndex(where: { $0.id == target.id }) ?? floorIdx
                    openDrawer(t)
                } else {
                    showToast("该桌位不在平面图投影内")
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 8)
        .padding(.top, topInset)
    }

    /// 全屏公屏浮层
    private var fullScreenChatLayer: some View {
        LobbyFullScreenChat(
            storeName: vm.store?.name ?? "门店",
            online: online,
            backdrop: plan?.image ?? vm.store?.cover,
            messages: boardMessages,
            inputHint: lobbyInputHint(seatedHere: seatedHere, state: seatSession.seat?.state, tableNo: seatSession.seat?.tableNo),
            sending: sending,
            autoFocusInput: chatFocusInput,
            onBackToPlan: { closeFullScreenChat() },
            onUserClick: { cardUser = $0.toCardTarget() },
            onReportRequest: { msg in
                if msg.canReport(myUserId: myUserId) { reportTarget = msg }
            },
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
                if let t = myTable {
                    sheet = .gift(lobbyGiftContext(t))
                } else {
                    sheet = .giftPick
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
    }

    // MARK: - 场景：全屏平面图（v75 场景化——平面图即页面）

    @ViewBuilder
    private var planScene: some View {
        if vm.loading && vm.plans.isEmpty {
            ProgressView().tint(LobbyColors.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.plans.isEmpty, let err = vm.error {
            LobbyLoadFailed(message: err, onRetry: { Task { await vm.load(storeId: storeId) } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.plans.isEmpty {
            Text("该门店尚未配置平面图")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            planContent
        }
    }

    private var planContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // 顶左对齐：桌位/表演区用顶左锚点 offset（对齐安卓 offset(x-22,y-12) 口径，
            // .position 的中心锚会随桌号文字长度左右漂移）
            ZStack(alignment: .topLeading) {
                // 底图：拉伸铺满（对齐安卓 ContentScale.FillBounds）——桌号按容器百分比定位，
                // 图若等比留边/裁边，图上桌子和百分比桌号就整体错位（两端向中间漂移）
                if let image = plan?.image, !image.isEmpty, let url = webImageURL(image) {
                    WebImage(url: url, stretch: true) { Color.clear }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // 图面压暗（对齐安卓四段垂直渐变）
                LinearGradient(stops: [
                    .init(color: Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.60), location: 0),
                    .init(color: Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.20), location: 0.22),
                    .init(color: Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.16), location: 0.62),
                    .init(color: Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.80), location: 1),
                ], startPoint: .top, endPoint: .bottom)

                // 桌位标记（按百分比坐标）
                ForEach(plan?.tables ?? []) { t in
                    let x = min(max((t.posX ?? 0) / 100, 0), 1)
                    let y = min(max((t.posY ?? 0) / 100, 0), 1)
                    LobbyTableMarker(
                        table: t,
                        highlighted: highlight == t.id,
                        mine: seatedHere && seatSession.seat?.tableId == t.id
                    )
                    .offset(x: w * x - 22, y: h * y - 12)
                    .onTapGesture { openDrawer(t) }
                }

                // 图内顶部：拼桌/组局滚动条
                VStack {
                    LobbyGapMarquee(gaps: vm.gaps) { gap in
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
                    .offset(x: w * sx - 70, y: h * sy - 16)
                    .onTapGesture {
                        Task { await vm.refreshRooms(storeId: storeId) }
                        sheet = .roomList
                    }
                }
            }
        }
    }

    // MARK: - 底部：图内聊天（PLAN 态）与显隐条

    /// 图内公屏（v75：42% 高、PLAN 五态、上缘渐隐）；点聊天区隐藏，「展开公屏」升全屏
    private var planChatPanel: some View {
        ZStack(alignment: .topTrailing) {
            LobbyChatList(
                messages: boardMessages,
                showStorePrefix: false,
                style: .plan,
                emptyText: "本店公屏暂无消息 · 说点什么都行 ✨",
                fadeTop: true,
                onBodyClick: { showChat = false },
                onUserClick: { cardUser = $0.toCardTarget() },
                onMessageLongPress: { msg in
                    if msg.canReport(myUserId: myUserId) { reportTarget = msg }
                }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Button {
                openFullScreenChat(focusInput: false)
            } label: {
                Text("展开公屏 ↗")
                    .font(.system(size: 8))
                    .foregroundStyle(LobbyColors.goldLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 0x0A/255, green: 0x08/255, blue: 0x0B/255).opacity(0.6)))
                    .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .frame(height: UIScreen.main.bounds.height * 0.42)
        .contentShape(Rectangle())
        .onTapGesture { showChat = false }
    }

    /// 聊天隐藏态：图例 + 「💬 点图显示聊天」+ 围观 chip
    private var hiddenChatBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(LobbyTableStatus.allCases, id: \.rawValue) { s in
                    Circle().fill(LobbyTableStyle.color(s)).frame(width: 5, height: 5)
                    Text(s.label)
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer().frame(width: 4)
                }
                Text("💬 点图显示聊天")
                    .font(.system(size: 8))
                    .foregroundStyle(LobbyColors.goldLight.opacity(0.7))
                    .contentShape(Rectangle())
                    .onTapGesture { showChat = true }
            }
            Spacer()
            let standing = vm.store?.standingCount ?? 0
            if standing > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "eye")
                        .font(.system(size: 8))
                        .foregroundStyle(LobbyColors.standing)
                    Text("围观 \(standing)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(LobbyColors.standing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0x10/255, green: 0x07/255, blue: 0x0A/255).opacity(0.8))
                .overlay(Capsule().stroke(LobbyColors.standing.opacity(0.45), lineWidth: 1))
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture { showToast("围观区 \(standing) 人 · 对方看不到你") }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// 店名/楼层/在线 + 我的桌 chip + 在语音房回房入口：紧贴输入框上方（v75 口径），渐变融入底栏
    private var storeStatusLine: some View {
        HStack(spacing: 4) {
            Circle().fill(LobbyColors.seated).frame(width: 5, height: 5)
            Text(vm.store?.name ?? "门店大厅")
                .font(.system(size: 9.5, weight: .semibold, design: .serif))
                .foregroundStyle(LobbyColors.goldLight.opacity(0.85))
                .lineLimit(1)
            Text("· \(plan?.label ?? "大厅") · \(online) 人在店")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
            if seatedHere, let tableNo = seatSession.seat?.tableNo {
                Spacer().frame(width: 6)
                Text("我的桌 \(tableNo)")
                    .font(.system(size: 8.5))
                    .foregroundStyle(LobbyColors.goldLight)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(LobbyColors.gold.opacity(0.14)))
                    .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.4), lineWidth: 1))
                    .fixedSize()
            }
            Spacer(minLength: 8)
            // 「留在房里」退出页面但未退房时常驻提示，点击直接回房；退房/解散即消失
            if let p = voiceSession.presence, p.storeId == storeId {
                HStack(spacing: 3) {
                    Circle().fill(LobbyColors.crimson).frame(width: 5, height: 5)
                    Text("在语音房")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(LobbyColors.crimson.opacity(0.95))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(LobbyColors.crimson.opacity(0.14)))
                .overlay(Capsule().stroke(LobbyColors.crimson.opacity(0.45), lineWidth: 1))
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture { voiceRoomNav = VoiceRoomNav(roomId: p.roomId) }
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .background(LinearGradient(stops: [
            .init(color: LobbyColors.bg.opacity(0), location: 0),
            .init(color: LobbyColors.bg.opacity(0.8), location: 0.28),
            .init(color: LobbyColors.bg.opacity(0.95), location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Sheet 构建器（拆出 modifier 链，编译器对超大表达式会超时）

    private func drawerSheetBuilder(_ snapshot: LobbyTable) -> some View {
        let live = vm.plans.flatMap { $0.tables ?? [] }.first { $0.id == snapshot.id } ?? snapshot
        return LobbyTableDrawerView(
            table: live,
            spectate: spectate,
            seat: seatSession.seat,
            myUserId: myUserId,
            hostApplies: vm.hostApplies.filter { $0.tableId == live.id },
            hostOrders: vm.hostOrders.filter { $0.tableId == live.id },
            myApply: vm.myApply,
            myOrders: vm.myOrders,
            onDismiss: { sheet = nil; highlight = -1 },
            onCheckIn: { startCheckIn(live) },
            onSwitch: { switchTo(live) },
            onLeave: { leaveConfirmFor = live },
            onApplyShare: { sheet = nil; startShareApply(live) },
            onUnlock: { sheet = .unlock(live); Task { await vm.refreshMyOrders() } },
            onGiftToTable: { sheet = .gift(lobbyGiftContext(live)) },
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
        // 抽屉是系统 sheet：场景层的资料卡/举报/toast 会被压在抽屉底下，
        // 抽屉内容里再挂一份浮层（成员点头像、桌主动作的提示都在抽屉上直接可见）
        .overlay {
            if let u = cardUser { userCard(u) }
            if let msg = reportTarget { reportSheet(msg) }
            if let t = toast { LobbyToastView(text: t) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(LobbyColors.panel)
    }

    private func unlockSheetBuilder(_ t: LobbyTable) -> some View {
        LobbyDndUnlockSheet(
            table: t,
            hostNickname: drawerSpectate(t)?.members?.first { $0.host == true || $0.userId == t.hostUserId }?.nickname,
            myOrders: vm.myOrders,
            onDismiss: { sheet = nil },
            onGiftTier: {
                let hostName = drawerSpectate(t)?.members?
                    .first { $0.host == true || $0.userId == t.hostUserId }?.nickname
                sheet = .gift(LobbyGiftContext(
                    tableId: t.id, tableNo: t.tableNo, scene: "lobby_dnd",
                    receivers: [], toName: hostName ?? "桌主"))
            },
            onOrderPlaced: {
                sheet = nil
                showToast("解锁订单已支付 · 等桌主响应（10 分钟内，超时自动退款）")
                Task { await vm.refreshMyOrders() }
            },
            onRefreshOrders: { Task { await vm.refreshMyOrders() } },
            onResolved: { msg in
                sheet = nil
                showToast(msg)
                Task { await vm.refreshMyOrders() }
            }
        )
    }

    private var giftTargetSheetBuilder: some View {
        LobbyGiftTargetSheet(
            tables: vm.plans.flatMap { $0.tables ?? [] }
                .filter { ($0.currentCount ?? 0) > 0 }
                .sorted { ($0.currentCount ?? 0) > ($1.currentCount ?? 0) },
            onDismiss: { sheet = nil },
            onPick: { t in
                Task {
                    spectate = await vm.spectate(tableId: t.id)
                    sheet = .gift(lobbyGiftContext(t))
                }
            }
        )
    }

    private func giftSheetBuilder(_ ctx: LobbyGiftContext) -> some View {
        LobbyGiftSheet(
            tableId: ctx.tableId,
            tableNo: ctx.tableNo,
            scene: ctx.scene,
            receivers: ctx.receivers,
            toName: ctx.toName,
            onClose: { sheet = nil },
            onSent: { gift in
                showToast(ctx.scene == "lobby_dnd" ? "礼物已送出 · 达门槛即解锁" : "\(gift.name) 已送出")
                // 送礼会改热力榜与桌况：刷新平面图 + 我的订单（勿扰档可能已发通行证）
                Task {
                    await vm.refreshPlan(storeId: storeId)
                    await vm.refreshMyOrders()
                }
            }
        )
    }

    private var roomListSheetBuilder: some View {
        VoiceRoomListSheet(
            storeId: storeId,
            rooms: vm.rooms,
            onRefresh: { Task { await vm.refreshRooms(storeId: storeId) } },
            onEnter: { room in
                sheet = nil
                voiceRoomNav = VoiceRoomNav(roomId: room.id)
            },
            onCreate: {
                sheet = .createRoom
            }
        )
    }

    private var createRoomSheetBuilder: some View {
        VoiceRoomCreateSheet(
            storeId: storeId,
            onDismiss: { sheet = nil },
            onCreated: { id in
                sheet = nil
                Task { await vm.refreshRooms(storeId: storeId) }
                voiceRoomNav = VoiceRoomNav(roomId: id)
            }
        )
    }

    // MARK: - 全屏公屏开合

    private func openFullScreenChat(focusInput: Bool) {
        chatFocusInput = focusInput
        showChat = false
        chatFocus = true
    }

    private func closeFullScreenChat() {
        chatFocus = false
        chatFocusInput = false
    }

    private func openDrawer(_ t: LobbyTable) {
        highlight = t.id
        sheet = .drawer(t)
        spectate = nil
        Task {
            if let result = await vm.spectate(tableId: t.id), drawerTable?.id == t.id {
                spectate = result
            }
        }
        let isHost = seatSession.seat?.tableId == t.id && t.hostUserId == myUserId
        Task { await vm.loadTableOps(tableId: t.id, status: t.status, isHost: isHost) }
    }

    // MARK: - 底部发言区

    private var speechSection: some View {
        // 底部输入框只作入口：点它从底部升起全屏公屏并自动聚焦（真实输入在全屏公屏里）
        LobbySpeechInput(
            hint: lobbyInputHint(seatedHere: seatedHere, state: seatSession.seat?.state, tableNo: seatSession.seat?.tableNo),
            sending: sending,
            onEntryClick: { openFullScreenChat(focusInput: true) },
            onSendText: { _ in },
            onSendSticker: { _, _ in },
            onPickImage: {},
            onVoiceStop: { _ in },
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
            userId: u.userId,
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
                    sheet = .gift(singleReceiverContext(tableId: tid, u))
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
                    sheet = .gift(singleReceiverContext(tableId: tid, u))
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
                        .font(.system(size: 7))
                        .foregroundStyle(color)
                }
                Text(table.tableNo ?? "?")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(color)
            }
            // 内边距与安卓一致（9/3）：顶左锚点 offset(x-22,y-12) 的定位口径按标签盒宽算，
            // 盒宽不一致会整批桌号统一偏移
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color(red: 0x06/255, green: 0x05/255, blue: 0x08/255).opacity(0.82))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(markerAlpha), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .lobbyGlow(RoundedRectangle(cornerRadius: 6), color: color, spread: 24, intensity: markerAlpha * 0.6)
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

    /// 只有需要动画的桌位才启动 repeatForever 动画；呼吸必须线性（端点不减速，拍板口径）
    private func startAnimationIfNeeded() {
        switch status {
        case .grouping where !breathe:
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
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

// MARK: - v75 场景化零件

/// 右上 HUD 圆形按钮（v75：视频/排行榜/小房间竖排；36pt 圆 + 金描边 42%）。
/// LIVE 徽标挂左上角（贴屏幕右缘，挂右侧会被裁掉）；live=右上绿点。
struct HudIconButton: View {
    let icon: String
    let label: String
    var badge: String? = nil
    var live = false
    let onClick: () -> Void

    var body: some View {
        ZStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(LobbyColors.goldLight)
            if live {
                Circle()
                    .fill(LobbyColors.seated)
                    .frame(width: 6, height: 6)
                    .offset(x: 13, y: -13)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(red: 0x0A/255, green: 0x08/255, blue: 0x0B/255).opacity(0.6))
        .overlay(Circle().stroke(LobbyColors.gold.opacity(0.42), lineWidth: 1))
        .clipShape(Circle())
        .overlay(alignment: .topLeading) {
            if let badge {
                LobbyLiveBadge()
                    .offset(x: -5, y: -3)
            }
        }
        .contentShape(Circle())
        .onTapGesture { onClick() }
        .accessibilityLabel(label)
    }
}

/// 左缘招募面板（v75 游戏任务追踪式）：最多 3 张组局红/拼桌紫浮动卡，整组 2.6s 线性呼吸，
/// 点击切层并打开桌位。
struct LobbyRecruitmentPanel: View {
    let gaps: [LobbyShareGap]
    let plans: [LobbyFloorPlan]
    let onLocate: (LobbyShareGap) -> Void

    @State private var breathe = false

    private var tablesById: [Int64: LobbyTable] {
        var map: [Int64: LobbyTable] = [:]
        for p in plans {
            for t in p.tables ?? [] { map[t.id] = t }
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 1, green: 0x7D/255, blue: 0x9C/255))
                Text("今夜招募 · \(gaps.count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0x7D/255, blue: 0x9C/255).opacity(0.8))
                    .lineLimit(1)
            }
            Spacer().frame(height: 6)
            ForEach(gaps.prefix(3)) { gap in
                recruitCard(gap)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 104)
        .scaleEffect(breathe ? 1.18 : 1)
        .onAppear {
            // 线性往返：端点不减速，避免到最大后看起来停顿（拍板口径）
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func recruitCard(_ gap: LobbyShareGap) -> some View {
        let status = LobbyTableStatus.of(tablesById[gap.tableId]?.status)
        let grouping = status == .grouping
        let color = grouping ? Color(red: 1, green: 0x3D/255, blue: 0x62/255) : Color(red: 0xA0/255, green: 0x8B/255, blue: 1)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ZStack {
                    Circle().fill(color).frame(width: 16, height: 16)
                    Image(systemName: grouping ? "flame.fill" : "person.2")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                }
                Text("\(gap.tableNo ?? "?")桌")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
                if (gap.gap ?? 0) > 0 {
                    Spacer(minLength: 2)
                    Text("缺\(gap.gap ?? 0)")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(LobbyColors.crimson))
                        .fixedSize()
                }
            }
            Text(gap.note?.replacingOccurrences(of: "拼桌中 · ", with: "") ?? (grouping ? "组局中" : "拼桌中"))
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: grouping
                ? [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255).opacity(0.78), Color(red: 0x1C/255, green: 0x07/255, blue: 0x0E/255).opacity(0.66)]
                : [Color(red: 0x1E/255, green: 0x14/255, blue: 0x34/255).opacity(0.78), Color(red: 0x12/255, green: 0x0D/255, blue: 0x22/255).opacity(0.66)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(shape.stroke(color.opacity(0.8), lineWidth: 1))
        .clipShape(shape)
        .lobbyGlow(shape, color: color, spread: 26, intensity: 0.6)
        .contentShape(Rectangle())
        .onTapGesture { onLocate(gap) }
    }
}

/// 排行榜浮层（v75：三档胶囊 + 榜单行；独立页已下线）
struct LobbyRankSheet: View {
    let storeId: Int64
    let onUserClick: (LobbyHeatItem) -> Void

    enum RankTab: String, CaseIterable {
        case total, week, realtime

        var wire: String { rawValue }
        var label: String {
            switch self {
            case .total: return "总榜"
            case .week: return "周榜"
            case .realtime: return "实时"
            }
        }
    }

    @State private var tab: RankTab = .realtime
    @State private var reloadKey = 0
    @State private var board: LobbyHeatBoard?
    @State private var loading = true
    @State private var error: String?
    @ObservedObject private var cardStore = MemberCardStore.shared

    private var items: [LobbyHeatItem] { board?.list ?? [] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                HStack(alignment: .bottom, spacing: 8) {
                    Text("门店排行榜")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(LobbyColors.ivory)
                    Text("RANKING")
                        .font(.system(size: 9).italic())
                        .kerning(1.2)
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                    if tab == .realtime {
                        HStack(spacing: 4) {
                            Circle().fill(LobbyColors.seated).frame(width: 6, height: 6)
                            Text("实时更新")
                                .font(.system(size: 9))
                                .foregroundStyle(LobbyColors.seated)
                        }
                    }
                }

                // 三档胶囊（v75：未选中金边描边，选中酒红渐变）
                HStack(spacing: 8) {
                    ForEach(RankTab.allCases, id: \.self) { t in
                        Text(t.label)
                            .font(.system(size: 11.5, weight: t == tab ? .semibold : .regular))
                            .foregroundStyle(t == tab ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if t == tab {
                                    Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                                } else {
                                    Capsule().stroke(LobbyColors.gold.opacity(0.3), lineWidth: 1)
                                }
                            }
                            .contentShape(Capsule())
                            .onTapGesture { tab = t }
                    }
                }
                .padding(.top, 12)

                if loading && items.isEmpty {
                    ProgressView().tint(LobbyColors.gold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .padding(.top, 12)
                } else if let err = error, items.isEmpty {
                    LobbyLoadFailed(message: err, onRetry: { reloadKey += 1 })
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    Text("本店暂无热力记录 · 送礼 / 拼桌 / 组局即可上榜 ✨")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                } else {
                    // 榜单行（v75：奖牌 + 头像框 + 昵称/等级 + 热力；第一行鎏金底）
                    // tab 与首行间距 12（对齐安卓 Spacer(12)）
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        rankRow(index: index, item: item)
                            .padding(.top, index == 0 ? 12 : 0)
                            .padding(.bottom, 6)
                            .task(id: item.userId) {
                                if let uid = item.userId, uid > 0 { MemberCardStore.shared.fetchMissing([uid]) }
                            }
                    }
                }

                Text("送礼 / 拼桌 / 组局均可获得热力值 · 实时榜每分钟刷新")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .task(id: reloadKey) { await load() }
        .task(id: tab) { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            board = try await LobbyAPI.heatBoard(storeId: storeId, type: tab.wire, limit: 50)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func rankRow(index: Int, item: LobbyHeatItem) -> some View {
        let card = cardStore.card(item.userId)
        let first = index == 0
        let medal: String = {
            switch index {
            case 0: return "🥇"
            case 1: return "🥈"
            case 2: return "🥉"
            default: return "\(item.rank ?? index + 1)"
            }
        }()
        return Button {
            onUserClick(item)
        } label: {
            HStack(spacing: 10) {
                Text(medal)
                    .font(.system(size: index < 3 ? 15 : 12, weight: .bold))
                    .foregroundStyle(index < 3 ? LobbyColors.goldLight : .white.opacity(0.35))
                    .frame(width: 28)
                LobbyMemberAvatar(userId: item.userId, fallbackAvatar: item.avatar, size: 40)
                HStack(spacing: 0) {
                    Text(memberDisplayName(card, item.nickname))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(LobbyColors.ivory)
                        .lineLimit(1)
                    if card?.vipName?.isEmpty == false {
                        Spacer().frame(width: 6)
                        LobbyVipChip(vipName: card?.vipName, vipColor: card?.vipColor,
                                     levelInTier: card?.levelInTier, fontSize: 8)
                    }
                    Spacer(minLength: 0)
                }
                Text("\(item.score ?? 0)")
                    .font(.lobbyNumber(12, weight: .bold))
                    .foregroundStyle(LobbyColors.goldLight)
                Text("热力")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(
                first
                    ? LinearGradient(colors: [LobbyColors.gold.opacity(0.16), LobbyColors.crimson.opacity(0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.white.opacity(0.025), .white.opacity(0.025)],
                                     startPoint: .leading, endPoint: .trailing)
            ))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                first ? LobbyColors.goldLight.opacity(0.45) : LobbyColors.gold.opacity(0.14),
                lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
