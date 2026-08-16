import SwiftUI

/// 真机诊断面板（长按首页左上角"棘"logo 唤出）：
/// 拉取轮播图/广场接口，展示原始 imageUrl 与逐个实测加载结果，
/// 用于定位图片不显示的真实原因（URL 格式 / 状态码 / 证书 / DNS）。
struct DiagnosticsSheet: View {

    struct Row: Identifiable {
        let id = UUID()
        let source: String   // banner / post
        let rawURL: String
        var result: String = "…"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var testing = false

    var body: some View {
        NavigationStack {
            List {
                Section("环境") {
                    LabeledContent("App 版本", value: "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")")
                    LabeledContent("API", value: Config.apiBaseURL.absoluteString)
                    LabeledContent("登录态", value: TokenManager.shared.isLoggedIn ? "已登录" : "未登录")
                }
                Section("图片实测") {
                    if rows.isEmpty {
                        Text(testing ? "加载中…" : "无数据").foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.source)：\(row.rawURL)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(row.result)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(row.result.hasPrefix("✅") ? .green : (row.result.hasPrefix("…") ? .secondary : .red))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("重测") { Task { await run() } }
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        testing = true
        rows = []
        do {
            let banners = try await HomeAPI.banners()
            for b in banners {
                rows.append(Row(source: "banner", rawURL: b.imageUrl ?? "(nil)"))
            }
        } catch {
            rows.append(Row(source: "banner接口", rawURL: "失败：\(error.localizedDescription)"))
        }
        if let page = try? await HomeAPI.latestPosts(), let list = page.list {
            for p in list.prefix(3) {
                rows.append(Row(source: "post头像", rawURL: p.avatar ?? "(nil)"))
            }
        }
        // 好友状态接口实测（加好友按钮不显示排查）
        do {
            let s = try await FollowAPI.friendStatus(userId: 2)
            rows.append(Row(source: "好友状态(uid=2)", rawURL: "app-api/member/friend-apply/status", result: "✅ 返回：\(s)"))
        } catch {
            rows.append(Row(source: "好友状态(uid=2)", rawURL: "app-api/member/friend-apply/status", result: "❌ \(error.localizedDescription)"))
        }
        testing = false
        await testAll()
    }

    /// 逐个实测：归一化 URL → 真实请求，记录状态码/字节数/错误
    private func testAll() async {
        for i in rows.indices {
            let raw = rows[i].rawURL
            guard rows[i].result == "…" else { continue } // 已有结论的探针行跳过
            guard !raw.hasPrefix("失败") else { continue }
            guard let url = webImageURL(raw) else {
                rows[i].result = "❌ URL 解析失败（归一化后仍非法）"
                continue
            }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                rows[i].result = status == 200 && UIImage(data: data) != nil
                    ? "✅ \(status) · \(data.count)B · 解码成功"
                    : (UIImage(data: data) == nil ? "❌ \(status) · \(data.count)B · 无法解码为图片" : "❌ \(status)")
            } catch {
                rows[i].result = "❌ \(error.localizedDescription)"
            }
        }
    }
}
