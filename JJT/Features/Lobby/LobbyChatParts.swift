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

// MARK: - 公屏消息样式（v75 五态，对齐安卓 LobbyChatStyle）

/// 公屏消息样式（v75 五态）：同一份消息在五个场景用不同密度与气泡形态。
/// - feed：暗夜大厅全城流——无气泡、紧凑行、容器上缘渐隐
/// - immersive：暗夜沉浸视图——无气泡、大字号、文字阴影、非当前店整行淡化
/// - plan：门店大厅图内——小气泡、元信息在气泡首行、半透明底
/// - fullscreen：全屏公屏——大气泡、元信息在气泡首行、可读性优先
/// - room：语音房——轻气泡、元信息在气泡外、头像带框
enum LobbyChatStyle {
    case feed, immersive, plan, fullscreen, room

    var avatarSize: CGFloat {
        switch self {
        case .feed: return 28
        case .immersive: return 32
        case .plan: return 24
        case .fullscreen: return 32
        case .room: return 30
        }
    }

    var avatarGap: CGFloat {
        switch self {
        case .feed: return 8
        case .immersive: return 10
        case .plan: return 6
        case .fullscreen: return 8
        case .room: return 6
        }
    }

    var metaSize: CGFloat {
        switch self {
        case .feed: return 9
        case .immersive: return 10
        case .plan: return 8
        case .fullscreen: return 9
        case .room: return 8.5
        }
    }

    var bodySize: CGFloat {
        switch self {
        case .feed: return 11.5
        case .immersive: return 13
        case .plan: return 11
        case .fullscreen: return 12.5
        case .room: return 11
        }
    }

    var timeSize: CGFloat {
        switch self {
        case .feed: return 8
        case .immersive: return 9
        case .plan: return 7
        case .fullscreen: return 7.5
        case .room: return 7.5
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .feed: return 5
        case .immersive: return 6
        default: return 4
        }
    }

    var rowGap: CGFloat {
        switch self {
        case .feed: return 8
        case .immersive: return 16
        case .plan: return 6
        case .fullscreen: return 10
        case .room: return 8
        }
    }

    var hasBubble: Bool { self == .plan || self == .fullscreen || self == .room }

    /// 元信息是否在气泡首行（v75 图内/全屏口径）；语音房与暗夜流放在气泡外
    var metaInsideBubble: Bool { self == .plan || self == .fullscreen }

    var bubbleColor: Color {
        switch self {
        case .plan: return Color(red: 0x0A/255, green: 0x08/255, blue: 0x0B/255).opacity(0.95)   // 压在平面图上仍可读
        case .fullscreen: return Color(red: 0x0E/255, green: 0x0B/255, blue: 0x0F/255).opacity(0.78) // + 模糊背景
        case .room: return Color(red: 0x0A/255, green: 0x08/255, blue: 0x0B/255).opacity(0.66)
        default: return .clear
        }
    }

    var bubbleBorderAlpha: Double {
        switch self {
        case .plan: return 0.22
        case .fullscreen: return 0.28
        case .room: return 0.2
        default: return 0
        }
    }

    /// 左上小角（对齐安卓 topStart=4）
    var bubbleShape: UnevenRoundedRectangle {
        switch self {
        case .fullscreen:
            return UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16)
        default:
            return UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 12)
        }
    }

    var bubblePaddingH: CGFloat {
        switch self {
        case .fullscreen: return 12
        case .room: return 10
        default: return 8
        }
    }

    var bubblePaddingV: CGFloat {
        switch self {
        case .fullscreen: return 8
        case .room: return 6
        default: return 5
        }
    }

    var bodyShadow: Bool { self == .immersive }

    var contentHorizontal: CGFloat {
        switch self {
        case .plan: return 8
        case .immersive, .fullscreen: return 16
        default: return 10
        }
    }

    var contentVertical: CGFloat {
        switch self {
        case .immersive: return 8
        case .fullscreen: return 12
        default: return 6
        }
    }
}

// MARK: - 公屏消息列表

/// 公屏消息列表（对齐安卓 LobbyChatList）：新消息在底部，自动滚到底。
/// showStorePrefix：聚合流（暗夜大厅）true——副本带门店元数据，渲染【门店】前缀；
/// 门店群（门店大厅）false——本店归属，不加前缀。
struct LobbyChatList: View {

