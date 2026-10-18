import Foundation

@MainActor
final class MeViewModel: ObservableObject {

    @Published var user: UserInfoResp?
    @Published var isLoading = false
    @Published var error: String?
    // 任务中心卡
    @Published var taskClaimable = 0
    @Published var taskDailyDone = 0
    @Published var taskDailyTotal = 0
    // 头像侧边挂载勋章（至多 5 枚）
    @Published var mountedBadges: [BadgeHallItem] = []
    // 入口角标：票夹=待使用票、我的订单=待付款、优惠券=未使用（失败静默保持旧值）
    @Published var ticketUsable = 0
    @Published var orderUnpaid = 0
    @Published var couponUsable = 0

    /// 对齐安卓 ProfileViewModel.loadProfile：主资料 + 任务摘要 + 挂载勋章（后两者失败静默）
    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                user = try await UserAPI.getUserInfo()
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        Task {
            if let tasks = try? await TaskAPI.taskList() {
                let dailies = tasks.filter { $0.type == "DAILY" }
                taskClaimable = tasks.filter { $0.status == "CLAIMABLE" }.count
                taskDailyDone = dailies.filter { ($0.currentCount ?? 0) >= ($0.threshold ?? Int.max) }.count
                taskDailyTotal = dailies.count
            }
        }
        Task {
            if let hall = try? await BadgeAPI.achievementHall() {
                let badges = hall.badges ?? []
                mountedBadges = (hall.mountedIds ?? []).compactMap { id in badges.first { $0.id == id } }
            }
        }
        loadBadges()
    }

    /// 入口角标数（对齐安卓 ProfileViewModel.loadBadges；失败静默）。
    /// 票夹=前 50 条里待使用（与票夹页同源）；订单=待付款（get-count unpaidCount，
    /// 与订单列表待付款 tab 同源）；优惠券=未使用（status=1 的 total 精确值，pageSize=1 只为拿 total）。
    func loadBadges() {
        Task {
            if let page = try? await ActivityAPI.ticketPage(pageNo: 1, pageSize: 50) {
                ticketUsable = (page.list ?? []).filter { $0.status == 0 }.count
            }
        }
        Task {
            if let counts = try? await OrderAPI.counts() {
                orderUnpaid = Int(counts["unpaidCount"] ?? 0)
            }
        }
        Task {
            if let page = try? await CouponAPI.myPage(status: 1, pageNo: 1, pageSize: 1) {
                couponUsable = Int(page.total ?? 0)
            }
        }
    }

    func update(_ req: UpdateUserReq) {
        Task {
            do {
                _ = try await UserAPI.updateUserInfo(req)
                isLoading = false
                user = try await UserAPI.getUserInfo()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
