import SwiftUI

/// 群设置（对齐安卓 GroupSettingsScreen，Noir 风重制）
/// 群公告（群主可编辑）/ 群信息 / 邀请好友 / 进群申请审批 / 全员禁言 / 加群审核 /
/// 解散·退群 / 成员列表（踢出/禁言/设撤管理员/转让群主/查看主页）
struct GroupSettingsView: View {

    let imGroupId: String
    var onBack: (() -> Void)? = nil

    @StateObject private var vm = GroupSettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showInvite = false
    @State private var showDissolveConfirm = false
    @State private var showQuitConfirm = false
    @State private var profileUserId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if vm.isLoading, vm.group == nil {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            noticeSection
                            infoSection
                            actionSection
                            memberSection
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear { vm.load(imGroupId: imGroupId) }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("知道了") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .alert(vm.successMsg ?? "", isPresented: Binding(
            get: { vm.successMsg != nil },
            set: { if !$0 { vm.successMsg = nil } }
        )) {
            Button("确定") { vm.successMsg = nil }
        }
        .confirmationDialog("确认解散群？", isPresented: $showDissolveConfirm, titleVisibility: .visible) {
            Button("确认解散", role: .destructive) {
                vm.dissolve { closeAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销")
        }
        .confirmationDialog("确认退出群聊？", isPresented: $showQuitConfirm, titleVisibility: .visible) {
            Button("确认退出", role: .destructive) {
                vm.quit { closeAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后将不再收到此群消息")
        }
        .sheet(isPresented: $showInvite) {
            inviteSheet
                .presentationDetents([.medium, .large])
                .presentationBackground(Noir.noir)
        }
        .fullScreenCover(item: Binding(
            get: { profileUserId.map { ProfileTarget(id: $0) } },
            set: { profileUserId = $0?.id }
        )) { target in
            UserProfileView(userId: target.id)
        }
    }

    private struct ProfileTarget: Identifiable { let id: Int64 }

    private func closeAll() {
        if let onBack { onBack() } else { dismiss() }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button { closeAll() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text(vm.group?.name ?? "群设置")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(2)
                .foregroundStyle(Noir.goldText)
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .serif))
            .tracking(2)
            .foregroundStyle(Noir.goldText)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    // MARK: - 群公告

    @ViewBuilder
    private var noticeSection: some View {
        sectionTitle("群公告")
        if vm.isOwner {
            VStack(spacing: 10) {
                TextEditor(text: $vm.notice)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .padding(10)
                    .background(Noir.noir2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
                Button { vm.saveNotice() } label: {
                    Text("保存公告")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
        } else {
            Text(vm.notice.isEmpty ? "暂无群公告" : vm.notice)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - 群信息

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("群信息")
            VStack(spacing: 0) {
                infoRow("群名称", vm.group?.name ?? "")
                infoRow("群号码", String(vm.group?.id ?? 0))
                infoRow("成员上限", String(vm.group?.maxMemberCount ?? 200), divider: false)
            }
            .padding(.horizontal, 20)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private func infoRow(_ label: String, _ value: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)
            if divider {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    // MARK: - 操作区

    @ViewBuilder
    private var actionSection: some View {
        sectionTitle("管理")
        VStack(spacing: 0) {
            // 邀请好友（所有成员可见）
            actionRow("邀请好友", "person.badge.plus") {
                vm.loadInviteFriends()
                showInvite = true
            }
            // 进群申请（群主/管理员）
            if vm.myRole == 1 || vm.myRole == 2 {
                actionRow("进群申请", "person.text.rectangle", badge: vm.pendingRequestCount) {
                    Task { await vm.tapRequests() }
                }
            }
            if vm.showRequests, !vm.requests.isEmpty {
                requestsList
            }
            if vm.isOwner {
                actionRow(vm.group?.mutedAll == true ? "取消全员禁言" : "全员禁言", "speaker.slash") {
                    vm.toggleMuteAll()
                }
                actionRow(vm.group?.joinApproval == true ? "关闭加群审核" : "开启加群审核", "checkmark.shield") {
                    vm.toggleJoinApproval()
                }
                actionRow("解散群", "trash", tint: Noir.crimsonHot, divider: false) {
                    showDissolveConfirm = true
                }
            } else {
                actionRow("退出群聊", "rectangle.portrait.and.arrow.right", tint: Noir.crimsonHot, divider: false) {
                    showQuitConfirm = true
                }
            }
        }
        .padding(.horizontal, 20)
        .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func actionRow(_ title: String, _ icon: String, tint: Color? = nil,
                           badge: Int = 0, divider: Bool = true, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(tint ?? Noir.gold.opacity(0.7))
                        .frame(width: 20)
                    Text(title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(tint ?? Color.white.opacity(0.85))
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Noir.crimsonHot)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if divider {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    /// 待处理申请列表（内嵌展开；handleStatus 缺省按待处理 0 计）
    private var requestsList: some View {
        VStack(spacing: 0) {
            ForEach(vm.requests.filter { ($0.handleStatus ?? 0) == 0 }) { req in
                HStack(spacing: 10) {
                    AppAvatar(url: req.avatar, size: 30)
                        .frame(width: 30, height: 30)
                    Text(req.nickname ?? "用户\(req.userId)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    Spacer()
                    Button("同意") { vm.agree(req.id) }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255))
                    Button("拒绝") { vm.refuse(req.id) }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Noir.crimsonHot)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - 成员列表

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("群成员（\(vm.members.count)）")
            VStack(spacing: 0) {
                ForEach(vm.members) { member in
                    memberRow(member)
                }
            }
            .padding(.horizontal, 20)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private func memberRow(_ member: GroupMember) -> some View {
        let isMuted = (member.muteEndTime ?? 0) > Int64(Date().timeIntervalSince1970)
        return HStack(spacing: 10) {
            AppAvatar(url: member.avatar, size: 36)
                .frame(width: 36, height: 36)
            Text(member.nickname ?? "用户\(member.userId)")
                .font(.system(size: 13.5))
                .foregroundStyle(Noir.ivory)
                .lineLimit(1)
            Spacer()
            if member.role == 1 {
                roleBadge("群主", fg: Color(red: 0xFF/255, green: 0x8A/255, blue: 0x65/255), bg: Color(red: 0x3D/255, green: 0x2E/255, blue: 0x1A/255))
            } else if member.role == 2 {
                roleBadge("管理员", fg: Noir.goldLight, bg: Noir.goldDeep.opacity(0.3))
            }
            if isMuted {
                roleBadge("禁言", fg: Noir.crimsonHot, bg: Color(red: 0x3D/255, green: 0x1A/255, blue: 0x1A/255))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu { memberMenu(member, isMuted: isMuted) }
    }

    @ViewBuilder
    private func memberMenu(_ member: GroupMember, isMuted: Bool) -> some View {
        let myId = TokenManager.shared.userId ?? 0
        if member.userId != myId {
            Button { profileUserId = member.userId } label: {
                Label("查看主页", systemImage: "person")
            }
        }
        // 管理权限：群主可管所有人；管理员可管普通成员
        let canManage = vm.isOwner || (vm.myRole == 2 && member.role != 1 && member.role != 2)
        if canManage, member.userId != myId {
            Button(role: .destructive) { vm.kick(member.userId) } label: {
                Label("踢出", systemImage: "xmark.circle")
            }
            if isMuted {
                Button { vm.unmute(member.userId) } label: {
                    Label("取消禁言", systemImage: "speaker")
                }
            } else {
                Button { vm.mute(member.userId) } label: {
                    Label("禁言", systemImage: "speaker.slash")
                }
            }
        }
        if vm.isOwner, member.userId != myId {
            if member.role == 2 {
                Button { vm.removeAdmin(member.userId) } label: {
                    Label("撤销管理员", systemImage: "shield.slash")
                }
            } else if member.role != 1 {
                Button { vm.setAdmin(member.userId) } label: {
                    Label("设为管理员", systemImage: "shield")
                }
            }
            Button { vm.transferOwner(member.userId) } label: {
                Label("转让群主", systemImage: "crown")
            }
        }
    }

    private func roleBadge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - 邀请好友弹层

    private var inviteSheet: some View {
        VStack(spacing: 0) {
            Text("邀请好友加入")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Noir.goldText)
                .padding(.top, 20)
                .padding(.bottom, 12)
            if vm.inviteFriends.isEmpty {
                Spacer()
                Text("没有可邀请的好友")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.inviteFriends) { friend in
                            inviteRow(friend)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            Button { vm.submitInvite() } label: {
                Text("邀请（已选 \(vm.selectedInviteIds.count) 人）")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        vm.selectedInviteIds.isEmpty
                            ? AnyShapeStyle(Color.white.opacity(0.08))
                            : AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedInviteIds.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func inviteRow(_ friend: FollowUser) -> some View {
        let selected = vm.selectedInviteIds.contains(friend.userId)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.clear))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(selected ? .clear : Noir.hairlineGold, lineWidth: 1))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                }
            }
            AppAvatar(url: friend.avatar, size: 34)
                .frame(width: 34, height: 34)
            Text(friend.nickname ?? "用户\(friend.userId)")
                .font(.system(size: 13.5))
                .foregroundStyle(Noir.ivory)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Noir.noir3 : Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(selected ? Noir.gold.opacity(0.45) : Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleInvite(friend.userId) }
    }
}

// MARK: - ViewModel（对齐安卓 GroupSettingsViewModel）

@MainActor
final class GroupSettingsViewModel: ObservableObject {

    @Published var group: GroupInfo?
    @Published var members: [GroupMember] = []
    @Published var notice = ""
    @Published var isOwner = false
    @Published var isLoading = false
    @Published var requests: [GroupRequest] = []
    @Published var showRequests = false
    @Published var inviteFriends: [FollowUser] = []
    @Published var selectedInviteIds: Set<Int64> = []
    @Published var error: String?
    @Published var successMsg: String?

    var myRole: Int {
        let myId = TokenManager.shared.userId ?? 0
        return members.first { $0.userId == myId }?.role ?? 0
    }

    var pendingRequestCount: Int {
        requests.filter { ($0.handleStatus ?? 0) == 0 }.count
    }

    func load(imGroupId: String) {
        isLoading = true
        Task {
            do {
                // 对齐安卓：list() 里按 imGroupId 找（get 接口只有内部 id 查法才返回全字段）
                let list = try await GroupAPI.list()
                guard let g = list.first(where: { $0.imGroupId == imGroupId }) else {
                    isLoading = false
                    error = "群不存在"
                    return
                }
                apply(g)
                isLoading = false
                await loadMembers(g.id)
                if myRole == 1 || myRole == 2 { await loadRequestsAsync(g.id) }
            } catch {
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    private func apply(_ g: GroupInfo) {
        group = g
        notice = g.notice ?? ""
        isOwner = g.ownerUserId == (TokenManager.shared.userId ?? 0)
    }

    private func reload() async {
        guard let g = group, let imGroupId = g.imGroupId else { return }
        if let list = try? await GroupAPI.list(),
           let fresh = list.first(where: { $0.imGroupId == imGroupId }) {
            apply(fresh)
        }
        await loadMembers(g.id)
    }

    private func loadMembers(_ groupId: Int64) async {
        members = (try? await GroupAPI.members(groupId: groupId)) ?? []
    }

    func saveNotice() {
        guard let g = group else { return }
        Task {
            do {
                _ = try await GroupAPI.update(id: g.id, notice: notice)
                successMsg = "公告已保存"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - 成员操作

    func kick(_ userId: Int64) { run("踢出") { try await GroupAPI.kick(groupId: $0, userIds: [userId]) } }
    func mute(_ userId: Int64) { run("禁言") { try await GroupAPI.muteMember(groupId: $0, userId: userId) } }
    func unmute(_ userId: Int64) { run("取消禁言") { try await GroupAPI.unmuteMember(groupId: $0, userId: userId) } }
    func setAdmin(_ userId: Int64) { run("设管理员") { try await GroupAPI.addAdmin(groupId: $0, userIds: [userId]) } }
    func removeAdmin(_ userId: Int64) { run("撤管理员") { try await GroupAPI.removeAdmin(groupId: $0, userIds: [userId]) } }
    func transferOwner(_ userId: Int64) { run("转让群主") { try await GroupAPI.transferOwner(groupId: $0, newOwnerUserId: userId) } }

    func toggleMuteAll() {
        let newVal = group?.mutedAll != true
        run(newVal ? "全员禁言" : "取消全员禁言") { try await GroupAPI.muteAll(groupId: $0, mutedAll: newVal) }
    }

    func toggleJoinApproval() {
        let newVal = group?.joinApproval != true
        run(newVal ? "已开启加群审核" : "已关闭加群审核") { try await GroupAPI.setJoinApproval(groupId: $0, enable: newVal) }
    }

    // MARK: - 审批

    func loadRequests() {
        guard let g = group else { return }
        Task { await loadRequestsAsync(g.id) }
    }

    /// 点击「进群申请」：拉完后有则展开、无则提示（修点击无反应——空列表时界面毫无变化）
    func tapRequests() async {
        guard let g = group else { return }
        await loadRequestsAsync(g.id)
        if pendingRequestCount == 0 {
            showRequests = false
            jjtShowToast("暂无待处理申请")
        } else {
            showRequests = true
        }
    }

    private func loadRequestsAsync(_ groupId: Int64) async {
        requests = (try? await GroupAPI.requests(groupId: groupId)) ?? []
    }

    func agree(_ requestId: Int64) {
        Task {
            do {
                _ = try await GroupAPI.agreeRequest(requestId: requestId)
                guard let g = group else { return }
                await loadRequestsAsync(g.id)
                await loadMembers(g.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func refuse(_ requestId: Int64) {
        Task {
            do {
                _ = try await GroupAPI.refuseRequest(requestId: requestId)
                guard let g = group else { return }
                await loadRequestsAsync(g.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - 邀请

    func loadInviteFriends() {
        Task {
            let all = (try? await FollowAPI.friends())?.list ?? []
            let existing = Set(members.map(\.userId))
            inviteFriends = all.filter { !existing.contains($0.userId) }
            selectedInviteIds = []
        }
    }

    func toggleInvite(_ userId: Int64) {
        if selectedInviteIds.contains(userId) { selectedInviteIds.remove(userId) }
        else { selectedInviteIds.insert(userId) }
    }

    func submitInvite() {
        let ids = Array(selectedInviteIds)
        guard !ids.isEmpty else { return }
        run("邀请") { try await GroupAPI.invite(groupId: $0, userIds: ids) }
        selectedInviteIds = []
    }

    // MARK: - 解散 / 退群

    func dissolve(onDone: @escaping () -> Void) {
        guard let g = group else { return }
        Task {
            do {
                _ = try await GroupAPI.dissolve(groupId: g.id)
                onDone()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func quit(onDone: @escaping () -> Void) {
        guard let g = group else { return }
        Task {
            do {
                _ = try await GroupAPI.quit(groupId: g.id)
                onDone()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - 通用操作

    private func run(_ name: String, _ work: @escaping (Int64) async throws -> Bool) {
        guard let g = group else { return }
        Task {
            do {
                _ = try await work(g.id)
                successMsg = "\(name)成功"
                await reload()
                if myRole == 1 || myRole == 2 { await loadRequestsAsync(g.id) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
