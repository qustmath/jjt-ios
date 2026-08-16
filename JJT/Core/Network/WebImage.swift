import SwiftUI

/// 图片 URL 归一化（对齐安卓 usesCleartextTraffic=true 的容忍度）：
/// 1. 相对路径（/upload/x.jpg）→ 拼 API 域名
/// 2. 协议相对（//cdn/x.jpg）→ 补 https
/// 3. http 明文原样返回（Info.plist 已放行 ATS，与安卓一致）
/// 空串/非法返回 nil（调用方显示占位）。
func webImageURL(_ raw: String?) -> URL? {
    guard let raw else { return nil }
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.hasPrefix("//") {
        s = "https:" + s
    } else if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
        let base = Config.apiBaseURL.absoluteString.hasSuffix("/")
            ? Config.apiBaseURL.absoluteString
            : Config.apiBaseURL.absoluteString + "/"
        s = s.hasPrefix("/") ? base + s.dropFirst() : base + s
    }
    return URL(string: s)
}

/// 全 App 共享的内存图片缓存
enum WebImageCache {
    static let shared: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 200
        return c
    }()
}

/// 网络图片（替代 AsyncImage：URL 归一化 + 内存缓存 + 取消/复用友好）。
/// 加载中/失败均显示 placeholder，与安卓 Coil 的占位行为对齐。
struct WebImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, contentMode: ContentMode = .fill,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        // 关键：以 Color.clear 为底座——它总是服从外部 frame 提议，
        // 避免图片按自身像素尺寸无限撑大（ScrollView 内高度无界时会整页撑爆）
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder()
                }
            }
            .clipped()
            .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        guard let url else { return }
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
            // 失败保持占位（与安卓失败静默一致）
        }
    }
}

extension WebImage where Placeholder == Color {
    /// 默认占位：noir2 近黑底（对齐安卓 AsyncImage 无占位时的底色）
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { Noir.noir2 }
    }
}
