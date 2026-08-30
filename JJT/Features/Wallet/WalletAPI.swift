import Foundation

// ════════════════════════════════════════════════════════════
// 钱包 / 充值 / 提现 / 支付密码 / 会员等级 / 头像框 —— API 与模型
// （对齐安卓 WalletApi / CoinRechargeApi / WithdrawApi /
//   PayPasswordApi / MemberLevelApi / AvatarFrameApi）
// ════════════════════════════════════════════════════════════

// MARK: - 钱包

struct WalletBalance: Decodable {
    let availableAmount: Int64?
}

struct WalletTransaction: Decodable, Identifiable {
    let id: Int64
    let direction: Int?       // 1=收入 其他=支出
    let amount: Int64?
    let balanceBefore: Int64?
    let balanceAfter: Int64?
    let bizType: String?
    let remark: String?
    let createTime: Int64?    // 毫秒时间戳
}

enum WalletAPI {
    static func getWallet(_ walletType: String) async throws -> WalletBalance {
        try await APIClient.shared.get("app-api/member/wallet/get", query: ["walletType": walletType])
    }

    static func transactions(_ walletType: String, pageNo: Int = 1, pageSize: Int = 20) async throws -> PageResult<WalletTransaction> {
        try await APIClient.shared.get("app-api/member/wallet/transactions", query: [
            "walletType": walletType, "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }

    /// 兔币兑换萝贝（1 兔币 = 10 萝贝），返回获得的萝贝数量
    static func exchangeRadish(amount: Int64) async throws -> Int64 {
        try await APIClient.shared.post("app-api/member/wallet/exchange-radish", query: ["amount": String(amount)])
    }
}

// MARK: - 充值

struct CoinRechargePackage: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let payPrice: Int?    // 充值兔币数（支付 = ÷10 元）
    let bonusPrice: Int?  // 赠送兔币数
}

struct CoinRechargeCreateReq: Encodable {
    var packageId: Int64? = nil
    var payPrice: Int? = nil   // 兔币数（自定义金额用，1 元 = 10 兔币）
}

struct PaySubmitReq: Encodable {
    let id: Int64
    let channelCode: String
}

struct PayOrderSubmitResp: Decodable {
    let status: Int?
    let displayMode: String?
    let displayContent: String?
}

/// 支付订单（status：0 未支付 10 已支付）
struct PayOrderInfo: Decodable {
    let id: Int64?
    let status: Int?
}

enum CoinRechargeAPI {
    static func packages() async throws -> [CoinRechargePackage] {
        try await APIClient.shared.get("app-api/member/coin-recharge/packages")
    }

    /// 创建充值订单，返回 payOrderId
    static func create(_ req: CoinRechargeCreateReq) async throws -> Int64 {
        try await APIClient.shared.post("app-api/member/coin-recharge/create", body: req)
    }

    /// 提交支付，返回收银台地址（displayContent）
    static func submitPay(id: Int64, channelCode: String = "juheba_alipay") async throws -> PayOrderSubmitResp {
        try await APIClient.shared.post("app-api/pay/order/submit", body: PaySubmitReq(id: id, channelCode: channelCode))
    }

    /// 查询支付订单（sync=true 后端主动向渠道同步一次）
    static func getPayOrder(id: Int64, sync: Bool = true) async throws -> PayOrderInfo {
        try await APIClient.shared.get("app-api/pay/order/get", query: ["id": String(id), "sync": String(sync)])
    }
}

// MARK: - 提现 / 银行卡

struct BankCardInfo: Decodable, Identifiable {
    let id: Int64
    let cardNo: String?
    let bankName: String?
    let cardholder: String?
    let isDefault: Bool?
}

struct BindCardReq: Encodable {
    let cardNo: String
    let bankName: String
    let cardholder: String
    let bankPhone: String
    let cardFrontUrl: String
    let cardBackUrl: String
}

struct WithdrawReq: Encodable {
    let amount: Int64        // 分
    let bankAccountId: Int64
    let payPassword: String
}

/// 提现规则配置（与后端实际扣费同源下发）
struct WithdrawConfig: Decodable {
    let taxRate: FlexibleDecimal?   // 税率，如 0.07
    let fixedFee: Int64?            // 单笔固定手续费（分）
    let minAmount: Int64?           // 最低提现金额（分）
    let maxSingleAmount: Int64?     // 单笔上限（分，0=不限）
    let maxDailyCount: Int?         // 日最大次数
    let maxMonthlyAmount: Int64?    // 月上限（分）

    /// 试算：税费 + 单笔费（分），与服务端 calcTaxFee 同公式（向下取整）
    func feeOf(_ amountCent: Int64) -> Int64 {
        guard let rateStr = taxRate?.value, let rate = Double(rateStr) else { return fixedFee ?? 0 }
        let tax = Int64((Double(amountCent) * rate).rounded(.down))
        return tax + (fixedFee ?? 0)
    }
}

struct WithdrawOrder: Decodable, Identifiable {
    let id: Int64
    let amount: Int64?         // 提现金额（分）
    let fee: Int64?            // 手续费（分）
    let actualAmount: Int64?   // 实际到账（分）
    let status: String?        // PENDING/PROCESSING/SUCCESS/FAILED
    let failReason: String?
    let createTime: String?
    let completedAt: String?

    var statusText: String {
        switch status {
        case "PENDING": return "待处理"
        case "PROCESSING": return "处理中"
        case "SUCCESS": return "已到账"
        case "FAILED": return "失败"
        default: return "未知"
        }
    }
}

enum WithdrawAPI {
    static func bindCard(_ req: BindCardReq) async throws -> Int64 {
        try await APIClient.shared.post("app-api/member/withdraw/bind-card", body: req)
    }

    static func cards() async throws -> [BankCardInfo] {
        try await APIClient.shared.get("app-api/member/withdraw/cards")
    }

    static func deleteCard(id: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/member/withdraw/card", query: ["id": String(id)])
    }

    static func apply(_ req: WithdrawReq) async throws -> Int64 {
        try await APIClient.shared.post("app-api/member/withdraw/apply", body: req)
    }

    static func withdrawList() async throws -> [WithdrawOrder] {
        try await APIClient.shared.get("app-api/member/withdraw/list")
    }

    static func config() async throws -> WithdrawConfig {
        try await APIClient.shared.get("app-api/member/withdraw/config")
    }
}

// MARK: - 支付密码

/// 后端错误码：未设置支付密码
let PAY_PASSWORD_NOT_SET_CODE = 1004021000

struct PayPasswordStatus: Decodable {
    let hasPayPassword: Bool?
}

struct PayPasswordSetReq: Encodable {
    let password: String
    let smsCode: String
}

struct PayPasswordUpdateReq: Encodable {
    let oldPassword: String
    let newPassword: String
    let smsCode: String
}

/// scene 固定 6（MEMBER_PAY_PASSWORD）；mobile 传占位即可，后端强制取绑定手机号
struct PayPasswordSmsSendReq: Encodable {
    let mobile: String
    let scene: Int
}

enum PayPasswordAPI {
    static func status() async throws -> PayPasswordStatus {
        try await APIClient.shared.get("app-api/member/pay-password/status")
    }

    static func set(password: String, smsCode: String) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/pay-password/set", body: PayPasswordSetReq(password: password, smsCode: smsCode))
    }

    static func update(old: String, new: String, smsCode: String) async throws -> Bool {
        try await APIClient.shared.post("app-api/member/pay-password/update", body: PayPasswordUpdateReq(oldPassword: old, newPassword: new, smsCode: smsCode))
    }

    static func sendSmsCode() async throws -> Bool {
        try await APIClient.shared.post("app-api/member/auth/send-sms-code", body: PayPasswordSmsSendReq(mobile: "13800000000", scene: 6))
    }
}

// MARK: - 会员等级（ADR 0007 段位化模型）

struct MemberTierConfig: Decodable, Identifiable {
    let tier: Int
    let name: String
    let enName: String?
    let color: String?
    let levelCount: Int
    let pricePerLevel: Int64
    let avatarFrame: String?
    let benefits: String?
    let startOrdinal: Int?

