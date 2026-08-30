import SwiftUI
import AVKit

/// 竖滑视频流（对齐安卓 VideoFeedScreen：抖音式上下滑切换视频帖）。
/// 入口：广场点视频卡。每页独立详情 VM（点赞/评论/关注互不影响）；
/// 基于 scrollTargetBehavior(.paging)（iOS 17+），当前页自动播放、离开暂停。
struct VideoFeedView: View {

    let initialPostId: Int64
    let tab: String

    @StateObject private var vm = VideoFeedViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var scrollID: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(Noir.crimson).scaleEffect(1.3)
                backButton
            } else if vm.ids.isEmpty {
                Text("暂时没有视频帖")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                backButton
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.ids.indices, id: \.self) { i in
                            VideoPostPageView(
                                postId: vm.ids[i],
                                active: (scrollID ?? vm.initialIndex) == i,
                                onBack: { dismiss() }
                            )
                            .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenHeight)
                            .id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $scrollID)
                .ignoresSafeArea()
                .onAppear { scrollID = vm.initialIndex }
                .onChange(of: scrollID) { _, new in
                    // 划到距末尾 3 条以内 → 预取下一页
                    if let new, new >= vm.ids.count - 3 { vm.loadMore(tab: tab) }
                }
            }
        }
        .onAppear { vm.start(initialPostId: initialPostId, tab: tab) }
    }

    private var backButton: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.35))
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                }
                .padding(.leading, 14)
                .padding(.top, 14)
                Spacer()
            }
            Spacer()
        }
    }
}

/// 视频流数据（对齐安卓 VideoFeedViewModel：拉视频帖 id 序列，定位到被点帖子）
@MainActor
final class VideoFeedViewModel: ObservableObject {
    @Published var ids: [Int64] = []
    @Published var initialIndex = 0
    @Published var isLoading = false

    private var page = 0
    private var hasMore = true
    private var started = false
    private var isLoadingMore = false

    func start(initialPostId: Int64, tab: String) {
        guard !started else { return }
        started = true
        isLoading = true
        Task {
            defer { isLoading = false }
            let resp = try? await SocialAPI.postList(pageNo: 1, tab: tab, mediaType: "video")
            var list = (resp?.list ?? []).map(\.id)
            var seen = Set<Int64>()
            list = list.filter { seen.insert($0).inserted }
            var idx = list.firstIndex(of: initialPostId)
            if idx == nil { list.insert(initialPostId, at: 0); idx = 0 }
            ids = list
            initialIndex = idx ?? 0
            page = 1
            hasMore = (resp?.list?.count ?? 0) >= 20
        }
    }

    func loadMore(tab: String) {
        guard started, !isLoading, !isLoadingMore, hasMore, !ids.isEmpty else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            let next = page + 1
            guard let resp = try? await SocialAPI.postList(pageNo: next, tab: tab, mediaType: "video") else { return }
            let new = (resp.list ?? []).map(\.id).filter { !ids.contains($0) }
            ids += new
            page = next
            hasMore = (resp.list?.count ?? 0) >= 20 && !new.isEmpty
        }
    }
}

/// 竖滑流单页：全屏沉浸视频 + 右侧操作栏 + 底部信息（对齐安卓 VideoPostPage/VideoPostImmersive）
private struct VideoPostPageView: View {
    let postId: Int64
    let active: Bool
    let onBack: () -> Void

    @StateObject private var vm: PostDetailViewModel
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var showComments = false
    @State private var commentText = ""
    @State private var previewEnded = false
    @State private var toast: String?

    init(postId: Int64, active: Bool, onBack: @escaping () -> Void) {
        self.postId = postId
        self.active = active
        self.onBack = onBack
        _vm = StateObject(wrappedValue: PostDetailViewModel(postId: postId))
    }

