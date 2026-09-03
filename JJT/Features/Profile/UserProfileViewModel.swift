import Foundation

/// 礼物全览弹层条目（收到的/送出的，按 礼物+对方 聚合，对齐安卓 GiftSheetItem）
struct ProfileGiftItem: Identifiable {
    let giftId: Int64
    let name: String
    let icon: String?
    let animationUrl: String?
    let count: Int
    /// 收到的：送礼人；送出的：接收人
    let counterparty: String?
    let iconScale: Int?

    var id: String { "\(giftId)_\(counterparty ?? "")" }
}

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
    // 本人：收到的/送出的礼物聚合（入口卡 + 全览弹层）
    @Published var recvGifts: [ProfileGiftItem] = []
    @Published var sentGifts: [ProfileGiftItem] = []
    // 勋章墙（本人/他人均加载；user-wall 对本人同样可用，仅返回已获得）
    @Published var badges: [BadgeItem] = []
    // 头像框选项与保存态（本人点头像更换，对齐安卓 frameOptions/frameSaving）
    @Published var frameOptions: AvatarFrameOptions?
    @Published var frameSaving = false

    private var page = 1
    private var userId: Int64 = 0

    var isSelf: Bool {
        profile?.isSelf == true || profile?.id == TokenManager.shared.userId
    }

    /// 并行加载资料 + 帖子首页 + 勋章墙（对齐安卓 UserProfileViewModel.load）
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
        Task {
            // 勋章墙失败静默
            badges = (try? await BadgeAPI.userBadgeWall(userId: userId)) ?? []
        }
    }

    /// 本人：入口卡数据（收到/送出礼物聚合 + 成就殿堂点亮数；失败静默，对齐安卓 loadSelfExtras）
    private func loadSelfExtras() {
        Task {
            if let hall = try? await BadgeAPI.achievementHall() {
                hallLit = hall.litStages ?? 0
                hallTotal = hall.totalStages ?? 0
            }
        }
        Task {
            // 按 礼物+对方 聚合，数量求和（对齐安卓 groupBy giftId to counterpartyName）
            func aggregate(_ orders: [GiftOrderVO]) -> [ProfileGiftItem] {
                let groups = Dictionary(grouping: orders) { o in
                    "\(o.giftId)_\(o.counterpartyName ?? "")"
                }
                return groups.values.map { orders in
                    let first = orders.first
                    return ProfileGiftItem(
                        giftId: first?.giftId ?? 0,
                        name: first?.giftName ?? "礼物",
                        icon: first?.giftIcon,
                        animationUrl: first?.animationUrl,
                        count: orders.reduce(0) { $0 + ($1.quantity ?? 1) },
                        counterparty: first?.counterpartyName.flatMap { $0.isEmpty ? nil : $0 },
                        iconScale: first?.iconScale
                    )
                }
                .sorted { $0.count > $1.count }
            }
            let recv = (try? await GiftAPI.receivedList()) ?? []
            let sent = (try? await GiftAPI.sentList()) ?? []
            recvGifts = aggregate(recv)
            sentGifts = aggregate(sent)
        }
    }

    /// 加载头像框选项（默认框 + 持有 + 段位专属含解锁态；失败静默）
    func loadFrameOptions() {
        Task {
            frameOptions = try? await AvatarFrameAPI.options()
        }
    }

    /// 更换头像框（url 空串 = 摘下），成功后刷新资料与选项（对齐安卓 selectFrame）
    func selectFrame(url: String) {
        frameSaving = true
        Task {
            defer { frameSaving = false }
            _ = try? await UserAPI.updateUserInfo(UpdateUserReq(avatarFrame: url))
            jjtShowToast(url.isEmpty ? "已摘下头像框" : "已更换头像框")
            profile = try? await UserAPI.getProfile(userId: userId)
            frameOptions = try? await AvatarFrameAPI.options()
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