    let messages: [LobbyChatMessage]
    var showStorePrefix = false
    /// 五态样式（默认全屏公屏口径）
    var style: LobbyChatStyle = .fullscreen
    var emptyText = "还没有人说话，来当第一个 ✨"
    /// 顶部欢迎语（全屏公屏用；随消息一起滚动）
    var headerText: String? = nil
    /// 列表上缘渐隐（暗夜流/沉浸/图内小窗）
    var fadeTop = false
    /// 整行淡化（沉浸视图非当前店）
    var dimmed: (LobbyChatMessage) -> Bool = { _ in false }
    /// 点气泡正文（图内小窗 → 展开全屏公屏）；nil = 不响应
    var onBodyClick: (() -> Void)? = nil
    var onUserClick: (LobbyChatMessage) -> Void = { _ in }
    /// 长按消息（举报入口）；nil = 不给长按动作
    var onMessageLongPress: ((LobbyChatMessage) -> Void)? = nil

    @ObservedObject private var cardStore = MemberCardStore.shared

    var body: some View {
        if messages.isEmpty {
            ZStack {
                Text(emptyText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if fadeTop {
            listContent.mask {
                // 上缘渐隐（v75 聊天容器 mask-image）：列表顶部 26% 淡出
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: 0.26),
                ], startPoint: .top, endPoint: .bottom)
            }
        } else {
            listContent
        }
    }

    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: style.rowGap) {
                    // 顶部欢迎语随历史滚到顶部
                    if let headerText, !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: 9))
                            .foregroundStyle(LobbyColors.gold.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    // 发言人会员名片按消息批量补（等级小标/头像框以名片缓存优先）
                    ForEach(messages) { msg in
                        if msg.kind == .system {
                            LobbySystemLine(text: msg.text ?? "")
                        } else {
                            LobbyMessageRow(
                                msg: msg,
                                card: cardStore.card(msg.senderId),
                                style: style,
                                showStorePrefix: showStorePrefix,
                                dimmed: dimmed(msg),
                                onBodyClick: onBodyClick,
                                onUserClick: { onUserClick(msg) },
                                onLongPress: { onMessageLongPress?(msg) }
                            )
                            .task(id: msg.senderId) {
                                if msg.senderId > 0 { MemberCardStore.shared.fetchMissing([msg.senderId]) }
                            }
                        }
                    }
                }
                .padding(.horizontal, style.contentHorizontal)
                .padding(.vertical, style.contentVertical)
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

/// 元信息行：店名前缀 + 桌号（图内/全屏为金底小胶囊） + 昵称 + VIP 段位 + 座位态点 + 时间
private struct LobbyChatMetaLine: View {
    let msg: LobbyChatMessage
    let card: LobbyMemberCard?
    let style: LobbyChatStyle
    let showStorePrefix: Bool
    /// true=气泡外元信息（占满整行、时间靠右）；false=气泡内（随气泡收窄，时间紧跟元信息）
    let fillWidth: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if showStorePrefix, let prefix = msg.storePrefix {
                    Text("【\(prefix)】")
                        .font(.system(size: 8.5))
                        .foregroundStyle(LobbyColors.gold.opacity(0.9))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer().frame(width: 3)
                }
                let chippedTable = style == .plan || style == .fullscreen
                if chippedTable, let tableNo = msg.tableNo, !tableNo.isEmpty {
                    LobbyTableChip(tableNo: tableNo, fontSize: style.timeSize)
                    Spacer().frame(width: 4)
                }
                Text(memberDisplayName(card, msg.nickname))
                    .font(.system(size: style.metaSize))
                    .foregroundStyle(style.hasBubble ? LobbyColors.goldLight.opacity(0.85) : .white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: fillWidth ? nil : 120, alignment: .leading)
                    .layoutPriority(1)
                if card?.vipName?.isEmpty == false {
                    Spacer().frame(width: 3)
                    LobbyVipChip(vipName: card?.vipName, vipColor: card?.vipColor,
                                 levelInTier: card?.levelInTier, fontSize: style.metaSize)
                }
                // 暗夜流：纯文本桌号；语音房不显示桌号
                if !chippedTable, style != .room, let tableNo = msg.tableNo, !tableNo.isEmpty {
                    Spacer().frame(width: 4)
                    Text(tableNo)
                        .font(.system(size: style.timeSize))
                        .foregroundStyle(LobbyColors.goldLight.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer().frame(width: 4)
                LobbyStateDot(seated: msg.seatState == "seated", size: style.dotSize)
                if fillWidth {
                    Spacer(minLength: 4)
                } else {
                    Spacer().frame(width: 6)
                }
            }
            if fillWidth {
                Spacer(minLength: 0)
            }
            Text(lobbyChatTime(msg.timeSec))
                .font(.lobbyNumber(style.timeSize))
                .foregroundStyle(.white.opacity(style == .feed ? 0.45 : 0.3))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 桌号小胶囊（v75：金底金边 + 鎏金字）
private struct LobbyTableChip: View {
    let tableNo: String
    let fontSize: CGFloat

    var body: some View {
        Text(tableNo)
            .font(.lobbyNumber(fontSize, weight: .semibold))
            .foregroundStyle(LobbyColors.goldLight)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(LobbyColors.gold.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1))
            .fixedSize()
    }
}

/// 单条用户消息（v75 五态：头像 + 元信息 + 气泡/无气泡正文）
private struct LobbyMessageRow: View {

