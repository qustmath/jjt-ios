import Combine
import Foundation

/// 入座/换桌/离桌成功通知（页面据此刷新平面图等派生数据；对齐安卓 LobbySeatSession.seatChanged）
extension Notification.Name {
    static let jjtLobbySeatChanged = Notification.Name("jjtLobbySeatChanged")
}

/// 坐席会话（对齐安卓 LobbySeatSession 单例）：全 App 唯一的「我的坐席态」来源 + 入座/换桌/离桌动作 + 前台定位心跳。
///
/// **为什么是单例**：一次入座/离桌会同时影响暗夜大厅（坐席胶囊、全城人数）与门店大厅（平面图桌态、
/// 「我的桌」、发言条），扫码入座又发生在第三个页面里——三处读同一份状态才不会各页漂移。
///
/// **心跳口径**：仅「前台 + 大厅页可见 + 已入座」时上报（页面用 .task 挂 heartbeatLoop，随页面消失取消）；
/// 间隔 3 分钟（围栏复检窗口 15min 依赖窗口内有新鲜上报）；被 1-010-009-008（未入座）拒绝说明已被判离
/// → 静默停报 + 刷新坐席态，不弹错误打扰用户。
@MainActor
final class LobbySeatSession: ObservableObject {

    static let shared = LobbySeatSession()

    /// 心跳间隔：票面要求 ≤5min；取 3min 给一轮失败留余量（复检 Job 每 15min 一轮）
    static let heartbeatInterval: TimeInterval = 3 * 60

    /// 无定位/无权限时的入座提示（入座需核验是否在门店 3km 内）
    static let locationRequiredHint = "入座需要定位权限：请在设置里允许「荆棘兔」使用定位"

    private static let stateSeated = "seated"
    /// 未入座错误码（后端 LOBBY_SEAT_NOT_SEATED）：心跳据此静默停报
    private static let codeNotSeated = 1_010_009_008

    @Published private(set) var seat: LobbySeatState?

    var isSeated: Bool { seat?.state == Self.stateSeated }

    /// 最近一次成功上报的时刻（系统单调钟：改系统时间不会把守卫卡住）
    private var lastReportAt: TimeInterval = 0

    private init() {}

    // MARK: - 读

    /// 拉取我的坐席态；失败保持上一次（坐席态属富化展示，静默）
    func refresh() async {
        guard let state = try? await LobbyAPI.mySeat() else { return }
        seat = state
    }

    // MARK: - 写

    /// 扫码入座：取一次 GPS 后交服务端三门槛判定。
    /// 定位不可用（无权限/定位失败）直接抛错交调用方提示——不提交必被拒的请求。
    func checkIn(token: String, tableId: Int64) async throws {
        guard LobbyLocator.hasPermission() else {
            throw APIError.business(code: -1, message: Self.locationRequiredHint)
        }
        guard let fix = await LobbyLocator.shared.currentFix() else {
            throw APIError.business(code: -1, message: "定位失败：请在开阔处重试（入座需核验是否在门店 3 公里内）")
        }
        let state = try await LobbyAPI.checkIn(
            token: token, tableId: tableId,
            latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        apply(state)
    }

    /// 主动离桌（回罚站）：成功后重拉坐席态（服务端会写 leave_reason 等）
    func leave() async throws {
        try await LobbyAPI.leaveSeat()
        await refresh()
        NotificationCenter.default.post(name: .jjtLobbySeatChanged, object: nil)
    }

    /// 换桌（同店原子换；跨店由服务端拒绝并提示重新扫码）
    func switchTo(tableId: Int64) async throws {
        let state = try await LobbyAPI.switchTable(tableId: tableId)
        apply(state)
    }

    // MARK: - 心跳

    /// 心跳循环：页面用 `.task { await LobbySeatSession.shared.heartbeatLoop() }` 挂载，
    /// 随页面消失自动取消（仅前台 + 页面可见 + 已入座时实际发请求）。
    func heartbeatLoop() async {
        while !Task.isCancelled {
            await heartbeatTick()
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))
            } catch {
                break // 页面取消
            }
        }
    }

    /// 心跳一拍：未入座直接返回；距上次成功上报不足一轮也跳过；定位失败静默跳过，下一周期再试。
    func heartbeatTick() async {
        guard isSeated else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if lastReportAt != 0, now - lastReportAt < Self.heartbeatInterval { return }
        guard let fix = await LobbyLocator.shared.currentFix() else { return }
        do {
            try await LobbyAPI.reportLocation(
                latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
            lastReportAt = now
        } catch APIError.business(let code, _) where code == Self.codeNotSeated {
            // 已被判离/强制离桌：静默停报 + 刷新坐席态（不弹错）
            await refresh()
        } catch {
            // 静默
        }
    }

    /// 登出：清本地坐席态与上报时刻（服务端坐席行保留，重新登录时由 refresh 拉回）
    func reset() {
        seat = nil
        lastReportAt = 0
    }

    private func apply(_ state: LobbySeatState) {
        seat = state
        NotificationCenter.default.post(name: .jjtLobbySeatChanged, object: nil)
    }
}
