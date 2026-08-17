import Foundation

@MainActor
final class UserProfileViewModel: ObservableObject {

    @Published var profile: UserProfileInfo?
    @Published var posts: [PostInfo] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var error: String?
    // 本人：成就殿堂点亮进度
    @Published var hallLit = 0
    @Published var hallTotal = 0

    private var page = 1
    private var userId: Int64 = 0

    var isSelf: Bool {
        profile?.isSelf == true || profile?.id == TokenManager.shared.userId
    }

    /// 并行加载资料 + 帖子首页（对齐安卓 UserProfileViewModel.load）
    func load(userId: Int64) {
        self.userId = userId
        page = 1
        hasMore = true
        isLoading = true
        Task {
            do {
                let p = try await UserAPI.getProfile(userId: userId)
                profile = p
                if p.isSelf == true { loadSelfExtras() }
            } catch {
                self.error = error.localizedDescription
            }
        }
        Task {
            defer { isLoading = false }
            do {
                let result = try await SocialAPI.userPostList(userId: userId, pageNo: 1)
                let list = result.list ?? []
                posts = list
                hasMore = list.count >= 20
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 本人：成就殿堂点亮数（失败静默）
    private func loadSelfExtras() {
        Task {
            if let hall = try? await BadgeAPI.achievementHall() {
                hallLit = hall.litStages ?? 0
                hallTotal = hall.totalStages ?? 0
            }
        }
    }

    func loadMore() {
        guard !isLoadingMore, hasMore, !isLoading else { return }
        isLoadingMore = true
        let nextPage = page + 1
        Task {
            defer { isLoadingMore = false }
            do {
                let result = try await SocialAPI.userPostList(userId: userId, pageNo: nextPage)
                let list = result.list ?? []
                posts += list
                page = nextPage
                hasMore = list.count >= 20
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 关注/取关（对齐安卓：本地同步粉丝数）
    func toggleFollow() {
        guard let p = profile else { return }
        let wasFollowing = p.isFollowing == true
        Task {
            do {
                if wasFollowing {
                    _ = try await FollowAPI.unfollow(userId: p.id)
                } else {
                    _ = try await FollowAPI.follow(userId: p.id)
                }
                profile?.isFollowing = !wasFollowing
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 删除自己的帖子，成功后从列表移除
    func deletePost(_ postId: Int64) {
        Task {
            do {
                _ = try await SocialAPI.deletePost(id: postId)
                posts.removeAll { $0.id == postId }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 本人资料更新（头像/封面/昵称/签名），成功后刷新
    func updateSelf(_ req: UpdateUserReq) {
        Task {
            do {
                _ = try await UserAPI.updateUserInfo(req)
                profile = try await UserAPI.getProfile(userId: userId)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