    let msg: LobbyChatMessage
    let card: LobbyMemberCard?
    let style: LobbyChatStyle
    let showStorePrefix: Bool
    let dimmed: Bool
    let onBodyClick: (() -> Void)?
    let onUserClick: () -> Void
    let onLongPress: () -> Void

    /// 表情包无气泡（同单聊）：即使图内/全屏的元信息口径在气泡内，也让表情保持无底
    private var bareSticker: Bool { msg.kind == .sticker }

    var body: some View {
        HStack(alignment: .top, spacing: style.avatarGap) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                // 语音房/暗夜流：元信息在气泡外；图内/全屏：元信息在气泡首行
                if !style.metaInsideBubble || bareSticker {
                    LobbyChatMetaLine(msg: msg, card: card, style: style,
                                      showStorePrefix: showStorePrefix, fillWidth: true)
                }
                if style.hasBubble && !bareSticker {
                    VStack(alignment: .leading, spacing: style == .plan ? 2 : 4) {
                        if style.metaInsideBubble {
                            LobbyChatMetaLine(msg: msg, card: card, style: style,
                                              showStorePrefix: showStorePrefix, fillWidth: false)
                        }
                        messageBody
                    }
                    .padding(.horizontal, style.bubblePaddingH)
                    .padding(.vertical, style.bubblePaddingV)
                    .background(style.bubbleShape.fill(style.bubbleColor))
                    .overlay(style.bubbleShape.stroke(Noir.gold.opacity(style.bubbleBorderAlpha), lineWidth: 1))
                    .frame(maxWidth: 280, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onBodyClick?() }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPress() })
                } else {
                    messageBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(dimmed ? 0.55 : 1)
    }

    /// 头像框靠溢出圆外呈现（AppAvatar 内部自裁圆），外挂裁剪会把框裁成圆内；
    /// 金色描边只在无框时画，避免与框叠圈
    private var avatar: some View {
        let hasFrame = !(card?.avatarFrame ?? "").isEmpty
        return LobbyMemberAvatar(userId: msg.senderId, fallbackAvatar: msg.avatar,
                                 size: style.avatarSize, frameScale: 1.2)
            .modifier(AvatarTap { onUserClick() })
            .modifier(AvatarRing(hasFrame: hasFrame))
    }

    @ViewBuilder
    private var messageBody: some View {
        switch msg.kind {
        case .sticker:
            stickerImage
                .frame(width: style == .plan ? 76 : 84, height: style == .plan ? 76 : 84)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { onUserClick() }
                .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPress() })
        case .voice:
            LobbyVoiceBubble(msg: msg, timeSize: style.timeSize)
        case .image:
            LobbyChatImage(msg: msg, size: style == .plan ? 96 : 110)
        default:
            Text(msg.text ?? "")
                .font(.system(size: style.bodySize))
                .lineSpacing(style.bodySize * 0.45)
                .foregroundStyle(LobbyColors.textBody)
                .shadow(color: style.bodyShadow ? .black.opacity(0.9) : .clear,
                        radius: 5, x: 0, y: 1)
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

/// 头像点击热区（圆外溢出的框也可点）
private struct AvatarTap: ViewModifier {
    let onTap: () -> Void
    func body(content: Content) -> some View {
        content.contentShape(Circle()).onTapGesture { onTap() }
    }
}

/// 无框时的金描边（有框不画，避免与框叠圈）
private struct AvatarRing: ViewModifier {
    let hasFrame: Bool
    func body(content: Content) -> some View {
        if hasFrame {
            content
        } else {
            content.overlay(Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
        }
    }
}

/// 语音气泡（播放键 + 波形 + 秒数）。URL 未到位时点击触发现场重取（自愈）
struct LobbyVoiceBubble: View {

