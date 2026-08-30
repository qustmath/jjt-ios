import SwiftUI
import AVKit

/// 帖子详情 — 暗夜奢华风（对齐安卓 PostDetailScreen.kt）
/// 结构：媒体区（多图翻页/视频 + 悬浮返回分享）→ 内容区（标题/正文/话题/时间地点）→
///       作者玻璃卡 → 鎏金线 + 私语（评论）列表；底部互动栏 + 评论输入条
/// 已含：付费解锁（支付密码链路）、编辑/删除、分享面板、送礼、长按删自己评论、图片全屏预览
struct PostDetailView: View {

    @StateObject private var vm: PostDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var commentText = ""
    @State private var replyTo: CommentInfo?
    @State private var isSending = false
    @State private var toast: String?
    @State private var previewIndex: Int?
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false
    @State private var showGiftPanel = false
    @State private var commentToDelete: CommentInfo?
    @StateObject private var payGuard = PayPasswordGuard()
    @State private var showPaySettings = false
    @State private var showRecharge = false
    @FocusState private var inputFocused: Bool

    init(postId: Int64) {
        _vm = StateObject(wrappedValue: PostDetailViewModel(postId: postId))
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            if let post = vm.post {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            heroMedia(post)
                            contentSection(post)
                            authorBar(post)
                            commentsSection
                        }
                    }
                    .refreshable { vm.load() }

