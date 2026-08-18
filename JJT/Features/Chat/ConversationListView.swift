import SwiftUI
import ImSDK_Plus

/// 密语（会话列表）— 对齐安卓 ConversationScreen
struct ConversationListView: View {

    @StateObject private var vm = ConversationListViewModel()
    @State private var chatTarget: ChatTarget?
    @State private var peerProfileId: Int64?
    /// 0=私聊 1=群聊（对齐安卓 ConversationScreen 双 tab）
    @State private var tab = 0
    @State private var showCreateGroup = false
    @State private var showSearchGroup = false

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

                tabBar
                Rectangle().fill(Noir.goldLine).frame(height: 1).opacity(0.4)

                TabView(selection: $tab) {
                    conversationPage(isGroup: false).tag(0)
                    conversationPage(isGroup: true).tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
        .fullScreenCover(isPresented: $showCreateGroup, onDismiss: { Task { await vm.load() } }) {
            // 建群成功：关闭建群页，由会话页打开新群聊天（对齐安卓 popUpTo 行为）
            CreateGroupView(onCreated: { imGroupId, name in
                showCreateGroup = false
                chatTarget = ChatTarget(peerId: imGroupId, isGroup: true, title: name)
            })
        }
        .fullScreenCover(isPresented: $showSearchGroup, onDismiss: { Task { await vm.load() } }) {
            SearchGroupView()
        }
    }

    // MARK: - 私聊/群聊 tab（绯红下划线，对齐安卓）

    private var tabBar: some View {
        HStack(spacing: 24) {
            tabButton(index: 0, label: "私聊")
            tabButton(index: 1, label: "群聊")
            Spacer()
            // 群聊 tab：搜索群 + 建群（对齐安卓群聊 tab 操作钮）
            if tab == 1 {
                Button { showSearchGroup = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Noir.gold.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Button { showCreateGroup = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(LinearGradient(colors: [Noir.crimson, Noir.wine],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func tabButton(index: Int, label: String) -> some View {
        let selected = tab == index
        return Button {
            withAnimation { tab = index }
        } label: {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Noir.crimsonHot : Color.white.opacity(0.4))
                Rectangle()
                    .fill(selected
                          ? LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 24, height: 2.5)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 会话分页

    @ViewBuilder
    private func conversationPage(isGroup: Bool) -> some View {
        let filtered = vm.conversations.filter { $0.isGroup == isGroup }
        if vm.isLoading, vm.conversations.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(Noir.gold)
                Spacer()
            }
        } else if filtered.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(Noir.gold.opacity(0.5))
                Text(isGroup ? "暂无群聊，去圈子逛逛吧" : "暂无私语")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { conv in
                        conversationRow(conv)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .refreshable { await vm.load() }
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
                    if conv.isOfficial {
                        Text("官方")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(LinearGradient(colors: [Noir.goldPale, Noir.gold],
                                                       startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
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
            // 官方号不能删会话（不能取关，对齐安卓禁止滑动删除）
            if !conv.isOfficial {
                Button("删除会话", role: .destructive) { vm.delete(conv) }
            }
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
    /// 官方号（1001 荆棘兔 / 1002 客服 / 1003 VIP客服）
    var isOfficial: Bool = false
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

    /// 官方号（数字 ID：1001 荆棘兔 / 1002 客服 / 1003 VIP客服），注册即自动关注，会话始终显示
    private static let officialAccounts: [(id: String, name: String)] = [
        ("1001", "荆棘兔"), ("1002", "客服"), ("1003", "VIP客服")
    ]

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
            // 官方号会话始终显示（无 IM 会话时补一条空会话）
            for official in Self.officialAccounts where !items.contains(where: { !$0.isGroup && $0.peerId == official.id }) {
                items.append(ConversationItem(
                    id: "c2c_\(official.id)", peerId: official.id, isGroup: false,
                    showName: official.name, faceUrl: nil, lastMessage: "",
                    unreadCount: 0, timeText: "", pinned: false, isOfficial: true
                ))
            }
            // 已有 IM 会话的官方号补 isOfficial 标记与固定名称
            items = items.map { item in
                guard !item.isGroup, let official = Self.officialAccounts.first(where: { $0.id == item.peerId }) else { return item }
                var item = item
                item.isOfficial = true
                if item.showName.isEmpty || item.showName == item.peerId { item.showName = official.name }
                return item
            }
            // 单聊：用后端昵称/头像/头像框覆盖 IM showName（官方号除外，对齐安卓 enrichUserInfo）
            let c2cIds = items.filter { !$0.isGroup && !$0.isOfficial }.compactMap { Int64($0.peerId) }
            // 缓存立即填充：头像框即时显示，不等 1 秒网络往返（对齐安卓 UserDisplayCache）
            let cached = UserDisplayCache.getMap(c2cIds)
            if !cached.isEmpty {
                items = items.map { item in
                    guard !item.isGroup, let uid = Int64(item.peerId), let d = cached[uid] else { return item }
                    var item = item
                    if item.showName.isEmpty || item.showName == item.peerId, let n = d.nickname {
                        item.showName = n
                    }
                    if item.faceUrl == nil { item.faceUrl = d.avatar }
                    item.avatarFrame = d.avatarFrame
                    item.avatarFrameScale = d.avatarFrameScale
                    return item
                }
            }
            if !c2cIds.isEmpty, let users = try? await UserAPI.getUserInfoList(ids: c2cIds) {
                UserDisplayCache.putAll(users.map { $0.toCachedDisplay() })
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
