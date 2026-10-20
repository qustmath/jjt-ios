import Foundation

/// 小房间语音房读写接口（对齐安卓 VoiceRoomApi，票 15 后端 / 票 20 App）。
///
/// 三条链路各自独立，别混用：
/// - **IM 群公屏**：join 拿到 imGroupIdStr → LobbyImSession 进群收发（有漫游留痕）。
/// - **LiveKit 语音**：token 拿 {url, token} 两件套（不硬编码接入地址）→ LiveKitClient 连房；
///   canPublish 按麦位白名单签发，闭麦/抱麦/下麦后必须重拉 token（旧 token 是签发快照）。
/// - **麦位状态**：全部经服务端（mic 系列接口）；说话音波是客户端 SDK ActiveSpeakersChanged 的事。
///
/// 进房门槛（本店入座 + 实名 + 一人一店在营上限）与模式判定全在服务端，客户端只透出拒绝文案。
enum VoiceRoomAPI {

    private static let client = APIClient.shared

    /// 开小房间（门槛：本店入座 + 实名 + 在营上限）；返回房间 id。
    /// 访问控制二选一（服务端校验）：accessPassword（4 位数字）XOR coinThreshold（须带 coinType）
    @discardableResult
    static func createRoom(storeId: Int64, title: String, tags: String?, mode: String,
                           accessPassword: String? = nil, coinType: String? = nil, coinThreshold: Int? = nil) async throws -> Int64 {
        struct Req: Encodable {
            let storeId: Int64
            let title: String
            let tags: String?
            let mode: String
            let accessPassword: String?
            let coinType: String?
            let coinThreshold: Int?
        }
        return try await client.post("app-api/social/lobby/voice-room/create",
                                     body: Req(storeId: storeId, title: title, tags: tags, mode: mode,
                                               accessPassword: accessPassword, coinType: coinType, coinThreshold: coinThreshold))
    }

    /// 关闭房间（仅房主）
    static func closeRoom(roomId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/close", query: ["roomId": String(roomId)])
    }

    /// 房间详情（麦位 + 我的状态 + 合规条；imGroupIdStr 仅在房返回）
    static func roomDetail(id: Int64) async throws -> LobbyVoiceRoomDetail {
        try await client.get("app-api/social/lobby/voice-room/get", query: ["id": String(id)])
    }

    /// 进房：public 直接进群 / approval 落申请待批 / invite 仅房主拉人（049）；密码房须带对 password（061）；
    /// 门票房（063）须带 payPassword 支付门票，不退、房主免票、已在房不重复扣
    static func join(roomId: Int64, password: String? = nil, payPassword: String? = nil) async throws -> VoiceRoomJoinResult {
        var query = ["roomId": String(roomId)]
        if let password { query["password"] = password }
        if let payPassword { query["payPassword"] = payPassword }
        return try await client.post("app-api/social/lobby/voice-room/join", query: query)
    }

