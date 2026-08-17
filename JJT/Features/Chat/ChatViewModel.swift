import Foundation
import ImSDK_Plus

// MARK: - 消息模型（对齐安卓 ChatMessage）

enum ChatMsgKind {
    case text
    case image
    case gift
    case sticker
    case redPacket
    case postShare
}

struct ChatMessage: Identifiable {
    /// 列表项唯一 ID（实例创建即生成；防止同秒同内容 key 冲突）
    let localId = UUID().uuidString
    var id: String { localId }
    /// IM 消息 ID（去重/历史合并用；本地乐观消息为 nil）
    var msgId: String?
    let isMine: Bool
    let senderId: String
    var senderName: String = ""
    var senderAvatar: String?
    let text: String
    let timestamp: Int64
    var kind: ChatMsgKind = .text
    // 图片
    var imageUrl: String?
    var imageThumbUrl: String?
    var imageWidth = 0
    var imageHeight = 0
    // 礼物
    var giftName: String?
    var giftIcon: String?
    var giftCount = 1
    var giftScale = 100
    var giftToName: String?
    // 表情包（pack: white/black，资源在 Resources/stickers/）
    var stickerPack: String?
    var stickerName: String?
    // 红包
    var redPacketId: Int64?
    var redPacketGreeting: String?
    var redPacketWalletType: String?
    var redPacketToName: String?
    // 帖子分享卡片
    var postId: Int64?
    var postTitle: String?
    var postCover: String?
    // 引用
    var quoteText: String?
    var quoteSenderName: String?
    var isAtMe = false
    // 发送者头像框/段位（后端批量补全）
    var senderAvatarFrame: String?
    var senderAvatarFrameScale: Double = 1.0
    var senderLevelName: String?
    var senderLevelNum: Int?
}

// MARK: - ViewModel（对齐安卓 ChatViewModel）

