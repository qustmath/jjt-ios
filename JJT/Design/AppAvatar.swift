import SwiftUI

/// 统一头像组件（对齐安卓 AppAvatar）：有头像显示头像，无头像显示默认图标。
/// frameURL：会员头像框（透明底静态图，后台上传），以画布中心对齐头像中心叠加，
/// frameScale 为整体外扩比例（默认 1.25，对齐安卓卡片用法）。
/// 注意：SVG/SVGA 动效素材 iOS 原生不支持，仅 PNG/JPG 有效（后续按需接 SVGKit/SVGAPlayer）。
struct AppAvatar: View {
    let url: String?
    var size: CGFloat = 36
    var frameURL: String? = nil
    var frameScale: CGFloat = 1.25

    var body: some View {
        ZStack {
            AsyncImage(url: webImageURL(url)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(Noir.gold.opacity(0.4))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if let frameURL, !frameURL.isEmpty {
                if frameURL.lowercased().hasSuffix(".svga") {
                    // SVGA 动框（SVGAPlayer 播放，全局缓存解析结果）
                    SvgaView(url: frameURL)
                        .frame(width: size * frameScale, height: size * frameScale)
                        .allowsHitTesting(false)
                } else if let fURL = webImageURL(frameURL) {
                    AsyncImage(url: fURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        }
                    }
                    .frame(width: size * frameScale, height: size * frameScale)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
