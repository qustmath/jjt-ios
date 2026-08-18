import Foundation

// MARK: - 整蛊 API（对齐安卓 PrankApi）

struct PrankEffectInfo: Decodable, Identifiable {
    let id: Int64
    let effectKey: String?
    let name: String?
    let nameEn: String?
    /// 兔币，0=免费
    let price: Int?
    let unlocked: Bool?
    let expireTime: String?

    var id_: Int64 { id }
}

enum PrankAPI {
    static func list() async throws -> [PrankEffectInfo] {
        try await APIClient.shared.get("app-api/member/prank/list")
    }

    /// 购买特效 3 天卡，返回到期时间
    static func purchase(effectId: Int64) async throws -> String? {
        try await APIClient.shared.post("app-api/member/prank/purchase", query: ["effectId": String(effectId)])
    }
}

/// 剩余天数（epoch 毫秒或 ISO 字符串，对齐安卓 remainDays）
func prankRemainDays(_ expireTime: String?) -> Int {
    guard let expireTime, !expireTime.isEmpty else { return 0 }
    var millis: Int64?
    if let v = Int64(expireTime) {
        millis = v
    } else {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = f.date(from: expireTime.replacingOccurrences(of: " ", with: "T")) {
            millis = Int64(d.timeIntervalSince1970 * 1000)
        }
    }
    guard let millis else { return 0 }
    let diff = millis - Int64(Date().timeIntervalSince1970 * 1000)
    return diff <= 0 ? 0 : Int(ceil(Double(diff) / 86400000.0))
}
