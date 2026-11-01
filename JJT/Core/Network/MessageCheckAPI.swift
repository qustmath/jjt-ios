import Foundation

/// 消息发送前预检（腾讯 IM 发送前回调已停用，客户端发送前主动询问服务端）
///
/// 服务端判定（对齐安卓 `MessageCheckApi`）：封号 / 非互关单聊条数 / 群封禁 /
/// 全员&个人禁言 / 大厅限频&禁言&聚合群只读。
enum MessageCheckAPI {

    private struct Req: Encodable {
        let scene: String
        let target: String
        var text: String? = nil
        var cloudCustomData: String? = nil
    }

    private struct Resp: Decodable {
        let allowed: Bool?
        let code: Int?
        let reason: String?
    }

    /// nil=放行；非 nil=拒绝文案。
    /// 接口异常/超时一律放行——预检是体验层兜底，不阻断正常聊天。
    static func check(
        scene: String,
        target: String,
        text: String? = nil,
        cloudCustomData: String? = nil
    ) async -> String? {
        do {
            let resp: Resp = try await APIClient.shared.post(
                "app-api/im/message/send-check",
                body: Req(scene: scene, target: target, text: text, cloudCustomData: cloudCustomData)
            )
            guard resp.allowed == false else { return nil }
            let reason = resp.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return reason.isEmpty ? "暂时无法发送消息" : reason
        } catch {
            return nil
        }
    }
}