@MainActor
final class ChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var isImReady = false
    @Published var peerName: String?
    @Published var peerAvatar: String?
    @Published var myAvatar: String?
    @Published var error: String?
    @Published var hasMoreHistory = false
    @Published var isLoadingMore = false
    // 对方资料（单聊顶栏）
    @Published var peerAvatarFrame: String?
    @Published var peerAvatarFrameScale: Double = 1.0
    @Published var peerLevelName: String?
    @Published var peerLevelNum: Int?
    // 自己资料（气泡渲染）
    @Published var myAvatarFrame: String?
    @Published var myAvatarFrameScale: Double = 1.0
    @Published var myLevelName: String?
    @Published var myLevelNum: Int?

    private(set) var peerId = ""
    private(set) var isGroup = false

    /// 历史消息游标（SDK 以最旧一条为锚点向前翻页；必须用未过滤原始消息）
    private var oldestRawMsg: V2TIMMessage?
    private var observer: NSObjectProtocol?
    private var refreshObserver: NSObjectProtocol?
    /// 已发过的红包 packetId（同一红包只允许发一条 IM 消息）
    private var sentRedPacketIds = Set<Int64>()

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let refreshObserver { NotificationCenter.default.removeObserver(refreshObserver) }
    }

    /// 初始化 IM 并加载历史（对齐安卓 initIm）
    func initIm(peerId: String, isGroup: Bool) {
        self.peerId = peerId
        self.isGroup = isGroup

        // 单聊：拉对方资料
        if !isGroup, let peerIdLong = Int64(peerId) {
            Task {
                if let users = try? await UserAPI.getUserInfoList(ids: [peerIdLong]),
                   let user = users.first {
                    peerName = user.nickname ?? "用户\(user.id)"
                    peerAvatar = user.avatar
                    peerAvatarFrame = user.avatarFrame
                    peerAvatarFrameScale = user.avatarFrameScale ?? 1.0
                }
                if let profile = try? await UserAPI.getProfile(userId: peerIdLong) {
                    peerLevelName = profile.level?.name
                    peerLevelNum = profile.level?.levelInTier
                }
            }
        }

        // 新消息监听（按当前会话过滤）
        observer = NotificationCenter.default.addObserver(
            forName: .jjtIMNewMessage, object: nil, queue: .main
        ) { [weak self] note in
            guard let msg = note.object as? V2TIMMessage else { return }
            Task { @MainActor in self?.addMessage(msg) }
        }
        // 断线重连/回前台 → 重拉历史
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .jjtIMDataRefresh, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isImReady, !self.peerId.isEmpty else { return }
                await self.loadHistory()
            }
        }

        isLoading = true
        Task {
            do {
                if !ImManager.shared.isLoggedIn {
                    let sig = try await ImAPI.userSig(userId: TokenManager.shared.userId ?? 0)
                    try await ImManager.shared.initAndLogin(userSig: sig)
                }
                isImReady = true
                syncImProfile()
                await loadHistory()
                markRead()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func markRead() {
        let convId = isGroup ? "group_\(peerId)" : "c2c_\(peerId)"
        ImManager.shared.markRead(conversationID: convId)
    }

    /// 同步自己的昵称/头像到 IM 名片
    private func syncImProfile() {
        Task {
            guard let user = try? await UserAPI.getUserInfo() else { return }
            myAvatar = user.avatar
            myAvatarFrame = user.avatarFrame
            myAvatarFrameScale = user.avatarFrameScale ?? 1.0
            myLevelName = user.level?.name
            myLevelNum = user.level?.levelInTier
            ImManager.shared.updateSelfInfo(nickname: user.nickname ?? "用户\(user.id)", avatar: user.avatar ?? "")
        }
    }

    // MARK: - 历史消息

    /// 加载历史（合并而非覆盖：快照返回期间监听器可能已追加新消息）
    func loadHistory() async {
        let raws = isGroup
            ? await ImManager.shared.groupHistory(groupId: peerId)
            : await ImManager.shared.c2cHistory(peerId: peerId)
        oldestRawMsg = raws.last ?? oldestRawMsg
        let parsed = parseMessages(raws)
        let existingIds = Set(messages.compactMap(\.msgId))
        let historyOnly = parsed.filter { $0.msgId == nil || !existingIds.contains($0.msgId!) }
        messages = historyOnly + messages
        hasMoreHistory = raws.count >= 20
        await enrichSenders()
    }

    /// 滚动到顶加载更早（前插去重，不打扰阅读位置）
    func loadMoreHistory() {
        guard !isLoadingMore, hasMoreHistory else { return }
        isLoadingMore = true
        Task {
            let raws = isGroup
                ? await ImManager.shared.groupHistory(groupId: peerId, lastMsg: oldestRawMsg)
                : await ImManager.shared.c2cHistory(peerId: peerId, lastMsg: oldestRawMsg)
            oldestRawMsg = raws.last ?? oldestRawMsg
            let parsed = parseMessages(raws)
            let existingIds = Set(messages.compactMap(\.msgId))
            let olderOnly = parsed.filter { $0.msgId == nil || !existingIds.contains($0.msgId!) }
            messages = olderOnly + messages
            hasMoreHistory = raws.count >= 20
            isLoadingMore = false
            await enrichSenders()
        }
    }

    // MARK: - 消息解析

    private func parseMessages(_ raws: [V2TIMMessage]) -> [ChatMessage] {
        // 过滤发送失败/已撤回（对齐安卓），SDK 历史新→旧，reverse 成旧→新
        let swiftArr = raws as [V2TIMMessage]
        return swiftArr.filter { $0.status != .MSG_STATUS_SEND_FAIL && $0.status != .MSG_STATUS_LOCAL_REVOKED }
            .reversed()
            .compactMap { v2ToChat($0) }
    }

    private func v2ToChat(_ msg: V2TIMMessage) -> ChatMessage? {
        let myId = String(TokenManager.shared.userId ?? 0)
        let isMine = msg.sender == myId
        let quote = parseQuote(msg.cloudCustomData.flatMap { String(data: $0, encoding: .utf8) })
        let atMe = msg.groupAtUserList?.contains(myId) == true

        func base(_ text: String) -> ChatMessage {
            ChatMessage(
                msgId: msg.msgID,
                isMine: isMine,
                senderId: msg.sender ?? "",
                senderName: msg.nickName ?? msg.sender ?? "",
                senderAvatar: msg.faceURL,
                text: text,
                timestamp: Int64(msg.timestamp?.timeIntervalSince1970 ?? 0),
                quoteText: quote?.text,
                quoteSenderName: quote?.senderName,
                isAtMe: atMe
            )
        }

        switch msg.elemType {
        case .ELEM_TYPE_TEXT:
            guard let text = msg.textElem?.text, !text.isEmpty else { return nil }
            return base(text)
        case .ELEM_TYPE_IMAGE:
            guard let img = msg.imageElem, let imgList = img.imageList as? [V2TIMImage] else { return nil }
            let large = imgList.first { $0.type == .IMAGE_TYPE_LARGE }
            let thumb = imgList.first { $0.type == .IMAGE_TYPE_THUMB }
            var m = base("[图片]")
            m.kind = .image
            m.imageUrl = large?.url ?? thumb?.url
            m.imageThumbUrl = thumb?.url ?? large?.url
            m.imageWidth = Int(large?.width ?? 0)
            m.imageHeight = Int(large?.height ?? 0)
            return m
        case .ELEM_TYPE_CUSTOM:
            guard let data = msg.customElem?.data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { return nil }
            switch type {
            case "image":
                guard let url = obj["url"] as? String else { return nil }
                var m = base("[图片]")
                m.kind = .image
                m.imageUrl = url
                m.imageThumbUrl = url
                return m
            case "gift":
                var m = base("[礼物] \(obj["name"] as? String ?? "")")
                m.kind = .gift
                m.giftName = obj["name"] as? String
                m.giftIcon = obj["icon"] as? String
                m.giftCount = (obj["count"] as? Int) ?? 1
                m.giftScale = (obj["scale"] as? Int) ?? 100
                let to = obj["to"] as? String ?? ""
                m.giftToName = to.isEmpty ? nil : to
                return m
            case "sticker":
                guard let pack = obj["pack"] as? String, !pack.isEmpty,
                      let name = obj["name"] as? String, !name.isEmpty else { return nil }
                var m = base("[表情]")
                m.kind = .sticker
                m.stickerPack = pack
                m.stickerName = name
                return m
            case "red_packet":
                let packetId = (obj["packetId"] as? Int64) ?? Int64((obj["packetId"] as? Int) ?? 0)
                guard packetId > 0 else { return nil }
                let greeting = (obj["greeting"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "恭喜发财，大吉大利"
                var m = base("[红包] \(greeting)")
                m.kind = .redPacket
                m.redPacketId = packetId
                m.redPacketGreeting = greeting
                let wt = obj["walletType"] as? String ?? ""
                m.redPacketWalletType = wt.isEmpty ? nil : wt
                let to = obj["to"] as? String ?? ""
                m.redPacketToName = to.isEmpty ? nil : to
                return m
            case "post_share":
                let postId = (obj["postId"] as? Int64) ?? Int64((obj["postId"] as? Int) ?? 0)
                guard postId > 0 else { return nil }
                var m = base("[帖子] \(obj["title"] as? String ?? "")")
                m.kind = .postShare
                m.postId = postId
                m.postTitle = obj["title"] as? String
                let cover = obj["cover"] as? String ?? ""
                m.postCover = cover.isEmpty ? nil : cover
                return m
            default:
                return nil
            }
        default:
            return nil
        }
    }

    // MARK: - 发送

    /// 发送文字（引用经 cloudCustomData 携带）
    func sendText(_ text: String, quote: ChatMessage? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var cloudData: String?
        if let quote {
            cloudData = "{\"t\":\"q\",\"txt\":\"\(String(quote.text.prefix(50)))\",\"sn\":\"\(quote.senderName)\"}"
        }
        Task {
            do {
                try await ImManager.shared.sendText(t, to: peerId, isGroup: isGroup, cloudCustomData: cloudData)
                var m = ChatMessage(isMine: true, senderId: "", senderName: "", senderAvatar: myAvatar,
                                    text: t, timestamp: Int64(Date().timeIntervalSince1970))
                m.quoteText = quote.map { String($0.text.prefix(50)) }
                m.quoteSenderName = quote?.senderName
                appendMine(m)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 发送图片（本地文件路径）
    func sendImage(localPath: String) {
        Task {
            do {
                try await ImManager.shared.sendImage(localPath, to: peerId, isGroup: isGroup)
                var m = ChatMessage(isMine: true, senderId: "", senderName: "", senderAvatar: myAvatar,
                                    text: "[图片]", timestamp: Int64(Date().timeIntervalSince1970))
                m.kind = .image
                m.imageThumbUrl = localPath
                appendMine(m)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 发送礼物消息（送礼成功后调用）
    func sendGiftMessage(gift: GiftItem, count: Int = 1, toName: String? = nil) {
        var obj: [String: Any] = [
            "type": "gift", "name": gift.name,
            "icon": giftDisplayIcon(gift.icon, gift.animationUrl) ?? "",
            "count": count, "scale": gift.iconScale ?? 100,
        ]
        if let toName, !toName.isEmpty { obj["to"] = toName }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return }
        Task {
            do {
                try await ImManager.shared.sendCustom(json, to: peerId, isGroup: isGroup)
                var m = ChatMessage(isMine: true, senderId: "", senderName: "", senderAvatar: myAvatar,
                                    text: "[礼物] \(gift.name)", timestamp: Int64(Date().timeIntervalSince1970))
                m.kind = .gift
                m.giftName = gift.name
                m.giftIcon = giftDisplayIcon(gift.icon, gift.animationUrl)
                m.giftCount = count
                m.giftScale = gift.iconScale ?? 100
                m.giftToName = toName
                appendMine(m)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 发送表情包
    func sendSticker(pack: String, name: String) {
        let json = "{\"type\":\"sticker\",\"pack\":\"\(pack)\",\"name\":\"\(name)\"}"
        Task {
            do {
                try await ImManager.shared.sendCustom(json, to: peerId, isGroup: isGroup)
                var m = ChatMessage(isMine: true, senderId: "", senderName: "", senderAvatar: myAvatar,
                                    text: "[表情]", timestamp: Int64(Date().timeIntervalSince1970))
                m.kind = .sticker
                m.stickerPack = pack
                m.stickerName = name
                appendMine(m)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 发送红包消息（红包 API 创建成功后调用；IM 发送失败则撤回红包退款）
    func sendRedPacketMessage(packetId: Int64, greeting: String, walletType: String, toName: String? = nil) {
        guard sentRedPacketIds.insert(packetId).inserted else { return }
        var obj: [String: Any] = [
            "type": "red_packet", "packetId": packetId, "greeting": greeting, "walletType": walletType,
        ]
        if let toName, !toName.isEmpty { obj["to"] = toName }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return }
        Task {
            do {
                try await ImManager.shared.sendCustom(json, to: peerId, isGroup: isGroup)
                var m = ChatMessage(isMine: true, senderId: "", senderName: "", senderAvatar: myAvatar,
                                    text: "[红包] \(greeting)", timestamp: Int64(Date().timeIntervalSince1970))
                m.kind = .redPacket
                m.redPacketId = packetId
                m.redPacketGreeting = greeting
                m.redPacketWalletType = walletType
                m.redPacketToName = toName
                appendMine(m)
            } catch {
                // IM 消息发送失败 → 撤回红包，金额原路退回
                _ = try? await RedPacketAPI.cancel(packetId: packetId)
                self.error = "红包发送失败：\(error.localizedDescription)（金额已退回钱包）"
            }
        }
    }

    // MARK: - 内部

    private func addMessage(_ msg: V2TIMMessage) {
        // 只收当前会话消息
        let belongs = isGroup ? (msg.groupID == peerId) : (msg.sender == peerId || msg.userID == peerId)
        guard belongs else { return }
        if let mid = msg.msgID, messages.contains(where: { $0.msgId == mid }) { return }
        guard let chatMsg = v2ToChat(msg) else { return }
        messages.append(chatMsg)
        markRead()
        Task { await enrichSenders() }
    }

    private func appendMine(_ m: ChatMessage) {
        messages.append(m)
        Task { await enrichSenders() }
    }

    /// 批量补全发送者头像框/段位（IM 消息只带 faceUrl，走后端批量查）
    private func enrichSenders() async {
        let myId = String(TokenManager.shared.userId ?? 0)
        let foreignIds = Array(Set(messages.map(\.senderId)
            .filter { !$0.isEmpty && $0 != myId }
            .compactMap { Int64($0) }))
        var userMap: [Int64: UserInfoResp] = [:]
        if !foreignIds.isEmpty, let users = try? await UserAPI.getUserInfoList(ids: foreignIds) {
            userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        }
        messages = messages.map { m in
            var m = m
            if m.isMine {
                m.senderAvatarFrame = myAvatarFrame
                m.senderAvatarFrameScale = myAvatarFrameScale
                m.senderLevelName = myLevelName
                m.senderLevelNum = myLevelNum
            } else if let u = userMap[Int64(m.senderId) ?? 0] {
                m.senderAvatarFrame = u.avatarFrame
                m.senderAvatarFrameScale = u.avatarFrameScale ?? 1.0
                m.senderLevelName = u.level?.name
                m.senderLevelNum = u.level?.levelInTier
            }
            return m
        }
    }

    private func parseQuote(_ data: String?) -> (text: String, senderName: String)? {
        guard let data, !data.isEmpty,
              let d = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              obj["t"] as? String == "q" else { return nil }
        return (obj["txt"] as? String ?? "", obj["sn"] as? String ?? "")
    }

    func clearError() { error = nil }
}
