import Foundation
import ImSDK_Plus

/// 坐席系统播报到达通知（sys=seat：入座/离桌/换桌，门店群广播）。
/// 平面图桌态的实时刷新源——他人坐席变化只走这条信号（对齐安卓 LobbyImSession.seatEvents）。
extension Notification.Name {
    static let jjtLobbySeatEvent = Notification.Name("jjtLobbySeatEvent")
}

/// 大厅公屏消息（对齐安卓 LobbyChatMessage：门店群原文 + 聚合群扇出副本统一模型）
struct LobbyChatMessage: Identifiable {
    enum Kind { case text, voice, image, sticker, system }

    /// IM 消息ID（举报用它；本地回显为 local- 前缀）
    let msgId: String
    /// 落在哪个群（门店群 = 本店公屏；聚合群 = 暗夜大厅全城流）
    let groupId: String
    /// 系统行为 0（不是用户发言，不参与资料卡/举报）
    let senderId: Int64
    let nickname: String
    let avatar: String?
    /// IM 时间戳（秒）
    let timeSec: Int64
    var kind: Kind
    var text: String?
    var voiceSeconds: Int
    var voicePath: String?
    var imageUrl: String?
    /// 本地图片路径（自己刚发出去的图先本地显示）
    var imagePath: String?
    /// 表情包（Resources/stickers/ 白兔/黑兔；IM 自定义消息 type=sticker）
    var stickerPack: String?
    var stickerName: String?
    /// 扇出副本携带的门店元数据（聚合流渲染门店前缀；门店群内为空）
    var storeName: String?
    var tableNo: String?
    var seatState: String?

    var id: String { msgId }
    var isUserMessage: Bool { kind != .system }
    var storePrefix: String? { storeName?.replacingOccurrences(of: " · ", with: "·") }

    /// 能否对这条消息发起举报：系统行与自己发的不行（服务端没有落库行）
    func canReport(myUserId: Int64) -> Bool {
        isUserMessage && senderId != myUserId && !msgId.hasPrefix("local-")
    }
}

/// 大厅公屏会话（对齐安卓 LobbyImSession 单例）：IM 直播群（AVChatRoom）的加入、收流、发言与举报。
///
/// 群模型：
/// - **聚合群**（channel/aggregate，全城）：暗夜大厅的读流，只读（服务端强制）。
/// - **门店群**（门店卡片 avchatroomId）：门店大厅收发同群；暗夜大厅沉浸视图按当前浏览门店发言。
///
/// 只收在线推送、不拉漫游（AVChatRoom 语义）：消息存内存，上限 maxMessages。
/// 监听按页面可见数引用计数注册/反注册（两个大厅页可同时在栈里）。
@MainActor
final class LobbyImSession: ObservableObject {

    static let shared = LobbyImSession()

    /// 消息内存上限
    static let maxMessages = 200
    /// 10013 = 已在群里（本地状态丢了而已），按成功处理
    static let codeAlreadyMember = 10013

    @Published private(set) var messages: [LobbyChatMessage] = []

    /// 聚合群 ID（未配置或未拉取到为 nil）
    private(set) var aggregateGroupId: String?
    /// 自己的 IM 名片缓存（本地回显用）
    private(set) var selfNickname: String?
    private(set) var selfAvatar: String?

    private var joinedGroups: Set<String> = []
    private var joiningGroups: Set<String> = []
    private var refCount = 0
    private var observer: NSObjectProtocol?
    private var imReady = false
    private var loginTask: Task<Void, Never>?
    private var selfProfileSynced = false
    /// 收到的语音 elem 暂存（msgId → elem），上限同消息数，超了整表清
    private var soundElems: [String: V2TIMSoundElem] = [:]

    private init() {}

    // MARK: - 生命周期

    /// 页面可见时调用（引用计数）
    func start() {
        refCount += 1
        registerObserverIfNeeded()
    }