    /// 拉人进房（房主/管理麦）
    static func invite(roomId: Int64, inviteeUserId: Int64) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let inviteeUserId: Int64
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/invite",
                                            body: Req(roomId: roomId, inviteeUserId: inviteeUserId))
    }

    /// 进房待审批列表（房主/管理麦）
    static func listJoinRequests(roomId: Int64) async throws -> [VoiceRoomJoinRequest] {
        try await client.get("app-api/social/lobby/voice-room/join-requests", query: ["roomId": String(roomId)])
    }

    /// 进房审批（房主/管理麦）
    static func handleJoinRequest(roomId: Int64, requestId: Int64, agree: Bool, reason: String?) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let requestId: Int64
            let agree: Bool
            let reason: String?
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/join-handle",
                                            body: Req(roomId: roomId, requestId: requestId, agree: agree, reason: reason))
    }

    /// 退房（在麦自动放麦）
    static func leave(roomId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/leave", query: ["roomId": String(roomId)])
    }

    /// 签 LiveKit 进房 token（须在房）：回 {url, token} 两件套
    static func token(roomId: Int64) async throws -> VoiceRoomToken {
        try await client.get("app-api/social/lobby/voice-room/token", query: ["roomId": String(roomId)])
    }

    /// 分享卡片信息（须在房）
    static func shareInfo(roomId: Int64) async throws -> VoiceRoomShare {
        try await client.get("app-api/social/lobby/voice-room/share-info", query: ["roomId": String(roomId)])
    }

    /// 申请上麦（须在房）；返回申请 id
    @discardableResult
    static func applyMic(roomId: Int64) async throws -> Int64 {
        try await client.post("app-api/social/lobby/voice-room/mic/apply", query: ["roomId": String(roomId)])
    }

    /// 上麦待处理列表（房主/管理麦）
    static func listMicApplications(roomId: Int64) async throws -> [VoiceRoomMicApply] {
        try await client.get("app-api/social/lobby/voice-room/mic/applications", query: ["roomId": String(roomId)])
    }

    /// 抱麦（房主/管理麦；seatNo 空 = 自动首个虚位，1 号麦仅房主）
    static func seatUser(roomId: Int64, targetUserId: Int64, seatNo: Int?) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let targetUserId: Int64
            let seatNo: Int?
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/mic/seat",
                                            body: Req(roomId: roomId, targetUserId: targetUserId, seatNo: seatNo))
    }

    /// 下麦（本人）
    static func leaveMic(roomId: Int64) async throws {
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/mic/leave", query: ["roomId": String(roomId)])
    }

    /// 强制下麦（房主/管理麦）：把麦上指定成员移下麦位
    static func kickMic(roomId: Int64, targetUserId: Int64) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let targetUserId: Int64
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/mic/kick",
                                            body: Req(roomId: roomId, targetUserId: targetUserId))
    }

    /// 移出房间（房主/管理麦）：退群 + 强制断 RTC + 清麦
    static func kickFromRoom(roomId: Int64, targetUserId: Int64) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let targetUserId: Int64
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/room/kick",
                                            body: Req(roomId: roomId, targetUserId: targetUserId))
    }

    /// 闭麦/开麦（房主/管理麦）
    static func muteMic(roomId: Int64, seatNo: Int, muted: Bool) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let seatNo: Int
            let muted: Bool
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/mic/mute",
                                            body: Req(roomId: roomId, seatNo: seatNo, muted: muted))
    }

    /// 指定/取消管理麦（仅房主，≤2 位）
    static func setMicRole(roomId: Int64, seatNo: Int, role: String) async throws {
        struct Req: Encodable {
            let roomId: Int64
            let seatNo: Int
            let role: String
        }
        let _: Bool = try await client.post("app-api/social/lobby/voice-room/mic/role",
                                            body: Req(roomId: roomId, seatNo: seatNo, role: role))
    }
}

// ===================== 响应模型 =====================

/// 进房结果：joined 已进房 / applied 已申请待审批 / already 已在房
struct VoiceRoomJoinResult: Decodable {
    let result: String?
    /// 腾讯 IM 群 ID（applied 时为 nil——审批通过后再拉详情）
    let imGroupIdStr: String?
}

/// LiveKit token 两件套
struct VoiceRoomToken: Decodable {
    let url: String?
    let token: String?
}

/// 分享卡片
struct VoiceRoomShare: Decodable {
    let roomId: Int64?
    let title: String?
    let mode: String?
    let ownerNickname: String?
    let micOccupied: Int?
    let micTotal: Int?
    let link: String?
    let complianceText: String?
}

/// 上麦申请条目：时间字段 epoch 毫秒
struct VoiceRoomMicApply: Decodable, Identifiable {
    let applyId: Int64?
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    let createTime: Int64?

    var id: Int64 { applyId ?? 0 }
}

/// 进房申请条目：时间字段 epoch 毫秒
struct VoiceRoomJoinRequest: Decodable, Identifiable {
    let requestId: Int64?
    let userId: Int64?
    let nickname: String?
    let avatar: String?
    let applyContent: String?
    let createTime: Int64?

    var id: Int64 { requestId ?? 0 }
}

// ===================== 文案与判据 =====================

/// 进房模式文案（后端 wire：public/invite/approval）
func voiceRoomModeLabel(_ mode: String?) -> String {
    switch mode {
    case "public": return "公开"
    case "invite": return "邀请制"
    case "approval": return "审批制"
    default: return "公开"
    }
}

/// 麦位角色文案：owner 房主 / admin 管理麦 / normal 普通麦
func voiceMicRoleLabel(_ role: String?) -> String? {
    switch role {
    case "owner": return "房主"
    case "admin": return "管理麦"
    default: return nil
    }
}

enum VoiceRoomConst {
    /// 官方号（后端口径 OFFICIAL_JJT=1001）：麦位变更通知的发送方，据此识别并重拉 token
    static let officialAccountId = "1001"
    /// 邀请制房间非成员进房被拒：用错误码判定，不匹配文案（文案可变）
    static let codeVoiceInviteOnly = 1_010_009_049
    /// 房间不存在或已关闭：进房撞上说明「在语音房」入口已过期
    static let codeVoiceRoomGone = 1_010_009_055
    /// 密码房密码缺失/错误（061）：进房弹密码输入再重试
    static let codeVoicePasswordWrong = 1_010_009_061
    /// 门票房进房须支付门票（063）：弹门票确认框走支付密码
    static let codeVoiceTicketPayPwdRequired = 1_010_009_063
}
