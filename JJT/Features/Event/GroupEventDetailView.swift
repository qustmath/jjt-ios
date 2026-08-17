import SwiftUI

/// 组局详情 — 暗夜奢华风（对齐安卓 GroupEventDetailScreen）
/// 结构：封面 Hero → 标题/标签 → 发起人 → 信息面板 → 详情 → 图集 → 已报名 → 沟通群 → 底部操作栏
struct GroupEventDetailView: View {

    let eventId: Int64
    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = GroupEventDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var peerProfileId: Int64?

    private static let EVENT_TYPES = [0: "聚餐", 1: "饮酒", 2: "KTV", 3: "运动", 4: "桌游", 5: "其他"]
    private static let EVENT_STATUS = [-1: "筹备中", 0: "组局中", 1: "已满", 2: "已取消", 3: "已结束"]

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            if vm.isLoading, vm.detail == nil {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = vm.detail {
                ScrollView {
                    VStack(spacing: 0) {
                        coverHeader(detail)
                        bodyContent(detail)
                    }
                    .padding(.bottom, 96)
                }
                // 底部操作栏
                VStack {
                    Spacer()
                    bottomBar(detail)
                }
            }
        }
        .onAppear { vm.load(eventId) }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("确定") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 实名引导
        .alert("需要实名认证", isPresented: Binding(
            get: { vm.needRealname },
            set: { if !$0 { vm.clearNeedRealname() } }
        )) {
            Button("去认证") {
                vm.clearNeedRealname()
                jjtShowToast("实名认证页建设中，敬请期待")
            }
            Button("取消", role: .cancel) { vm.clearNeedRealname() }
        } message: {
            Text("报名组局需要先完成实名认证，是否前往认证？")
        }
        // 报名弹窗
        .alert("报名入局", isPresented: Binding(
            get: { vm.showJoinDialog },
            set: { if !$0 { vm.showJoinDialog(false) } }
        )) {
            Button("确认") { vm.joinEvent() }
            Button("取消", role: .cancel) { vm.showJoinDialog(false) }
        } message: {
            let price = vm.detail?.rabbitCoinPrice ?? 0
            Text(price > 0 ? "费用 \(price) 兔币/人，确认支付并报名？" : "确认报名该组局？")
        }
        // 退出/取消/结束确认
        .alert("确认退出", isPresented: Binding(
            get: { vm.showQuitConfirm },
            set: { if !$0 { vm.showQuitConfirm(false) } }
        )) {
            Button("确定退出", role: .destructive) { vm.quitEvent() }
            Button("取消", role: .cancel) { vm.showQuitConfirm(false) }
        } message: {
            Text("确定要退出此组局吗？")
        }
        .alert("取消组局", isPresented: Binding(
            get: { vm.showCancelConfirm },
            set: { if !$0 { vm.showCancelConfirm(false) } }
        )) {
            Button("确定取消", role: .destructive) { vm.cancelEvent() }
            Button("再想想", role: .cancel) { vm.showCancelConfirm(false) }
        } message: {
            Text("取消后将通知所有已报名用户，确定取消？")
        }
        .alert("结束组局", isPresented: Binding(
            get: { vm.showFinishConfirm },
            set: { if !$0 { vm.showFinishConfirm(false) } }
        )) {
            Button("确定结束", role: .destructive) { vm.finishEvent() }
            Button("取消", role: .cancel) { vm.showFinishConfirm(false) }
        } message: {
            Text("确定要结束此组局吗？结束后将无法再报名。")
        }
        // 编辑草稿
        .fullScreenCover(isPresented: Binding(
            get: { vm.showEditDraft },
            set: { if !$0 { vm.showEditDraft = false } }
        ), onDismiss: { vm.load(eventId) }) {
            CreateGroupEventView(draftId: eventId)
        }
        // 用户主页
        .fullScreenCover(isPresented: Binding(
            get: { peerProfileId != nil },
            set: { if !$0 { peerProfileId = nil } }
        )) {
            if let id = peerProfileId {
                UserProfileView(userId: id)
            }
        }
    }

    // MARK: - 封面

    private func coverHeader(_ detail: GroupEventDetailInfo) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let img = detail.coverImage, !img.isEmpty, let url = URL(string: img) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            coverFallback
                        }
                    }
                } else {
                    coverFallback
                }
            }
            .frame(width: JJTMetrics.screenWidth, height: 220)
            .clipped()

            LinearGradient(stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .clear, location: 0.5),
                .init(color: Noir.noir, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: JJTMetrics.screenWidth, height: 220)

            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 16)

            HStack {
                Spacer()
                Text((detail.rabbitCoinPrice ?? 0) == 0 ? "免费" : "\(detail.rabbitCoinPrice ?? 0) 兔币/人")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Noir.goldText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(.trailing, 16)
            .padding(.top, 16)
        }
        .frame(width: JJTMetrics.screenWidth, height: 220)
    }

    private var coverFallback: some View {
        LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255),
                                Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255), Noir.noir],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 正文

    private func bodyContent(_ detail: GroupEventDetailInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            Text(detail.title ?? "")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .padding(.top, 16)

            // 类型 + 状态标签
            HStack(spacing: 8) {
                tag(Self.EVENT_TYPES[detail.eventType ?? -1] ?? "其他", Noir.gold)
                tag(Self.EVENT_STATUS[detail.status ?? -99] ?? "", statusColor(detail.status))
                if detail.joined == true {
                    tag("已报名", Noir.crimsonHot)
                }
            }
            .padding(.top, 10)

            Rectangle().fill(Noir.goldLine).frame(height: 1)
                .padding(.vertical, 16)

            // 发起人
            HStack(spacing: 10) {
                AppAvatar(url: detail.organizerAvatar, size: 34)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                Text(detail.organizerName ?? "用户\(detail.organizerId ?? 0)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.gold)
                Text("发起人")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
            .onTapGesture { if let oid = detail.organizerId { peerProfileId = oid } }

            // 信息面板
            VStack(spacing: 0) {
                infoRow("clock", "时间", detail.eventTime ?? "待定")
                infoRow("mappin", "地点", locationText(detail))
                infoRow("person.2", "人数", "\(detail.currentCount ?? 0)/\(detail.participantLimit ?? 0) 人")
                infoRow("ticket", "费用", (detail.rabbitCoinPrice ?? 0) == 0 ? "免费" : "\(detail.rabbitCoinPrice ?? 0) 兔币/人",
                        goldValue: (detail.rabbitCoinPrice ?? 0) > 0)
                infoRow("info.circle", "退出", detail.allowQuit == 1 ? "允许退出" : "不可退出", divider: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.top, 16)

            // 详情描述
            if let desc = detail.description, !desc.isEmpty {
                sectionTitle("详情")
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(8)
                    .padding(.top, 12)
            }

            // 图集
            if let images = detail.images, !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Noir.noir3
                                }
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
                .padding(.top, 20)
            }

            // 已报名
            if let records = detail.joinRecords, !records.isEmpty {
                sectionTitle("已报名 · \(records.count)")
                VStack(spacing: 6) {
                    ForEach(records) { record in
                        HStack(spacing: 10) {
                            AppAvatar(url: record.avatar, size: 28)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Noir.gold.opacity(0.3), lineWidth: 1))
                            Text(record.nickname ?? "用户\(record.userId)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Text("\(record.participantCount ?? 1) 人")
                                .font(.system(size: 12, design: .serif))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { peerProfileId = record.userId }
                    }
                }
                .padding(.top, 12)
            }

            // 沟通群
            sectionTitle("沟通群")
            groupChatSection(detail)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func locationText(_ d: GroupEventDetailInfo) -> String {
        let parts = [d.location, d.storeName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "待定" : parts.joined(separator: " · ")
    }

    private func statusColor(_ status: Int?) -> Color {
        switch status {
        case 0: return Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255)
        case 1: return Color(red: 0xFF/255, green: 0xC1/255, blue: 0x07/255)
        case 3: return Color(red: 0xE5/255, green: 0x73/255, blue: 0x73/255)
        default: return Color(red: 0x8C/255, green: 0x8C/255, blue: 0x8C/255)
        }
    }

    // MARK: - 沟通群区

    @ViewBuilder
    private func groupChatSection(_ detail: GroupEventDetailInfo) -> some View {
        if detail.isOrganizer == true, detail.hasGroup != true {
            outlineButton(vm.isCreatingGroup ? "创建中…" : "创建沟通群", loading: vm.isCreatingGroup) {
                vm.createGroup()
            }
        } else if detail.hasGroup == true,
                  detail.isOrganizer == true || (detail.joined == true && detail.isInGroup == true) {
            // 群卡片（密语未接入，点击提示）
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255))
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                    if let avatar = detail.imGroupAvatar, !avatar.isEmpty {
                        AppAvatar(url: avatar, size: 42)
                            .frame(width: 42, height: 42)
                    } else {
                        Text(String((detail.imGroupName ?? "群").prefix(1)))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Noir.goldLight)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.imGroupName ?? "沟通群")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Noir.ivory)
                    Text("点击进入群聊")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.65),
                                                Color(red: 0x12/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { jjtShowToast("密语功能建设中，敬请期待") }
        } else if detail.joined == true, detail.hasGroup == true, detail.isInGroup != true {
            luxButton(vm.isJoiningGroup ? "加入中…" : "加入沟通群", loading: vm.isJoiningGroup) {
                vm.joinGroup()
            }
        } else if detail.hasGroup == true {
            Text("已有沟通群，报名后可加入")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        } else {
            Text("暂未创建沟通群")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - 底部操作栏

    @ViewBuilder
    private func bottomBar(_ detail: GroupEventDetailInfo) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack(spacing: 12) {
                if detail.status == -1 {
                    outlineButton("编辑") { vm.showEditDraft = true }
                    luxButton("发布") { vm.publishDraft() }
                } else if detail.isOrganizer == true, detail.status == 0 || detail.status == 1 {
                    outlineButton(vm.isCancelling ? "取消中…" : "取消组局", loading: vm.isCancelling, danger: true) {
                        vm.showCancelConfirm(true)
                    }
                    luxButton(vm.isFinishing ? "结束中…" : "结束组局", loading: vm.isFinishing) {
                        vm.showFinishConfirm(true)
                    }
                } else if detail.joined == true, detail.allowQuit == 1 {
                    outlineButton(vm.isQuitting ? "退出中…" : "退出组局", loading: vm.isQuitting, danger: true) {
                        vm.showQuitConfirm(true)
                    }
                } else if detail.joined == true, detail.allowQuit == 0 {
                    Text("已报名 · 不可退出")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                } else if detail.status == 0, detail.isOrganizer != true {
                    luxButton(vm.isJoining ? "报名中…" : "报名入局", loading: vm.isJoining) {
                        vm.tryJoin()
                    }
                } else {
                    Text(Self.EVENT_STATUS[detail.status ?? -99] ?? "")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255))
    }

    // MARK: - 通用小组件

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String,
                         goldValue: Bool = false, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.crimsonHot)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 44, alignment: .leading)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(goldValue ? AnyShapeStyle(Noir.goldText) : AnyShapeStyle(Color.white.opacity(0.85)))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            if divider {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Rectangle()
                .fill(Noir.goldLine)
                .frame(width: 40, height: 1)
        }
        .padding(.top, 20)
    }

    private func luxButton(_ text: String, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Text(text)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    private func outlineButton(_ text: String, loading: Bool = false, danger: Bool = false,
                               action: @escaping () -> Void) -> some View {
        let color = danger ? Noir.crimsonHot : Noir.gold
        return Button(action: action) {
            Group {
                if loading {
                    ProgressView().tint(color).scaleEffect(0.8)
                } else {
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(color.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }
}

// MARK: - ViewModel（对齐安卓 GroupEventDetailViewModel）

@MainActor
final class GroupEventDetailViewModel: ObservableObject {

    @Published var detail: GroupEventDetailInfo?
    @Published var isLoading = false
    @Published var isJoining = false
    @Published var isQuitting = false
    @Published var isCancelling = false
    @Published var isFinishing = false
    @Published var isCreatingGroup = false
    @Published var isJoiningGroup = false
    @Published var showJoinDialog = false
    @Published var showQuitConfirm = false
    @Published var showCancelConfirm = false
    @Published var showFinishConfirm = false
    @Published var showEditDraft = false
    @Published var needRealname = false
    @Published var error: String?

    private var eventId: Int64 = 0

    func load(_ id: Int64) {
        eventId = id
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                detail = try await GroupEventAPI.detail(id: id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // ---- 报名 ----

    /// 先验实名（对齐安卓：realnameStatus==1 才放行），通过则弹报名确认
    func tryJoin() {
        Task {
            do {
                let user = try await UserAPI.getUserInfo()
                if user.realnameStatus == 1 {
                    showJoinDialog = true
                } else {
                    needRealname = true
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func showJoinDialog(_ show: Bool) { showJoinDialog = show }

    func joinEvent() {
        guard let d = detail else { return }
        isJoining = true
        showJoinDialog = false
        Task {
            do {
                _ = try await GroupEventAPI.join(id: d.id, participantCount: 1)
                isJoining = false
                load(eventId)
            } catch let e as APIError {
                isJoining = false
                self.error = e.errorDescription
            } catch {
                isJoining = false
                self.error = error.localizedDescription
            }
        }
    }

    // ---- 退出/取消/结束 ----

    func showQuitConfirm(_ show: Bool) { showQuitConfirm = show }
    func showCancelConfirm(_ show: Bool) { showCancelConfirm = show }
    func showFinishConfirm(_ show: Bool) { showFinishConfirm = show }

    func quitEvent() { run(flag: \.isQuitting, confirm: \.showQuitConfirm) { try await GroupEventAPI.quit(id: $0) } }
    func cancelEvent() { run(flag: \.isCancelling, confirm: \.showCancelConfirm) { try await GroupEventAPI.cancel(id: $0) } }
    func finishEvent() { run(flag: \.isFinishing, confirm: \.showFinishConfirm) { try await GroupEventAPI.finish(id: $0) } }

    private func run(flag: ReferenceWritableKeyPath<GroupEventDetailViewModel, Bool>,
                     confirm: ReferenceWritableKeyPath<GroupEventDetailViewModel, Bool>,
                     action: @escaping (Int64) async throws -> Bool) {
        guard let d = detail else { return }
        self[keyPath: flag] = true
        self[keyPath: confirm] = false
        Task {
            do {
                _ = try await action(d.id)
                self[keyPath: flag] = false
                load(eventId)
            } catch {
                self[keyPath: flag] = false
                self.error = error.localizedDescription
            }
        }
    }

    // ---- 沟通群 ----

    /// 发起人创建沟通群并绑定（对齐安卓：create → bindGroup）
    func createGroup() {
        guard let d = detail else { return }
        isCreatingGroup = true
        Task {
            defer { isCreatingGroup = false }
            do {
                let group = try await GroupAPI.create(name: d.title ?? "组局群")
                let imGroupId = Int64(group.imGroupId ?? "") ?? group.id
                _ = try await GroupEventAPI.bindGroup(eventId: d.id, imGroupId: imGroupId)
                load(eventId)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 报名者加入沟通群
    func joinGroup() {
        guard let d = detail, let imGroupId = d.imGroupId else { return }
        isJoiningGroup = true
        Task {
            defer { isJoiningGroup = false }
            do {
                _ = try await GroupAPI.join(groupId: imGroupId)
                load(eventId)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // ---- 草稿 ----

    func publishDraft() {
        guard let d = detail else { return }
        Task {
            do {
                _ = try await GroupEventAPI.publish(id: d.id)
                load(eventId)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
    func clearNeedRealname() { needRealname = false }
}
