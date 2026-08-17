import Foundation

/// IM 后端 API（对齐安卓 ImApi）
enum ImAPI {
    /// 获取 UserSig
    static func userSig(userId: Int64) async throws -> String {
        try await APIClient.shared.get("app-api/im/tencent-im/user-sig", query: ["userId": String(userId)])
    }
}

// MARK: - 红包 API（对齐安卓 RedPacketApi）
// 类型：1拼手气 2普通 3专属；场景：1单聊 2群聊；状态：1进行中 2已领完 3已过期

struct RedPacketSendReq: Encodable {
    let scene: Int
    let targetId: String
    let walletType: String
    let packetType: Int
    let totalAmount: Int
    var totalCount: Int? = nil
    var exclusiveUserId: Int64? = nil
    var greeting: String? = nil
    let payPassword: String
}

struct RedPacketSendResp: Decodable {
    let packetId: Int64
    let packetNo: String?
}

struct RedPacketStatusResp: Decodable {
    let packetId: Int64
    let status: Int
    let packetType: Int
    let scene: Int
    let walletType: String?
    let greeting: String?
    let senderId: Int64
    let senderNickname: String?
    let senderAvatar: String?
    let exclusiveUserId: Int64?
    let exclusiveNickname: String?
    let totalCount: Int
    let remainCount: Int
    let opened: Bool
    let myAmount: Int?
    let canOpen: Bool
    let expireTime: String?
}

struct RedPacketOpenResp: Decodable {
    /// 1领取成功 2已领过 3已领完 4已过期 5无权领取
    let result: Int
    let amount: Int?
    let openedCount: Int
    let totalCount: Int
}

struct RedPacketDetailResp: Decodable {
    let packetId: Int64
    let status: Int
    let packetType: Int
    let scene: Int
    let walletType: String?
    let greeting: String?
    let senderId: Int64
    let senderNickname: String?
    let senderAvatar: String?
    let totalAmount: Int
    let totalCount: Int
    let remainAmount: Int
    let remainCount: Int
    let exclusiveNickname: String?
    let myAmount: Int?
    let createTime: String?
    let claims: [RedPacketClaim]?
}

struct RedPacketClaim: Decodable, Identifiable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let amount: Int
    let luckiest: Bool
    let createTime: String?

    var id: Int64 { userId }
}

/// 钱包类型展示名
func walletTypeLabel(_ walletType: String?) -> String {
    walletType == "radish_coin" ? "萝贝" : "兔币"
}

enum RedPacketAPI {
    static func send(_ req: RedPacketSendReq) async throws -> RedPacketSendResp {
        try await APIClient.shared.post("app-api/im/red-packet/send", body: req)
    }

    static func status(packetId: Int64) async throws -> RedPacketStatusResp {
        try await APIClient.shared.get("app-api/im/red-packet/status", query: ["packetId": String(packetId)])
    }

    static func open(packetId: Int64) async throws -> RedPacketOpenResp {
        try await APIClient.shared.post("app-api/im/red-packet/open", query: ["packetId": String(packetId)])
    }

    /// 撤回（IM 消息发送失败等场景，未领取全额退回）
    static func cancel(packetId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/im/red-packet/cancel", query: ["packetId": String(packetId)])
    }

    static func detail(packetId: Int64) async throws -> RedPacketDetailResp {
        try await APIClient.shared.get("app-api/im/red-packet/detail", query: ["packetId": String(packetId)])
    }
}