                    bottomBar(post)
                }
                .ignoresSafeArea(edges: .top)
            } else if vm.isLoading {
                ProgressView().tint(Noir.crimson).scaleEffect(1.4)
            } else {
                VStack(spacing: 16) {
                    Text(vm.errorMessage ?? "加载失败")
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.textDim)
                    Button("返回") { dismiss() }
                        .foregroundStyle(Noir.crimsonHot)
                }
            }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Noir.noir3.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 120)
                        .transition(.opacity)
                }
            }
        }
        .onAppear { if vm.post == nil { vm.load() } }
        // 彩蛋「静音剧场」：安静读完一篇帖子（停留 8 秒，对齐安卓）
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            EggTrigger.report("post")
        }
        .fullScreenCover(isPresented: $showEditor, onDismiss: { vm.load() }) {
            CreatePostView(editPostId: vm.postId)
        }
        // 支付密码守卫（付费解锁）；余额不足 → 充值引导
        .payPasswordGuard(payGuard, hint: vm.post.map { "支付 \($0.paidPrice ?? 0) 兔币解锁本条内容" }) { showPaySettings = true }
        .onReceive(NotificationCenter.default.publisher(for: .jjtInsufficientBalance)) { _ in
            showRecharge = true
        }
        .fullScreenCover(isPresented: $showPaySettings) {
            PayPasswordSettingsView()
        }
        .fullScreenCover(isPresented: $showRecharge) {
            CoinRechargeView()
        }
        // 分享面板
        .sheet(isPresented: $showShareSheet) {
            if let post = vm.post {
                PostShareSheet(post: post) { showShareSheet = false }
                    .presentationDetents([.medium])
                    .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
            }
        }
        // 送礼面板（收礼人 = 帖子作者；scene=post 服务端分账给发帖人并计礼物热度）
        .sheet(isPresented: $showGiftPanel) {
            GiftPanelSheet(
                receiverId: vm.post?.userId ?? 0,
                toName: vm.post?.nickname ?? "TA",
                onClose: { showGiftPanel = false },
                scene: "post",
                sceneId: vm.postId
            )
            .presentationDetents([.medium])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        // 删除自己的评论（长按触发）
        .confirmationDialog("删除这条私语？", isPresented: Binding(
            get: { commentToDelete != nil },
            set: { if !$0 { commentToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let c = commentToDelete { vm.deleteComment(c.id) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确定删除这条帖子吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    _ = try? await SocialAPI.deletePost(id: vm.postId)
                    NotificationCenter.default.post(name: .jjtPostCreated, object: nil)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewIndex != nil },
            set: { if !$0 { previewIndex = nil } }
        )) {
            if let post = vm.post, let images = post.images, let i = previewIndex {
                ImagePreviewViewer(images: images, initialIndex: i)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: - 1. 媒体区

    private var heroHeight: CGFloat { JJTMetrics.screenWidth * 4 / 3 }

    @ViewBuilder
    private func heroMedia(_ post: PostInfo) -> some View {
        ZStack(alignment: .top) {
            if post.mediaType == "video", let video = post.video, !post.isPaidLocked {
                // 视频：内联播放器
                if let url = webImageURL(video) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenWidth * 9 / 16)
                        .background(Color.black)
                }
            } else if post.mediaType == "video", post.isPaidLocked {
                // 付费视频未解锁：封面虚化 + 锁
                ZStack {
                    AsyncImage(url: webImageURL(post.videoCover)) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir3 }
                    }
                    .frame(width: JJTMetrics.screenWidth, height: heroHeight)
                    .clipped()
                    .blur(radius: 14)
                    lockOverlay
                }
                .frame(width: JJTMetrics.screenWidth, height: heroHeight)
            } else if let images = post.images, !images.isEmpty {
                // 多图翻页（TabView 显式定宽定高，避免布局协商）
                ZStack(alignment: .bottom) {
                    TabView {
                        ForEach(images.indices, id: \.self) { i in
                            AsyncImage(url: webImageURL(images[i])) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir3 }
                            }
                            .frame(width: JJTMetrics.screenWidth, height: heroHeight)
                            .clipped()
                            .blur(radius: post.isPaidLocked ? 14 : 0)
                            .contentShape(Rectangle())
                            // 付费未解锁不给预览，保持虚化遮罩
                            .onTapGesture { if !post.isPaidLocked { previewIndex = i } }
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(width: JJTMetrics.screenWidth, height: heroHeight)
                    .clipped()

                    if post.isPaidLocked { lockOverlay }
                }
                .frame(width: JJTMetrics.screenWidth, height: heroHeight)
            }

            // 渐变：顶部压暗 + 底部融入页面底色
            if post.mediaType == "video" || !(post.images ?? []).isEmpty {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .clear, location: 0.85),
                    .init(color: Noir.noir, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(width: JJTMetrics.screenWidth,
                       height: post.mediaType == "video" && !post.isPaidLocked ? JJTMetrics.screenWidth * 9 / 16 : heroHeight)
                .allowsHitTesting(false)
            }

            // 悬浮返回 / 编辑 / 删除 / 分享
            HStack {
                floatingButton(systemImage: "chevron.left") { dismiss() }
                Spacer()
                // 自己的帖子：编辑 + 删除（对齐安卓 onEdit/deletePost）
                if post.userId == TokenManager.shared.userId {
                    floatingButton(systemImage: "pencil") { showEditor = true }
                    floatingButton(systemImage: "trash") { showDeleteConfirm = true }
                }
                floatingButton(systemImage: "square.and.arrow.up") { showShareSheet = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
    }

    private var lockOverlay: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(Noir.goldPale)
            Text("付费内容 · 解锁后查看")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func floatingButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.45))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
        }
    }

    // MARK: - 2. 内容区

    @ViewBuilder
    private func contentSection(_ post: PostInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let paid = (post.paidPrice ?? 0) > 0
            let isMasked = paid && post.unlocked != true && post.content != nil

            if isMasked {
                // 付费遮罩：解锁走支付密码守卫（余额不足自动联动充值引导）
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Noir.goldPale)
                    Text("这是一条付费密语")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text("支付 \(post.paidPrice ?? 0) 兔币解锁全文")
                        .font(.system(size: 11))
                        .foregroundStyle(Noir.textDim)
                    Button {
                        payGuard.require { pwd in try await vm.unlock(payPassword: pwd) }
                    } label: {
                        Text("解锁")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
            } else {
                if paid {
                    Text("已解锁")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .padding(.bottom, 10)
                }

                let (title, body) = Self.splitTitleBody(post)
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(Noir.ivory)
                }
                if !body.isEmpty {
                    ExpandableBodyText(body)
                        .padding(.top, 12)
                }
            }

            // 话题
            if let topics = post.topics, !topics.isEmpty {
                HStack(spacing: 8) {
                    ForEach(topics, id: \.self) { topic in
                        Text("#\(topic)")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.crimsonHot)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Noir.wine.opacity(0.35))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Noir.hairlineRed, lineWidth: 1))
                    }
                }
                .padding(.top, 12)
            }

            // 时间 + 阅读量
            HStack(spacing: 10) {
                Text(post.createTime.map(Self.formatTime) ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.textFaint)
                HStack(spacing: 3) {
                    Image(systemName: "eye").font(.system(size: 11))
                    Text(Self.formatCount(post.viewCount ?? 0)).font(.system(size: 11))
                }
                .foregroundStyle(Noir.textFaint)
            }
            .padding(.top, 10)

            // 定位地址（手输地点优先，其次定位城市）
            if let place = [post.location, post.cityName].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.crimsonHot)
                    Text(place)
                        .font(.system(size: 11))
                        .foregroundStyle(Noir.textFaint)
                        .lineLimit(1)
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// 标题/正文拆分（对齐安卓：后端从 content 首行拆 title 下发）
    private static func splitTitleBody(_ post: PostInfo) -> (String, String) {
        let content = post.content ?? ""
        let title = post.title?.isEmpty == false ? post.title! : (content.components(separatedBy: "\n").first ?? "")
        let body: String
        if content.isEmpty {
            body = ""
        } else if let nl = content.firstIndex(of: "\n"), content.hasPrefix(title) {
            body = String(content[content.index(after: nl)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if content == title {
            body = ""
        } else {
            body = content
        }
        return (title, body)
    }

    // MARK: - 3. 作者玻璃卡

    private func authorBar(_ post: PostInfo) -> some View {
        Button { showToast("个人主页敬请期待") } label: {
            HStack(spacing: 12) {
                AppAvatar(url: post.avatar, size: 44,
                          frameURL: post.avatarFrame, frameScale: CGFloat(post.avatarFrameScale ?? 1.15))
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(post.nickname ?? "用户\(post.userId ?? 0)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(1)
                        if let vip = post.vipLevel {
                            let c = Noir.tierColor(post.vipLevelColor)
                            Text("\(vip) · Lv.\(post.levelInTier ?? 1)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(c)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.9))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(c.opacity(0.55), lineWidth: 1))
                        }
                    }
                    Text("点击查看主页")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                // 加好友（非本人帖；已是好友/已申请时组件内部控制状态）
                FriendApplyButton(targetUserId: post.userId)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: - 4/5. 私语（评论）

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 鎏金线 + 标题
            Rectangle()
                .fill(Noir.goldLine)
                .frame(height: 1)
                .opacity(0.5)
                .padding(.horizontal, 20)
                .padding(.top, 22)
            HStack(spacing: 8) {
                Text("WHISPERS")
                    .font(.system(size: 10, design: .serif).italic())
                    .tracking(3)
                    .foregroundStyle(Noir.gold.opacity(0.6))
                Text("私语")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text("\(vm.comments.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.textDim)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if vm.comments.isEmpty {
                Text("还没有私语，来第一句吧")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                ForEach(vm.comments) { comment in
                    commentRow(comment)
                }
            }
        }
        .padding(.bottom, 30)
    }

    private func commentRow(_ comment: CommentInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppAvatar(url: comment.avatar, size: 32,
                      frameURL: comment.avatarFrame, frameScale: CGFloat(comment.avatarFrameScale ?? 1.2))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(comment.nickname ?? "用户\(comment.userId ?? 0)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    if let vip = comment.vipLevel {
                        let c = Noir.tierColor(comment.vipLevelColor)
                        Text("\(vip) · Lv.\(comment.levelInTier ?? 1)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(c)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.9))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(c.opacity(0.55), lineWidth: 1))
                    }
                    Spacer()
                    Text(comment.createTime.map(Self.formatTime) ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.textFaint)
                }
                if let pid = comment.parentId, pid > 0,
                   let parent = vm.comments.first(where: { $0.id == pid }) {
                    Text("回复 \(parent.nickname ?? "用户\(parent.userId ?? 0)")")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.gold.opacity(0.7))
                }
                Text(comment.content)
                    .font(.system(size: 13))
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            replyTo = comment
            inputFocused = true
        }
        // 长按删除自己的评论（对齐安卓）
        .onLongPressGesture {
            if comment.userId == TokenManager.shared.userId { commentToDelete = comment }
        }
    }

    // MARK: - 底部互动栏 + 评论输入

    private func bottomBar(_ post: PostInfo) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Noir.goldLine)
                .frame(height: 1)
                .opacity(0.6)

            HStack(spacing: 0) {
                // 评论输入胶囊
                HStack {
                    Image(systemName: replyTo == nil ? "bubble.left" : "arrowshape.turn.up.left")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                    TextField(replyTo.map { "回复 \($0.nickname ?? "TA")" } ?? "说点暗语…", text: $commentText)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendComment() }
                    if !commentText.isEmpty {
                        Button(action: sendComment) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(isSending ? Noir.textDim : Noir.crimsonHot)
                        }
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))

                actionIcon(systemImage: post.liked == true ? "heart.fill" : "heart",
                           count: post.likeCount ?? 0,
                           active: post.liked == true) { vm.toggleLike() }
                actionIcon(systemImage: post.favorited == true ? "star.fill" : "star",
                           count: post.favoriteCount ?? 0,
                           active: post.favorited == true) { vm.toggleFavorite() }
                // 送礼入口（自己的帖子不显示，对齐安卓）
                if post.userId != TokenManager.shared.userId {
                    actionIcon(systemImage: "gift",
                               count: nil,
                               active: false) { showGiftPanel = true }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.95))
    }

    private func actionIcon(systemImage: String, count: Int?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                    .foregroundStyle(active ? Noir.crimsonHot : .white.opacity(0.6))
                if let count {
                    Text(Self.formatCount(count))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 52)
        }
        .buttonStyle(.plain)
    }

    private func sendComment() {
        guard !isSending else { return }
        isSending = true
        let text = commentText
        let parent = replyTo?.id
        Task {
            let ok = await vm.addComment(content: text, parentId: parent)
            isSending = false
            if ok {
                commentText = ""
                replyTo = nil
                inputFocused = false
            } else if let err = vm.errorMessage {
                showToast(err)
                vm.errorMessage = nil
            }
        }
    }

    // MARK: - 工具

    /// 时间戳(ms) → 相对时间（对齐安卓 formatTime）
    static func formatTime(_ ts: Int64) -> String {
        let diff = Date().timeIntervalSince1970 * 1000 - Double(ts)
        switch diff {
        case ..<60_000: return "刚刚"
        case ..<3_600_000: return "\(Int(diff / 60_000))分钟前"
        case ..<86_400_000: return "\(Int(diff / 3_600_000))小时前"
        case ..<604_800_000: return "\(Int(diff / 86_400_000))天前"
        default:
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date(timeIntervalSince1970: Double(ts) / 1000))
        }
    }

    static func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - 正文折叠（默认 4 行，超出显示「展开」）

private struct ExpandableBodyText: View {
    let body_: String
    @State private var expanded = false

    init(_ body: String) { self.body_ = body }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(body_)
                .font(.system(size: 13.5))
                .lineSpacing(8.5)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(expanded ? nil : 4)
            // 粗判超长即给展开入口（SwiftUI 无溢出回调，4 行约 140 字）
            if expanded || body_.count > 140 {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "收起" : "… 展开")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Noir.crimsonHot)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
