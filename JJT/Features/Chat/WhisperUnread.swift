import Foundation

/// 底部导航「密语」未读角标（对齐安卓 WhisperBadgeViewModel）。
///
/// 口径：与密语列表可见会话一致——官方号（1001/1002/1003）不计入；
/// 群会话只在仍在此群时计入（已加入群白名单，AVChatRoom 本就不进列表，
/// 当前所在的语音房群不计）。未登录时恒 0。
@MainActor
final class WhisperUnreadCenter: ObservableObject {

    static let shared = WhisperUnreadCenter()

    @Published private(set) var count = 0

    private var started = false

    /// 主界面创建后调用一次；登录后（AppState.didLogin）再调安全（幂等）
    func start() {
        guard !started else { return }
        started = true
        // 未读变化 / 会话变化 / 新消息 / 断线重连与回前台 / 被踢需重登 → 重算
        for name in [Notification.Name.jjtIMUnreadChanged,
                     .jjtIMDataRefresh,
                     .jjtIMNewMessage,
                     .jjtIMNeedRelogin] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.recompute() }
            }
        }
        Task { await recompute() }
    }

    private func recompute() async {
        guard TokenManager.shared.userId ?? 0 > 0 else { count = 0; return }
        if !ImManager.shared.isLoggedIn {
            do {
                let sig = try await ImAPI.userSig(userId: TokenManager.shared.userId ?? 0)
                try await ImManager.shared.initAndLogin(userSig: sig)
            } catch {
                return
            }
        }
        guard let list = try? await ImManager.shared.conversationList() else { return }
        let joined = await ImManager.shared.joinedGroupIds()
        let voiceRoomGroup = VoiceRoomSession.shared.detail?.imGroupIdStr
        var total = 0
        for conv in list {
            let isGroup = conv.type == .GROUP
            if isGroup {
                guard let gid = conv.groupID, !gid.isEmpty,
                      joined.contains(gid), gid != voiceRoomGroup else { continue }
            } else if let uid = conv.userID, jjtIsOfficialUserId(Int64(uid)) {
                continue // 官方号不计角标
            }
            total += Int(conv.unreadCount)
        }
        count = total
    }
}
