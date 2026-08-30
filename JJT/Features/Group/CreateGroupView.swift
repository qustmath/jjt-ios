import SwiftUI

/// 建群（对齐安卓 CreateGroupScreen）
/// 群名称 + 好友多选（至少 3 人）→ 创建成功直入群聊；创建前查实名
struct CreateGroupView: View {

    var onBack: (() -> Void)? = nil
    /// 创建成功回调（imGroupId, name），默认 nil 时内部打开聊天页
    var onCreated: ((_ imGroupId: String, _ name: String) -> Void)? = nil

    @StateObject private var vm = CreateGroupViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var chatTarget: ChatTarget?
    @State private var showRealname = false

    struct ChatTarget: Identifiable {
        let id: String
        let title: String
    }

    private var canCreate: Bool { vm.selectedIds.count >= 3 && !vm.groupName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                nameField
                inviteHeader
                friendList
            }
        }
        .jjtKeyboardDismiss()
        .onAppear { vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        .alert("需要实名认证", isPresented: Binding(
            get: { vm.needRealname },
            set: { if !$0 { vm.needRealname = false } }
        )) {
            Button("去认证") {
                vm.needRealname = false
                showRealname = true
            }
            Button("取消", role: .cancel) { vm.needRealname = false }
        } message: {
            Text("创建群聊需要先完成实名认证，是否前往认证？")
        }
        .fullScreenCover(isPresented: $showRealname) {
            // 认证成功 → 关认证页并复查实名（通过后 needRealname 不再弹）
            RealnameVerifyView(onVerified: {
                showRealname = false
                vm.checkRealname()
            })
        }
        .fullScreenCover(item: $chatTarget) { target in
            ChatView(peerId: target.id, isGroup: true, title: target.title)
        }
        .onChange(of: vm.created) { _, created in
            guard created, let imGroupId = vm.createdImGroupId else { return }
            if let onCreated {
                onCreated(imGroupId, vm.groupName)
            } else {
                // 创建成功直入群聊（聊天页覆盖在建群页之上，返回键两层退出）
                chatTarget = ChatTarget(id: imGroupId, title: vm.groupName)
            }
        }
    }

    // MARK: - 顶栏（含创建按钮）

    private var topBar: some View {
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
                Text("建群")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("CREATE CIRCLE")
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Button { vm.create() } label: {
                Text("创建")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(canCreate ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : .white.opacity(0.25))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(canCreate
                                ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.white.opacity(0.08)))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canCreate || vm.creating)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 群名称

    private var nameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 15))
                .foregroundStyle(Noir.goldLight.opacity(0.8))
            TextField("群名称", text: $vm.groupName)
                .font(.system(size: 14))
                .foregroundStyle(Noir.ivory)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 邀请好友标题

    private var inviteHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Noir.goldPale, Noir.goldDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: 14)
                Text("邀请好友")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Noir.goldText)
                Text("INVITE FRIENDS")
                    .font(.system(size: 8, design: .serif))
                    .italic()
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.25))
            }
            Text("已选 \(vm.selectedIds.count) 人 · 至少 3 人")
                .font(.system(size: 11))
                .foregroundStyle(vm.selectedIds.count >= 3 ? Noir.goldLight : Noir.crimsonHot.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - 好友列表

    @ViewBuilder
    private var friendList: some View {
        if vm.isLoading {
            Spacer()
            ProgressView().tint(Noir.gold)
            Spacer()
        } else if vm.friends.isEmpty {
            Spacer()
            Text("暂无可邀请的好友")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.friends) { friend in
                        friendRow(friend)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func friendRow(_ friend: FollowUser) -> some View {
        let selected = vm.selectedIds.contains(friend.userId)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.clear))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(selected ? .clear : Noir.hairlineGold, lineWidth: 1))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                }
            }
            AppAvatar(url: friend.avatar, size: 40,
                      frameURL: friend.avatarFrame,
                      frameScale: friend.avatarFrameScale ?? 1.0)
                .frame(width: 40, height: 40)
            Text(friend.nickname ?? "用户\(friend.userId)")
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Noir.ivory : .white.opacity(0.75))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selected ? Noir.noir3 : Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(selected ? Noir.gold.opacity(0.45) : Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(friend.userId) }
    }
}

// MARK: - ViewModel（对齐安卓 CreateGroupViewModel）

@MainActor
final class CreateGroupViewModel: ObservableObject {

    @Published var friends: [FollowUser] = []
    @Published var selectedIds: Set<Int64> = []
    @Published var groupName = ""
    @Published var isLoading = false
    @Published var creating = false
    @Published var needRealname = false
    @Published var created = false
    @Published var createdImGroupId: String?
    @Published var error: String?

    func load() {
        isLoading = true
        Task {
            friends = (try? await FollowAPI.friends())?.list ?? []
            isLoading = false
        }
        checkRealname()
    }

    /// 创建前查实名（对齐安卓 LaunchedEffect 检查）
    func checkRealname() {
        Task {
            if let user = try? await UserAPI.getUserInfo(), user.realnameStatus != 1 {
                needRealname = true
            }
        }
    }

    func toggle(_ userId: Int64) {
        if selectedIds.contains(userId) { selectedIds.remove(userId) }
        else { selectedIds.insert(userId) }
    }

    func create() {
        let name = groupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "请输入群名称"; return }
        guard selectedIds.count >= 3 else { error = "至少邀请3位好友"; return }
        guard !creating else { return }
        creating = true
        Task {
            do {
                let info = try await GroupAPI.create(name: name, memberUserIds: Array(selectedIds))
                creating = false
                createdImGroupId = info.imGroupId
                created = true
            } catch {
                creating = false
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
