import AVFoundation
import Foundation
import ImSDK_Plus
import LiveKitClient

/// LiveKit 连接态（页面据此显示「连接中/已连接/重连中」）
enum VoiceConnState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case failed
}

/// 在房成员（LiveKit 远端参会者；name=进房 token 签发的昵称）
struct VoiceRoomPeer: Identifiable {
    let userId: Int64
    let name: String?
    var id: Int64 { userId }
}

/// 进行中语音房的轻量存在信息（门店大厅顶栏入口用；storeId 用于只在所属门店大厅显示）
struct VoiceRoomPresence: Equatable {
    let roomId: Int64
    let storeId: Int64
    let title: String?
}

/// 语音房会话（对齐安卓 VoiceRoomSession）：房间状态（服务端真值）+ LiveKit 连房 + 麦位动作 + 麦位变更通知联动。
///
/// **三条真值来源各归其位，别互相替代**：
/// 1. 麦位/在房/我的状态 = 服务端（voice-room/get）——连房失败也不影响麦位显示；
/// 2. 说话音波 = 客户端 SDK ActiveSpeakersChanged（服务端拿不到说话态）；
/// 3. 能不能发声 = token 里的 canPublish（签发快照）——收到抱麦/闭麦/下麦通知后必须重连。
///
/// token 过期/权限变更走整房重连（disconnect + connect）：这是 LiveKit 应用新权限的确定路径。
@MainActor
final class VoiceRoomSession: ObservableObject {

    static let shared = VoiceRoomSession()

    /// 成员资料兜底（userId→昵称/头像）：LiveKit 只透传 name 不带头像
    struct UserBrief {
        let nickname: String?
        let avatar: String?
    }

    @Published private(set) var detail: LobbyVoiceRoomDetail?
    @Published private(set) var conn: VoiceConnState = .idle
    /// 正在说话的用户 id（客户端 SDK 本地渲染音波/高亮）
    @Published private(set) var speaking: Set<Int64> = []
    /// 在房成员（LiveKit 远端参会者实时视图）：进房即连麦，未上麦的听众也在列
    @Published private(set) var peers: [VoiceRoomPeer] = []
    /// 成员资料兜底表（成员条/房间管理按参会者名单补拉）
    @Published private(set) var profiles: [Int64: UserBrief] = [:]
    /// 进行中的房间（「留在房里」只退页面不退房——大厅顶栏常驻入口据此显示）
    @Published private(set) var presence: VoiceRoomPresence?
    /// 麦克风本地开关（用户自己按的临时静音；与服务端闭麦是两回事）
    @Published private(set) var localMicOn = false
    /// 一次性提示（连接失败/被踢/通知联动结果），由页面消费后清空
    @Published private(set) var notice: String?
    /// 非本人意愿的会话终止（房主解散/服务端删房把 RTC 踢下线）：页面据此提示并自动退出
    @Published private(set) var roomClosed: String?

    /// 当前房间 id（连房/动作都要带）
    private(set) var roomId: Int64 = -1

    private var room: Room?
    private var observer: NSObjectProtocol?
    private var refCount = 0
    /// 主动断开标志：区分被动踢线（解散）与自己退房
    private var leavingIntentionally = false
    /// 我上一轮的麦位号（0→N 边沿检测"刚上麦"，用于默认开麦意图）
    private var lastSeatNo = 0
    /// 重连互斥：抱麦/闭麦通知连发时两次重连会在空中互踩，在跑就跳过本次
    private var reconnectTask: Task<Void, Never>?

    private init() {}

    // MARK: - 生命周期

    /// 房间页可见时调用（引用计数：语音房可能在返回栈里叠多层）
    func start() {
        refCount += 1
        registerObserverIfNeeded()
    }

