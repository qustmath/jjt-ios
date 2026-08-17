import SwiftUI

/// 关注与粉丝 — 暗夜奢华风（对齐安卓 FollowScreen）
struct FollowListView: View {

    /// 0=粉丝 1=关注
    let initialTab: Int
    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = FollowListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var peerProfileId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                tabSwitcher

                if vm.isLoading, vm.users.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.users.isEmpty {
                    Spacer()
                    Text(vm.tab == 0 ? "暂无粉丝" : "暂无关注")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.users) { user in
                                userRow(user)
                            }
                            if vm.isLoading {
                                ProgressView().tint(Noir.gold)
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                            } else if vm.hasMore {
                                Color.clear.frame(height: 1)
                                    .onAppear { vm.loadMore() }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { vm.load(tab: initialTab) }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("确定") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
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
                    Text("关注与粉丝")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("FOLLOWING & FOLLOWERS")
                        .font(.system(size: 8.5, design: .serif))
                        .italic()
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    // MARK: - Tab 切换

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabPill("粉丝", selected: vm.tab == 0) { vm.switchTab(0) }
            tabPill("关注", selected: vm.tab == 1) { vm.switchTab(1) }
        }
        .padding(3)
        .background(Noir.noir2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func tabPill(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : Color.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 用户行

    private func userRow(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            AppAvatar(url: user.avatar, size: 46,
                      frameURL: user.avatarFrame,
                      frameScale: user.avatarFrameScale.map { CGFloat($0) } ?? 1.25)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.nickname ?? "用户\(user.userId)")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    if user.isMutual == true {
                        Text("互关")
                            .font(.system(size: 9))
                            .foregroundStyle(Noir.crimsonHot)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(Noir.hairlineRed, lineWidth: 1))
                    }
                    if let vip = user.vipLevel, !vip.isEmpty {
                        let color = Noir.tierColor(user.vipLevelColor)
                        HStack(spacing: 3) {
                            Image(systemName: "crown")
                                .font(.system(size: 9))
                            Text("\(vip) · Lv.\(user.levelInTier ?? 1)")
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
                if let mark = user.mark, !mark.isEmpty {
                    Text(mark)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 关注按钮：已关注=描边灰，未关注=酒红渐变
            let followed = user.isMutual == true
            Button { vm.toggleFollow(user: user) } label: {
                Text(followed ? "已关注" : "关注")
                    .font(.system(size: 11.5, weight: followed ? .regular : .semibold))
                    .foregroundStyle(followed ? Color.white.opacity(0.4) : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        followed
                            ? AnyShapeStyle(Color.clear)
                            : AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(followed ? 0.15 : 0), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { peerProfileId = user.userId }
    }
}

// MARK: - ViewModel

@MainActor
final class FollowListViewModel: ObservableObject {

    @Published var users: [FollowUser] = []
    @Published var tab = 0
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = true
    private var pageNo = 1
    private var loaded = false

    func load(tab: Int) {
        guard !loaded else { return }
        loaded = true
        self.tab = tab
        loadPage(1)
    }

    func switchTab(_ tab: Int) {
        guard tab != self.tab else { return }
        self.tab = tab
        users = []
        hasMore = true
        loadPage(1)
    }

    func loadMore() {
        guard !isLoading, hasMore else { return }
        loadPage(pageNo + 1)
    }

    private func loadPage(_ page: Int) {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let result = tab == 0
                    ? try await FollowAPI.followers(pageNo: page)
                    : try await FollowAPI.following(pageNo: page)
                let list = result.list ?? []
                users = page == 1 ? list : users + list
                pageNo = page
                hasMore = list.count >= 20
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 关注/取关（对齐安卓：本地翻转 isMutual）
    func toggleFollow(user: FollowUser) {
        let followed = user.isMutual == true
        Task {
            do {
                if followed {
                    _ = try await FollowAPI.unfollow(userId: user.userId)
                } else {
                    _ = try await FollowAPI.follow(userId: user.userId)
                }
                if let idx = users.firstIndex(where: { $0.userId == user.userId }) {
                    users[idx].isMutual = !followed
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
