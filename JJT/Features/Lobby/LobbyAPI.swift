import Foundation

/// 门店大厅（聊天室）数据层（对齐安卓 ui/lobby/LobbyApi + LobbySeatApi + LobbyHostApi + LobbyShareApi
/// + LobbyDndApi + LobbyInviteApi + LobbyChatApi）。字段名与后端 VO 逐字一致。
/// 语音房（小房间）相关接口本期不接入——Android 端该功能未收口。

// ===================== 只读查询 =====================

/// 门店卡片（LobbyStoreCardRespVO）
struct LobbyStoreCard: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let area: String?
    let cover: String?
    let businessHours: String?
    let seatedCount: Int?
    let avchatroomId: String?
    let latestMessage: String?
}

/// 楼层平面图（LobbyFloorPlanRespVO）
struct LobbyFloorPlan: Decodable, Identifiable {
    let id: Int64
    let floorKey: String?
    let label: String?
    let image: String?
    let stageX: Double?
    let stageY: Double?
    let sort: Int?
    let tables: [LobbyTable]?
}

/// 桌位（LobbyFloorPlanRespVO.Table）
struct LobbyTable: Decodable, Identifiable, Equatable {
    let id: Int64
    let tableNo: String?
    let posX: Double?
    let posY: Double?
    let capacity: Int?
    let status: String?
    let note: String?
    let currentCount: Int?
    let hostUserId: Int64?
    let groupEventId: Int64?
    let reserveText: String?
}

/// 拼桌缺口（LobbyShareGapRespVO）
struct LobbyShareGap: Decodable, Identifiable {
    let tableId: Int64
    let floorPlanId: Int64?
    let tableNo: String?
    let gap: Int?
    let capacity: Int?
    let currentCount: Int?
    let note: String?
    let justShouted: Bool?

    var id: Int64 { tableId }
}

/// 门店视频（AppLobbyVideoController.VideoRespVO）
struct LobbyVideo: Decodable, Identifiable {
    let id: Int64
    let title: String?
    let video: String?
    let videoCover: String?
    let durationSec: Int?
    /// 上架时间：epoch 毫秒
    let publishTime: Int64?
}

/// 热力榜（LobbyHeatBoardRespVO）
struct LobbyHeatBoard: Decodable {
    let type: String?
    let list: [LobbyHeatItem]?
    let myRank: LobbyHeatMyRank?
}

struct LobbyHeatItem: Decodable, Identifiable {
    let rank: Int?
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    let score: Int64?

    var id: Int64 { userId ?? Int64(rank ?? 0) }
}

struct LobbyHeatMyRank: Decodable {
    let ranked: Bool?
    let rank: Int?
    let score: Int64?
}

/// 围观桌况（LobbyTableSpectateRespVO）
struct LobbyTableSpectate: Decodable {
    let tableId: Int64
    let floorPlanId: Int64?
    let tableNo: String?
    let status: String?
    let capacity: Int?
    let currentCount: Int?
    let hostUserId: Int64?
    let note: String?
    let members: [LobbySpectateMember]?
}

struct LobbySpectateMember: Decodable, Identifiable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let host: Bool?

    var id: Int64 { userId }
}

// ===================== 小房间（语音房）列表与详情 =====================

/// 小房间摘要（LobbyVoiceRoomRespVO）
struct LobbyVoiceRoom: Decodable, Identifiable {
    let id: Int64
    let title: String?
    let tags: String?
    let mode: String?
    let ownerUserId: Int64?
    let ownerNickname: String?
    let micOccupied: Int?
    let micTotal: Int?
    /// 建房时间：epoch 毫秒
    let createTime: Int64?
}

/// 小房间详情（LobbyVoiceRoomDetailRespVO）
struct LobbyVoiceRoomDetail: Decodable {
    let id: Int64
    let storeId: Int64?
    let title: String?
    let tags: String?
    let mode: String?
    let ownerUserId: Int64?
    let ownerNickname: String?
    let mics: [LobbyMicItem]?
    let mySeatNo: Int?
    let inRoom: Bool?
    /// 腾讯 IM 群 ID（App SDK 进群用）：仅在房用户返回
    let imGroupIdStr: String?
    let complianceText: String?
}