    /// 房间页离开时调用；计数归零才断开语音与监听（页面退出即停止出声）。
    /// 注意：这里只断 LiveKit 不退房——「留在房里」语义，presence 保留给大厅顶栏入口。
    func stop() {
        refCount = max(0, refCount - 1)
        if refCount == 0 {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
            }
            observer = nil
            disconnectLiveKit()
        }
    }

    /// 登出：清状态（IM 已 logout，LiveKit 连接必须断开，否则麦克风仍占着）
    func clear() {
        disconnectLiveKit()
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
        }
        observer = nil
        refCount = 0
        roomId = -1
        detail = nil
        speaking = []
        peers = []
        profiles = [:]
        presence = nil
        conn = .idle
        notice = nil
        roomClosed = nil
        localMicOn = false
        lastSeatNo = 0
    }

    private func registerObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .jjtIMNewMessage, object: nil, queue: .main
        ) { [weak self] note in
            guard let msg = note.object as? V2TIMMessage else { return }
            Task { @MainActor in self?.onImMessage(msg) }
        }
    }

    // MARK: - 进入/退出房间

    /// 进入房间页：拉详情 + 连语音（幂等：同房间重复进入只连一次）
    func enter(roomId: Int64) {
        self.roomId = roomId
        Task {
            try? await refresh()
            await connectLiveKit()
        }
    }

    /// 进房（public 直进 / approval 落申请 / invite 仅房主拉人）：返回结果供页面分流
    func join(roomId: Int64) async -> VoiceRoomJoinResult {
        self.roomId = roomId
        return (try? await VoiceRoomAPI.join(roomId: roomId)) ?? VoiceRoomJoinResult(result: nil, imGroupIdStr: nil)
    }

    /// 退房（在麦自动放麦）；同时断开语音并清详情
    func leave() async throws {
        let id = roomId
        if id > 0 { try await VoiceRoomAPI.leave(roomId: id) }
        disconnectLiveKit()
        detail = nil
        presence = nil
        speaking = []
        lastSeatNo = 0
    }

    // MARK: - 服务端状态

    /// 拉房间详情（麦位/在房/我的麦位）。失败静默——页面的失败态由首屏兜底。
    /// 抛出版本（供审批轮询等需要感知失败的调用方）：默认吞掉网络异常，与安卓 dataOrNull 口径一致。
    @discardableResult
    func refresh() async throws -> LobbyVoiceRoomDetail? {
        let id = roomId
        guard id > 0 else { return nil }
        guard let d = try? await VoiceRoomAPI.roomDetail(id: id) else { return nil }
        detail = d
        presence = (d.inRoom == true) ? VoiceRoomPresence(roomId: d.id, storeId: d.storeId ?? 0, title: d.title) : nil
        // 上麦瞬间（自己上/被抱）默认开麦——只在这条 0→N 边沿重置意图，用户此后手动关麦
        // 不会被轮询同步又强开
        let seatNo = d.mySeatNo ?? 0
        if seatNo > 0, lastSeatNo == 0 { localMicOn = true }
        lastSeatNo = seatNo
        // 麦位权限变化（被抱上麦/被闭麦/下麦）已在服务端即时生效，本地发布状态必须对齐——
        // 对齐时尊重用户本地开关意图（effective = 服务端许可 && 意图）
        if room != nil, conn == .connected {
            await syncLocalPublish()
        }
        return d
    }

    // MARK: - 麦位动作（服务端）

    private func requireRoom() throws -> Int64 {
        guard roomId > 0 else {
            throw APIError.business(code: -1, message: "房间未就绪，请返回重进")
        }
        return roomId
    }

    /// 申请上麦（须在房）
    func applyMic() async throws {
        try await VoiceRoomAPI.applyMic(roomId: try requireRoom())
    }

    /// 上麦待处理列表（房主/管理麦）
    func listMicApplications() async throws -> [VoiceRoomMicApply] {
        try await VoiceRoomAPI.listMicApplications(roomId: try requireRoom())
    }

    /// 下麦（本人）：服务端放麦后本地要重连（canPublish 变 false）
    func leaveMic() async throws {
        try await VoiceRoomAPI.leaveMic(roomId: try requireRoom())
        try? await refresh()
        reconnectIfConnected()
    }

    /// 强制下麦（房主/管理麦）：移下指定成员，其本人收通知自动对齐
    func kickMic(targetUserId: Int64) async throws {
        try await VoiceRoomAPI.kickMic(roomId: try requireRoom(), targetUserId: targetUserId)
        try? await refresh()
    }

    /// 移出房间（房主/管理麦）：退群+断 RTC，其本人收通知自动退出房间页
    func kickFromRoom(targetUserId: Int64) async throws {
        try await VoiceRoomAPI.kickFromRoom(roomId: try requireRoom(), targetUserId: targetUserId)
        try? await refresh()
    }

    /// 抱麦（房主/管理麦；seatNo 空 = 自动首个虚位）
    func seatUser(targetUserId: Int64, seatNo: Int?) async throws {
        try await VoiceRoomAPI.seatUser(roomId: try requireRoom(), targetUserId: targetUserId, seatNo: seatNo)
        try? await refresh()
    }

    /// 闭麦/开麦（房主/管理麦）：被闭麦者由官方号通知触发重连，操作者自己也要刷详情
    func muteMic(seatNo: Int, muted: Bool) async throws {
        try await VoiceRoomAPI.muteMic(roomId: try requireRoom(), seatNo: seatNo, muted: muted)
        try? await refresh()
        // 闭的是自己 → 立刻停止发声（不等通知往返）
        if detail?.mySeatNo == seatNo {
            await muteLocalPublish(muted: muted)
        }
    }

    /// 指定/取消管理麦（仅房主）
    func setMicRole(seatNo: Int, role: String) async throws {
        try await VoiceRoomAPI.setMicRole(roomId: try requireRoom(), seatNo: seatNo, role: role)
        try? await refresh()
    }

    /// 进房待审批列表（房主/管理麦）
    func listJoinRequests() async throws -> [VoiceRoomJoinRequest] {
        try await VoiceRoomAPI.listJoinRequests(roomId: try requireRoom())
    }

    /// 进房审批（房主/管理麦）
    func handleJoinRequest(requestId: Int64, agree: Bool, reason: String?) async throws {
        try await VoiceRoomAPI.handleJoinRequest(roomId: try requireRoom(), requestId: requestId, agree: agree, reason: reason)
    }

    /// 拉人进房（房主/管理麦）
    func invite(inviteeUserId: Int64) async throws {
        try await VoiceRoomAPI.invite(roomId: try requireRoom(), inviteeUserId: inviteeUserId)
    }

    /// 关房（仅房主）：关房后页面须退出
    func closeRoom() async throws {
        try await VoiceRoomAPI.closeRoom(roomId: try requireRoom())
        disconnectLiveKit()
        detail = nil
    }

    /// 面板内的异步动作入口：失败落 notice 由页面 toast，不静默（低频显式操作必须让操作者看见）
    func runAction(_ block: @escaping () async throws -> Void) {
        Task {
            do {
                try await block()
            } catch {
                notice = (error as? APIError)?.errorDescription ?? "操作失败，请重试"
            }
        }
    }

    // MARK: - presence 入口过期

    /// 进房撞 055（房间不存在/已关闭）：大厅顶栏的进行中入口已过期，一并摘掉
    func clearStalePresence(_ rid: Int64) {
        if presence?.roomId == rid { presence = nil }
    }

    /// 页面消费完提示后清空（避免重进页面重复弹）
    func clearNotice() { notice = nil }

    /// 页面消费完解散态后清空
    func consumeRoomClosed() { roomClosed = nil }

    // MARK: - LiveKit

    /// 连语音：先拉 {url, token} 两件套（不硬编码接入地址），再连房；已在同房则跳过。
    /// canPublish 由服务端按麦位签发——非麦上者只订阅、不发布。
    func connectLiveKit() async {
        let id = roomId
        guard id > 0 else { return }
        if room != nil, conn == .connected { return }
        guard let t = try? await VoiceRoomAPI.token(roomId: id),
              let url = t.url, !url.isEmpty,
              let jwt = t.token, !jwt.isEmpty else { return }
        conn = .connecting
        disconnectLiveKit() // 重连前先清旧连接（同 identity 重连会踢前一个连接）
        leavingIntentionally = false // 新连接开始：后续被动断开按解散处理
        let r = Room(delegate: VoiceRoomLiveKitDelegate(owner: self))
        room = r
        // 连接是异步的：状态由 delegate 的 didUpdateConnectionState 回正，
        // 这里不乐观置 connected（否则连接窗口内小标失真）
        do {
            try await r.connect(url: url, token: jwt)
        } catch {
            if room === r { room = nil }
            if Task.isCancelled || error is CancellationError {
                // 取消型失败 = 更新的连接取代了这一次（重连互踩），属预期——静默归位
                conn = .idle
            } else {
                conn = .failed
                notice = liveKitErrorText(error)
            }
        }
    }

    /// 断开语音（页面退出/退房/重连前）
    func disconnectLiveKit() {
        leavingIntentionally = true
        reconnectTask?.cancel()
        reconnectTask = nil
        let r = room
        room = nil
        if let r {
            Task {
                await r.disconnect()
            }
        }
        conn = .idle
        speaking = []
        peers = []
        localMicOn = false
    }

    /// 本地麦克风开关（仅在麦上且未被服务端闭麦时可用；页面按钮调用）。
    /// 调用方须已取得麦克风权限。
    func setLocalMic(on: Bool) async {
        guard let r = room else { return }
        if on && !canPublishNow() {
            notice = "你当前不在麦上或已被闭麦"
            return
        }
        do {
            try await r.localParticipant.setMicrophone(enabled: on)
            localMicOn = on
        } catch {
            notice = "麦克风切换失败：\(error.localizedDescription)"
        }
    }

    /// 麦克风权限（上麦/开麦前必须拿到；LiveKit 发布音轨要录音权限）
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    private var isServerAudible: Bool {
        guard let mine = detail?.mySeatNo, mine > 0 else { return false }
        let mic = (detail?.mics ?? []).first { $0.seatNo == mine }
        return mic?.muted != true
    }

    private var canPublishNow: Bool { isServerAudible }

    /// 按服务端权限对齐本地发布状态（上麦 → 开麦；被闭麦/下麦 → 停麦）。
    /// 尊重用户本地开关意图：effective = 服务端许可 && 用户意图——否则 5s 轮询会把
    /// 用户手动关掉的麦克风反复强开。localMicOn 只由用户切换与「上麦边沿」写入。
    private func syncLocalPublish() async {
        guard let r = room else { return }
        let effective = canPublishNow && localMicOn
        try? await r.localParticipant.setMicrophone(enabled: effective)
    }

    private func muteLocalPublish(muted: Bool) async {
        guard let r = room else { return }
        if muted {
            // 服务端闭麦：立即停声；意图不动（解禁后按原意图恢复）
            try? await r.localParticipant.setMicrophone(enabled: false)
        } else {
            await syncLocalPublish()
        }
    }

    /// 权限可能变了（麦位变更通知）：重拉详情 + 重连拿新 token；只影响连着的房。
    /// 先强制断再连——connectLiveKit 的「已连接早退」卫语句会吞掉强推重连，
    /// 被抱上麦的听众永远拿不到新 token。互斥：通知连发时两次重连互踩，在跑就跳过。
    private func reconnectIfConnected() {
        guard room != nil, reconnectTask == nil else { return }
        reconnectTask = Task {
            defer { reconnectTask = nil }
            disconnectLiveKit()
            await connectLiveKit()
        }
    }

    // MARK: - LiveKit 事件（delegate 转发到主 actor）

    func handleConnState(_ state: ConnectionState) {
        switch state {
        case .connected:
            conn = .connected
            syncPeers()
            Task { await syncLocalPublish() }
        case .reconnecting:
            conn = .reconnecting
        case .disconnected:
            conn = .idle
            speaking = []
            // 非本人主动断开 = 服务端删房/解散把 RTC 踢下线：通知页面自动退出。
            // 自己退房的 disconnect 走 leavingIntentionally，不置解散态
            if !leavingIntentionally, roomId > 0 {
                roomClosed = "房间已解散"
                notice = "房间已解散"
                presence = nil
            }
        default:
            break
        }
    }

    func handleSpeaking(_ ids: Set<Int64>) {
        speaking = ids
    }

    func handleConnectFailed(_ message: String) {
        if message.lowercased().contains("cancel") {
            conn = .idle
        } else {
            conn = .failed
            notice = liveKitErrorText(message)
        }
    }

    /// 从 LiveKit 房间同步在房成员（Connected/Reconnected/参会者进出事件统一入口）
    func syncPeers() {
        guard let r = room else { return }
        var list: [VoiceRoomPeer] = []
        for p in r.remoteParticipants.values {
            // LiveKit 的 identity 就是后端签发时写入的 userId（signJoinToken(identity=userId)）
            guard let sv = p.identity?.stringValue, let id = Int64(sv) else { continue }
            list.append(VoiceRoomPeer(userId: id, name: p.name))
        }
        peers = list
        // 自己也在列补拉（成员条「我」的兜底头像）：自己不是远端参会者
        var ids = list.map(\.userId)
        ids.append(TokenManager.shared.userId ?? 0)
        ensureProfiles(ids)
    }

    /// 补拉缺失的成员资料；失败不打扰（下次参会者变化会重试），去重避免并发重复请求
    private func ensureProfiles(_ userIds: [Int64]) {
        let missing = Array(Set(userIds.filter { $0 > 0 && profiles[$0] == nil }))
        guard !missing.isEmpty else { return }
        Task {
            if let users = try? await UserAPI.getUserInfoList(ids: missing) {
                for u in users {
                    profiles[u.id] = UserBrief(nickname: u.nickname, avatar: u.avatar)
                }
            }
        }
    }

    // MARK: - 官方号麦位通知

    /// 官方号通知（抱麦/闭麦/开麦/管理麦）→ 重拉 token 重连 + 刷详情。
    /// 只处理与本房间相关的通知（后端文案里带房名）。
    private func onImMessage(_ msg: V2TIMMessage) {
        if msg.groupID != nil { return } // 只关心 C2C 官方号
        if msg.userID != VoiceRoomConst.officialAccountId { return }
        guard let text = msg.textElem?.text else { return }
        let title = detail?.title
        // 房名已知：必须命中房名（后端四类通知文案都带房名）——避免别的房间的通知触发本房重连；
        // 房名未知（详情还没拉回）时才退化为关键词兜底
        let related: Bool
        if let title, !title.isEmpty {
            related = text.contains(title)
        } else {
            related = text.contains("号麦") || text.contains("管理麦") || text.contains("闭麦") || text.contains("开麦")
        }
        guard related else { return }
        if text.contains("申请上麦") {
            // 上麦申请通知（发房主/管理麦）：不重连（无权限变化），弹提示（红点计数随轮询更新）
            notice = text
            return
        }
        Task {
            try? await refresh()
            reconnectIfConnected()
        }
    }

    private func liveKitErrorText(_ message: String) -> String {
        let m = message
        if m.lowercased().contains("timeout") { return "语音连接超时，检查网络后重进房间" }
        if m.lowercased().contains("unauthorized") || m.contains("401") { return "语音凭证失效，请重进房间" }
        return "语音连接失败（\(String(m.prefix(40)))）"
    }
}

/// LiveKit 事件桥：SDK 在其内部线程回调（协议 @objc optional、要求 Sendable），
/// 这里只做一件事——把事件转回主 actor 的会话。无状态转发，天然 Sendable。
private final class VoiceRoomLiveKitDelegate: RoomDelegate {

    let owner: VoiceRoomSession

    init(owner: VoiceRoomSession) {
        self.owner = owner
    }

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        Task { @MainActor in owner.handleConnState(connectionState) }
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in owner.syncPeers() }
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in owner.syncPeers() }
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let ids = Set(participants.compactMap { p in
            p.identity?.stringValue.flatMap { Int64($0) }
        })
        Task { @MainActor in owner.handleSpeaking(ids) }
    }

    func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        let msg = error.map { String(describing: $0) } ?? ""
        Task { @MainActor in owner.handleConnectFailed(msg) }
    }
}
