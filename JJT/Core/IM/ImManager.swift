import Foundation
import ImSDK_Plus

/// IM 全局通知
extension Notification.Name {
    /// 新消息（object: V2TIMMessage）
    static let jjtIMNewMessage = Notification.Name("jjtIMNewMessage")
    /// 未读总数变化（object: Int）
    static let jjtIMUnreadChanged = Notification.Name("jjtIMUnreadChanged")
    /// 断线重连/回前台 → 各页重拉数据（对齐安卓 dataRefreshSignal）
    static let jjtIMDataRefresh = Notification.Name("jjtIMDataRefresh")
    /// 被踢下线 / userSig 过期 → 需重新登录 IM
    static let jjtIMNeedRelogin = Notification.Name("jjtIMNeedRelogin")
}

/// 腾讯 IM SDK 管理器（单例，对齐安卓 ImManager）
@MainActor
final class ImManager: NSObject {

    static let shared = ImManager()

    private(set) var isLoggedIn = false
    private var sdkInited = false

    private let sdkListener = SDKListener()
    private var msgListener: AdvancedMsgListener?
    private var convListener: ConversationListener?

    private override init() {
        super.init()
        sdkListener.owner = self
    }

    // MARK: - 初始化 + 登录

    /// 初始化并登录 IM（userSig 由后端签发）。重复调用：已登录直接成功。
    func initAndLogin(userSig: String) async throws {
        if isLoggedIn { return }
        if !sdkInited {
            let config = V2TIMSDKConfig()
            let ok: Bool = await withCheckedContinuation { cont in
                sdkListener.onInitResult = { cont.resume(returning: $0) }
                V2TIMManager.sharedInstance().initSDK(Config.imSDKAppID, config: config, listener: sdkListener)
            }
            guard ok else { throw APIError.business(code: -1, message: "IM 初始化失败") }
            sdkInited = true
        }
        let userId = String(TokenManager.shared.userId ?? 0)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            V2TIMManager.sharedInstance().login(userId, userSig: userSig) {
                self.isLoggedIn = true
                self.registerGlobalListeners()
                cont.resume()
            } fail: { code, msg in
                cont.resume(throwing: APIError.business(code: Int(code), message: "IM登录失败: \(msg ?? "")"))
            }
        }
    }

    private func registerGlobalListeners() {
        if msgListener == nil {
            let l = AdvancedMsgListener()
            msgListener = l
            V2TIMManager.sharedInstance().addAdvancedMsgListener(l)
        }
        if convListener == nil {
            let l = ConversationListener()
            convListener = l
            V2TIMManager.sharedInstance().addConversationListener(l)
        }
    }

    /// App 回前台：广播数据刷新（对齐安卓 notifyForeground）
    func notifyForeground() {
        if isLoggedIn {
            NotificationCenter.default.post(name: .jjtIMDataRefresh, object: nil)
        }
    }

    func logout() {
        V2TIMManager.sharedInstance().logout {} fail: {}
        isLoggedIn = false
    }

    // MARK: - SDK 回调（由 listener 转发）

    fileprivate func handleConnectSuccess() {
        if sdkInited {
            // 运行期断线重连成功 → 通知各页重拉数据
            NotificationCenter.default.post(name: .jjtIMDataRefresh, object: nil)
        }
    }

    fileprivate func handleKickedOrExpired() {
        isLoggedIn = false
        NotificationCenter.default.post(name: .jjtIMNeedRelogin, object: nil)
    }

    // MARK: - 会话

    func conversationList() async throws -> [V2TIMConversation] {
        try await withCheckedThrowingContinuation { cont in
            V2TIMManager.sharedInstance().getConversationList(0, count: 100) { result in
                cont.resume(returning: result?.conversationList ?? [])
            } fail: { code, msg in
                cont.resume(throwing: APIError.business(code: Int(code), message: msg ?? "获取会话失败"))
            }
        }
    }

    func totalUnreadCount() async -> Int {
        await withCheckedContinuation { cont in
            V2TIMManager.sharedInstance().getTotalUnreadMessageCount { count in
                cont.resume(returning: Int(count))
            } fail: { _, _ in
                cont.resume(returning: 0)
            }
        }
    }

    func markRead(conversationID: String) {
        V2TIMManager.sharedInstance().cleanConversationUnreadMessageCount(conversationID, cleanTimestamp: 0, cleanSequence: 0) {} fail: {}
    }

    func deleteConversation(_ conversationID: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            V2TIMManager.sharedInstance().deleteConversation(conversationID) {
                cont.resume()
            } fail: { code, msg in
                cont.resume(throwing: APIError.business(code: Int(code), message: msg ?? "删除失败"))
            }
        }
    }

    func pinConversation(_ conversationID: String, pinned: Bool) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            V2TIMManager.sharedInstance().pinConversation(conversationID, isPinned: pinned) {
                cont.resume()
            } fail: { code, msg in
                cont.resume(throwing: APIError.business(code: Int(code), message: msg ?? "操作失败"))
            }
        }
    }

    // MARK: - 历史消息（游标分页，对齐安卓：lastMsg 用最旧原始消息）

    func c2cHistory(peerId: String, count: Int32 = 20, lastMsg: V2TIMMessage? = nil) async -> [V2TIMMessage] {
        await withCheckedContinuation { cont in
            V2TIMManager.sharedInstance().getC2CHistoryMessageList(peerId, count: count, lastMsg: lastMsg) { msgs in
                cont.resume(returning: msgs ?? [])
            } fail: { _, _ in
                cont.resume(returning: [])
            }
        }
    }

    func groupHistory(groupId: String, count: Int32 = 20, lastMsg: V2TIMMessage? = nil) async -> [V2TIMMessage] {
        await withCheckedContinuation { cont in
            V2TIMManager.sharedInstance().getGroupHistoryMessageList(groupId, count: count, lastMsg: lastMsg) { msgs in
                cont.resume(returning: msgs ?? [])
            } fail: { _, _ in
                cont.resume(returning: [])
            }
        }
    }

    // MARK: - 发送

    /// text / imagePath / customData 三选一由调用方组合；isGroup 决定路由
    func sendText(_ text: String, to peerId: String, isGroup: Bool, cloudCustomData: String? = nil) async throws {
        guard let msg = V2TIMManager.sharedInstance().createTextMessage(text) else { return }
        msg.cloudCustomData = cloudCustomData
        try await send(msg, to: peerId, isGroup: isGroup)
    }

    func sendImage(_ localPath: String, to peerId: String, isGroup: Bool) async throws {
        guard let msg = V2TIMManager.sharedInstance().createImageMessage(localPath) else { return }
        try await send(msg, to: peerId, isGroup: isGroup)
    }

    func sendCustom(_ jsonData: String, to peerId: String, isGroup: Bool) async throws {
        guard let msg = V2TIMManager.sharedInstance().createCustomMessage(Data(jsonData.utf8)) else { return }
        try await send(msg, to: peerId, isGroup: isGroup)
    }

    private func send(_ msg: V2TIMMessage, to peerId: String, isGroup: Bool) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            V2TIMManager.sharedInstance().sendMessage(
                msg,
                receiver: isGroup ? nil : peerId,
                groupID: isGroup ? peerId : nil,
                priority: .PRIORITY_DEFAULT,
                onlineUserOnly: false,
                offlinePushInfo: nil,
                progress: nil
            ) {
                cont.resume()
            } fail: { code, desc in
                cont.resume(throwing: APIError.business(code: Int(code), message: Self.translateError(desc)))
            }
        }
    }

    /// 设置自己的 IM 名片（昵称+头像）
    func updateSelfInfo(nickname: String, avatar: String) {
        let info = V2TIMUserFullInfo()
        info.nickName = nickname
        info.faceURL = avatar
        V2TIMManager.sharedInstance().setSelfInfo(info) {} fail: { _, _ in }
    }

    /// 翻译 IM SDK 常见英文错误为中文（对齐安卓 translateError）
    private static func translateError(_ desc: String?) -> String {
        let msg = desc ?? "发送失败"
        let lower = msg.lowercased()
        if lower.contains("only send one message") || lower.contains("non-friend") || lower.contains("at most once") {
            return "非好友只能发送一条消息"
        }
        if lower.contains("not a friend") || lower.contains("not friend") || lower.contains("friend check failed") || lower.contains("need friend") {
            return "对方不是您的好友"
        }
        if lower.contains("blocked") || lower.contains("blacklist") {
            return "消息被拒收"
        }
        if lower.contains("forbid the message") || lower.contains("callback prior to sending") {
            return lower.contains("one-to-one") ? "你们还未互相关注，只能发送一条消息" : "消息被平台拦截，发送失败"
        }
        if lower.contains("muted") || lower.contains("silent") || lower.contains("forbidden") {
            return "您已被禁言"
        }
        return msg
    }
}

