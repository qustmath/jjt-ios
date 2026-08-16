import SwiftUI

/// 「加好友」入口按钮：自含状态查询与申请动作（对齐安卓 FriendApplyEntry）。
/// none → 「加好友」；pending_out → 「已申请」（禁用）；pending_in → 「同意申请」（点了直接互关）；
/// friend / self / 未加载 → 不渲染
struct FriendApplyButton: View {
    let targetUserId: Int64?

    @State private var status: String?
    @State private var busy = false
    /// 状态加载失败（调试用：真机上接口/解析异常时不再静默）
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let targetUserId,
               targetUserId != TokenManager.shared.userId {
                if let status, status != "friend", status != "self" {
                    let enabled = status != "pending_out"
                    let label = status == "pending_out" ? "已申请" : (status == "pending_in" ? "同意申请" : "加好友")
                    button(label: label, enabled: enabled)
                } else if status == nil {
                    // 调试期：槽位常显——加载中 "…"，失败显示"加好友（重试）"，
                    // 若一直转圈说明视图层状态加载有 bug
                    if loadFailed {
                        button(label: "加好友", enabled: true)
                    } else {
                        Text("…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(height: 30)
                            .padding(.horizontal, 12)
                            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                }
                // status == friend/self → 不渲染（对齐安卓）
            }
        }
        .onAppear { reload() }
        .onChange(of: targetUserId) { _, _ in reload() }
    }

    @ViewBuilder
    private func button(label: String, enabled: Bool) -> some View {
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

    private func reload() {
        Task {
            guard let targetUserId else { return }
            do {
                status = try await FollowAPI.friendStatus(userId: targetUserId)
                loadFailed = false
            } catch {
                loadFailed = true
            }
        }
    }

    private func apply() {
        guard let targetUserId, !busy else { return }
        busy = true
        Task {
            _ = try? await FollowAPI.friendApply(userId: targetUserId)
            reload()
            busy = false
        }
    }
}
