import Foundation

/// 兔币余额不足错误码（送礼/红包/解锁等场景 → 引导充值）
let WALLET_INSUFFICIENT_BALANCE_CODE = 1004013000

extension Notification.Name {
    /// 资金操作余额不足（守卫抛出 → 页面弹充值引导）
    static let jjtInsufficientBalance = Notification.Name("jjtInsufficientBalance")
}

// MARK: - 模型（对齐安卓 GiftApi.kt）

struct GiftItem: Decodable, Identifiable {
    let id: Int64
    let name: String
    let description: String?
    let icon: String?
    let categoryId: Int64?
    let categoryName: String?
    let priceRabbit: Int?
    let animationUrl: String?
    /// 图标显示缩放（百分比，100=原始大小）
    let iconScale: Int?
}

struct SendGiftReq: Encodable {
    let giftId: Int64
    var receiverId: Int64? = nil
    var quantity: Int = 1
    var scene: String = "profile"
    var sceneId: Int64? = nil
    let payPassword: String
}

struct GiftOrderVO: Decodable, Identifiable {
    let id: Int64
    let giftId: Int64
    let giftName: String?
    let giftIcon: String?
    let animationUrl: String?
    let senderId: Int64?
    let receiverId: Int64?
    let counterpartyName: String?
    let quantity: Int?
    let payAmount: Int64?
    let revenueAmount: Int64?
    let status: String?       // PAID 未送出 / SENT 已送出 / RECEIVED 已接收
    let scene: String?
    let receivedAt: String?
    let createTime: String?
    let iconScale: Int?
}

struct GiftWallItem: Decodable, Identifiable {
    let giftId: Int64
    let name: String
    let icon: String?
    let animationUrl: String?
    let series: String?
    let tier: Int?
    let quantity: Int?
    let totalCount: Int?
    let iconScale: Int?

    var id: Int64 { giftId }
}

// MARK: - 渲染键工具（对齐安卓 GiftPanelSheet.kt 底部工具函数）

/// 渲染键解析：gift2d:/gift3d: 内置渲染键，.svga/.glb 为后台上传素材 URL
func giftRenderKindOf(_ icon: String?) -> (String, String)? {
    guard let icon else { return nil }
    if icon.hasPrefix("gift2d:") { return ("2d", String(icon.dropFirst(7))) }
    if icon.hasPrefix("gift3d:") { return ("3d", String(icon.dropFirst(7))) }
    let path = icon.components(separatedBy: "?").first ?? icon
    if path.lowercased().hasSuffix(".svga") { return ("svga", icon) }
    if path.lowercased().hasSuffix(".glb") { return ("glb", icon) }
    return nil
}

/// 礼物展示图：icon 为空时回退动效素材（svga/glb 可同时充当列表图）
func giftDisplayIcon(_ icon: String?, _ animationUrl: String?) -> String? {
    if let icon, !icon.isEmpty { return icon }
    if let animationUrl, !animationUrl.isEmpty { return animationUrl }
    return nil
}

/// 渲染类型归组到 2D/3D tab：svga 归 2D，glb 归 3D
func giftKindGroupOf(_ kind: String?) -> String {
    (kind == "3d" || kind == "glb") ? "3d" : "2d"
}

// MARK: - API

enum GiftAPI {
    static func giftList(categoryId: Int64? = nil) async throws -> [GiftItem] {
        var q: [String: String] = [:]
        if let categoryId { q["categoryId"] = String(categoryId) }
        return try await APIClient.shared.get("app-api/social/gift/list", query: q.isEmpty ? nil : q)
    }

    /// 送礼物（需支付密码）
    static func send(_ req: SendGiftReq) async throws -> Int64 {
        try await APIClient.shared.post("app-api/social/gift/send", body: req)
    }

    /// 指定接收人（先买后送）
    static func assignReceiver(orderId: Int64, receiverId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/gift/assign", query: [
            "orderId": String(orderId), "receiverId": String(receiverId)
        ])
    }

    /// 接收礼物，返回收益
    static func receive(orderId: Int64) async throws -> Int64 {
        try await APIClient.shared.post("app-api/social/gift/receive", query: ["orderId": String(orderId)])
    }

    static func receivedList() async throws -> [GiftOrderVO] {
        try await APIClient.shared.get("app-api/social/gift/received")
    }

    static func sentList() async throws -> [GiftOrderVO] {
        try await APIClient.shared.get("app-api/social/gift/sent")
    }

    static func myGiftWall() async throws -> [GiftWallItem] {
        try await APIClient.shared.get("app-api/social/gift-wall/my")
    }

    static func userGiftWall(userId: Int64) async throws -> [GiftWallItem] {
        try await APIClient.shared.get("app-api/social/gift-wall/user", query: ["userId": String(userId)])
    }
}
