import SwiftUI
import Bugly

/// 真机诊断面板（首页滑到底，点页脚几乎隐形的 "build N" 小字唤出）：
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
    @State private var buglyTestMsg: String?

    var body: some View {
        NavigationStack {
            List {
                Section("环境") {
                    LabeledContent("App 版本", value: "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")")
                    LabeledContent("API", value: Config.apiBaseURL.absoluteString)
                    LabeledContent("登录态", value: TokenManager.shared.isLoggedIn ? "已登录" : "未登录")
                    LabeledContent("Bugly", value: Config.buglyAppID.isEmpty ? "未配置" : "已启用 \(Config.buglyAppID)")
                }
                // 文字卡片渲染实测（纯文字帖封面：页内直接渲染样例，肉眼验证文字是否正常绘制/换行）
                Section("文字卡片渲染测试") {
                    Image(uiImage: TextCardRenderer.render("夜行手记\n今晚的风把城市吹成一杯冷酒，我们把剩下的故事留在天台说完，聊到月亮也困了。", styleIndex: 0))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                // Bugly 上报链路测试（对齐安卓 CrashLogScreen 的测试崩溃入口）
                Section("Bugly 上报测试") {
                    Button("测试异常上报（不闪退）") {
                        Bugly.report(NSException(
                            name: NSExceptionName("JJTTestException"),
                            reason: "Bugly 上报链路测试（手动触发，非真实bug）",
                            userInfo: nil))
                        buglyTestMsg = "已上报一条测试异常，几分钟后在 Bugly 后台「错误分析」查看"
                    }
                    Button("测试崩溃（App 会闪退）") {
                        buglyTestMsg = "即将闪退…"
                        // 延迟半秒让提示渲染出来再崩；崩溃将在 Bugly 后台「崩溃分析」出现
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let empty: [Int] = []
                            let i = Int(Date().timeIntervalSince1970) % 5 + 1 // 非常量下标，防编译期优化掉
                            _ = empty[i]
                        }
                    }
                    .foregroundStyle(.red)
                    if let buglyTestMsg {
                        Text(buglyTestMsg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
