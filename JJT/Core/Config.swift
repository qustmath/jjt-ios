import Foundation

/// 全局配置（与安卓 ApiClient.kt 对齐）
enum Config {
    /// 后端 API 域名（生产）
    static let apiBaseURL = URL(string: "https://jjtapi.tuxiansheng.online/")!
    /// 本地联调时改用（HTTP 需配合 ATS 例外，仅建议短期使用）
    // static let apiBaseURL = URL(string: "http://jjt.mynatapp.cc/")!

    /// H5 邀请注册页
    static let h5RegisterURL = URL(string: "https://register.tuxiansheng.online/")!

    /// 腾讯 IM SDK App ID（对齐安卓 ImManager.SDK_APP_ID）
    static let imSDKAppID: Int32 = 1600148788

    /// Bugly iOS 产品 App ID（与安卓 743f5ae4a2 分平台，需在 bugly.qq.com 新建 iOS 产品后填入）
    /// TODO: 创建后替换；空串时 Bugly 不初始化
    static let buglyAppID = ""
}
