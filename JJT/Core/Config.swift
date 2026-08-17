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

    /// Bugly iOS 产品 App ID（与安卓 743f5ae4a2 分平台）
    static let buglyAppID = "3850b55428"
    /// Bugly iOS 产品 App Key（运行时只需 App ID；App Key 留给符号表/dSYM 上传工具用）
    static let buglyAppKey = "2efa084d-44ca-40ec-ab51-cb242a0dc853"
}
