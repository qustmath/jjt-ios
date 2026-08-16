import Foundation

/// 帖子详情状态（对齐安卓 PostDetailViewModel；付费解锁/编辑/分享后续迁移）
@MainActor
final class PostDetailViewModel: ObservableObject {

    @Published var post: PostInfo?
    @Published var comments: [CommentInfo] = []
    @Published var isLoading = false
    @Published var isFollowed = false
    @Published var errorMessage: String?

    let postId: Int64

    init(postId: Int64) {
        self.postId = postId
    }

    func load() {
        isLoading = true
        Task {
            do {
                let p = try await SocialAPI.postDetail(id: postId)
                post = p
                isLoading = false
                async let c: () = loadComments()
                async let f: () = checkFollow(authorId: p.userId)
                _ = await (c, f)
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadComments() async {
        if let list = try? await SocialAPI.comments(postId: postId) { comments = list }
    }

    private func checkFollow(authorId: Int64?) async {
        guard let authorId, authorId != TokenManager.shared.userId else { return }
        if let r = try? await FollowAPI.check(userId: authorId) { isFollowed = r }
    }

    /// 关注/取关（对齐安卓 toggleFollow）
    func toggleFollow() {
        guard let uid = post?.userId, uid != TokenManager.shared.userId else { return }
        Task {
            let ok = isFollowed
                ? try? await FollowAPI.unfollow(userId: uid)
                : try? await FollowAPI.follow(userId: uid)
            if ok != nil { isFollowed.toggle() }
        }
    }

    /// 点赞（乐观更新，失败回滚）
    func toggleLike() {
        guard var p = post else { return }
        let old = p
        p = p.updating(liked: !(p.liked ?? false), likeDelta: (p.liked ?? false) ? -1 : 1)
        post = p
        Task {
            if (try? await SocialAPI.like(postId: postId)) == nil { post = old }
        }
    }

    func toggleFavorite() {
        guard var p = post else { return }
        let old = p
        p = p.updating(favorited: !(p.favorited ?? false), favoriteDelta: (p.favorited ?? false) ? -1 : 1)
        post = p
        Task {
            if (try? await SocialAPI.favorite(postId: postId)) == nil { post = old }
        }
    }

    /// 发评论/回复，成功后重拉列表
    func addComment(content: String, parentId: Int64?) async -> Bool {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return false }
        do {
            _ = try await SocialAPI.addComment(postId: postId, parentId: parentId, content: c)
            await loadComments()
            if var p = post {
                p = p.updating(commentDelta: 1)
                post = p
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// 局部更新辅助（PostInfo 是值类型且字段 let，复制改值）
private extension PostInfo {
    func updating(liked: Bool? = nil, likeDelta: Int = 0,
                  favorited: Bool? = nil, favoriteDelta: Int = 0,
                  commentDelta: Int = 0) -> PostInfo {
        PostInfo(
            id: id, userId: userId, nickname: nickname, avatar: avatar,
            vipLevel: vipLevel, vipLevelColor: vipLevelColor, levelInTier: levelInTier,
            avatarFrame: avatarFrame, avatarFrameScale: avatarFrameScale,
            mediaType: mediaType, title: title, content: content,
            images: images, video: video, videoCover: videoCover,
            topics: topics, location: location, cityName: cityName,
            likeCount: (likeCount ?? 0) + likeDelta,
            commentCount: (commentCount ?? 0) + commentDelta,
            favoriteCount: (favoriteCount ?? 0) + favoriteDelta,
            viewCount: viewCount,
            liked: liked ?? self.liked,
            favorited: favorited ?? self.favorited,
            unlocked: unlocked, paidPrice: paidPrice, auditStatus: auditStatus,
            createTime: createTime
        )
    }
}
