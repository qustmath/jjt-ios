import SwiftUI

/// 好友申请管理 — 收到的申请（同意/拒绝）+ 我发出的（等待处理）
/// 对齐安卓 FriendApplyScreen；同意后双方自动互关
struct FriendApplyListView: View {

    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = FriendApplyViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var peerProfileId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar

                if vm.isLoading, vm.received.isEmpty, vm.sent.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.received.isEmpty, vm.sent.isEmpty {
                    Spacer()
                    Text("暂无申请")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if !vm.received.isEmpty {
                                sectionTitle("收到的申请")
                                ForEach(vm.received) { apply in
                                    applyRow(apply, busy: vm.busyId == apply.id) {
                                        HStack(spacing: 8) {
                                            applyButton("拒绝", outline: true) { vm.handle(id: apply.id, agree: false) }
                                            applyButton("同意", outline: false) { vm.handle(id: apply.id, agree: true) }
                                        }
                                    }
                                }
                            }
                            if !vm.sent.isEmpty {
                                sectionTitle("我发出的")
                                ForEach(vm.sent) { apply in
                                    applyRow(apply, busy: false) {
                                        Text("等待处理")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                }
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
        .fullScreenCover(isPresented: Binding(
            get: { peerProfileId != nil },
            set: { if !$0 { peerProfileId = nil } }
        )) {
            if let id = peerProfileId {
                UserProfileView(userId: id)
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button { (onBack ?? { dismiss() })() } label: {
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
                    Text("好友申请")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("NEW FRIENDS")
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .tracking(3)
            .foregroundStyle(Noir.gold.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func applyRow<Trailing: View>(
        _ apply: FriendApplyInfo, busy: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            AppAvatar(url: apply.avatar, size: 42)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(apply.nickname ?? "用户\(apply.peerUserId)")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
                if let time = apply.createTime?.prefix(10) {
                    Text(time)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView().tint(Noir.gold).scaleEffect(0.8)
            } else {
                trailing()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { peerProfileId = apply.peerUserId }
    }

    private func applyButton(_ text: String, outline: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(outline ? Color.white.opacity(0.55) : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    outline
                        ? AnyShapeStyle(Color.clear)
                        : AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(outline ? 0.2 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
final class FriendApplyViewModel: ObservableObject {

    @Published var received: [FriendApplyInfo] = []
    @Published var sent: [FriendApplyInfo] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var busyId: Int64?

    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            async let receivedTask = FollowAPI.friendApplyReceived()
            async let sentTask = FollowAPI.friendApplySent()
            received = (try? await receivedTask) ?? []
            sent = (try? await sentTask) ?? []
        }
    }

    /// 同意/拒绝（busyId 防重复点击；同意后刷新并提示）
    func handle(id: Int64, agree: Bool) {
        guard busyId == nil else { return }
        busyId = id
        Task {
            defer { busyId = nil }
            do {
                if agree {
                    _ = try await FollowAPI.friendApplyAgree(id: id)
                    jjtShowToast("已同意，你们已成为好友")
                } else {
                    _ = try await FollowAPI.friendApplyReject(id: id)
                }
                load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
