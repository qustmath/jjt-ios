import SwiftUI

/// 搜索群聊（对齐安卓 SearchGroupScreen）
/// 空关键词 = 推荐列表；加入：直接进群 / 需审批提示
struct SearchGroupView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = SearchGroupViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var chatTarget: CreateGroupView.ChatTarget?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                searchField
                groupList
            }
        }
        .jjtPageGestures()
        .onAppear { vm.loadRecommend() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("知道了") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .alert(vm.resultMsg ?? "", isPresented: Binding(
            get: { vm.resultMsg != nil },
            set: { if !$0 { vm.resultMsg = nil } }
        )) {
            Button("知道了") { vm.resultMsg = nil }
        }
        .fullScreenCover(item: $chatTarget) { target in
            ChatView(peerId: target.id, isGroup: true, title: target.title)
        }
        .onChange(of: vm.joinedGroup?.id) { _, _ in
            // 加入成功 → 直入群聊
            if let joined = vm.joinedGroup, let imGroupId = joined.imGroupId {
                chatTarget = CreateGroupView.ChatTarget(id: imGroupId, title: joined.name ?? "群聊")
                vm.joinedGroup = nil
            }
        }
    }

    // MARK: - 顶栏

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
                Text("搜索群聊")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("FIND CIRCLE")
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
    }

    // MARK: - 搜索框

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Noir.goldLight.opacity(0.8))
            TextField("搜索群名称 / 群号", text: $vm.keyword)
                .font(.system(size: 14))
                .foregroundStyle(Noir.ivory)
                .onSubmit { vm.search(vm.keyword) }
                .onChange(of: vm.keyword) { _, v in vm.search(v) }
            if !vm.keyword.isEmpty {
                Button {
                    vm.keyword = ""
                    vm.search("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 列表

    @ViewBuilder
    private var groupList: some View {
        let shown = vm.keyword.trimmingCharacters(in: .whitespaces).isEmpty ? vm.recommend : vm.results
        if vm.isLoading {
            Spacer()
            ProgressView().tint(Noir.gold)
            Spacer()
        } else if shown.isEmpty {
            Spacer()
            Text(vm.keyword.isEmpty ? "暂无推荐群聊" : "没有找到相关群聊")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.keyword.isEmpty {
                        Text("推荐群聊")
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .tracking(2)
                            .foregroundStyle(Noir.goldText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    ForEach(shown) { group in
                        groupRow(group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func groupRow(_ group: GroupInfo) -> some View {
        HStack(spacing: 12) {
            AppAvatar(url: group.avatar, size: 44)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name ?? "群\(group.id)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
                Text("群号 \(group.id) · \(group.memberCount ?? 0)/\(group.maxMemberCount ?? 200) 人")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            if group.joined == true {
                Text("已加入")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            } else {
                Button { vm.join(group) } label: {
                    Text("加入")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            // 已加入的群点卡片直接进群聊
            if group.joined == true, let imGroupId = group.imGroupId {
                chatTarget = CreateGroupView.ChatTarget(id: imGroupId, title: group.name ?? "群聊")
            }
        }
    }
}

// MARK: - ViewModel（对齐安卓 SearchGroupViewModel）

@MainActor
final class SearchGroupViewModel: ObservableObject {

    @Published var keyword = ""
    @Published var results: [GroupInfo] = []
    @Published var recommend: [GroupInfo] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var resultMsg: String?
    /// 刚加入成功的群（触发跳转群聊）
    @Published var joinedGroup: GroupInfo?

    private var searchTask: Task<Void, Never>?

    func loadRecommend() {
        Task {
            recommend = (try? await GroupAPI.search(keyword: "")) ?? []
        }
    }

    func search(_ keyword: String) {
        self.keyword = keyword
        searchTask?.cancel()
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { results = []; return }
        // 输入防抖 300ms
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isLoading = true
            do {
                results = try await GroupAPI.search(keyword: kw)
                isLoading = false
            } catch {
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    func join(_ group: GroupInfo) {
        Task {
            do {
                let msg = try await GroupAPI.join(groupId: group.id) ?? "操作成功"
                if msg.contains("已加入") {
                    joinedGroup = group
                } else {
                    resultMsg = msg
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