// MARK: - SDK 监听器（ObjC 协议桥接）

private final class SDKListener: NSObject, V2TIMSDKListener {
    weak var owner: ImManager?
    var onInitResult: ((Bool) -> Void)?

    func onConnectSuccess() {
        onInitResult?(true)
        onInitResult = nil
        Task { @MainActor in self.owner?.handleConnectSuccess() }
    }

    func onConnectFailed(_ code: Int32, msg: String?) {
        if let cb = onInitResult {
            onInitResult = nil
            cb(false)
        }
        // 运行期重连失败：SDK 自动重试，静默
    }

    func onKickedOffline() {
        Task { @MainActor in self.owner?.handleKickedOrExpired() }
    }

    func onUserSigExpired() {
        Task { @MainActor in self.owner?.handleKickedOrExpired() }
    }
}

private final class AdvancedMsgListener: NSObject, V2TIMAdvancedMsgListener {
    func onRecvNewMessage(_ msg: V2TIMMessage?) {
        guard let msg else { return }
        NotificationCenter.default.post(name: .jjtIMNewMessage, object: msg)
    }
}

private final class ConversationListener: NSObject, V2TIMConversationListener {
    func onTotalUnreadMessageCountChanged(_ totalUnreadCount: UInt64) {
        NotificationCenter.default.post(name: .jjtIMUnreadChanged, object: Int(totalUnreadCount))
    }

    func onConversationChanged(_ conversationList: [V2TIMConversation]?) {
        // 会话内容变化 → 会话列表页重拉
        NotificationCenter.default.post(name: .jjtIMDataRefresh, object: nil)
    }
}
