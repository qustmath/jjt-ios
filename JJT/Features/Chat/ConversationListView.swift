import SwiftUI
import ImSDK_Plus

/// 密语（会话列表）— 对齐安卓 ConversationScreen
struct ConversationListView: View {

    @StateObject private var vm = ConversationListViewModel()
    @State private var chatTarget: ChatTarget?
    @State private var peerProfileId: Int64?

    /// 跳转目标（fullScreenCover 用 Binding 呈现）
    struct ChatTarget {
        let peerId: String
        let isGroup: Bool
        let title: String
    }

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶栏
                HStack {
                    Text("密语")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .tracking(3.6)
                        .foregroundStyle(Noir.goldText)
                    Text("MESSAGES")
                        .font(.system(size: 9, design: .serif))
                        .italic()
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                if vm.isLoading, vm.conversations.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.conversations.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(Noir.gold.opacity(0.5))
                        Text("暂无私语")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.conversations) { conv in
                                conversationRow(conv)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .refreshable { await vm.load() }
                }
            }
        }
        .onAppear {
            vm.start()
        }
        .fullScreenCover(isPresented: Binding(
            get: { chatTarget != nil },
            set: { if !$0 { chatTarget = nil } }
        ), onDismiss: { Task { await vm.load() } }) {
            if let t = chatTarget {
                ChatView(peerId: t.peerId, isGroup: t.isGroup, title: t.title)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { peerProfileId != nil },
            set: { if !$0 { peerProfileId = nil } }
        )) {
            if let id = peerProfileId {
                UserProfileView(userId: id)
            }
        }
    }

    private func conversationRow(_ conv: ConversationItem) -> some View {
        HStack(spacing: 12) {
            AppAvatar(url: conv.faceUrl, size: 46,
                      frameURL: conv.avatarFrame, frameScale: conv.avatarFrameScale)
                .frame(width: 46, height: 46)
                .onTapGesture {
                    if !conv.isGroup, let uid = Int64(conv.peerId) { peerProfileId = uid }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conv.showName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    Spacer()
                    Text(conv.timeText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                HStack {
                    Text(conv.lastMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if conv.unreadCount > 0 {
                        Text("\(min(conv.unreadCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Noir.crimson)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(
            conv.pinned ? Noir.gold.opacity(0.35) : Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { chatTarget = ChatTarget(peerId: conv.peerId, isGroup: conv.isGroup, title: conv.showName) }
        .contextMenu {
            Button(conv.pinned ? "取消置顶" : "置顶") { vm.togglePin(conv) }
            Button("删除会话", role: .destructive) { vm.delete(conv) }
        }
    }
}

// MARK: - 会话项 + ViewModel

struct ConversationItem: Identifiable {
    let id: String           // conversationID
    let peerId: String       // userID / groupID
    let isGroup: Bool
    var showName: String
    var faceUrl: String?
    var lastMessage: String
    var unreadCount: Int
    var timeText: String
    var pinned: Bool
    // 头像框（后端补全）
    var avatarFrame: String?
    var avatarFrameScale: Double = 1.0
}

@MainActor
final class ConversationListViewModel: ObservableObject {

    @Published var conversations: [ConversationItem] = []
    @Published var isLoading = false

    private var started = false
    private var refreshObserver: NSObjectProtocol?

    deinit {
        if let refreshObserver { NotificationCenter.default.removeObserver(refreshObserver) }
    }

    /// 进入密语 tab：登录 IM（若未登录）并加载会话；监听数据刷新信号
    func start() {
        if !started {
            started = true
            refreshObserver = NotificationCenter.default.addObserver(
                forName: .jjtIMDataRefresh, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.load() }
            }
        }
        Task { await ensureLoginAndLoad() }
    }

    private func ensureLoginAndLoad() async {
        if !ImManager.shared.isLoggedIn {
            isLoading = true
            do {
                let sig = try await ImAPI.userSig(userId: TokenManager.shared.userId ?? 0)
                try await ImManager.shared.initAndLogin(userSig: sig)
            } catch {
                isLoading = false
                jjtShowToast(error.localizedDescription)
                return
            }
        }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await ImManager.shared.conversationList()
            var items = list.map { conv -> ConversationItem in
                let isGroup = conv.type == .GROUP
                let lastMsg = Self.lastMessageText(conv.lastMessage)
                return ConversationItem(
                    id: conv.conversationID ?? (isGroup ? "group_\(conv.groupID ?? "")" : "c2c_\(conv.userID ?? "")"),
                    peerId: isGroup ? (conv.groupID ?? "") : (conv.userID ?? ""),
                    isGroup: isGroup,
                    showName: conv.showName ?? "",
                    faceUrl: conv.faceUrl,
                    lastMessage: lastMsg,
                    unreadCount: Int(conv.unreadCount),
                    timeText: Self.timeText(conv.lastMessage?.timestamp),
                    pinned: conv.isPinned
                )
            }
            // 单聊：用后端昵称/头像/头像框覆盖 IM showName（对齐安卓 enrichUserInfo）
            let c2cIds = items.filter { !$0.isGroup }.compactMap { Int64($0.peerId) }
            if !c2cIds.isEmpty, let users = try? await UserAPI.getUserInfoList(ids: c2cIds) {
                let map = Dictionary<String, UserInfoResp>(uniqueKeysWithValues: users.map { (String($0.id), $0) })
                items = items.map { item in
                    guard let u = map[item.peerId] else { return item }
                    var item = item
                    if item.showName.isEmpty || item.showName == item.peerId {
                        item.showName = u.nickname ?? "用户\(u.id)"
                    }
                    item.faceUrl = u.avatar ?? item.faceUrl
                    item.avatarFrame = u.avatarFrame
                    item.avatarFrameScale = u.avatarFrameScale ?? 1.0
                    return item
                }
            }
            // 置顶在前，其余按时间倒序（SDK 已按时间排，这里只稳置顶）
            conversations = items.sorted { ($0.pinned ? 1 : 0) > ($1.pinned ? 1 : 0) }
        } catch {
            jjtShowToast(error.localizedDescription)
        }
    }

    func togglePin(_ item: ConversationItem) {
        Task {
            try? await ImManager.shared.pinConversation(item.id, pinned: !item.pinned)
            await load()
        }
    }

    func delete(_ item: ConversationItem) {
        Task {
            try? await ImManager.shared.deleteConversation(item.id)
            await load()
        }
    }

    /// 会话最后一条消息摘要
    private static func lastMessageText(_ msg: V2TIMMessage?) -> String {
        guard let msg else { return "" }
        switch msg.elemType {
        case .ELEM_TYPE_TEXT: return msg.textElem?.text ?? ""
        case .ELEM_TYPE_IMAGE: return "[图片]"
        case .ELEM_TYPE_CUSTOM:
            if let data = msg.customElem?.data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = obj["type"] as? String {
                switch type {
                case "gift": return "[礼物] \(obj["name"] as? String ?? "")"
                case "sticker": return "[表情]"
                case "red_packet": return "[红包] \(obj["greeting"] as? String ?? "")"
                case "post_share": return "[帖子] \(obj["title"] as? String ?? "")"
                case "image": return "[图片]"
                default: return ""
                }
            }
            return ""
        default: return ""
        }
    }

    private static func timeText(_ date: Date?) -> String {
        guard let date else { return "" }
        let now = Date()
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(date) {
            return "昨天"
        } else if cal.dateComponents([.day], from: date, to: now).day ?? 0 < 7 {
            f.dateFormat = "EEE"
            f.locale = Locale(identifier: "zh_CN")
        } else {
            f.dateFormat = "MM-dd"
        }
        return f.string(from: date)
    }
}