/// 麦位项（LobbyMicItemRespVO）
struct LobbyMicItem: Decodable, Identifiable {
    let seatNo: Int?
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    let role: String?
    let muted: Bool?

    var id: Int64 { Int64(seatNo ?? 0) }
}

// ===================== 坐席 =====================

/// 入座请求：token 来自平板入座码，坐标来自客户端 GPS
struct LobbyCheckInReq: Encodable {
    let token: String
    let tableId: Int64
    let latitude: Double
    let longitude: Double
}

/// 定位心跳请求
struct LobbyLocationReq: Encodable {
    let latitude: Double
    let longitude: Double
}

/// 我的坐席状态（seated 在坐 / stand 罚站 / null 未入座）
struct LobbySeatState: Decodable {
    let state: String?
    let storeId: Int64?
    let tableId: Int64?
    let tableNo: String?
    let hostUserId: Int64?
    /// 入座时间：epoch 毫秒
    let checkInTime: Int64?
    let leaveReason: String?
}

// ===================== 桌主动作 =====================

struct LobbyHostInviteReq: Encodable {
    let tableId: Int64
    let inviteeId: Int64
}

/// 喊人文案：note ≤50 字，随公屏播报出现在本店滚动条
struct LobbyHostShoutReq: Encodable {
    let tableId: Int64
    let note: String?
}

/// 勿扰设置：note ≤50 字；silent=true 为完全静音档（不可付费解锁）
struct LobbyHostDndReq: Encodable {
    let tableId: Int64
    let note: String?
    let silent: Bool
}

struct LobbyHostTransferReq: Encodable {
    let tableId: Int64
    let targetUserId: Int64
}

struct LobbyHostRemoveReq: Encodable {
    let tableId: Int64
    let targetUserId: Int64
}

// ===================== 拼桌 =====================

/// 拼桌申请请求：坐标为申请瞬间 GPS，作为 3km 围栏证据
struct LobbyShareApplyReq: Encodable {
    let tableId: Int64
    let longitude: Double
    let latitude: Double
}

/// 拼桌申请：status=pending/approved/rejected；expired=pending 且超审批窗口
struct LobbyShareApply: Decodable, Identifiable {
    let id: Int64
    let storeId: Int64?
    let tableId: Int64?
    let tableNo: String?
    let userId: Int64?
    let userNickname: String?
    let userAvatar: String?
    let status: String?
    let expired: Bool?
    let createTime: Int64?
}

// ===================== 勿扰付费解锁 =====================

/// 解锁下单：level 见 LobbyDndUnlockLevel，金额由服务端定，客户端不传
struct LobbyDndUnlockCreateReq: Encodable {
    let tableId: Int64
    let level: String
    let payPassword: String
}

/// 解锁订单：时间字段均为 epoch 毫秒
struct LobbyDndUnlockOrder: Decodable, Identifiable {
    let id: Int64
    let tableId: Int64?
    let tableNo: String?
    let userId: Int64?
    let userNickname: String?
    let userAvatar: String?
    let unlockLevel: String?
    /// 来源：order=付费订单 / gift=送礼解锁确认单（钱随礼物已结算，展示与接受口径不同）
    let source: String?
    let amount: Int64?
    let status: String?
    /// 该单已发且未核销的通行证（accepted 单才有意义）
    let passHeld: Bool?
    let expireTime: Int64?
    let refundTime: Int64?
    let createTime: Int64?

    var isGift: Bool { source == "gift" }
    var holdsPass: Bool { passHeld == true }
}

// ===================== 桌位邀请（受邀端） =====================

/// 桌位邀请：expireTime 核销截止（毫秒），服务端 my-invites 已滤过期
struct LobbyTableInvite: Decodable, Identifiable {
    let id: Int64
    let storeId: Int64
    let storeName: String?
    let tableId: Int64
    let tableNo: String?
    let inviterId: Int64
    let inviterNickname: String?
    let inviterAvatar: String?
    let expireTime: Int64?
    let createTime: Int64?
}

struct LobbyInviteAcceptReq: Encodable {
    let inviteId: Int64
    let longitude: Double
    let latitude: Double
}

// ===================== 公屏非 IM 侧 =====================

struct LobbyReportReq: Encodable {
    let msgId: String
    let reason: String
    let detail: String?
}