    var id: Int { tier }
}

struct MyLevelInfo: Decodable {
    let tier: Int?
    let levelInTier: Int?
    let displayTier: Int?
    let effectiveDisplayTier: Int?
    let displayTierName: String?
    let displayTierColor: String?
    let avatarFrame: String?
    let ordinal: Int?
    let totalRabbitCoinCost: Int64?
    let rabbitCoinBalance: Int64?
}

struct MemberLevelPage: Decodable {
    let tiers: [MemberTierConfig]?
    let my: MyLevelInfo?
}

struct UpgradeReq: Encodable {
    let targetTier: Int
    let targetLevel: Int
}

struct DisplayTierReq: Encodable {
    let tier: Int?
}

struct UpgradeFeeInfo: Decodable {
    let items: [Item]?
    let total: Int64?
    let balance: Int64?

    struct Item: Decodable {
        let tier: Int
        let name: String
        let count: Int
        let pricePerLevel: Int64
        let subtotal: Int64
    }
}

enum MemberLevelAPI {
    static func levelPage() async throws -> MemberLevelPage {
        try await APIClient.shared.get("app-api/member/level/page")
    }

    static func upgradeFee(targetTier: Int, targetLevel: Int) async throws -> UpgradeFeeInfo {
        try await APIClient.shared.post("app-api/member/level/upgrade-fee", body: UpgradeReq(targetTier: targetTier, targetLevel: targetLevel))
    }

    // 付费升级已停用（2026-08 产品调整，对齐安卓）：不再调用 level/upgrade 接口，差额仅展示

    /// 设置外显段位（tier=nil 恢复跟随实际最高）
    static func setDisplayTier(_ tier: Int?) async throws -> MyLevelInfo {
        try await APIClient.shared.post("app-api/member/level/display-tier", body: DisplayTierReq(tier: tier))
    }
}

// MARK: - 头像框

struct AvatarFrameOptions: Decodable {
    let current: String?
    let defaults: [FrameItem]?
    let tiers: [TierFrameItem]?
    let owned: [OwnedFrameItem]?

    struct FrameItem: Decodable, Identifiable {
        let id: Int64
        let name: String
        let url: String
        let scale: Double?
    }

    struct TierFrameItem: Decodable, Identifiable {
        let tier: Int
        let name: String
        let url: String
        let scale: Double?
        let unlocked: Bool?

        var id: Int { tier }
    }

    struct OwnedFrameItem: Decodable, Identifiable {
        let id: Int64
        let name: String?
        let url: String
        let scale: Double?
        let expireTime: Int64?   // null=永久
    }
}

enum AvatarFrameAPI {
    static func options() async throws -> AvatarFrameOptions {
        try await APIClient.shared.get("app-api/member/avatar-frame/options")
    }
}
