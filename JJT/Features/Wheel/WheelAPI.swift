import Foundation

// MARK: - 抽奖转盘 API（对齐安卓 WheelApi）

struct WheelPrizeItem: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let sub: String?
    let icon: String?
    let color: String?
    /// coin兔币 / radish萝贝 / gift礼物 / frame头像框 / product商城商品
    let prizeType: String?
    let prizeCount: Int?
    let grand: Bool?
    /// 每人限中次数（0=不限）
    let winLimit: Int?
    /// 我已中次数（已发放）
    var myWins: Int?
}

struct WheelActivityInfo: Decodable {
    let activityId: Int64?
    let name: String?
    let nameEn: String?
    let cover: String?
    let rules: String?
    let startTime: Int64?
    let endTime: Int64?
    let drawPrice: Int64?
    /// 0未开始 1进行中 2已结束 3无活动
    let state: Int?
    var radishBalance: Int64?
    var prizes: [WheelPrizeItem]?
}

struct WheelDrawResult: Decodable {
    let prizeId: Int64?
    /// 奖品在盘面列表中的下标（转盘落点用）
    let prizeIndex: Int?
    /// 是否实际发放（达个人上限/发奖失败=false）
    let granted: Bool?
    let remark: String?
    let prizeName: String?
    let sub: String?
    let icon: String?
    let color: String?
    let prizeType: String?
    let prizeCount: Int?
    let grand: Bool?
    let radishBalance: Int64?
}

struct WheelRecordItem: Decodable, Identifiable {
    let id: Int64
    let activityId: Int64?
    let prizeId: Int64?
    let prizeName: String?
    let prizeType: String?
    let prizeCount: Int?
    let granted: Bool?
    let grantRemark: String?
    let createTime: Int64?
}

enum WheelAPI {
    static func activity() async throws -> WheelActivityInfo {
        try await APIClient.shared.get("app-api/member/wheel/activity")
    }

    static func draw() async throws -> WheelDrawResult {
        try await APIClient.shared.post("app-api/member/wheel/draw", query: [:])
    }

    static func recordPage(pageNo: Int, pageSize: Int = 20) async throws -> PageResult<WheelRecordItem> {
        try await APIClient.shared.get("app-api/member/wheel/record/page", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize)
        ])
    }
}
