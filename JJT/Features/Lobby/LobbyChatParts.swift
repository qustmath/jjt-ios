import PhotosUI
import SwiftUI

// MARK: - 时间

private let lobbyChatTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

/// 公屏消息时间（epoch 秒 → HH:mm）
func lobbyChatTime(_ sec: Int64) -> String {
    guard sec > 0 else { return "" }
    return lobbyChatTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(sec)))
}

// MARK: - 公屏消息列表

/// 公屏消息列表（对齐安卓 LobbyChatList）：新消息在底部，自动滚到底。
/// showStorePrefix：聚合流（暗夜大厅）true——副本带门店元数据，渲染【门店】前缀；
/// 门店群（门店大厅）false——本店归属，不加前缀。
struct LobbyChatList: View {

    let messages: [LobbyChatMessage]
    var showStorePrefix = false
    var emptyText = "还没有人说话，来当第一个 ✨"
    var onUserClick: (LobbyChatMessage) -> Void = { _ in }
    /// 长按消息（举报入口）；nil = 不给长按动作
    var onMessageLongPress: ((LobbyChatMessage) -> Void)? = nil

    var body: some View {
        if messages.isEmpty {
            ZStack {
                Text(emptyText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(messages) { msg in
                            if msg.kind == .system {
                                LobbySystemLine(text: msg.text ?? "")
                            } else {
                                LobbyMessageRow(
                                    msg: msg,
                                    showStorePrefix: showStorePrefix,
                                    onUserClick: { onUserClick(msg) },
                                    onLongPress: { onMessageLongPress?(msg) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: messages.count) { _, _ in
                    // 新消息到达自动贴底（用户上翻时立即被新消息拽回，与安卓「只跟最后一条」行为一致）
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

/// 系统行（入座/离桌播报：后端以 CloudCustomData sys=seat 标记）
struct LobbySystemLine: View {
    let text: String

    var body: some View {
        Text("—— \(text) ——")
            .font(.system(size: 8.5))
            .foregroundStyle(LobbyColors.seated.opacity(0.6))
            .frame(maxWidth: .infinity)
    }
}

/// 单条用户消息（头像 + 门店前缀 + 昵称 + 座位态点 + 桌号 + 时间 + 气泡）
private struct LobbyMessageRow: View {

    let msg: LobbyChatMessage
    let showStorePrefix: Bool
    let onUserClick: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            AppAvatar(url: msg.avatar, size: 26)
                .overlay(Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture { onUserClick() }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if showStorePrefix, let prefix = msg.storePrefix {
                        Text("【\(prefix)】")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Noir.gold.opacity(0.9))
                        Spacer().frame(width: 4)
                    }
                    Text(msg.nickname)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let tableNo = msg.tableNo, !tableNo.isEmpty {
                        Spacer().frame(width: 4)
                        Text(tableNo)
                            .font(.system(size: 8))
                            .foregroundStyle(Noir.goldLight.opacity(0.8))
                    }
                    Spacer().frame(width: 4)
                    Circle()
                        .fill(msg.seatState == "seated" ? LobbyColors.seated : LobbyColors.standing)
                        .frame(width: 5, height: 5)
                    Spacer(minLength: 4)
                    Text(lobbyChatTime(msg.timeSec))
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.45))
                }

                if msg.kind == .sticker {
                    // 表情包无气泡底（同单聊）；点击开资料卡与文字消息一致
                    stickerImage
                        .frame(width: 84, height: 84)
                        .contentShape(Rectangle())
                        .onTapGesture { onUserClick() }
                        .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPress() })
                } else {
                    // 底色 95% 不透明：压在门店平面图上时正文仍可读；左上小角（对齐安卓 topStart=4）
                    bubbleContent
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 4, bottomLeadingRadius: 12,
                                bottomTrailingRadius: 12, topTrailingRadius: 12)
                                .fill(Color(red: 0x0A/255, green: 0x08/255, blue: 0x0B/255).opacity(0.95))
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 4, bottomLeadingRadius: 12,
                                bottomTrailingRadius: 12, topTrailingRadius: 12)
                                .stroke(Noir.gold.opacity(0.22), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPress() })
                }
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch msg.kind {
        case .voice:
            LobbyVoiceBubble(msg: msg)
        case .image:
            LobbyChatImage(msg: msg)
        default:
            Text(msg.text ?? "")
                .font(.system(size: 11.5))
                .foregroundStyle(LobbyColors.textBody)
        }
    }