/// 举报原因（与后端 ReportReasonEnum 的 code 逐字一致）
enum LobbyReportReason: String, CaseIterable {
    case porn, harassment, ad, illegal, other

    var label: String {
        switch self {
        case .porn: return "色情低俗"
        case .harassment: return "骚扰辱骂"
        case .ad: return "广告营销"
        case .illegal: return "违法犯罪"
        case .other: return "其他"
        }
    }
}

// ===================== 枚举口径 =====================

/// 六态桌位（与安卓 TableStatus 对齐：颜色/发光/动画样式在 LobbyParts 里渲染）
enum LobbyTableStatus: String, CaseIterable {
    case occupied
    case reserved
    case free
    case grouping
    case sharing
    case dnd

    var label: String {
        switch self {
        case .occupied: return "有人"
        case .reserved: return "预定"
        case .free: return "空闲"
        case .grouping: return "组局"
        case .sharing: return "拼桌"
        case .dnd: return "勿扰"
        }
    }

    /// 未知/空态按「空闲」渲染（后端新增枚举时不崩）
    static func of(_ wire: String?) -> LobbyTableStatus {
        LobbyTableStatus(rawValue: wire ?? "") ?? .free
    }
}

/// 订单档档位（同价 300 兔币，仅展示与分析标签不同）
enum LobbyDndUnlockLevel: String, CaseIterable {
    case toastAll = "toast_all"
    case passTicket = "pass_ticket"

    var label: String {
        switch self {
        case .toastAll: return "敬全场"
        case .passTicket: return "通行券"
        }
    }

    var desc: String {
        switch self {
        case .toastAll: return "请全场喝一杯，桌主接受即解锁"
        case .passTicket: return "买一张通行券，桌主接受即解锁"
        }
    }
}

/// 订单状态文案（未知状态原样透出）；送礼确认单走 dndGiftOrderStatusLabel
func lobbyDndOrderStatusLabel(_ status: String?) -> String {
    switch status {
    case "pending": return "待桌主响应"
    case "accepted": return "已接受 · 通行证已发放"
    case "rejected": return "桌主已拒绝 · 已原路退款"
    case "timeout_refund": return "桌主未响应 · 已原路退款"
    case "refunded": return "已取消勿扰 · 已原路退款"
    case "expired": return "已过期失效"
    default: return status ?? "未知"
    }
}

/// 送礼确认单状态文案：礼物照收（钱随礼物结算给桌主），流转的只是解锁与否
func lobbyDndGiftOrderStatusLabel(_ status: String?) -> String {
    switch status {
    case "pending": return "送礼解锁 · 待桌主确认"
    case "accepted": return "桌主已确认 · 通行证已发放"
    case "rejected": return "桌主婉拒 · 礼物已收到，未发通行证"
    case "expired": return "桌主未响应 · 礼物已收到，未发通行证"
    default: return lobbyDndOrderStatusLabel(status)
    }
}

// ===================== API =====================

enum LobbyAPI {

    private static let client = APIClient.shared

    // MARK: 只读查询

    /// 门店卡片列表（店名/商圈/封面/实时入座数/最新一条消息）
    static func listStores() async throws -> [LobbyStoreCard] {
        try await client.get("app-api/social/lobby/query/stores")
    }

    /// 指定门店的楼层平面图 + 桌位（六态）
    static func listFloorPlans(storeId: Int64) async throws -> [LobbyFloorPlan] {
        try await client.get("app-api/social/lobby/query/floor-plans", query: ["storeId": String(storeId)])
    }

    /// 拼桌缺口滚动条投影
    static func listSharingGaps(storeId: Int64) async throws -> [LobbyShareGap] {
        try await client.get("app-api/social/lobby/query/sharing-gaps", query: ["storeId": String(storeId)])
    }

    /// 门店视频区（上架 + 近 24h）
    static func listVideos(storeId: Int64) async throws -> [LobbyVideo] {
        try await client.get("app-api/social/lobby/video/list", query: ["storeId": String(storeId)])
    }

    /// 门店热力榜（type=total/week/realtime）
    static func heatBoard(storeId: Int64, type: String, limit: Int? = nil) async throws -> LobbyHeatBoard {
        var query = ["storeId": String(storeId), "type": type]
        if let limit { query["limit"] = String(limit) }
        return try await client.get("app-api/social/lobby/heat/board", query: query)
    }

