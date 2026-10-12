import SwiftUI

/// 语音房（对齐安卓 VoiceRoomScreen）：LiveKit 语音 + IM 群公屏 + 麦位管理。
///
/// **三条真值来源各归其位**（详见 VoiceRoomSession）：
/// 麦位/在房=服务端 · 说话音波=LiveKit ActiveSpeakersChanged · 能否发声=token 的 canPublish。
/// 收到官方号麦位通知会自动重拉 token 重连——这是「被抱上麦却发不出声」的唯一解。
///
/// 进房三态（服务端 join 的返回）：joined/already 直接进 → 进 IM 群 + 连语音；
/// applied（审批制）停在等待态并按 10s 轮询详情；invite（邀请制）非成员被拒（049）给「等房主邀请」态。
struct VoiceRoomView: View {

    let storeId: Int64
    let roomId: Int64
    let storeName: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = VoiceRoomSession.shared
    @ObservedObject private var imSession = LobbyImSession.shared

    /// 票 17 的预览壳（无真实房间）：保留可达性，但不连语音不发言
    private var preview: Bool { roomId <= 0 }

    @State private var joinState: JoinState = .joining
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var inputText = ""
    @State private var sending = false
    @State private var selfCard: MicMember?
    @State private var opsOpen = false
    /// 管理面板外部动作计数：抱麦等动作后 +1，面板重拉申请/进房列表（核销的申请立即消失）
    @State private var opsRefreshTick = 0
    @State private var inviteOpen = false
    @State private var leaveConfirm = false
    /// 本地记录「已申请上麦」（服务端没有「我的申请状态」查询——上麦申请只对房主/管理麦可见）
    @State private var micApplied = false
    /// 房主/管理麦：轮询上麦待审数（管理钮挂红点）
    @State private var pendingMicApplies = 0
    @State private var chatNav: NightLobbyView.LobbyNavTarget?
    @State private var giftNav: NightLobbyView.LobbyNavTarget?

    enum JoinState: Equatable {
        case joining, inRoom, applied, inviteOnly, failed, preview
    }

    /// 房间内临时成员视图（资料卡用；id/昵称/头像）
    struct MicMember: Identifiable {
        let userId: Int64
        let nickname: String?
        let avatar: String?
        var seatNo: Int? = nil
        var id: Int64 { userId }
    }

    private var myUserId: Int64 { TokenManager.shared.userId ?? -1 }
    private var me: LobbyMicItem? {
        (session.detail?.mics ?? []).first { $0.userId == myUserId }
    }
    private var onMic: Bool { me != nil }
    private var iAmHost: Bool { session.detail?.ownerUserId == myUserId }
    private var iAmAdmin: Bool { me?.role == "admin" }
    private var canManage: Bool { iAmHost || iAmAdmin }

    private var roomGroupId: String? { session.detail?.imGroupIdStr }
    private var roomMessages: [LobbyChatMessage] {
        guard let gid = roomGroupId, !gid.isEmpty else { return [] }
        return imSession.messages.filter { $0.groupId == gid }
    }

    private var compliance: String {
        if let c = session.detail?.complianceText, !c.isEmpty { return c }
        return "平台将24小时巡查违规内容，对私下交易、发布广告内容等予以严厉处理。共同营造善意、平等、真实的聊天室氛围。"
    }