    /// 页面离开时调用；计数归零才反注册，避免两页互踢
    func stop() {
        refCount = max(0, refCount - 1)
        if refCount == 0 {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
            }
            observer = nil
        }
    }

    /// 登出：清消息与群状态（IM 已 logout，监听器不再收）
    func clear() {
        messages = []
        joinedGroups.removeAll()
        joiningGroups.removeAll()
        aggregateGroupId = nil
        soundElems.removeAll()
        imReady = false
        selfNickname = nil
        selfAvatar = nil
        selfProfileSynced = false
        loginTask?.cancel()
        loginTask = nil
        refCount = 0
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
        }
        observer = nil
    }

    private func registerObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .jjtIMNewMessage, object: nil, queue: .main
        ) { [weak self] note in
            guard let msg = note.object as? V2TIMMessage else { return }
            Task { @MainActor in self?.handleIncoming(msg) }
        }
    }

    // MARK: - 登录与进群

    /// 确保 IM 已登录：大厅原本只在密语/聊天页懒登录 IM，从大厅直接发言会撞 sdk not init。
    /// 并发首入只发一次登录（在途任务复用），成功后补 join 在途群 + 同步自己的名片。
    func ensureImReady() async {
        if imReady { return }
        if let task = loginTask {
            await task.value
            return
        }
        let task = Task { [weak self] () -> Void in
            guard let self else { return }
            defer { self.loginTask = nil }
            guard !self.imReady else { return }
            do {
                guard let userId = TokenManager.shared.userId else { return }
                let sig = try await ImAPI.userSig(userId: userId)
                guard !sig.isEmpty else { return }
                try await ImManager.shared.initAndLogin(userSig: sig)
                self.imReady = true
                // 登录成功后把已在等的群补加一遍（首次进入大厅时 join 会因 sdk 未就绪而失败）
                for gid in self.joinedGroups.union(self.joiningGroups) { self.ensureJoined(gid) }
                if let agg = self.aggregateGroupId { self.ensureJoined(agg) }
                self.syncSelfProfile()
            } catch {
                // 静默：发送失败时按「公屏连接中」提示
            }
        }
        loginTask = task
        await task.value
    }

    /// 同步自己的昵称/头像：缓存给本地回显 + 推到腾讯 IM 名片。失败静默（回显退回「我」）。
    private func syncSelfProfile() {
        guard !selfProfileSynced else { return }
        selfProfileSynced = true
        Task {
            guard let user = try? await UserAPI.getUserInfo() else { return }
            let uid = TokenManager.shared.userId ?? 0
            selfNickname = (user.nickname?.isEmpty == false) ? user.nickname : "用户\(uid)"
            selfAvatar = user.avatar
            ImManager.shared.updateSelfInfo(nickname: selfNickname ?? "", avatar: selfAvatar ?? "")
        }
    }

    /// 拉聚合群 ID（失败静默——暗夜大厅退化为「聚合流暂无」空态）
    func loadAggregateGroupId() async {
        aggregateGroupId = try? await LobbyAPI.aggregateGroup()
    }

    /// 加入聚合群（幂等；失败只记日志，聚合流空态由页面兜底）
    func ensureAggregateJoined() {
        ensureJoined(aggregateGroupId)
    }

    /// 加入门店群（幂等；groupId 为空说明该店未建群，静默跳过）
    func ensureStoreJoined(_ groupId: String?) {
        ensureJoined(groupId)
    }

    private func ensureJoined(_ groupId: String?) {
        guard let groupId, !groupId.isEmpty else { return }
        guard !joinedGroups.contains(groupId), !joiningGroups.contains(groupId) else { return }
        joiningGroups.insert(groupId)
        Task {
            do {
                try await ImManager.shared.joinGroup(groupId)
                markJoined(groupId)
            } catch APIError.business(let code, _) where code == Self.codeAlreadyMember {
                markJoined(groupId)
            } catch {
                joiningGroups.remove(groupId)
            }
        }
    }

    private func markJoined(_ groupId: String) {
        joinedGroups.insert(groupId)
        joiningGroups.remove(groupId)
    }

    // MARK: - 收流

    /// 收到新消息：解析 → 去重 → 入队（只保留最近 maxMessages 条）
    private func handleIncoming(_ msg: V2TIMMessage) {
        guard let groupId = msg.groupID else { return }
        guard joinedGroups.contains(groupId) || groupId == aggregateGroupId else { return }
        let meta = Self.parseMeta(msg.cloudCustomData)
        if meta?["sys"] as? String == "seat" {
            NotificationCenter.default.post(name: .jjtLobbySeatEvent, object: nil)
        }
        guard let parsed = Self.parse(msg, meta: meta) else { return }
        // 留住收到的语音 elem：取 URL 与点击自愈都从这里拿对象
        if parsed.kind == .voice, parsed.voicePath == nil, let elem = msg.soundElem {
            if soundElems.count >= Self.maxMessages { soundElems.removeAll() }
            soundElems[parsed.msgId] = elem
        }
        guard !messages.contains(where: { $0.msgId == parsed.msgId }) else { return }
        messages.append(parsed)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
        // 取址在入列之后发起：回填必然命中已入列的气泡
        if parsed.kind == .voice, parsed.voicePath == nil {
            requestVoiceUrl(parsed.msgId)
        }
    }

    /// cloudCustomData → 扇出副本/系统播报元数据（snake_case：store_id/store_name/table_no/seat_state/sys）
    private static func parseMeta(_ data: Data?) -> [String: Any]? {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !obj.isEmpty else { return nil }
        return obj
    }

    /// V2TIMMessage → 公屏消息。只解析文本/语音/图片/表情包四类；未知元素返回 null。
    static func parse(_ msg: V2TIMMessage, meta: [String: Any]?) -> LobbyChatMessage? {
        guard let msgId = msg.msgID, let groupId = msg.groupID else { return nil }
        let textElem = msg.textElem
        // 收流统一取 sender（群消息的 userID 在收流侧为 null——它是单聊对端字段）
        let rawSender = msg.sender ?? msg.userID
        // 系统播报（入座/离桌/换桌）判据先于用户账号判据：发方是后端管理员账号（administrator，
        // 非数字）。「非数字账号 = 系统」与后端发送后回调同口径：数字账号即便带 sys 标记也不算系统行。
        let senderIsNumeric = rawSender.flatMap { Int64($0) } != nil
        if meta?["sys"] != nil, textElem != nil, !senderIsNumeric {
            return LobbyChatMessage(
                msgId: msgId, groupId: groupId, senderId: 0,
                nickname: "", avatar: nil,
                timeSec: Int64(msg.timestamp?.timeIntervalSince1970 ?? 0),
                kind: .system, text: textElem?.text,
                voiceSeconds: 0
            )
        }
        guard let rawSender, let sender = Int64(rawSender) else { return nil }
        let nickname = (msg.nickName?.isEmpty == false) ? msg.nickName! : "用户\(sender)"
        var m = LobbyChatMessage(
            msgId: msgId, groupId: groupId, senderId: sender,
            nickname: nickname, avatar: msg.faceURL,
            timeSec: Int64(msg.timestamp?.timeIntervalSince1970 ?? 0),
            kind: .text, text: nil, voiceSeconds: 0
        )
        if let meta {
            m.storeName = meta["store_name"] as? String
            m.tableNo = meta["table_no"] as? String
            m.seatState = meta["seat_state"] as? String
        }
        switch msg.elemType {
        case .ELEM_TYPE_TEXT:
            guard let text = textElem?.text, !text.isEmpty else { return nil }
            m.kind = .text
            m.text = text
        case .ELEM_TYPE_SOUND:
            guard let sound = msg.soundElem else { return nil }
            m.kind = .voice
            m.voiceSeconds = Int(sound.duration)
            // path 是发方本机的录音文件路径，接收方设备上不存在；统一走 getUrl 回填
        case .ELEM_TYPE_IMAGE:
            guard let imgElem = msg.imageElem, let imgList = imgElem.imageList as? [V2TIMImage] else { return nil }
            let large = imgList.first { $0.type == .IMAGE_TYPE_LARGE }
            m.kind = .image
            m.imageUrl = large?.url ?? imgList.first?.url
        case .ELEM_TYPE_CUSTOM:
            guard let data = msg.customElem?.data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "sticker",
                  let pack = obj["pack"] as? String, !pack.isEmpty,
                  let name = obj["name"] as? String, !name.isEmpty else { return nil }
            m.kind = .sticker
            m.stickerPack = pack
            m.stickerName = name
        default:
            return nil
        }
        return m
    }

    /// 点击尚未拿到 URL 的语音气泡：现场重取下载直链并回填（解析时 getUrl 没回调的自愈口）
    func requestVoiceUrl(_ msgId: String) {
        guard let elem = soundElems[msgId] else { return }
        elem.getUrl { url in
            guard let url, !url.isEmpty else { return }
            Task { @MainActor in
                guard let idx = self.messages.firstIndex(where: { $0.msgId == msgId }) else { return }
                self.messages[idx].voicePath = url
            }
        }
    }

    // MARK: - 发言（IM 直发；服务端发送前回调做罚站限频与禁言判定）

    /// 发文本。返回 nil=成功；返回文案=失败提示（本地回显只在成功后做）。
    @discardableResult
    func sendText(groupId: String?, text: String, seatedInStore: Bool) async -> String? {
        guard let gid = validGroup(groupId) else { return "本店公屏暂未开通（门店群未建）" }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        do {
            try await ImManager.shared.sendText(body, to: gid, isGroup: true)
            appendLocal(gid, .text, text: body)
            return nil
        } catch {
            return reportSendFailure(gid, ImManager.translateError(error.localizedDescription), seatedInStore)
        }
    }

    /// 发语音（本地录音文件路径 + 时长秒）
    @discardableResult
    func sendVoice(groupId: String?, path: String, seconds: Int, seatedInStore: Bool) async -> String? {
        guard let gid = validGroup(groupId) else { return "本店公屏暂未开通（门店群未建）" }
        do {
            try await ImManager.shared.sendSound(path, seconds: Int32(seconds), to: gid, isGroup: true)
            appendLocal(gid, .voice, voiceSeconds: seconds, voicePath: path)
            return nil
        } catch {
            return reportSendFailure(gid, ImManager.translateError(error.localizedDescription), seatedInStore)
        }
    }

    /// 发图片（本地图片路径，SDK 负责上传）
    @discardableResult
    func sendImage(groupId: String?, path: String, seatedInStore: Bool) async -> String? {
        guard let gid = validGroup(groupId) else { return "本店公屏暂未开通（门店群未建）" }
        do {
            try await ImManager.shared.sendImage(path, to: gid, isGroup: true)
            appendLocal(gid, .image, imagePath: path)
            return nil
        } catch {
            return reportSendFailure(gid, ImManager.translateError(error.localizedDescription), seatedInStore)
        }
    }

    /// 发表情包（同单聊贴纸：IM 自定义消息 type=sticker；聚合群扇出只发文本——贴纸只在本店公屏）
    @discardableResult
    func sendSticker(groupId: String?, pack: String, name: String, seatedInStore: Bool) async -> String? {
        guard let gid = validGroup(groupId) else { return "本店公屏暂未开通（门店群未建）" }
        let payload: [String: Any] = ["type": "sticker", "pack": pack, "name": name]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        do {
            try await ImManager.shared.sendCustom(String(data: data, encoding: .utf8) ?? "", to: gid, isGroup: true)
            appendLocal(gid, .sticker, stickerPack: pack, stickerName: name)
            return nil
        } catch {
            return reportSendFailure(gid, ImManager.translateError(error.localizedDescription), seatedInStore)
        }
    }

    private func validGroup(_ groupId: String?) -> String? {
        guard let groupId, !groupId.isEmpty else { return nil }
        return groupId
    }

    /// 发送失败分流：服务端发送前回调拒发时 SDK 只给「被回调拦截」英文描述、不回传后端 ErrorInfo，
    /// 故按用户当前坐席态给最贴切的提示。
    private func reportSendFailure(_ groupId: String, _ translated: String, _ seatedInStore: Bool) -> String {
        if translated.contains("sdk not init") || translated.contains("未初始化") {
            return "公屏连接中，请稍后再发"
        }
        if translated.contains("禁言") {
            return translated
        }
        let blockedByCallback = translated.contains("平台拦截") || translated.contains("禁言")
        if blockedByCallback && !seatedInStore {
            return "发言太快了，喝口水慢慢来 · 罚站限频中，入座本店可免限频"
        }
        return translated
    }

    /// 本地回显一条自己刚发出的消息（IM 不把自己发的推回给自己；msgId 用 local- 前缀）
    private func appendLocal(
        _ groupId: String, _ kind: LobbyChatMessage.Kind,
        text: String? = nil,
        voiceSeconds: Int = 0,
        voicePath: String? = nil,
        imagePath: String? = nil,
        stickerPack: String? = nil,
        stickerName: String? = nil
    ) {
        let msgId = "local-\(Int64(Date().timeIntervalSince1970 * 1000))"
        messages.append(LobbyChatMessage(
            msgId: msgId, groupId: groupId,
            senderId: TokenManager.shared.userId ?? 0,
            nickname: selfNickname ?? "我", avatar: selfAvatar,
            timeSec: Int64(Date().timeIntervalSince1970),
            kind: kind, text: text,
            voiceSeconds: voiceSeconds, voicePath: voicePath,
            imagePath: imagePath,
            stickerPack: stickerPack, stickerName: stickerName
        ))
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }

    // MARK: - 举报

    /// 举报一条公屏消息（只上送 msgId + 原因；业务拒绝走 APIError 由调用方提示）
    func report(msgId: String, reason: LobbyReportReason, detail: String?) async throws {
        try await LobbyAPI.reportMessage(msgId: msgId, reason: reason, detail: detail)
    }
}
