import Foundation

/// 用户展示信息本地缓存（内存 + UserDefaults，对齐安卓 UserDisplayCache）
/// 会话列表 / 聊天页的头像框、段位来自 /member/user/list 批量接口，网络往返约 1 秒，
/// 会导致所有头像框"延迟 1 秒同时出现"。缓存优先渲染（同步读，立即显示），
/// 接口返回后静默刷新并回写缓存。
struct CachedDisplay: Codable {
    let id: Int64
    var nickname: String?
    var avatar: String?
    var avatarFrame: String?
    var avatarFrameScale: Double = 1.0
    var levelName: String?
    var levelNum: Int?
    var levelColor: String?
}

extension UserInfoResp {
    func toCachedDisplay() -> CachedDisplay {
        CachedDisplay(
            id: id,
            nickname: nickname,
            avatar: avatar,
            avatarFrame: avatarFrame,
            avatarFrameScale: avatarFrameScale ?? 1.0,
            levelName: level?.name,
            levelNum: level?.levelInTier,
            levelColor: level?.color
        )
    }
}

enum UserDisplayCache {

    private static let key = "user_display_cache"
    private static let maxEntries = 300

    private static var mem: [Int64: CachedDisplay] = [:]
    /// 最近写入时间（截断磁盘缓存时按此保留最新条目）
    private static var lastWrite: [Int64: TimeInterval] = [:]
    private static var loaded = false

    /// 应用启动时调用：从磁盘回填内存缓存
    static func load() {
        guard !loaded else { return }
        loaded = true
        guard let raw = UserDefaults.standard.string(forKey: key),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([CachedDisplay].self, from: data) else { return }
        for d in list { mem[d.id] = d }
    }

    /// 同步取缓存（未初始化/未命中返回空 map，不阻塞）
    static func getMap(_ ids: [Int64]) -> [Int64: CachedDisplay] {
        guard loaded, !ids.isEmpty else { return [:] }
        var result: [Int64: CachedDisplay] = [:]
        for id in ids {
            if let d = mem[id] { result[id] = d }
        }
        return result
    }

    /// 接口返回后回写（内存立即生效，磁盘异步落盘）
    static func putAll(_ displays: [CachedDisplay]) {
        guard loaded, !displays.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        for d in displays {
            mem[d.id] = d
            lastWrite[d.id] = now
        }
        // 截断到最近写入的 maxEntries 条，防无限膨胀
        let snapshot = mem.values
            .sorted { (lastWrite[$0.id] ?? 0) > (lastWrite[$1.id] ?? 0) }
            .prefix(maxEntries)
        let arr = Array(snapshot)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(arr),
                  let raw = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(raw, forKey: key)
        }
    }
}
