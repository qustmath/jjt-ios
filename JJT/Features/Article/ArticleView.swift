import SwiftUI

/// 图文详情 — 暗夜奢华风（对齐安卓 ArticleScreen.kt）
/// 仅经轮播图/弹窗/扫码 DeepLink 直达，与帖子严格隔离（不进广场、无互动）。
/// 结构：顶栏（返回 + 图文详情）→ 大字号标题 → 发布时间·浏览次数 → 正文块流（文字/全宽图片），整页滚动
struct ArticleView: View {

    let articleId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var article: ArticleInfo?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if loading {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else if let errorMessage {
                    errorPlaceholder(errorMessage)
                } else if let article {
                    contentView(article)
                } else {
                    // 兜底（非加载、无数据、无错误）：按错误占位处理，不崩溃
                    errorPlaceholder("图文不存在或已下架")
                }
            }
        }
        .onAppear { load() }
        .jjtPageGestures()
    }

    // MARK: - 数据

    private func load() {
        Task {
            do {
                article = try await ArticleAPI.get(id: articleId)
                errorMessage = nil
            } catch {
                // 禁用/不存在（code=1002017000）与网络失败统一走错误占位页（对齐安卓）
                let msg = error.localizedDescription
                errorMessage = msg.isEmpty ? "图文不存在或已下架" : msg
            }
            loading = false
        }
    }

    // MARK: - 顶栏（返回 + 标题）

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text("图文详情")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Noir.ivory)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 错误占位（禁用/不存在/网络失败统一展示，不崩溃）

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Noir.textDim)
            Text("返回上一页继续浏览")
                .font(.system(size: 11))
                .foregroundStyle(Noir.textFaint)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 正文

    private func contentView(_ article: ArticleInfo) -> some View {
        let blocks = parseBlocks(article.content)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 标题（大字号衬线，对齐安卓 20sp SemiBold Serif，行高 28sp）
                Text(article.title ?? "")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .lineSpacing(8)
                    .foregroundStyle(Noir.ivory)

                // 发布时间 · 浏览次数（次要色一行；时间口径与帖子详情一致）
                HStack(spacing: 10) {
                    if let ts = article.publishTime {
                        Text(PostDetailView.formatTime(ts))
                    }
                    Text("浏览 \(PostDetailView.formatCount(article.browseCount ?? 0))")
                }
                .font(.system(size: 11))
                .foregroundStyle(Noir.textFaint)
                .padding(.top, 10)

                // 正文块流（文字/全宽图片混排，块间距对齐安卓 14dp、正文首块前 18dp）
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    blockView(for: block)
                        .padding(.top, index == 0 ? 18 : 14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func blockView(for block: ArticleBlock) -> some View {
        switch block.type {
        case "text":
            // 对齐安卓：13.5sp / 行高 22sp / 白 70%
            Text(block.value ?? "")
                .font(.system(size: 13.5))
                .lineSpacing(8.5)
                .foregroundStyle(Color.white.opacity(0.7))
        case "image":
            ArticleImageView(rawUrl: block.url)
        default:
            EmptyView()
        }
    }
}

// MARK: - 正文块解析（对齐安卓 parseBlocks）

/// 正文块：{"type":"text","value":"..."} / {"type":"image","url":"..."}
private struct ArticleBlock: Decodable {
    let type: String?
    let value: String?
    let url: String?
}

/// 解析 content JSON 为块列表；解析失败按空正文处理（不崩）；未知类型/缺字段的块跳过
private func parseBlocks(_ content: String?) -> [ArticleBlock] {
    guard let content, !content.isEmpty,
          let data = content.data(using: .utf8),
          let blocks = try? JSONDecoder().decode([ArticleBlock].self, from: data) else { return [] }
    return blocks.filter {
        ($0.type == "text" && !($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            ($0.type == "image" && !($0.url ?? "").isEmpty)
    }
}

// MARK: - 正文图片块

/// 正文图片：全宽按比例自适应（对齐安卓 ContentScale.FillWidth）。
/// WebImage 是 scaledToFill + Color.clear 底座（高度需外部给定），不适合按比例自适应；
/// 这里复用其加载链路（webImageURL 归一化 + WebImageCache 内存缓存），自行按 scaledToFit 渲染。
private struct ArticleImageView: View {

    let rawUrl: String?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                // 加载中/失败不占位（对齐安卓 Coil 无占位行为：未加载时高度塌缩为 0）
                Color.clear.frame(height: 0)
            }
        }
        .task(id: rawUrl) { await load() }
    }

    private func load() async {
        image = nil
        guard let url = webImageURL(rawUrl) else { return }
        if let cached = WebImageCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let img = UIImage(data: data) else { return }
            WebImageCache.shared.setObject(img, forKey: url as NSURL)
            guard !Task.isCancelled else { return }
            image = img
        } catch {
            // 失败保持空（与安卓失败静默一致）
        }
    }
}