    @ViewBuilder
    private var stickerImage: some View {
        if let pack = msg.stickerPack, let name = msg.stickerName,
           let path = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "stickers/\(pack)"),
           let ui = UIImage(contentsOfFile: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        } else {
            Text("[表情]")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// 语音气泡（播放键 + 波形 + 秒数）。URL 未到位时点击触发现场重取（自愈）
struct LobbyVoiceBubble: View {

    let msg: LobbyChatMessage
    @ObservedObject private var player = LobbyVoicePlayer.shared

    var body: some View {
        let playing = player.playingMsgId == msg.msgId
        HStack(spacing: 4) {
            Image(systemName: playing ? "speaker.wave.2.fill" : "play.fill")
                .font(.system(size: 10))
                .foregroundStyle(Noir.goldLight)
            HStack(spacing: 2) {
                ForEach([5, 9, 7, 11, 8, 5], id: \.self) { h in
                    Capsule()
                        .fill(Noir.goldLight.opacity(playing ? 0.4 : 0.8))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
            Text(msg.voicePath == nil ? "语音 \(msg.voiceSeconds)″ · 加载中" : "\(msg.voiceSeconds)″")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let src = msg.voicePath {
                LobbyVoicePlayer.shared.toggle(msgId: msg.msgId, path: src)
            } else {
                LobbyImSession.shared.requestVoiceUrl(msg.msgId)
            }
        }
    }
}

/// 图片消息（本地路径优先：刚发出去的图 url 还没回填）
struct LobbyChatImage: View {

    let msg: LobbyChatMessage

    var body: some View {
        Group {
            if let url = msg.imageUrl, let remote = webImageURL(url) {
                WebImage(url: remote) { Noir.noir3 }
            } else if let path = msg.imagePath, let ui = UIImage(contentsOfFile: path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("图片加载失败")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 110, height: 110)
            }
        }
        .frame(width: 110, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 资料卡

/// 资料卡目标（聊天消息 / 同桌成员 / 榜单人物共用）：三处来源的可用字段不同，统一成一种形态
struct LobbyCardTarget: Identifiable {
    let userId: Int64
    let nickname: String
    let avatar: String?
    /// 所在桌号（同桌成员有；聊天消息/榜单可能为空）
    var tableNo: String? = nil
    /// 所在桌位 id（知道时送礼走大厅礼物面板；未知则走礼物中心）
    var tableId: Int64? = nil
    var seated: Bool = false
    /// 状态文案（nil=按 seated 推断「在座/围观中」）
    var stateText: String? = nil
    /// 来源公屏消息（只有聊天消息有）：举报以消息为凭据——nil 表示该卡不给举报入口
    var message: LobbyChatMessage? = nil

    var id: Int64 { userId }
}

extension LobbyChatMessage {
    /// 聊天消息 → 资料卡目标
    func toCardTarget() -> LobbyCardTarget {
        LobbyCardTarget(
            userId: senderId, nickname: nickname, avatar: avatar,
            tableNo: tableNo, seated: seatState == "seated", message: self)
    }
}

extension LobbySpectateMember {
    /// 围观成员 → 资料卡目标：成员必在座，桌号/桌位取自被打开的抽屉
    func toCardTarget(tableId: Int64, tableNo: String?) -> LobbyCardTarget {
        LobbyCardTarget(
            userId: userId, nickname: nickname ?? "本桌用户", avatar: avatar,
            tableNo: tableNo, tableId: tableId, seated: true)
    }
}

/// 资料卡（点头像弹出）：送礼 / 私信 / 加好友 / 邀请拼桌 / 请喝一杯 + 举报入口。
/// 页面把它放在 ZStack 最顶层（对齐安卓 Dialog 窗口承载，保证盖在桌位抽屉等 sheet 之上）。
struct LobbyUserCard: View {

    let nickname: String
    let avatar: String?
    let tableNo: String?
    let seated: Bool
    let isSelf: Bool
    /// 状态文案（nil=按 seated 推断「在座/围观中」）
    var stateText: String? = nil
    let onDismiss: () -> Void
    let onGift: () -> Void
    let onChat: () -> Void
    let onFollow: () -> Void
    let onInviteShare: () -> Void
    let onDrink: () -> Void
    /// 举报入口（nil=不显示）：举报以公屏消息 msgId 为凭据
    var onReport: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color(red: 0x04/255, green: 0x03/255, blue: 0x06/255).opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                AppAvatar(url: avatar, size: 72)
                Spacer().frame(height: 10)
                HStack(spacing: 6) {
                    Text(nickname)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LobbyColors.ivory)
                    if let tableNo, !tableNo.isEmpty {
                        Text(tableNo)
                            .font(.system(size: 9))
                            .foregroundStyle(Noir.goldLight)
                    }
                }
                Spacer().frame(height: 4)
                HStack(spacing: 4) {
                    Circle()
                        .fill(seated ? LobbyColors.seated : LobbyColors.standing)
                        .frame(width: 6, height: 6)
                    Text(stateText ?? (seated ? "在座" : "围观中"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer().frame(height: 16)
                HStack {
                    LobbyCardAction(label: "送礼", icon: "storefront") { onGift() }
                    LobbyCardAction(label: "私信", icon: "message") { onChat() }
                    LobbyCardAction(label: "加好友", icon: "person.badge.plus") { onFollow() }
                    LobbyCardAction(label: "邀请拼桌", icon: "person.2.wave.2") { onInviteShare() }
                    LobbyCardAction(label: "请喝一杯", icon: "wineglass") { onDrink() }
                }
                if !isSelf, let onReport {
                    Spacer().frame(height: 12)
                    Text("举报该用户发言")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                        .onTapGesture { onReport() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(Color(red: 0x14/255, green: 0x10/255, blue: 0x16/255))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 32)
        }
    }
}

private struct LobbyCardAction: View {
    let label: String
    let icon: String
    let onClick: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Noir.goldLight)
                .frame(width: 46, height: 46)
                .background(Noir.gold.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.28), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
    }
}

// MARK: - 举报

/// 举报原因选择（预设枚举；提交只上送 msgId + code）
struct LobbyReportSheet: View {
    let onDismiss: () -> Void
    let onSubmit: (LobbyReportReason) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0x04/255, green: 0x03/255, blue: 0x06/255).opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 0) {
                Text("举报这条发言")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                Text("提交后由运营核查处置，平台会保留证据链（消息落库留痕）")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 4)
                ForEach(LobbyReportReason.allCases, id: \.rawValue) { reason in
                    Text(reason.label)
                        .font(.system(size: 12))
                        .foregroundStyle(LobbyColors.ivory)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture { onSubmit(reason) }
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(LobbyColors.panel)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        }
    }
}

// MARK: - 发言输入

/// 发言框状态提示：入座免限频、罚站（离桌未退座）限频、未入座围观限频。
/// 后端口径：非本店入座者一律按罚站受限。
func lobbyInputHint(seatedHere: Bool, state: String?, tableNo: String?) -> String {
    if seatedHere { return "\(tableNo ?? "在座") · 向全店说点什么…" }
    if state == "stand" { return "罚站中 · 发言限频…" }
    return "围观中 · 发言限频…"
}

/// 公屏发言输入区（双模式，对齐安卓 LobbySpeechInput）：
/// - 文字模式：[语音切换] [输入胶囊·内嵌表情] [发送] [+]
/// - 语音模式：[键盘切换] [按住说话长胶囊（上滑取消）] [+]
/// - 「+」面板：图片 / 送礼；表情：白兔/黑兔贴纸面板（IM 自定义消息直发）
struct LobbySpeechInput: View {

    let hint: String
    let sending: Bool
    let onSendText: (String) -> Void
    let onSendSticker: (String, String) -> Void
    let onPickImage: () -> Void
    /// 送礼入口（nil=隐藏「+」面板里的送礼条目，如暗夜大厅无送礼语境）
    var onGift: (() -> Void)? = nil
    let onVoiceStop: (LobbyVoiceRecorder.Result) -> Void
    let onError: (String) -> Void

    @State private var text = ""
    @State private var voiceMode = false
    @State private var showSticker = false
    @State private var showPlus = false
    @State private var recorder = LobbyVoiceRecorder()
    @State private var recording = false
    @State private var recordSeconds = 0
    @State private var cancelArmed = false
    @State private var pressStarted = false
    @State private var recordTimer: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        inputBar
            .overlay(alignment: .bottom) {
                // 面板悬浮在输入栏上方（盖在聊天流/平面图上，不挤压布局）
                VStack(spacing: 8) {
                    if showSticker { stickerPanel }
                    if showPlus { plusPanel }
                }
                .padding(.bottom, 52)
            }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            // 模式切换：文字模式显示麦克风（去录音）、语音模式显示键盘（回打字）
            circleIconButton(icon: voiceMode ? "keyboard" : "mic.fill", active: false) {
                voiceMode.toggle()
                showSticker = false
                showPlus = false
                if voiceMode { focused = false }
            }

            if !voiceMode {
                inputCapsule
                sendButton
            } else {
                voiceCapsule
            }

            circleIconButton(icon: "plus", active: showPlus, enabled: !sending) {
                showPlus.toggle()
                showSticker = false
                if showPlus { focused = false }
            }
        }
    }