    let msg: LobbyChatMessage
    var timeSize: CGFloat = 9.5
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
                .font(.lobbyNumber(timeSize))
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
    var size: CGFloat = 110

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
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 全屏公屏

/// 全屏公屏（v75 chatFocus）：平面图高斯模糊 + 压暗作背景，顶部店名/在线/回到座位图，
/// 大号消息流 + 与图内同源的发言栏。状态由门店大厅持有（chatFocus），从底部升起不是新页面。
struct LobbyFullScreenChat: View {
    let storeName: String
    let online: Int
    /// 背景：当前楼层平面图（无则门店封面）
    let backdrop: String?
    let messages: [LobbyChatMessage]
    let inputHint: String
    let sending: Bool
    /// 从底部输入框进入时自动聚焦并弹键盘；从聊天内容进入时不弹
    let autoFocusInput: Bool
    let onBackToPlan: () -> Void
    let onUserClick: (LobbyChatMessage) -> Void
    let onReportRequest: (LobbyChatMessage) -> Void
    let onSendText: (String) -> Void
    let onSendSticker: (String, String) -> Void
    let onPickImage: () -> Void
    let onGift: (() -> Void)?
    let onVoiceStop: (LobbyVoiceRecorder.Result) -> Void
    let onError: (String) -> Void

    var body: some View {
        ZStack {
            if let backdrop, !backdrop.isEmpty, let url = webImageURL(backdrop) {
                WebImage(url: url) { LobbyColors.bg }
                    .blur(radius: 26)
                    .scaleEffect(1.08)
                    .ignoresSafeArea()
            }
            // 双向压暗，像场内灯光调暗
            LinearGradient(stops: [
                .init(color: dim(0.75), location: 0),
                .init(color: dim(0.45), location: 0.3),
                .init(color: dim(0.55), location: 0.7),
                .init(color: dim(0.92), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 底部抽屉拖拽柄：视觉上表明这是从底部升起的浮层，不是新页面
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(storeName) · 公屏")
                                .font(.system(size: 15, weight: .bold, design: .serif))
                                .foregroundStyle(LobbyColors.ivory)
                                .lineLimit(1)
                            HStack(spacing: 3) {
                                Circle().fill(LobbyColors.seated).frame(width: 4, height: 4)
                                Text("\(online)")
                                    .font(.lobbyNumber(8, weight: .bold))
                                    .foregroundStyle(LobbyColors.seated)
                                Text("在线")
                                    .font(.system(size: 8))
                                    .foregroundStyle(LobbyColors.seated)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(LobbyColors.seated.opacity(0.4), lineWidth: 1))
                        }
                        Text("消息实时同步门店大屏")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer(minLength: 8)
                    Button {
                        onBackToPlan()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map")
                                .font(.system(size: 9))
                            Text("回到座位图")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(LobbyColors.goldLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(LobbyColors.gold.opacity(0.12)))
                        .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)

                LobbyChatList(
                    messages: messages,
                    showStorePrefix: false,
                    style: .fullscreen,
                    emptyText: "本店公屏暂无消息 · 说点什么都行 ✨",
                    headerText: "—— 欢迎进入\(storeName)大厅 🍷 ——",
                    fadeTop: true,
                    onUserClick: onUserClick,
                    onMessageLongPress: { onReportRequest($0) }
                )

                Spacer().frame(height: 6)
                LobbySpeechInput(
                    hint: inputHint,
                    sending: sending,
                    autoFocus: autoFocusInput,
                    onSendText: onSendText,
                    onSendSticker: onSendSticker,
                    onPickImage: onPickImage,
                    onGift: onGift,
                    onVoiceStop: onVoiceStop,
                    onError: onError
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private func dim(_ alpha: Double) -> Color {
        Color(red: 0x08/255, green: 0x06/255, blue: 0x09/255).opacity(alpha)
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
    /// 出现即聚焦并弹键盘（全屏公屏从输入框进入时）
    var autoFocus = false
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
            .onAppear {
                if autoFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
                }
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
