import Foundation

/// 全局配置（与安卓 ApiClient.kt 对齐）
enum Config {
    /// 后端 API 域名（生产）
    static let apiBaseURL = URL(string: "https://jjtapi.tuxiansheng.online/")!
    /// 本地联调时改用（HTTP 需配合 ATS 例外，仅建议短期使用）
    // static let apiBaseURL = URL(string: "http://jjt.mynatapp.cc/")!

    /// H5 邀请注册页
    static let h5RegisterURL = URL(string: "https://register.tuxiansheng.online/")!
}
