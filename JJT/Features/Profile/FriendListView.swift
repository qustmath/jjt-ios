import SwiftUI

/// 好友 — 暗夜奢华风（对齐安卓 FriendScreen：好友列表 + 亲密关系 + 申请入口）
struct FriendListView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = FriendListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var peerProfileId: Int64?
    @State private var showApplies = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar

                if vm.isLoading, vm.friends.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.friends.isEmpty {
                    Spacer()
                    Text("暂无好友")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.friends) { friend in
                                friendRow(friend)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .onAppear { vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("确定") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 亲密关系角色选择弹窗（发起 / 回应共用）
        .alert(vm.dialogTitle, isPresented: Binding(
            get: { vm.dialogKind != nil },
            set: { if !$0 { vm.dismissDialog() } }
        )) {
            Button("上位") { vm.selectRole("upper") }
            Button("下位") { vm.selectRole("lower") }
            Button("取消", role: .cancel) { vm.dismissDialog() }
        } message: {
            Text(vm.dialogDesc + "\n（点角色即确认）")
        }
        .fullScreenCover(isPresented: Binding(
            get: { peerProfileId != nil },
            set: { if !$0 { peerProfileId = nil } }
        )) {
            if let id = peerProfileId {
                UserProfileView(userId: id)
            }
        }
        .fullScreenCover(isPresented: $showApplies) {
            FriendApplyListView()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Noir.goldLight)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("好友")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("INTIMATE CIRCLE")
                        .font(.system(size: 8.5, design: .serif))
                        .italic()
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                // 好友申请入口（有待处理申请显示红点）
                Button { showApplies = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Text("申")
                            .font(.system(size: 13))
                            .foregroundStyle(Noir.goldLight)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                        if vm.applyCount > 0 {
                            Circle()
                                .fill(Noir.crimsonHot)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                                .padding(.trailing, 7)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    // MARK: - 好友行

    private func friendRow(_ friend: FollowUser) -> some View {
        let relation = vm.relations.first { $0.peerUserId == friend.userId }
        let pending = vm.pendingList.first { $0.peerUserId == friend.userId }

        return HStack(spacing: 12) {
            AppAvatar(url: friend.avatar, size: 46,
                      frameURL: friend.avatarFrame,
                      frameScale: friend.avatarFrameScale.map { CGFloat($0) } ?? 1.25)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.nickname ?? "用户\(friend.userId)")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    if let vip = friend.vipLevel, !vip.isEmpty {
                        let color = Noir.tierColor(friend.vipLevelColor)
                        HStack(spacing: 3) {
                            Image(systemName: "crown")
                                .font(.system(size: 9))
                            Text("\(vip) · Lv.\(friend.levelInTier ?? 1)")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.9))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 1))
                    }
                }
                if let relation {
                    Text("我:\(roleName(relation.myRole)) / 对方:\(roleName(relation.peerRole))")
                        .font(.system(size: 11))
                        .foregroundStyle(Noir.goldLight.opacity(0.8))
                } else if pending != nil {
                    Text("等待对方确认")
                        .font(.system(size: 11))
                        .foregroundStyle(Noir.crimsonHot.opacity(0.8))
                }
                if let mark = friend.mark, !mark.isEmpty {
                    Text(mark)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if relation == nil {
                Button {
                    if let pending {
                        vm.showAcceptDialog(pending)
                    } else {
                        vm.showInviteDialog(friend)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.system(size: 12))
                        Text(pending != nil ? "回应" : "亲密")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(pending != nil ? Noir.crimsonHot : Noir.goldLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(pending != nil ? Noir.hairlineRed : Noir.hairlineGold, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { peerProfileId = friend.userId }
    }

    private func roleName(_ role: String?) -> String {
        switch role {
        case "upper": return "上位"
        case "lower": return "下位"
        default: return role ?? ""
        }
    }
}

// MARK: - ViewModel

@MainActor
final class FriendListViewModel: ObservableObject {

    enum DialogKind {
        case invite(FollowUser)
        case accept(IntimateRelation)
    }

    @Published var friends: [FollowUser] = []
    @Published var relations: [IntimateRelation] = []
    @Published var pendingList: [IntimateRelation] = []
    @Published var applyCount = 0
    @Published var isLoading = false
    @Published var error: String?
    @Published var dialogKind: DialogKind?

    var dialogTitle: String {
        switch dialogKind {
        case .invite: return "发起亲密关系"
        case .accept: return "回应亲密关系邀请"
        case nil: return ""
        }
    }

    var dialogDesc: String {
        switch dialogKind {
        case .invite(let f): return "与 \(f.nickname ?? "用户\(f.userId)") 建立亲密关系，选择我的角色："
        case .accept(let r): return "\(r.peerNickname ?? "用户\(r.peerUserId)") 邀请你建立亲密关系，选择我的角色："
        case nil: return ""
        }
    }

    private var loaded = false

    /// 并行加载好友/亲密关系/待回应/申请数（对齐安卓 FriendViewModel.load）
    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            async let friendsTask = FollowAPI.friends()
            async let relTask = FollowAPI.intimateList()
            async let pendingTask = FollowAPI.intimatePending()
            async let applyTask = FollowAPI.friendApplyReceived()
            friends = (try? await friendsTask.list) ?? []
            relations = (try? await relTask) ?? []
            pendingList = (try? await pendingTask) ?? []
            applyCount = (try? await applyTask.count) ?? 0
        }
    }

    func showInviteDialog(_ friend: FollowUser) { dialogKind = .invite(friend) }
    func showAcceptDialog(_ rel: IntimateRelation) { dialogKind = .accept(rel) }
    func dismissDialog() { dialogKind = nil }

    /// 选定角色即提交（对齐安卓 RolePill + 确认两步，合并为一步）
    func selectRole(_ role: String) {
        guard let kind = dialogKind else { return }
        dialogKind = nil
        Task {
            do {
                switch kind {
                case .invite(let friend):
                    _ = try await FollowAPI.intimateInvite(peerUserId: friend.userId, role: role)
                case .accept(let rel):
                    _ = try await FollowAPI.intimateAccept(peerUserId: rel.peerUserId, role: role)
                }
                load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
