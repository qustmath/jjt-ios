import SwiftUI

/// 活动主题令牌（报名制活动换肤）：全部来自服务端 theme JSON 配置，逐键可选、逐键容错，
/// 解析失败/键缺失一律回退默认暗夜金（Noir.Gold 系）。代码里不得写死任何活动专属皮肤。
///
/// 键语义（PRD §2.1，对齐安卓 ActivityTheme）：
///  accent      主色（按钮/边框/角标）          默认暗夜金
///  accent2     渐变副色（按钮渐变端点）        默认深金
///  deco        背景装饰字符（1-2 个）          默认空
///  passLabel   凭证卡英文标                    默认 "ACTIVITY PASS"
///  wallTitle   穿搭墙标题                      默认 "报名通过 · 会员风采"
///  wallTitleEn 穿搭墙英文副标                  默认 "PASSED REVIEW · COSTUME WALL"
struct ActivityTheme {
    var accent: Color = Noir.gold
    var accent2: Color = Noir.goldDeep
    var deco: String = ""
    var passLabel: String = "ACTIVITY PASS"
    /// nil = 调用方按「报名通过 · 会员风采」回退
    var wallTitle: String? = nil
    var wallTitleEn: String = "PASSED REVIEW · COSTUME WALL"

    /// 按钮主渐变（accent → accent2）
    var buttonGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
    }

    /// 穿搭墙标题（缺省回退会员风采口径）
    var resolvedWallTitle: String {
        if let wallTitle, !wallTitle.isEmpty { return wallTitle }
        return "报名通过 · 会员风采"
    }
}

/// 主题令牌解析：整体容错（坏 JSON 整体回退默认），色值逐键防御（非法色不崩、回默认）
func parseActivityTheme(_ json: String?) -> ActivityTheme {
    guard let json, !json.isEmpty,
          let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return ActivityTheme()
    }
    func str(_ key: String) -> String? {
        guard let v = obj[key] as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "null" ? nil : t
    }
    return ActivityTheme(
        accent: parseActivityHexColor(str("accent")) ?? Noir.gold,
        accent2: parseActivityHexColor(str("accent2")) ?? Noir.goldDeep,
        deco: str("deco") ?? "",
        passLabel: str("passLabel") ?? "ACTIVITY PASS",
        wallTitle: str("wallTitle"),
        wallTitleEn: str("wallTitleEn") ?? "PASSED REVIEW · COSTUME WALL"
    )
}

/// #RGB / #RRGGBB / #AARRGGBB 容错解析，非法返回 nil（对齐安卓 colorOrNull）
func parseActivityHexColor(_ raw: String?) -> Color? {
    guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    guard let value = UInt64(s, radix: 16) else { return nil }
    let r, g, b: Double
    switch s.count {
    case 3: // RGB
        r = Double((value >> 8) & 0xF) / 15
        g = Double((value >> 4) & 0xF) / 15
        b = Double(value & 0xF) / 15
    case 6: // RRGGBB
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    case 8: // AARRGGBB
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
        let a = Double((value >> 24) & 0xFF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    default:
        return nil
    }
    return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
}

/// 审核通过语义绿（流程条完成态/凭证卡「审核通过」角标/风采区角标共用，安卓同色）
let activityPassGreen = Color(red: 0x7D / 255, green: 0xE3 / 255, blue: 0xA0 / 255)