    var body: some View {
        ZStack {
            Color.black

            if let post = vm.post {
                if post.isPaidLocked && (post.previewSeconds ?? 0) <= 0 {
                    lockedPage(post)
                } else {
                    immersive(post)
                }
            } else {
                ProgressView().tint(Noir.crimson)
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
                }
            }
        }
        .onAppear { vm.load() }
        .onChange(of: vm.post?.id) { _, _ in
            if let p = vm.post { setupPlayer(for: p) }
        }
        .onChange(of: active) { _, now in
            if now { player?.play() } else { player?.pause() }
        }
        // 退出/滑出页面必须停播并释放，否则声音还在后台放
        .onDisappear {
            player?.pause()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = nil
            player = nil
        }
        .sheet(isPresented: $showComments) { commentsSheet }
    }

    // MARK: - 沉浸视频页

    @ViewBuilder
    private func immersive(_ post: PostInfo) -> some View {
        // 全屏视频
        if let player {
            VideoPlayer(player: player)
                .ignoresSafeArea()
        }

        // 顶部压暗 + 返回
        VStack {
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 96)
            Spacer()
        }
        .allowsHitTesting(false)
        VStack {
            HStack {
                Button(action: onBack) {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.35))
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                }
                .padding(.leading, 14)
                .padding(.top, 14)
                Spacer()
            }
            Spacer()
        }

        // 试看徽标
        if post.isPaidLocked, (post.previewSeconds ?? 0) > 0, !previewEnded {
            VStack {
                HStack {
                    Spacer()
                    Text("试看 \(post.previewSeconds ?? 0) 秒")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing)))
                        .padding(.trailing, 14)
                        .padding(.top, 14)
                }
                Spacer()
            }
        }

        // 试看结束遮罩
        if previewEnded {
            VStack(spacing: 12) {
                Text("试看结束")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text("完整视频 \(post.paidPrice ?? 0) 兔币解锁 · 永久可看")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Button { showToast("付费解锁即将上线") } label: {
                    Text("立即解锁")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.75))
        }

        // 底部压暗渐变
        VStack {
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
        }
        .allowsHitTesting(false)

        // 右侧操作栏
        VStack(spacing: 20) {
            Spacer()
            immersiveAction(icon: post.liked == true ? "heart.fill" : "heart",
                            count: post.likeCount ?? 0,
                            tint: post.liked == true ? Noir.crimsonHot : .white,
                            label: "点赞") { vm.toggleLike() }
            immersiveAction(icon: "bubble.right",
                            count: post.commentCount ?? 0,
                            tint: .white,
                            label: "评论") { showComments = true }
            immersiveAction(icon: post.favorited == true ? "star.fill" : "star",
                            count: post.favoriteCount ?? 0,
                            tint: post.favorited == true ? Noir.gold : .white,
                            label: "收藏") { vm.toggleFavorite() }
            if post.userId != TokenManager.shared.userId {
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "gift.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)
                    Text("送礼")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .onTapGesture { showToast("礼物敬请期待") }
            }
        }
        .padding(.trailing, 12)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, alignment: .trailing)

        // 底部信息
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(spacing: 10) {
                AppAvatar(url: post.avatar, size: 38,
                          frameURL: post.avatarFrame, frameScale: CGFloat(post.avatarFrameScale ?? 1.2))
                Text(post.nickname ?? "TA")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                if post.userId != TokenManager.shared.userId {
                    Button { vm.toggleFollow() } label: {
                        Text(vm.isFollowed ? "已关注" : "+ 关注")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(vm.isFollowed ? .white.opacity(0.6) : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(vm.isFollowed ? Color.white.opacity(0.12) : Noir.crimson))
                    }
                }
            }
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
            if let content = post.content, !content.isEmpty, content != post.title {
                Text(content.replacingOccurrences(of: (post.title ?? "") + "\n", with: ""))
                    .font(.system(size: 13))
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .padding(.top, 6)
            }
            HStack(spacing: 0) {
                if let loc = post.location, !loc.isEmpty {
                    Image(systemName: "mappin").font(.system(size: 10))
                    Text(" \(loc) · ")
                }
                Text(post.createTime.map(PostDetailView.formatTime) ?? "")
                Text("  ")
                Image(systemName: "eye").font(.system(size: 10))
                Text(" \(PostDetailView.formatCount(post.viewCount ?? 0))")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.top, 8)
            // 评论入口胶囊
            HStack(spacing: 6) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 12))
                Text("说点什么…")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .padding(.top, 10)
            .onTapGesture { showComments = true }
        }
        .padding(.leading, 16)
        .padding(.trailing, 84)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - 付费锁定页（无试看）

    private func lockedPage(_ post: PostInfo) -> some View {
        ZStack {
            AsyncImage(url: webImageURL(post.videoCover)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Color.black }
            }
            .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenHeight)
            .clipped()
            .blur(radius: 16)

            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Noir.goldPale)
                Text("完整视频 \(post.paidPrice ?? 0) 兔币解锁 · 永久可看")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button { showToast("付费解锁即将上线") } label: {
                    Text("立即解锁")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .padding(.bottom, 120)
            }

            VStack {
                HStack {
                    Button(action: onBack) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.35))
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 14)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    // MARK: - 评论面板

    private var commentsSheet: some View {
        NavigationStack {
            ZStack {
                Noir.noir.ignoresSafeArea()
                VStack(spacing: 0) {
                    List {
                        ForEach(vm.comments) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(c.nickname ?? "用户\(c.userId ?? 0)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.4))
                                    Spacer()
                                    Text(c.createTime.map(PostDetailView.formatTime) ?? "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Noir.textFaint)
                                }
                                Text(c.content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .listRowBackground(Color.clear)
                        }
                        if vm.comments.isEmpty {
                            Text("还没有私语，来第一句吧")
                                .font(.system(size: 12))
                                .foregroundStyle(Noir.textFaint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)

                    HStack(spacing: 8) {
                        TextField("说点暗语…", text: $commentText)
                            .font(.system(size: 13))
                            .foregroundStyle(Noir.ivory)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                            .submitLabel(.send)
                            .onSubmit { send() }
                        Button(action: send) {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(Noir.crimsonHot)
                        }
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("私语")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func send() {
        let text = commentText
        Task {
            if await vm.addComment(content: text, parentId: nil) {
                commentText = ""
            }
        }
    }

    private func immersiveAction(icon: String, count: Int, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(tint)
                Text(PostDetailView.formatCount(count))
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: - 播放器

    private func setupPlayer(for post: PostInfo) {
        guard player == nil, let url = webImageURL(post.video) else { return }
        let p = AVPlayer(url: url)
        player = p
        // 循环播放
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            p.seek(to: .zero)
            p.play()
        }
        // 试看上限
        if post.isPaidLocked, let sec = post.previewSeconds, sec > 0 {
            p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { t in
                if t.seconds >= Double(sec) {
                    p.pause()
                    previewEnded = true
                }
            }
        }
        if active { p.play() }
    }
}