    var body: some View {
        ZStack {
            LobbyColors.bg.ignoresSafeArea()
            BlurredStoreBackdrop(cover: nil)

            // 键盘弹出整列压缩，底栏不会与键盘叠加出空隙
            VStack(spacing: 0) {
                topBar
                titleSection
                mainSection
                bottomBar
            }

            if let t = toast { LobbyToastView(text: t) }

            // 麦位成员资料卡（房间内没有消息 id，故不带举报入口）
            if let m = selfCard { memberCard(m) }
        }
        .task { await joinRoom() }
        .task(id: joinState) {
            // 审批制待批：10s 轮询详情，通过后服务端把人加进群（inRoom 变真）
            guard joinState == .applied else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                _ = try? await session.refresh()
                if session.detail?.inRoom == true {
                    joinState = .inRoom
                    showToast("房主已同意，进房成功")
                    break
                }
            }
        }
        .task(id: joinState) {
            // 在房：5s 轮询详情兜底（麦位变化只 C2C 通知当事人，其他成员的麦位视图会陈旧）
            guard joinState == .inRoom, !preview else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                try? await session.refresh()
            }
        }
        .task(id: JoinTaskKey(canManage: canManage, inRoom: joinState == .inRoom, preview: preview)) {
            // 房主/管理麦：轮询上麦待审数（管理钮挂红点；申请后房主有提示）
            guard canManage, joinState == .inRoom, !preview else {
                pendingMicApplies = 0
                return
            }
            while !Task.isCancelled {
                pendingMicApplies = (try? await session.listMicApplications())?.count ?? 0
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
            }
        }
        .onAppear {
            LobbyImSession.shared.start()
            VoiceRoomSession.shared.start()
        }
        .onDisappear {
            LobbyImSession.shared.stop()
            VoiceRoomSession.shared.stop()
        }
        .onReceive(session.$notice) { n in
            guard let n else { return }
            showToast(n)
            session.clearNotice()
        }
        // 房被解散/服务端删房把 RTC 踢下线：提示后自动退出
        .onReceive(session.$roomClosed) { closed in
            guard let closed else { return }
            showToast(closed)
            session.consumeRoomClosed()
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        }
        .onChange(of: onMic) { _, nowOn in
            // 被抱上麦即申请已被消费：清本地标志，否则之后下麦会误显「已申请上麦」横幅
            if nowOn { micApplied = false }
        }
        // 进房失败不悬挂：toast 已给原因，短停后自动退回列表
        .onChange(of: joinState) { _, newValue in
            if newValue == .failed {
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    dismiss()
                }
            }
            // 在房：进 IM 群（公屏）+ 连语音
            if newValue == .inRoom {
                Task {
                    await LobbyImSession.shared.ensureImReady()
                    LobbyImSession.shared.ensureStoreJoined(session.detail?.imGroupIdStr)
                    VoiceRoomSession.shared.enter(roomId: roomId)
                }
            }
        }
        // 邀请好友进房（复用大厅好友选择）
        .sheet(isPresented: $inviteOpen) {
            LobbyFriendPickerSheet(
                title: "邀请好友进房",
                onDismiss: { inviteOpen = false },
                onPick: { u in
                    inviteOpen = false
                    session.runAction {
                        try await session.invite(inviteeUserId: u.userId)
                        showToast("已邀请 \(u.nickname ?? "好友")（进房后即可语音）")
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(LobbyColors.panel)
        }
        // 房间管理（房主/管理麦）
        .sheet(isPresented: $opsOpen) {
            VoiceRoomOpsSheet(
                isHost: iAmHost,
                roomTitle: session.detail?.title ?? "房间",
                myUserId: myUserId,
                refreshTick: opsRefreshTick,
                avatarOf: { id in avatarOfById(id) },
                onDismiss: { opsOpen = false },
                onSeat: { uid in
                    session.runAction {
                        try await session.seatUser(targetUserId: uid, seatNo: nil)
                        showToast("已抱上麦")
                        opsRefreshTick += 1
                    }
                },
                onMute: { seatNo, muted in
                    session.runAction {
                        try await session.muteMic(seatNo: seatNo, muted: muted)
                        showToast(muted ? "已闭麦" : "已开麦")
                    }
                },
                onKick: { uid in
                    session.runAction {
                        try await session.kickMic(targetUserId: uid)
                        showToast("已移下麦位")
                    }
                },
                onKickFromRoom: { uid in
                    session.runAction {
                        try await session.kickFromRoom(targetUserId: uid)
                        showToast("已移出房间")
                    }
                },
                onRole: { seatNo, admin in
                    session.runAction {
                        try await session.setMicRole(seatNo: seatNo, role: admin ? "admin" : "normal")
                        showToast(admin ? "已设为管理麦" : "已取消管理麦")
                    }
                },
                onCloseRoom: {
                    session.runAction {
                        try await session.closeRoom()
                        opsOpen = false
                        showToast("房间已关闭")
                        dismiss()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(LobbyColors.panel)
        }
        .alert(
            onMic ? "退出房间？你在麦上" : "退出房间？",
            isPresented: $leaveConfirm
        ) {
            Button("退房 · 放麦", role: .destructive) {
                leaveConfirm = false
                Task {
                    try? await VoiceRoomSession.shared.leave()
                    dismiss()
                }
            }
            Button("留在房里") {
                // 只是停止收听，下次进来直接听（审批制房间不用重新申请）
                leaveConfirm = false
                dismiss()
            }
        } message: {
            Text("「退房」会离开房间并放麦；「留在房里」只是停止收听，下次进来直接听（审批制房间不用重新申请）。")
        }
        .fullScreenCover(item: $chatNav) { nav in
            ChatView(peerId: String(nav.userId), isGroup: false, title: nav.nickname)
        }
        .fullScreenCover(item: $giftNav) { nav in
            GiftCenterView(receiverId: nav.userId, receiverName: nav.nickname)
        }
    }

    struct JoinTaskKey: Equatable {
        let canManage: Bool
        let inRoom: Bool
        let preview: Bool
    }

    // MARK: - 进房

    private func joinRoom() async {
        if preview {
            joinState = .preview
            return
        }
        do {
            let r = try await VoiceRoomAPI.join(roomId: roomId)
            switch r.result {
            case "joined", "already": joinState = .inRoom
            case "applied": joinState = .applied
            default: joinState = .inRoom // 后端新增结果值时按已进房处理（拉详情自证）
            }
        } catch let APIError.business(code, _) where code == VoiceRoomConst.codeVoiceInviteOnly {
            // 邀请制非成员是预期业务态（按错误码判定——文案会变，码稳定）
            joinState = .inviteOnly
        } catch {
            joinState = .failed
            showToast(error.localizedDescription)
            // 房间已关/不存在（055）：大厅顶栏的「在语音房」入口已过期，同步摘掉
            if let apiError = error as? APIError, case .business(let code, _) = apiError,
               code == VoiceRoomConst.codeVoiceRoomGone {
                VoiceRoomSession.shared.clearStalePresence(roomId)
            }
        }
    }

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toast = msg
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    /// 成员头像：房间公屏消息发送者资料 → Session 资料兜底表（没说过话的成员也有头像）
    private func avatarOfById(_ id: Int64) -> String? {
        if let p = session.profiles[id] { return p.avatar }
        return roomMessages.first { $0.senderId == id }?.avatar
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 8) {
            LobbyIconAction(icon: "chevron.left", tint: .white.opacity(0.7)) {
                if joinState == .inRoom && !preview {
                    leaveConfirm = true
                } else {
                    dismiss()
                }
            }
            HStack(spacing: 6) {
                Text("麦")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(3)
                Text("\(storeName ?? "门店") · 表演区")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.55))
            .overlay(Capsule().stroke(Noir.gold.opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
            Spacer()
            if !preview && joinState == .inRoom {
                ConnChip(conn: session.conn) {
                    Task { await VoiceRoomSession.shared.connectLiveKit() }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
    }

    // MARK: - 房名 + 模式 + 在房成员条 + 合规条 + 状态横幅

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(session.detail?.title ?? (preview ? "表演区语音房（预览）" : "语音房"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
                // 详情没拉到（房间不存在/未进房）时不编造进房模式
                if let mode = session.detail?.mode {
                    Text(voiceRoomModeLabel(mode))
                        .font(.system(size: 8))
                        .foregroundStyle(LobbyColors.goldLight)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(Capsule().stroke(LobbyColors.goldLight.opacity(0.45), lineWidth: 1))
                }
                let onMicCount = (session.detail?.mics ?? []).filter { $0.userId != nil }.count
                Text("麦上 \(onMicCount)/\(session.detail?.mics?.count ?? 8)")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // 在房成员条（LiveKit 实时参会者 + 自己）
            if joinState == .inRoom && !preview {
                memberStrip
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            Text(compliance)
                .font(.system(size: 8.5))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.15), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 14)
                .padding(.top, 6)

            statusBanner
                .padding(.horizontal, 14)
                .padding(.top, 6)
        }
    }

    private var memberStrip: some View {
        HStack(spacing: 5) {
            Text("在房 \(session.peers.count + 1)")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(LobbyColors.goldLight)
            MemberBubble(
                url: me?.avatar ?? avatarOfById(myUserId),
                name: "我",
                mine: true)
            ForEach(Array(session.peers.prefix(8))) { p in
                MemberBubble(
                    url: avatarOfById(p.userId),
                    name: (p.name?.isEmpty == false) ? p.name! : (session.profiles[p.userId]?.nickname ?? "用户\(p.userId)"))
            }
            if session.peers.count > 8 {
                Text("…共 \(session.peers.count + 1) 人")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch joinState {
        case .applied:
            StatusBannerView(text: "已申请进房 · 等房主审批（通过后自动进入）", color: LobbyColors.goldLight) {
                Task { try? await VoiceRoomSession.shared.refresh() }
            }
        case .inviteOnly:
            StatusBannerView(text: "邀请制房间 · 等房主拉你进房", color: LobbyColors.goldLight) {
                Task { try? await VoiceRoomSession.shared.refresh() }
            }
        case .failed:
            StatusBannerView(text: "进房失败 · 可能是房间已关闭或网络异常", color: LobbyColors.crimson) {
                Task { try? await VoiceRoomSession.shared.refresh() }
            }
        case .joining:
            StatusBannerView(text: "正在进房…", color: .white.opacity(0.5)) {}
        default:
            EmptyView()
        }
    }

    // MARK: - 主区：左公屏 + 右麦位

    private var mainSection: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 8) {
                if joinState == .inRoom && !preview {
                    LobbyChatList(
                        messages: roomMessages,
                        showStorePrefix: false,
                        emptyText: "房间公屏暂无消息 · 打个招呼吧 ✨",
                        onUserClick: { msg in
                            // 点人 → 资料卡（可抱麦/送礼/私信）：只有真用户行有 userId
                            if msg.senderId > 0 {
                                selfCard = MicMember(userId: msg.senderId, nickname: msg.nickname, avatar: msg.avatar)
                            }
                        }
                    )
                } else {
                    ZStack {
                        Text(joinState == .preview
                             ? "预览模式 · 未连接真实房间"
                             : (joinState == .applied || joinState == .inviteOnly ? "进房后即可参与公屏聊天"
                                : joinState == .failed ? "进房失败 · 公屏不可用" : "正在进房…"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                RoomChatBar(
                    text: $inputText,
                    enabled: joinState == .inRoom && !preview,
                    sending: sending,
                    hint: onMic ? "在麦上，也可以打字…" : "说点什么…",
                    onSend: sendRoomText
                )
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            micColumn
                .padding(.trailing, 8)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity)
    }

    private func sendRoomText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sending = true
        Task {
            // 房间公屏不做大厅那套罚站限频：传 true 避免把大厅限频文案带到房间里
            let err = await LobbyImSession.shared.sendText(groupId: roomGroupId, text: text, seatedInStore: true)
            sending = false
            if let err { showToast(err) }
        }
    }

    /// 麦位列（1 号麦房主固定，2-8 号）。可滚动：8 个麦位高度超屏
    private var micColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(1...8, id: \.self) { no in
                    let mic = (session.detail?.mics ?? []).first { $0.seatNo == no }
                    let uid = mic?.userId
                    MicSlotView(
                        seatNo: no,
                        nickname: mic?.nickname ?? (no == 1 ? session.detail?.ownerNickname : nil),
                        avatar: mic?.avatar,
                        role: voiceMicRoleLabel(mic?.role),
                        muted: mic?.muted == true,
                        speaking: uid != nil && session.speaking.contains(uid!),
                        mine: uid != nil && uid == myUserId,
                        big: no == 1
                    ) {
                        handleMicTap(seatNo: no, uid: uid, mic: mic)
                    }
                }

                if canManage && !preview {
                    manageButton
                } else if !preview {
                    inviteButton
                }
            }
            .padding(.vertical, 2)
        }
        .frame(width: 74)
    }

    private func handleMicTap(seatNo: Int, uid: Int64?, mic: LobbyMicItem?) {
        if uid == nil {
            // 虚位：房主/管理麦可去申请列表抱人上麦；已在麦上的人别再引导「申请上麦」
            if canManage {
                opsOpen = true
            } else if onMic {
                showToast("你已在麦上 · 换位请先下麦")
            } else {
                showToast("虚位 · 可申请上麦")
            }
        } else if uid == myUserId {
            session.runAction {
                try await session.leaveMic()
                showToast("已下麦")
            }
        } else {
            selfCard = MicMember(userId: uid!, nickname: mic?.nickname, avatar: mic?.avatar, seatNo: seatNo)
        }
    }

    private var manageButton: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(systemName: "person.3")
                    .font(.system(size: 13))
                    .foregroundStyle(LobbyColors.goldPale)
                Text("管理")
                    .font(.system(size: 8.5))
                    .foregroundStyle(LobbyColors.goldPale)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(LobbyColors.crimson.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LobbyColors.crimson.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture { opsOpen = true }

            if pendingMicApplies > 0 {
                // 固定尺寸正圆徽标
                Text(pendingMicApplies > 9 ? "9+" : "\(pendingMicApplies)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(LobbyColors.crimson))
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var inviteButton: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(LobbyColors.goldLight)
            Text("邀请")
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { inviteOpen = true }
    }

    // MARK: - 底部：麦位动作

    private var bottomBar: some View {
        HStack(spacing: 8) {
            if preview {
                BottomHintView(text: "预览模式 · 未连接语音")
            } else if joinState != .inRoom {
                BottomHintView(text: joinState == .applied ? "等待房主审批…"
                               : joinState == .inviteOnly ? "邀请制 · 等房主拉人"
                               : joinState == .failed ? "进房失败" : "正在进房…")
            } else if onMic {
                // 在麦上：麦克风开关（本地）+ 下麦
                MicToggleButton(
                    on: session.localMicOn,
                    enabled: me?.muted != true
                ) {
                    Task {
                        if await VoiceRoomSession.shared.requestMicPermission() {
                            await VoiceRoomSession.shared.setLocalMic(on: !session.localMicOn)
                        } else {
                            showToast("未授权麦克风，无法出声（可继续听）")
                        }
                    }
                }
                PrimaryBarButton(label: "下麦", icon: "mic.slash") {
                    session.runAction {
                        try await session.leaveMic()
                        showToast("已下麦")
                    }
                }
            } else if micApplied {
                BottomHintView(text: "已申请上麦 · 等房主抱你上麦")
            } else {
                PrimaryBarButton(label: iAmHost ? "回到麦上" : "申请上麦", icon: "mic") {
                    session.runAction {
                        try await session.applyMic()
                        // 房主在服务端直上 1 号麦（无需审批）；普通成员仍待审
                        try? await session.refresh()
                        if !iAmHost {
                            micApplied = true
                            showToast("已申请上麦 · 等房主抱麦")
                        }
                    }
                }
            }
            Spacer()
            if joinState == .inRoom && !preview {
                CircleIconButton(icon: "message") {
                    if roomGroupId?.isEmpty != false {
                        showToast("公屏未就绪")
                    } else {
                        inviteOpen = true
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: - 资料卡

    private func memberCard(_ m: MicMember) -> some View {
        let seat = (session.detail?.mics ?? []).first { $0.userId == m.userId }
        return LobbyUserCard(
            nickname: m.nickname ?? "房间用户",
            avatar: m.avatar,
            tableNo: nil,
            seated: seat != nil,
            isSelf: m.userId == myUserId,
            stateText: seat.map { "\($0.seatNo ?? 0) 号麦\($0.muted == true ? " · 已闭麦" : "")" } ?? "在房间里",
            onDismiss: { selfCard = nil },
            onGift: { selfCard = nil; giftNav = .init(userId: m.userId, nickname: m.nickname) },
            onChat: { selfCard = nil; chatNav = .init(userId: m.userId, nickname: m.nickname) },
            onFollow: {
                selfCard = nil
                Task {
                    do {
                        _ = try await FollowAPI.friendApply(userId: m.userId)
                        showToast("好友申请已发送")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            },
            onInviteShare: {
                // 房主/管理麦：把该用户抱上麦（房间语境下「邀请拼桌」= 抱麦）
                selfCard = nil
                guard canManage else {
                    showToast("仅房主/管理麦可抱麦")
                    return
                }
                session.runAction {
                    try await session.seatUser(targetUserId: m.userId, seatNo: nil)
                    showToast("已抱上麦")
                }
            },
            onDrink: { selfCard = nil; giftNav = .init(userId: m.userId, nickname: m.nickname) },
            onReport: nil
        )
    }
}

// MARK: - 零件

/**
 * 单个麦位：有/无占用 + 角色标 + 闭麦标 + 说话音波（speaking 来自 LiveKit ActiveSpeakersChanged）。
 * 说话时头像外圈金环 + 轻微放大（本地渲染，不向服务端要说话态）。
 */
struct MicSlotView: View {
    let seatNo: Int
    let nickname: String?
    let avatar: String?
    let role: String?
    let muted: Bool
    let speaking: Bool
    let mine: Bool
    var big = false
    let onClick: () -> Void

    @State private var pulse = false

    private var size: CGFloat { big ? 46 : 40 }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .top) {
                Group {
                    if nickname != nil || avatar != nil {
                        AppAvatar(url: avatar, size: size)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.5))
                                .overlay(Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                            Image(systemName: "mic")
                                .font(.system(size: size * 0.32))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .frame(width: size, height: size)
                    }
                }
                .frame(width: size + 8, height: size + 8)
                .background(
                    Circle().stroke(
                        speaking ? LobbyColors.seated : (mine ? LobbyColors.goldLight : .clear),
                        lineWidth: speaking ? 2 : 1.5
                    )
                )
                .scaleEffect(speaking && pulse ? 1.12 : 1)
                .animation(speaking
                           ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true)
                           : .default,
                           value: pulse)
                if let role {
                    Text(role)
                        .font(.system(size: 7))
                        .foregroundStyle(role == "房主" ? Color(red: 0x1A/255, green: 0x14/255, blue: 0x08/255) : .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            LinearGradient(
                                colors: role == "房主"
                                    ? [LobbyColors.gold, LobbyColors.deepGold]
                                    : [LobbyColors.crimson, LobbyColors.crimsonTail],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .offset(y: -6)
                }
            }
            .frame(width: 66, height: size + 10)
            // 闭麦标（头像底部小圆）
            .overlay(alignment: .bottom) {
                ZStack {
                    Circle()
                        .fill(muted ? Color(red: 0x7D/255, green: 0x72/255, blue: 0x88/255).opacity(0.9) : LobbyColors.gold.opacity(0.9))
                        .frame(width: 16, height: 16)
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(muted ? .white.opacity(0.8) : Color(red: 0x1A/255, green: 0x14/255, blue: 0x08/255))
                }
                .overlay(Circle().stroke(Color(red: 0x0C/255, green: 0x0A/255, blue: 0x0D/255), lineWidth: 1.5))
                .offset(y: 4)
            }
            Text(nickname.map { String($0.prefix(5)) } ?? "\(seatNo) 号麦")
                .font(.system(size: 8.5))
                .foregroundStyle(
                    speaking ? LobbyColors.seated
                    : (nickname != nil ? LobbyColors.goldLight : .white.opacity(0.4)))
                .lineLimit(1)
        }
        .frame(width: 66)
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
        .onChange(of: speaking) { _, newValue in
            pulse = newValue
        }
    }
}

/// 连接态小标：点击可重连（连接失败时用户需要一条自愈路径）
struct ConnChip: View {
    let conn: VoiceConnState
    let onRetry: () -> Void

    var body: some View {
        let (text, color): (String, Color) = {
            switch conn {
            case .connected: return ("语音已连", LobbyColors.seated)
            case .connecting: return ("连接中…", LobbyColors.goldLight)
            case .reconnecting: return ("重连中…", LobbyColors.goldLight)
            case .failed: return ("语音失败 · 点重连", LobbyColors.crimson)
            case .idle: return ("未连语音", .white.opacity(0.4))
            }
        }()
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 8.5))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.55))
        .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { onRetry() }
    }
}

/// 在房成员圆头像（头像取公屏消息发送者资料；没说过话用首字占位——都是正圆）
struct MemberBubble: View {
    let url: String?
    let name: String
    var mine = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(.white.opacity(0.08))
                if let url, let remote = webImageURL(url) {
                    WebImage(url: remote) { Text(String(name.prefix(1))).font(.system(size: 12)).foregroundStyle(LobbyColors.goldLight) }
                        .clipShape(Circle())
                } else {
                    Text(String(name.prefix(1)))
                        .font(.system(size: 12))
                        .foregroundStyle(LobbyColors.goldLight)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(LobbyColors.gold.opacity(mine ? 0.65 : 0.25), lineWidth: 1))
            Text(name)
                .font(.system(size: 8))
                .foregroundStyle(mine ? LobbyColors.goldLight : .white.opacity(0.55))
                .lineLimit(1)
                .frame(width: 40)
        }
        .frame(width: 40)
    }
}

/// 进房/等待状态横幅（点击可刷新）
struct StatusBannerView: View {
    let text: String
    let color: Color
    let onRetry: () -> Void

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Spacer()
            Text("刷新")
                .font(.system(size: 9.5))
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { onRetry() }
    }
}

/// 房间公屏输入（纯文本：房间内不走录音——与 LiveKit 抢麦风险 + 语音房发语音消息无意义）
struct RoomChatBar: View {
    @Binding var text: String
    let enabled: Bool
    let sending: Bool
    let hint: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                TextField("", text: $text)
                    .font(.system(size: 12))
                    .foregroundStyle(LobbyColors.ivory)
                    .disabled(!enabled || sending)
                    .submitLabel(.send)
                    .onSubmit { if enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty { onSend() } }
            }
            .padding(.leading, 14)

            Image(systemName: "paperplane.fill")
                .font(.system(size: 12))
                .foregroundStyle(enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty ? .white : .white.opacity(0.3))
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? LobbyColors.crimson : .white.opacity(0.08))
                }
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture {
                    if enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty && !sending { onSend() }
                }
        }
        .frame(height: 40)
        .background(.white.opacity(0.06))
        .overlay(Capsule().stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }
}

/// 麦克风开关（在麦上时）
struct MicToggleButton: View {
    let on: Bool
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "mic" : "mic.slash")
                .font(.system(size: 12))
                .foregroundStyle(on ? .white : .white.opacity(enabled ? 0.7 : 0.3))
            Text(!enabled ? "已被闭麦" : (on ? "麦克风开" : "麦克风关"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(on ? .white : .white.opacity(enabled ? 0.7 : 0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(on ? LobbyColors.crimson.opacity(0.9) : .white.opacity(0.08))
        )
        .overlay(Capsule().stroke(on ? LobbyColors.crimson : Noir.gold.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
        .opacity(enabled ? 1 : 0.6)
        .contentShape(Capsule())
        .onTapGesture { if enabled { onClick() } }
    }
}

/// 底栏主按钮（申请上麦/下麦）
struct PrimaryBarButton: View {
    let label: String
    let icon: String
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { onClick() }
    }
}

/// 底栏圆形小钮（邀请）
struct CircleIconButton: View {
    let icon: String
    let onClick: () -> Void

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 38, height: 38)
            .background(.white.opacity(0.05))
            .overlay(Circle().stroke(Noir.gold.opacity(0.3), lineWidth: 1))
            .clipShape(Circle())
            .contentShape(Circle())
            .onTapGesture { onClick() }
    }
}

/// 底栏提示（等待态）
struct BottomHintView: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05))
        .overlay(Capsule().stroke(Noir.gold.opacity(0.25), lineWidth: 1))
        .clipShape(Capsule())
    }
}
