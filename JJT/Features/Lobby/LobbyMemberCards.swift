import SwiftUI

// MARK: - 发言人会员名片（对齐安卓 LobbyChatParts 的 ChatMemberCard / ChatMemberProfiles）

/// 聊天发言人会员名片（公屏渲染等级小标 + 头像框用；IM 消息只带昵称头像，会员字段批量补）
struct LobbyMemberCard {
    var nickname: String = ""
    var avatar: String?
    var avatarFrame: String?
    var avatarFrameScale: Double?
    /// 外显段位名/色 + 段内等级（nil=未达到任何段位，不显示小标）
    var vipName: String?
    var vipColor: String?
    var levelInTier: Int?
}

/// 发言人名片缓存：门店大厅/暗夜大厅/小房间三处公屏与列表头像位共用。
/// fetchMissing 对未知名片批量拉 member/user/list（该端点已带头像框+段位）；失败静默（渲染退回 IM 名片）。
@MainActor
final class MemberCardStore: ObservableObject {
    static let shared = MemberCardStore()

    @Published private(set) var cards: [Int64: LobbyMemberCard] = [:]
    private var fetching: Set<Int64> = []

    func card(_ userId: Int64?) -> LobbyMemberCard? {
        guard let userId, userId > 0 else { return nil }
        return cards[userId]
    }

    /// 已拉到的资料直接入缓存（历史拉取顺路喂卡，列表不再重复批量）
    func seed(_ cards: [Int64: LobbyMemberCard]) {
        guard !cards.isEmpty else { return }
        self.cards.merge(cards) { _, new in new }
    }

    /// 未知名片批量补拉（幂等；在途/已缓存跳过，50/批对齐安卓）
    func fetchMissing(_ ids: [Int64]) {
        let missing = ids.filter { $0 > 0 && cards[$0] == nil && !fetching.contains($0) }
        guard !missing.isEmpty else { return }
        fetching.formUnion(missing)
        var batch: [Int64] = []
        func flush() {
            guard !batch.isEmpty else { return }
            let chunk = batch
            batch = []
            Task {
                defer { fetching.subtract(chunk) }
                guard let users = try? await UserAPI.getUserInfoList(ids: chunk) else { return }
                var mapped: [Int64: LobbyMemberCard] = [:]
                for u in users {
                    mapped[u.id] = LobbyMemberCard(
                        nickname: u.nickname ?? "",
                        avatar: u.avatar,
                        avatarFrame: u.avatarFrame,
                        avatarFrameScale: u.avatarFrameScale,
                        vipName: u.level?.name,
                        vipColor: u.level?.color,
                        levelInTier: u.level?.levelInTier)
                }
                seed(mapped)
            }
        }
        for id in missing {
            batch.append(id)
            if batch.count == 50 { flush() }
        }
        flush()
    }
}

/// 成员昵称：名片优先，回退列表/IM 自带字段
func memberDisplayName(_ card: LobbyMemberCard?, _ fallback: String?) -> String {
    if let n = card?.nickname, !n.isEmpty { return n }
    return fallback ?? ""
}

// MARK: - 会员等级小标（对齐安卓 LobbyVipChip：皇冠 + 「段位 · Lv.N」，裸排无胶囊底）

struct LobbyVipChip: View {
    let vipName: String?
    let vipColor: String?
    let levelInTier: Int?
    var fontSize: CGFloat = 8

    var body: some View {
        if let vipName, !vipName.isEmpty {
            HStack(spacing: 2) {
                Image(systemName: "crown.fill")
                    .font(.system(size: fontSize * 0.95))
                    .foregroundStyle(tier)
                Text("\(vipName) · Lv.\(levelInTier ?? 1)")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(tier)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var tier: Color { Noir.tierColor(vipColor) }
}

// MARK: - 会员头像位（名片驱动头像框）

/// 大厅域会员头像：名片缓存优先接头像框（有框按 frameScale 溢出绘制，无框原样），
/// 缺失名片自动补拉。公屏行/桌位/审批/麦位/榜单/收礼人等头像位共用。
/// 注意：头像框溢出画布，父容器不要再加圆形裁剪（对齐安卓「去调用处 clip」口径）。
struct LobbyMemberAvatar: View {
    let userId: Int64?
    var fallbackAvatar: String? = nil
    var size: CGFloat = 36
    /// 无显式 frameScale 时的兜底外扩比例（对齐安卓 1.2f）
    var frameScale: CGFloat = 1.2
    /// 无框时画金描边（榜单/领奖台口径；有框不画避免叠圈）
    var ringWhenNoFrame = false
    var ringColor: Color = Noir.gold.opacity(0.5)

    @ObservedObject private var store = MemberCardStore.shared

    var body: some View {
        let card = store.card(userId)
        let scale = (card?.avatarFrameScale ?? 0) > 0 ? CGFloat(card!.avatarFrameScale!) : frameScale
        let noFrame = (card?.avatarFrame ?? "").isEmpty
        AppAvatar(url: card?.avatar ?? fallbackAvatar,
                  size: size,
                  frameURL: card?.avatarFrame,
                  frameScale: scale)
            .overlay {
                if ringWhenNoFrame && noFrame {
                    Circle().stroke(ringColor, lineWidth: 1)
                }
            }
            .task(id: userId) {
                if let userId, userId > 0 {
                    MemberCardStore.shared.fetchMissing([userId])
                }
            }
    }
}