    /// 围观桌况（纯读，含入座成员昵称头像；抽屉展示用）
    static func spectateTable(tableId: Int64) async throws -> LobbyTableSpectate {
        try await client.get("app-api/social/lobby/query/spectate", query: ["tableId": String(tableId)])
    }

    /// 门店营业中小房间列表（表演区）
    static func listOpenRooms(storeId: Int64) async throws -> [LobbyVoiceRoom] {
        try await client.get("app-api/social/lobby/voice-room/list", query: ["storeId": String(storeId)])
    }

    // MARK: 坐席

    /// 我的坐席状态。从未入座时后端 data=null（APIClient 抛「数据为空」），这里转 nil；
    /// 网络错误照常抛出（调用方保持上一次坐席态）。
    static func mySeat() async throws -> LobbySeatState? {
        do {
            return try await client.get("app-api/social/lobby/seat/my") as LobbySeatState?
        } catch APIError.business(_, let message) where message == "数据为空" {
            return nil
        }
    }

    /// 入座申请（服务端三门槛；已 seated 他桌时按换桌原子处理）
    static func checkIn(token: String, tableId: Int64, latitude: Double, longitude: Double) async throws -> LobbySeatState {
        try await client.post("app-api/social/lobby/seat/check-in",
                              body: LobbyCheckInReq(token: token, tableId: tableId, latitude: latitude, longitude: longitude))
    }

    /// 主动离桌（回罚站，桌位行保留）
    static func leaveSeat() async throws {
        let _: Bool = try await client.post("app-api/social/lobby/seat/leave", body: LobbyEmptyReq())
    }

    /// 换桌（原子「离旧桌 + 入新桌」，限同店、不重复核验门槛）
    static func switchTable(tableId: Int64) async throws -> LobbySeatState {
        try await client.post("app-api/social/lobby/seat/switch", query: ["tableId": String(tableId)])
    }

