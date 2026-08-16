import SwiftUI

/// 「加好友」入口按钮：自含状态查询与申请动作（对齐安卓 FriendApplyEntry）。
/// none → 「加好友」；pending_out → 「已申请」（禁用）；pending_in → 「同意申请」（点了直接互关）；
/// friend / self / 未加载 → 不渲染
struct FriendApplyButton: View {
    let targetUserId: Int64?

    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Group {
            if let targetUserId,
               targetUserId != TokenManager.shared.userId,
               let status, status != "friend", status != "self" {
                let enabled = status != "pending_out"
                let label = status == "pending_out" ? "已申请" : (status == "pending_in" ? "同意申请" : "加好友")
                Button { apply() } label: {
                    HStack(spacing: 4) {
                        if enabled {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 11))
                        }
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(enabled ? Noir.goldLight : Color.white.opacity(0.35))
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .overlay(Capsule().stroke(enabled ? Noir.gold.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1))
                }
                .disabled(!enabled || busy)
            }
        }
        .task(id: targetUserId) { await loadStatus() }
    }

    private func loadStatus() async {
        guard let targetUserId else { return }
        status = try? await FollowAPI.friendStatus(userId: targetUserId)
    }

    private func apply() {
        guard let targetUserId, !busy else { return }
        busy = true
        Task {
            _ = try? await FollowAPI.friendApply(userId: targetUserId)
            await loadStatus()
            busy = false
        }
    }
}
