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