    /// 定位心跳（围栏复检数据源；未 seated 返回 1-010-009-008，客户端据此静默停报）
    static func reportLocation(latitude: Double, longitude: Double) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/seat/location",
                                            body: LobbyLocationReq(latitude: latitude, longitude: longitude))
    }

    // MARK: 桌主动作

    /// 邀请好友补位（返回邀请 id）
    @discardableResult
    static func hostInvite(tableId: Int64, inviteeId: Int64) async throws -> Int64 {
        try await client.post("app-api/social/lobby/host/invite", body: LobbyHostInviteReq(tableId: tableId, inviteeId: inviteeId))
    }

    /// 喊人拼桌：有人桌转拼桌态并播报一条喊人消息（滚动条 3 分钟高亮）；服务端限流 10 次/小时
    static func hostShout(tableId: Int64, note: String?) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/host/shout",
                                            body: LobbyHostShoutReq(tableId: tableId, note: note))
    }

    /// 停止拼桌：拼桌态按当前人数回空闲/有人；本桌待审批申请批量拒绝并通知申请人
    static func hostStopShout(tableId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/host/stop-shout", query: ["tableId": String(tableId)])
    }

    /// 设置本桌勿扰（有人桌转勿扰态）
    static func hostEnableDnd(tableId: Int64, note: String?, silent: Bool) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/host/dnd",
                                            body: LobbyHostDndReq(tableId: tableId, note: note, silent: silent))
    }

    /// 取消本桌勿扰：在途解锁订单由服务端逐单原路退款
    static func hostCancelDnd(tableId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/host/cancel-dnd", query: ["tableId": String(tableId)])
    }

    /// 转让桌主（须为本桌另一入座成员）
    static func hostTransfer(tableId: Int64, targetUserId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/host/transfer",
                                            body: LobbyHostTransferReq(tableId: tableId, targetUserId: targetUserId))
    }

    /// 移出成员（本桌入座成员回罚站，leave_reason=kick）
    static func hostRemove(tableId: Int64, targetUserId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/host/remove",
                                            body: LobbyHostRemoveReq(tableId: tableId, targetUserId: targetUserId))
    }

    // MARK: 拼桌

    /// 发起拼桌申请（目标须为拼桌中且未满员）；返回申请 id
    @discardableResult
    static func shareApply(tableId: Int64, longitude: Double, latitude: Double) async throws -> Int64 {
        try await client.post("app-api/social/lobby/share/apply",
                              body: LobbyShareApplyReq(tableId: tableId, longitude: longitude, latitude: latitude))
    }

    /// 桌主审批通过：申请人随即入桌（服务端走特权入桌，不再核验门槛）
    static func shareApprove(applyId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/share/approve", query: ["applyId": String(applyId)])
    }

    /// 桌主审批拒绝：结果经官方号 IM 通知申请人
    static func shareReject(applyId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/share/reject", query: ["applyId": String(applyId)])
    }

    /// 本桌待审批申请（桌主；先到先审）
    static func sharePendingByHost(tableId: Int64) async throws -> [LobbyShareApply] {
        try await client.get("app-api/social/lobby/share/pending-by-host", query: ["tableId": String(tableId)])
    }

    /// 我的当前申请（含状态与是否过期；无申请 data=null → nil，与安卓 dataOrNull 口径一致；
    /// 网络错误照常抛出）
    static func shareMyApply() async throws -> LobbyShareApply? {
        do {
            return try await client.get("app-api/social/lobby/share/my-apply") as LobbyShareApply?
        } catch APIError.business(_, let message) where message == "数据为空" {
            return nil
        }
    }

    // MARK: 勿扰付费解锁

    /// 订单档建单（返回订单 id）：支付密码校验 + 扣兔币 + 通知桌主；一人一桌一单 pending
    @discardableResult
    static func dndCreateOrder(tableId: Int64, level: String, payPassword: String) async throws -> Int64 {
        try await client.post("app-api/social/lobby/dnd-unlock/order",
                              body: LobbyDndUnlockCreateReq(tableId: tableId, level: level, payPassword: payPassword))
    }

    /// 桌主接受：分账 50% + 发通行证（仅收款桌主且在 10 分钟窗口内）
    static func dndAcceptOrder(orderId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/dnd-unlock/accept", query: ["orderId": String(orderId)])
    }

    /// 桌主拒绝：原路退款（仅收款桌主；不受窗口限制）
    static func dndRejectOrder(orderId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/dnd-unlock/reject", query: ["orderId": String(orderId)])
    }

    /// 我的待响应订单（桌主视角，最急的在前）
    static func dndPendingByHost() async throws -> [LobbyDndUnlockOrder] {
        try await client.get("app-api/social/lobby/dnd-unlock/pending-by-host")
    }

    /// 我的解锁订单（解锁方视角，近 20 条含状态）
    static func dndMyOrders() async throws -> [LobbyDndUnlockOrder] {
        try await client.get("app-api/social/lobby/dnd-unlock/my-orders")
    }

    // MARK: 桌位邀请（受邀端）

    /// 我的待核销邀请（服务端只回 pending 且未过期的，最早到期在前）
    static func myInvites() async throws -> [LobbyTableInvite] {
        try await client.get("app-api/social/lobby/invite/my")
    }

    /// 到店核销入桌（带核销瞬间 GPS 作 3km 围栏证据；并发双核销只生效一次）
    static func acceptInvite(_ invite: LobbyTableInvite, latitude: Double, longitude: Double) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/invite/accept",
                                            body: LobbyInviteAcceptReq(inviteId: invite.id, longitude: longitude, latitude: latitude))
    }

    // MARK: 公屏非 IM 侧

    /// 全城聚合群 ID（未配置时 groupId 为 null）
    static func aggregateGroup() async throws -> String? {
        struct Resp: Decodable { let groupId: String? }
        let resp: Resp = try await client.get("app-api/social/lobby/channel/aggregate")
        return resp.groupId
    }

    /// 举报大厅消息：只上送 msgId + 原因编码，发送者/时间戳/门店由服务端查库补齐
    static func reportMessage(msgId: String, reason: LobbyReportReason, detail: String?) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/report",
                                            body: LobbyReportReq(msgId: msgId, reason: reason.rawValue, detail: detail))
    }
}

/// 空 body 占位（POST 无参数接口）
struct LobbyEmptyReq: Encodable {}
