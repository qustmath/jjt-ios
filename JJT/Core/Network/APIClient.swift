import Foundation

/// 后端统一响应壳：HTTP 恒 200，code=0 成功（与安卓 CommonResp 对齐）
struct CommonResp<T: Decodable>: Decodable {
    let code: Int
    let msg: String?
    let data: T?
}

/// 空 data 占位（logout 等只关心 code 的接口）
struct EmptyData: Decodable {}

enum APIError: LocalizedError {
    case business(code: Int, message: String)
    case unauthorized
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .business(_, let message): return message
        case .unauthorized: return "登录已过期，请重新登录"
        case .network(let e): return "网络异常：\(e.localizedDescription)"
        case .decoding: return "数据解析失败"
        }
    }
}

/// 全局未授权通知（token 失效 → 回登录页）
extension Notification.Name {
    static let jjtUnauthorized = Notification.Name("jjt.unauthorized")
}

/// 网络层：URLSession + async/await，自动带 Bearer Token，401 自动刷新重放一次
/// （对齐安卓 ApiClient 的 authCheckInterceptor + tokenAuthenticator）
final class APIClient {

    static let shared = APIClient()
    private init() {}

    private let session: URLSession = {
        let conf = URLSessionConfiguration.default
        conf.timeoutIntervalForRequest = 30
        return URLSession(configuration: conf)
    }()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// 防并发重复刷新
    private var refreshTask: Task<Bool, Never>?

    // MARK: - 公开入口

    func get<T: Decodable>(_ path: String, query: [String: String]? = nil) async throws -> T {
        try await request(path, method: "GET", query: query, body: nil as EmptyBody?, retryOnAuth: true)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(path, method: "POST", query: nil, body: body, retryOnAuth: true)
    }

    func post<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        try await request(path, method: "POST", query: query, body: nil as EmptyBody?, retryOnAuth: true)
    }

    // MARK: - 核心请求

    private struct EmptyBody: Encodable {}

    private func request<T: Decodable, B: Encodable>(
        _ path: String, method: String, query: [String: String]?,
        body: B?, retryOnAuth: Bool
    ) async throws -> T {
        var components = URLComponents(url: Config.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        if let query {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenManager.shared.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try encoder.encode(body) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network(URLError(.badServerResponse)) }

        let resp: CommonResp<T>
        do {
            resp = try decoder.decode(CommonResp<T>.self, from: data)
        } catch {
            // HTTP 层错误且无法解析业务壳
            if http.statusCode == 401 { return try await handleUnauthorized(path, method: method, query: query, body: body, retryOnAuth: retryOnAuth) }
            throw APIError.decoding(error)
        }

        if resp.code == 0 {
            guard let d = resp.data else { throw APIError.business(code: -1, message: resp.msg ?? "数据为空") }
            return d
        }
        if resp.code == 401 {
            return try await handleUnauthorized(path, method: method, query: query, body: body, retryOnAuth: retryOnAuth)
        }
        throw APIError.business(code: resp.code, message: resp.msg ?? "请求失败(\(resp.code))")
    }

    /// 401 处理：刷新 token 成功后重放一次原请求；失败则广播未授权
    private func handleUnauthorized<T: Decodable, B: Encodable>(
        _ path: String, method: String, query: [String: String]?,
        body: B?, retryOnAuth: Bool
    ) async throws -> T {
        guard retryOnAuth else {
            notifyUnauthorized()
            throw APIError.unauthorized
        }
        let ok = await refreshTokenIfNeeded()
        if ok {
            return try await request(path, method: method, query: query, body: body, retryOnAuth: false)
        }
        notifyUnauthorized()
        throw APIError.unauthorized
    }

    // MARK: - Token 刷新

    private func refreshTokenIfNeeded() async -> Bool {
        if let task = refreshTask { return await task.value }
        let task = Task<Bool, Never> { [session, decoder] in
            guard let rt = TokenManager.shared.refreshToken else { return false }
            var components = URLComponents(url: Config.apiBaseURL.appendingPathComponent("app-api/member/auth/refresh-token"), resolvingAgainstBaseURL: true)!
            components.queryItems = [URLQueryItem(name: "refreshToken", value: rt)]
            var req = URLRequest(url: components.url!)
            req.httpMethod = "POST"
            do {
                let (data, _) = try await session.data(for: req)
                let resp = try decoder.decode(CommonResp<LoginResp>.self, from: data)
                guard resp.code == 0, let d = resp.data,
                      let at = d.accessToken, let newRt = d.refreshToken, let uid = d.userId else { return false }
                TokenManager.shared.save(accessToken: at, refreshToken: newRt, userId: uid)
                return true
            } catch {
                return false
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func notifyUnauthorized() {
        TokenManager.shared.clear()
        NotificationCenter.default.post(name: .jjtUnauthorized, object: nil)
    }
}
