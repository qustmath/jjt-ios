import SwiftUI
import SVGAPlayer

/// SVGA 动效视图（会员头像框等），对齐安卓 SvgaView。
///
/// 解析结果（SVGAVideoEntity）全局内存缓存：头像框常出现在列表中，
/// 同一素材只下载/解析一次，多个视图可共享同一 videoItem 各自播放。
/// 无限循环播放；解析失败记 nil 不重试（对齐安卓 SvgaEntityCache）。
struct SvgaView: UIViewRepresentable {
    let url: String

    final class Coordinator {
        var loadedURL: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SVGAImageView {
        let view = SVGAImageView(frame: .zero)
        view.loops = 0                 // 无限循环
        view.clearsAfterStop = false   // 停止后保留最后一帧
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SVGAImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        let target = url
        Task {
            let item = await SvgaEntityCache.load(target)
            await MainActor.run {
                // 回到主线程时 url 可能已变（复用 cell），二次校验
                guard context.coordinator.loadedURL != target else { return }
                context.coordinator.loadedURL = target
                if let item {
                    uiView.videoItem = item
                    uiView.startAnimation()
                }
            }
        }
    }
}

/// videoItem 全局缓存：url → 解析结果（nil 表示解析失败，不重试）；并发请求合并
actor SvgaEntityCache {

    static let shared = SvgaEntityCache()

    private var map: [String: SVGAVideoEntity?] = [:]
    private var inflight: [String: Task<SVGAVideoEntity?, Never>] = [:]

    static func load(_ url: String) async -> SVGAVideoEntity? {
        await shared.get(url)
    }

    private func get(_ url: String) async -> SVGAVideoEntity? {
        if let cached = map[url] { return cached }
        if let task = inflight[url] { return await task.value }
        let task = Task<SVGAVideoEntity?, Never> { await Self.parse(url) }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        map[url] = result
        return result
    }

    private static func parse(_ urlString: String) async -> SVGAVideoEntity? {
        guard let url = URL(string: urlString) else { return nil }
        return await withCheckedContinuation { cont in
            SVGAParser().parse(with: url, completionBlock: { entity in
                cont.resume(returning: entity)
            }, failureBlock: { _ in
                cont.resume(returning: nil)
            })
        }
    }
}
