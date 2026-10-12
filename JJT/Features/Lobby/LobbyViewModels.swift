import Foundation

/// 暗夜大厅（大厅列表页）状态（对齐安卓 LobbyHomeViewModel）
@MainActor
final class LobbyHomeViewModel: ObservableObject {

    @Published var loading = false
    @Published var stores: [LobbyStoreCard] = []
    @Published var error: String?

    /// 门店列表是页面主内容：失败写 error 由页面渲染「加载失败 + 重试」
    func load() async {
        loading = true
        error = nil
        do {
            stores = try await LobbyAPI.listStores()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// 门店大厅（单店详情页）状态（对齐安卓 StoreLobbyViewModel）
@MainActor
final class StoreLobbyViewModel: ObservableObject {

    @Published var loading = false
    @Published var store: LobbyStoreCard?
    @Published var plans: [LobbyFloorPlan] = []
    @Published var videos: [LobbyVideo] = []
    @Published var gaps: [LobbyShareGap] = []
    @Published var heatTop: [LobbyHeatItem] = []
    /// 门店营业中小房间列表（表演区）
    @Published var rooms: [LobbyVoiceRoom] = []
    @Published var error: String?
    /// 本桌待审批拼桌申请（桌主视角；抽屉打开时按需拉取）
    @Published var hostApplies: [LobbyShareApply] = []
    /// 本桌待响应解锁订单（桌主视角）
    @Published var hostOrders: [LobbyDndUnlockOrder] = []
    /// 我的当前拼桌申请（申请人视角）
    @Published var myApply: LobbyShareApply?
    /// 我的解锁订单（解锁方视角；勿扰面板展示在途单与历史结果）
    @Published var myOrders: [LobbyDndUnlockOrder] = []
    /// 我在本店待核销的桌位邀请（页内横幅展示，只留本店的）
    @Published var myInvites: [LobbyTableInvite] = []

    private(set) var storeId: Int64?

    /// 只读数据整体加载。**平面图是页面主内容**：失败写 error（页面渲染失败态 + 重试，
    /// 与「该门店尚未配置平面图」的空态区分开）；门店卡片/视频/拼桌投影/热力横幅为富化，失败静默。
    func load(storeId: Int64) async {
        self.storeId = storeId
        loading = true
        error = nil
        do {
            plans = try await LobbyAPI.listFloorPlans(storeId: storeId)
        } catch {
            self.error = error.localizedDescription
        }
        if let all = try? await LobbyAPI.listStores() {
            store = all.first { $0.id == storeId }
        }
        videos = (try? await LobbyAPI.listVideos(storeId: storeId)) ?? []
        gaps = (try? await LobbyAPI.listSharingGaps(storeId: storeId)) ?? []
        if let board = try? await LobbyAPI.heatBoard(storeId: storeId, type: "realtime", limit: 3) {
            heatTop = board.list ?? []
        }
        rooms = (try? await LobbyAPI.listOpenRooms(storeId: storeId)) ?? []
        loading = false
    }

    /// 围观桌况（点桌抽屉用；纯读）。失败返回 nil：抽屉降级用平面图自带快照渲染。
    func spectate(tableId: Int64) async -> LobbyTableSpectate? {
        try? await LobbyAPI.spectateTable(tableId: tableId)
    }

    /// 拼桌缺口滚动条轮询（轻量接口客户端轮询）
    func refreshGaps(storeId: Int64) async {
        gaps = (try? await LobbyAPI.listSharingGaps(storeId: storeId)) ?? gaps
    }

    /// 小房间列表刷新（房间列表 sheet 打开与轮询时）
    func refreshRooms(storeId: Int64) async {
        rooms = (try? await LobbyAPI.listOpenRooms(storeId: storeId)) ?? rooms
    }

    /// 只重拉平面图 + 拼桌投影（入座/离桌/换桌后桌态与人数已变，页面要跟着刷新）。
    /// 只刷主内容，不动视频/热力——那些与坐席无关。
    func refreshPlan(storeId: Int64) async {
        plans = (try? await LobbyAPI.listFloorPlans(storeId: storeId)) ?? plans
        gaps = (try? await LobbyAPI.listSharingGaps(storeId: storeId)) ?? gaps
    }

    /// 我的解锁订单（勿扰面板打开时刷新）
    func refreshMyOrders() async {
        myOrders = (try? await LobbyAPI.dndMyOrders()) ?? myOrders
    }

    /// 我的待核销桌位邀请（受邀端）：进页/轮询/回前台时刷，只留本店的；失败静默
    func refreshInvites(storeId: Int64) async {
        if let all = try? await LobbyAPI.myInvites() {
            myInvites = all.filter { $0.storeId == storeId }
        }
    }

    /// 抽屉打开时按需拉审批数据（不做全量轮询）：
    /// - 桌主 + 拼桌中/有人桌 → 本桌待审批申请；桌主 + 勿扰 → 本桌待响应解锁订单；
    /// - 非桌主 + 拼桌中/有人桌 → 我的申请状态（「已申请 · 等桌主审批」的入口态）；
    /// - 非桌主 + 勿扰 → 我的解锁单（持证者要在付费按钮出现前就看到「已持有通行证」）。
    /// 三者均为抽屉内的过程性数据，失败静默（抽屉正文仍由平面图快照渲染）。
    func loadTableOps(tableId: Int64, status: String?, isHost: Bool) async {
        let wire = LobbyTableStatus.of(status)
        if isHost && (wire == .sharing || wire == .occupied) {
            hostApplies = (try? await LobbyAPI.sharePendingByHost(tableId: tableId)) ?? hostApplies
        } else if isHost && wire == .dnd {
            await refreshHostOrders()
        } else if !isHost && (wire == .sharing || wire == .occupied) {
            myApply = try? await LobbyAPI.shareMyApply()
        } else if !isHost && wire == .dnd {
            await refreshMyOrders()
        }
    }

    private func refreshHostOrders() async {
        hostOrders = (try? await LobbyAPI.dndPendingByHost()) ?? hostOrders
    }

    /// 桌主动作改了桌态后重拉平面图与拼桌投影。延后 300ms：生产数据源走读写分离地址，
    /// 毫秒级复制延迟可能把刚改完的桌态盖回旧值，延后一拍只是降低闪回概率（真闪回下次刷新自愈）。
    private func reloadPlan() async {
        guard let storeId else { return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        await refreshPlan(storeId: storeId)
    }
}

// MARK: - 写操作（async throws；成功后的 toast 与刷新由调用方编排）

extension StoreLobbyViewModel {

    /// 喊人拼桌（有人桌 → 拼桌态 + 公屏播报；服务端限流 10 次/小时）
    func shout(tableId: Int64, note: String?) async throws {
        try await LobbyAPI.hostShout(tableId: tableId, note: note)
        if let storeId { await loadTableOps(tableId: tableId, status: "sharing", isHost: true) }
        await reloadPlan()
    }

    /// 停止拼桌
    func stopShout(tableId: Int64) async throws {
        try await LobbyAPI.hostStopShout(tableId: tableId)
        await reloadPlan()
    }

    /// 设置本桌勿扰（有人桌 → 勿扰态；silent=true 为完全静音档）
    func enableDnd(tableId: Int64, note: String?, silent: Bool) async throws {
        try await LobbyAPI.hostEnableDnd(tableId: tableId, note: note, silent: silent)
        if let storeId { await loadTableOps(tableId: tableId, status: "dnd", isHost: true) }
        await reloadPlan()
    }

    /// 取消本桌勿扰（在途解锁订单由服务端逐单原路退款）
    func cancelDnd(tableId: Int64) async throws {
        try await LobbyAPI.hostCancelDnd(tableId: tableId)
        await reloadPlan()
    }

    /// 转让桌主（须为本桌另一入座成员）
    func transferHost(tableId: Int64, targetUserId: Int64) async throws {
        try await LobbyAPI.hostTransfer(tableId: tableId, targetUserId: targetUserId)
        await reloadPlan()
    }

    /// 移出成员（本桌入座成员回罚站；被移出者收官方号通知）
    func removeMember(tableId: Int64, targetUserId: Int64) async throws {
        try await LobbyAPI.hostRemove(tableId: tableId, targetUserId: targetUserId)
        await reloadPlan()
    }

    /// 邀请好友补位（一桌对一人一条，重邀刷新 30 分钟有效期）
    func invite(tableId: Int64, inviteeId: Int64) async throws {
        try await LobbyAPI.hostInvite(tableId: tableId, inviteeId: inviteeId)
    }

    /// 桌主审批通过拼桌申请（申请人随即入桌）
    func approveApply(applyId: Int64, tableId: Int64) async throws {
        try await LobbyAPI.shareApprove(applyId: applyId)
        if let storeId { await loadTableOps(tableId: tableId, status: "sharing", isHost: true) }
        await reloadPlan()
    }

    /// 桌主审批拒绝拼桌申请（结果经官方号通知申请人）
    func rejectApply(applyId: Int64, tableId: Int64) async throws {
        try await LobbyAPI.shareReject(applyId: applyId)
        if let storeId { await loadTableOps(tableId: tableId, status: "sharing", isHost: true) }
    }

    /// 桌主接受勿扰解锁（分账 50% + 发通行证；仅 10 分钟窗口内）
    func acceptOrder(orderId: Int64) async throws {
        try await LobbyAPI.dndAcceptOrder(orderId: orderId)
        await refreshHostOrders()
    }

    /// 桌主拒绝勿扰解锁（原路退款）
    func rejectOrder(orderId: Int64) async throws {
        try await LobbyAPI.dndRejectOrder(orderId: orderId)
        await refreshHostOrders()
    }

    /// 接受桌位邀请（到店核销）：GPS 作 3km 围栏证据；成功后重拉平面图并清掉横幅
    func acceptInvite(_ invite: LobbyTableInvite, latitude: Double, longitude: Double) async throws {
        try await LobbyAPI.acceptInvite(invite, latitude: latitude, longitude: longitude)
        await reloadPlan()
        if let storeId { await refreshInvites(storeId: storeId) }
    }
}
