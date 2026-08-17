import SwiftUI

/// 礼物统一渲染（对齐安卓 GiftIcon）：svga → SvgaView 动效；glb → 静态兜底（iOS 暂无 3D 引擎）；
/// 普通图片 → AsyncImage；内置渲染键 gift2d:/gift3d: → 图标兜底
struct GiftIconView: View {
    let icon: String?
    var size: CGFloat = 56
    /// iconScale 百分比缩放（100=原始）
    var scale: CGFloat = 1.0

    var body: some View {
        let kind = giftRenderKindOf(icon)
        Group {
            if let kind, kind.0 == "svga" {
                SvgaView(url: kind.1)
            } else if let kind, kind.0 == "glb" {
                // GLB 3D 素材：iOS 端暂无 3D 引擎，占位图标
                Image(systemName: "rotate.3d")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Noir.gold.opacity(0.6))
            } else if let icon, icon.hasPrefix("http"), let url = URL(string: icon) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: size * scale, height: size * scale)
        .allowsHitTesting(false)
    }

    private var placeholderIcon: some View {
        Image(systemName: "gift.fill")
            .font(.system(size: size * 0.45))
            .foregroundStyle(Noir.gold.opacity(0.6))
    }
}

/// 全屏赠送动效（对齐安卓 GiftSendOverlay：升起 + 放大 + 连击数，2.4s 或点击关闭）
struct GiftSendOverlay: View {
    let gift: GiftItem
    let combo: Int
    let onDone: () -> Void

    @State private var progress: CGFloat = 0

    // rise-fade 关键帧（对齐安卓）：0% 下60/0.6倍/透明 → 20% 全显 → 70% 上移/1.05 → 100% 消失
    private var translateY: CGFloat {
        switch progress {
        case ..<0.2: return 60 * (1 - progress / 0.2)
        case ..<0.7: return -30 * ((progress - 0.2) / 0.5)
        default: return -30 - 60 * ((progress - 0.7) / 0.3)
        }
    }
    private var scale: CGFloat {
        switch progress {
        case ..<0.2: return 0.6 + 0.45 * (progress / 0.2)
        case ..<0.7: return 1.05
        default: return 1
        }
    }
    private var alpha: CGFloat {
        switch progress {
        case ..<0.2: return progress / 0.2
        case ..<0.7: return 1
        default: return 1 - (progress - 0.7) / 0.3
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDone() }
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Noir.crimson.opacity(0.4), .clear],
                                             center: .center, startRadius: 0, endRadius: 140))
                        .frame(width: 280, height: 280)
                    GiftIconView(
                        icon: (gift.animationUrl?.isEmpty == false ? gift.animationUrl : gift.icon),
                        size: 220,
                        scale: CGFloat(gift.iconScale ?? 100) / 100
                    )
                }
                .padding(.bottom, 28)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(gift.name)
                        .font(.system(size: 22, design: .serif))
                        .italic()
                        .foregroundStyle(Noir.goldText)
                    Text("×\(combo)")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [Noir.crimsonHot, Noir.crimson], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .padding(.bottom, 8)
                Text("赠 予 心 动 的 人")
                    .font(.system(size: 11))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .offset(y: translateY)
            .scaleEffect(scale)
            .opacity(alpha)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.4)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { onDone() }
        }
    }
}
