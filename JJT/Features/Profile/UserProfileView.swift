import SwiftUI
import PhotosUI

/// 个人主页 — 暗夜奢华风（对齐安卓 UserProfileScreen）
/// 结构：封面 → 头像/徽章 → 昵称/签名 → 统计 → 操作栏(他人)/入口卡(本人) → 帖子瀑布流
struct UserProfileView: View {

    let userId: Int64
    var onBack: (() -> Void)? = nil

    @StateObject private var vm = UserProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var editingField: EditField?
    @State private var editInput = ""
    @State private var pendingDeletePost: PostInfo?
    @State private var detailPostId: Int64?
    @State private var followListTab: Int?     // 0=粉丝 1=关注（nil 关闭）
    @State private var showGiftPanel = false
    @State private var showGiftWall = false
    @State private var showChat = false
    @State private var showAchievementHall = false

    private enum EditField: Identifiable {
        case nickname, mark
        var id: Int { hashValue }
        var title: String { self == .nickname ? "修改昵称" : "编辑签名" }
    }

    private var isSelf: Bool { vm.isSelf }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            if vm.isLoading, vm.profile == nil {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        coverHeader
                        profileSection
                        postsSection
                    }
                }
            }
        }
        .onAppear { vm.load(userId: userId) }
        // 彩蛋「无名之辈」：点开一位 TA 的资料卡（资料加载后判定，对齐安卓）
        .onChange(of: vm.profile?.id) { _, id in
            if id != nil, !vm.isSelf { EggTrigger.report("stranger") }
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        .alert(editingField?.title ?? "", isPresented: Binding(
            get: { editingField != nil },
            set: { if !$0 { editingField = nil } }
        )) {
            TextField("请输入", text: $editInput)
            Button("保存") { commitEdit() }
            Button("取消", role: .cancel) { editingField = nil }
        }
        .confirmationDialog("删除帖子", isPresented: Binding(
            get: { pendingDeletePost != nil },
            set: { if !$0 { pendingDeletePost = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let post = pendingDeletePost {
                    vm.deletePost(post.id)
                    pendingDeletePost = nil
                }
            }
            Button("取消", role: .cancel) { pendingDeletePost = nil }
        } message: {
            Text("删除后不可恢复，帖子的图片/视频也会一并删除。")
        }
        .fullScreenCover(isPresented: Binding(
            get: { detailPostId != nil },
            set: { if !$0 { detailPostId = nil } }
        )) {
            if let id = detailPostId {
                PostDetailView(postId: id)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { followListTab != nil },
            set: { if !$0 { followListTab = nil } }
        )) {
            if let tab = followListTab {
                FollowListView(initialTab: tab)
            }
        }
        // 送礼面板（底部弹层）
        .sheet(isPresented: $showGiftPanel) {
            GiftPanelSheet(
                receiverId: userId,
                toName: vm.profile?.nickname ?? "TA",
                onClose: { showGiftPanel = false }
            )
            .presentationDetents([.medium])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        // 礼物墙（他人）
        .fullScreenCover(isPresented: $showGiftWall) {
            GiftWallView(userId: userId)
        }
        // 私信
        .fullScreenCover(isPresented: $showChat) {
            ChatView(peerId: String(userId), isGroup: false, title: vm.profile?.nickname)
        }
        // 成就殿堂（本人）
        .fullScreenCover(isPresented: $showAchievementHall) {
            AchievementHallView()
        }
        .jjtPageGestures()
    }

    // MARK: - 封面

    private var coverHeader: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let bg = vm.profile?.profileBg, !bg.isEmpty {
                    WebImage(url: webImageURL(bg)) { coverFallback }
                } else {
                    coverFallback
                }
            }
            .frame(width: JJTMetrics.screenWidth, height: 208)
            .clipped()

            // 渐变蒙版
            LinearGradient(stops: [
                .init(color: .black.opacity(0.5), location: 0),
                .init(color: .clear, location: 0.45),
                .init(color: Noir.noir, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: JJTMetrics.screenWidth, height: 208)

            // 返回
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

            // 分享（占位）
            HStack {
                Spacer()
                Button { jjtShowToast("分享功能敬请期待") } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                }
            }
            .padding(.trailing, 16)
            .padding(.top, 16)

            // 更换封面（本人）
            if isSelf {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $coverItem, matching: .images) {
                        HStack(spacing: 6) {
                            if isUploading {
                                ProgressView().tint(.white).scaleEffect(0.6)
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 12))
                            }
                            Text("更换封面")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45))
                        .clipShape(Capsule())
                    }
                    .disabled(isUploading)
                    .onChange(of: coverItem) { _, item in
                        uploadPicked(item) { UpdateUserReq(profileBg: $0) }
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 208 - 52 - 30)
            }
        }
        .frame(width: JJTMetrics.screenWidth, height: 208)
    }

    private var coverFallback: some View {
        LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255),
                                Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255), Noir.noir],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 资料区（整体上移与封面交叠）

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头像 + VIP 徽章
            HStack(alignment: .bottom) {
                ZStack(alignment: .bottomTrailing) {
                    AppAvatar(url: vm.profile?.avatar, size: 108,
                              frameURL: vm.profile?.avatarFrame,
                              frameScale: vm.profile?.avatarFrameScale.map { CGFloat($0) } ?? 1.25)
                        .frame(width: 108, height: 108)
                        // 彩蛋「第三只兔耳」：本人点头像（对齐安卓，头像框更换入口同期触发）
                        .contentShape(Circle())
                        .onTapGesture { if isSelf { EggTrigger.report("third-ear") } }

                    if isSelf {
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 26, height: 26)
                                if isUploading {
                                    ProgressView().tint(.white).scaleEffect(0.5)
                                } else {
                                    Image(systemName: "camera")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(isUploading)
                        .onChange(of: avatarItem) { _, item in
                            uploadPicked(item) { UpdateUserReq(avatar: $0) }
                        }
                        .offset(x: 2, y: 2)
                    }
                }
                Spacer()
                if let level = vm.profile?.level, let name = level.name, !name.isEmpty {
                    vipBadge(level)
                }
            }

            // 昵称
            HStack(spacing: 6) {
                Text(vm.profile?.nickname ?? "用户")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
                if isSelf {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.top, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isSelf else { return }
                editInput = vm.profile?.nickname ?? ""
                editingField = .nickname
            }

            // 签名
            HStack(spacing: 6) {
                Text("“\((vm.profile?.mark?.isEmpty == false) ? vm.profile!.mark! : "这个人很神秘，什么都没留下")”")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                if isSelf {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isSelf else { return }
                editInput = vm.profile?.mark ?? ""
                editingField = .mark
            }

            // 位置
            if let area = vm.profile?.areaName, !area.isEmpty {
                Text(area)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 4)
            }

            // 统计：动态 / 关注 / 粉丝 / 获赞（本人主页关注、粉丝可点）
            HStack(spacing: 28) {
                statPair("\(vm.profile?.postCount ?? 0)", "动态")
                statPair("\(vm.profile?.followCount ?? 0)", "关注") {
                    if isSelf { followListTab = 1 }
                }
                statPair("\(vm.profile?.fansCount ?? 0)", "粉丝") {
                    if isSelf { followListTab = 0 }
                }
                statPair("\(vm.profile?.likeCount ?? 0)", "获赞")
            }
            .padding(.top, 12)

            // 操作栏（他人）：关注 / 私信 / 送礼 / 加好友
            if !isSelf, let p = vm.profile {
                HStack(spacing: 10) {
                    let following = p.isFollowing == true
                    Button { vm.toggleFollow() } label: {
                        Text(following ? "已关注" : "关注")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                following
                                    ? AnyShapeStyle(Color.white.opacity(0.06))
                                    : AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(following ? 0.15 : 0), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    outlineButton("私信") { showChat = true }
                    outlineButton("送礼", gold: true) { showGiftPanel = true }
                    FriendApplyButton(targetUserId: p.id)
                }
                .padding(.top, 20)
            }

            // 入口卡（本人）：成就勋章；（他人）：礼物墙
            if isSelf {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        entryCard("成就勋章", "\(vm.hallLit)/\(vm.hallTotal)", "medal", gold: true) {
                            showAchievementHall = true
                        }
                    }
                }
                .padding(.top, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        entryCard("礼物墙", "查看", "gift", gold: true) { showGiftWall = true }
                    }
                }
                .padding(.top, 20)
            }

            // 动态标题
            VStack(spacing: 10) {
                HStack {
                    Text("我 的 帖 子")
                        .font(.system(size: 12))
                        .tracking(3.6)
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                }
                Rectangle().fill(Noir.goldLine).frame(height: 1)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .offset(y: -44)
        .padding(.bottom, -44)
    }

    // MARK: - 帖子瀑布流

    private var postsSection: some View {
        Group {
            if vm.posts.isEmpty {
                Text("暂无动态")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else {
                let left = vm.posts.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                let right = vm.posts.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
                HStack(alignment: .top, spacing: 6) {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(left.enumerated()), id: \.element.id) { i, post in
                            masonryCard(post, tall: i % 2 == 1)
                        }
                    }
                    LazyVStack(spacing: 6) {
                        ForEach(Array(right.enumerated()), id: \.element.id) { i, post in
                            masonryCard(post, tall: i % 2 == 0)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)

                if vm.isLoadingMore {
                    ProgressView().tint(Noir.crimson)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                } else if vm.hasMore {
                    // 触底加载更多
                    Color.clear.frame(height: 1)
                        .onAppear { vm.loadMore() }
                }
            }
        }
    }

    private func masonryCard(_ post: PostInfo, tall: Bool) -> some View {
        let coverUrl = post.mediaType == "video" ? post.videoCover : post.images?.first
        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Noir.noir3
                    .aspectRatio(tall ? 0.75 : 1.0, contentMode: .fit)
                    .overlay {
                        if let cover = coverUrl {
                            WebImage(url: webImageURL(cover)) { Noir.noir3 }
                        } else {
                            Noir.noir3.overlay(
                                Text("暂无图片")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Noir.textFaint)
                            )
                        }
                    }
                    .clipped()
                    .overlay(
                        LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    )

                HStack(spacing: 6) {
                    if post.auditStatus == 0 {
                        Text("审核中")
                            .font(.system(size: 9))
                            .foregroundStyle(Noir.gold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Noir.gold.opacity(0.6), lineWidth: 1))
                    }
                    if post.isPaidLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Noir.goldLight)
                            .padding(6)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Noir.ivory.opacity(0.9))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 9))
                    Text("\(post.likeCount ?? 0)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { detailPostId = post.id }
        .onLongPressGesture {
            if isSelf { pendingDeletePost = post }
        }
    }

    // MARK: - 小组件

    private func vipBadge(_ level: UserLevelInfo) -> some View {
        let color = Noir.tierColor(level.color)
        return HStack(spacing: 4) {
            Image(systemName: "crown")
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text("\(level.name ?? "") · Lv.\(level.levelInTier ?? 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.65), lineWidth: 1.5))
        .onTapGesture {
            if isSelf { jjtShowToast("会员中心建设中，敬请期待") }
        }
    }

    private func statPair(_ value: String, _ label: String, onTap: (() -> Void)? = nil) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 20, design: .serif))
                .foregroundStyle(Noir.goldText)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func outlineButton(_ label: String, gold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(gold ? Noir.goldLight : Color.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(gold ? Noir.gold.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func entryCard(_ title: String, _ sub: String, _ icon: String, gold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: gold
                                ? [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Color(red: 0x14/255, green: 0x0D/255, blue: 0x04/255)]
                                : [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                            center: .center, startRadius: 0, endRadius: 26))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Noir.goldLight.opacity(0.5), lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Noir.goldLight)
                }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(width: 108)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private func commitEdit() {
        guard let field = editingField else { return }
        let value = editInput.trimmingCharacters(in: .whitespacesAndNewlines)
        editingField = nil
        switch field {
        case .nickname:
            guard !value.isEmpty, value != vm.profile?.nickname else { return }
            vm.updateSelf(UpdateUserReq(nickname: value))
        case .mark:
            guard value != vm.profile?.mark else { return }
            vm.updateSelf(UpdateUserReq(mark: value))
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem?, makeReq: @escaping (String) -> UpdateUserReq) {
        guard let item else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      let jpeg = uiImage.jpegData(compressionQuality: 0.82) else { return }
                let url = try await APIClient.shared.uploadFile(
                    data: jpeg, filename: "profile_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")
                vm.updateSelf(makeReq(url))
            } catch {
                vm.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    UserProfileView(userId: 1)
}
