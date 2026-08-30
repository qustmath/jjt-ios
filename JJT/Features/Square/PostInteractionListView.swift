import SwiftUI

/// 我的收藏 / 我的点赞 帖子列表（对齐安卓 PostInteractionListScreen：两个路由复用同一实现）
/// 双列网格卡片，点击进帖子详情（视频帖进竖滑视频流）
struct PostInteractionListView: View {

    enum Kind {
        case favorite, like

        var title: String { self == .favorite ? "我的收藏" : "我的点赞" }
    }

    let kind: Kind
    @StateObject private var vm = PostInteractionListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var detailPostId: Int64?
    @State private var videoFeedPostId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
        }
        .onAppear { vm.load(kind: kind, page: 1, isRefresh: true) }
        .fullScreenCover(isPresented: Binding(
            get: { detailPostId != nil },
            set: { if !$0 { detailPostId = nil } }
        )) {
            if let id = detailPostId { PostDetailView(postId: id) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoFeedPostId != nil },
            set: { if !$0 { videoFeedPostId = nil } }
        )) {
            if let id = videoFeedPostId { VideoFeedView(initialPostId: id, tab: "recommend") }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                        .frame(width: 32, height: 32)
                }
                Text(kind.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Noir.goldText)
                Spacer()
                Text("\(vm.total)")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.textDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1).opacity(0.4)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.posts.isEmpty, vm.isLoading {
            ProgressView().tint(Noir.crimson).scaleEffect(1.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.posts.isEmpty {
            VStack(spacing: 10) {
                Text(kind == .favorite ? "NO FAVORITES YET" : "NO LIKES YET")
                    .font(.system(size: 10, design: .serif).italic())
                    .tracking(2)
                    .foregroundStyle(Noir.gold.opacity(0.6))
                Text(kind == .favorite ? "还没有收藏任何帖子" : "还没有点赞任何帖子")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(vm.posts) { post in
                        card(post)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                if vm.isLoadingMore {
                    ProgressView().tint(Noir.crimson).frame(maxWidth: .infinity).padding(16)
                } else if !vm.hasMore {
                    Text("NO MORE · 到底啦")
                        .font(.system(size: 10, design: .serif).italic())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    Color.clear.frame(height: 1)
                        .onAppear { vm.load(kind: kind, page: vm.page + 1, isRefresh: false) }
                }
            }
            .refreshable { vm.load(kind: kind, page: 1, isRefresh: true) }
        }
    }

    private func card(_ post: PostInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let url = post.mediaType == "video" ? webImageURL(post.videoCover) : webImageURL(post.images?.first) {
                    WebImage(url: url) { Noir.noir3 }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                } else {
                    Noir.noir3
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .overlay(
                            Text(post.content ?? "")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(5)
                                .padding(10),
                            alignment: .topLeading
                        )
                }
                if post.mediaType == "video" {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("视频").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                }
            }
            .frame(height: 150)
            .clipped()

            if !post.displayTitle.isEmpty {
                Text(post.displayTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
            }

            HStack(spacing: 4) {
                AppAvatar(url: post.avatar, size: 20,
                          frameURL: post.avatarFrame, frameScale: CGFloat(post.avatarFrameScale ?? 1.25))
                    .frame(width: 24, height: 24)
                Text(post.nickname ?? "用户\(post.userId ?? 0)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "heart.fill").font(.system(size: 8))
                Text("\(post.likeCount ?? 0)").font(.system(size: 9))
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if post.mediaType == "video" { videoFeedPostId = post.id } else { detailPostId = post.id }
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class PostInteractionListViewModel: ObservableObject {
    @Published var posts: [PostInfo] = []
    @Published var total: Int64 = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    var page = 1

    func load(kind: PostInteractionListView.Kind, page: Int, isRefresh: Bool) {
        if isRefresh { isLoading = posts.isEmpty } else {
            guard !isLoading, !isLoadingMore, hasMore, !posts.isEmpty else { return }
            isLoadingMore = true
        }
        Task {
            let resp = try? await (kind == .favorite
                ? SocialAPI.favoritePage(pageNo: page)
                : SocialAPI.likePage(pageNo: page))
            isLoading = false
            isLoadingMore = false
            guard let resp else { return }
            let list = resp.list ?? []
            if isRefresh {
                posts = list
            } else {
                var seen = Set(posts.map(\.id))
                posts += list.filter { seen.insert($0.id).inserted }
            }
            total = resp.total ?? Int64(posts.count)
            hasMore = list.count >= 20
            self.page = page
        }
    }
}