    private var inputCapsule: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .font(.system(size: 12))
                .foregroundStyle(LobbyColors.textBody)
                .focused($focused)
                .disabled(sending)
                .submitLabel(.send)
                .onSubmit { sendText() }
                .onChange(of: text) { _, newValue in
                    if newValue.count > 200 { text = String(newValue.prefix(200)) }
                }
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text(hint)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.3))
                            .allowsHitTesting(false)
                    }
                }
            Image(systemName: "face.smiling")
                .font(.system(size: 14))
                .foregroundStyle(showSticker ? Noir.goldLight : .white.opacity(0.4))
                .contentShape(Rectangle())
                .onTapGesture {
                    showSticker.toggle()
                    showPlus = false
                    if showSticker { focused = false }
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.white.opacity(0.06))
        .overlay(Capsule().stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var sendButton: some View {
        Button {
            sendText()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background {
                    if sending || text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Circle().fill(.white.opacity(0.1))
                    } else {
                        Circle().fill(LinearGradient(colors: [LobbyColors.crimson, Color(red: 0xA0/255, green: 0x10/255, blue: 0x2E/255)], startPoint: .leading, endPoint: .trailing))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// 语音模式：按住说话长胶囊（上滑取消；录音状态显示在胶囊内，避免提示行让高度跳变）
    private var voiceCapsule: some View {
        Text(recording ? (cancelArmed ? "松开取消" : "松手发送 \(recordSeconds)″") : "按住 说话")
            .font(.system(size: 12))
            .foregroundStyle(recording ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(recording ? LobbyColors.crimson : .white.opacity(0.06))
            .overlay(Capsule().stroke(Noir.gold.opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(voiceGesture)
    }

    private var voiceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressStarted {
                    pressStarted = true
                    cancelArmed = false
                    startRecording()
                } else {
                    cancelArmed = value.translation.height < -60
                }
            }
            .onEnded { _ in
                if pressStarted {
                    finishRecording(send: !cancelArmed)
                }
                pressStarted = false
                cancelArmed = false
            }
    }

    private func startRecording() {
        Task {
            if let err = await recorder.start() {
                onError(err)
                pressStarted = false
                return
            }
            recording = true
            recordSeconds = 0
            recordTimer?.cancel()
            recordTimer = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { break }
                    recordSeconds += 1
                    if recordSeconds >= LobbyVoiceRecorder.maxSeconds {
                        // 到 60s 上限自动发送（对齐安卓超时自动停录）
                        finishRecording(send: true)
                        break
                    }
                }
            }
        }
    }

    private func finishRecording(send: Bool) {
        recordTimer?.cancel()
        recordTimer = nil
        recording = false
        let r = recorder.stop()
        if send { onVoiceStop(r) } // <1s 误触：path=nil，调用方静默
    }

    private func sendText() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        text = ""
        showSticker = false
        focused = false
        onSendText(t)
    }

    private var plusPanel: some View {
        HStack(spacing: 12) {
            plusEntry(icon: "photo.on.rectangle.angled", label: "图片", enabled: !sending) {
                showPlus = false
                onPickImage()
            }
            if let onGift {
                plusEntry(icon: "storefront", label: "送礼", enabled: !sending) {
                    showPlus = false
                    onGift()
                }
            }
        }
        .padding(12)
        .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.8))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func plusEntry(icon: String, label: String, enabled: Bool, onClick: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Noir.goldLight)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(LobbyColors.ivory)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { onClick() } }
    }

    private var stickerPanel: some View {
        LobbyStickerPanel { pack, name in
            showSticker = false
            onSendSticker(pack, name)
        }
    }

    private func circleIconButton(icon: String, active: Bool, enabled: Bool = true, onClick: @escaping () -> Void) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15))
            .foregroundStyle(active ? Noir.goldLight : Noir.goldLight.opacity(0.85))
            .frame(width: 40, height: 40)
            .background(active ? Noir.gold.opacity(0.16) : .white.opacity(0.05))
            .overlay(Circle().stroke(Noir.gold.opacity(active ? 0.6 : 0.35), lineWidth: 1))
            .clipShape(Circle())
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Circle())
            .onTapGesture { if enabled { onClick() } }
    }
}

/// 表情包面板（同单聊：白兔/黑兔双包 + 网格；对齐安卓 StickerPanel）
struct LobbyStickerPanel: View {
    let onPick: (String, String) -> Void

    @State private var pack = "white"

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(["white", "black"], id: \.self) { p in
                    Text(p == "white" ? "白兔" : "黑兔")
                        .font(.system(size: 12, weight: pack == p ? .bold : .regular))
                        .foregroundStyle(pack == p ? Noir.gold : .white.opacity(0.4))
                        .onTapGesture { pack = p }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(StickerAssets.names(pack: pack), id: \.self) { name in
                        if let path = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "stickers/\(pack)"),
                           let ui = UIImage(contentsOfFile: path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 52)
                                .onTapGesture { onPick(pack, name) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 180)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
