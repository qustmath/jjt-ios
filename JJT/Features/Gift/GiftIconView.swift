import SwiftUI

/// 礼物统一渲染（对齐安卓 GiftIcon）：icon 五种形态——
/// 1. `gift2d:xxx` → 程序化 2D 动效（Gift2DRender）
/// 2. `gift3d:xxx` → 内置 GLB 3D 模型（Gift3DView）
/// 3. `*.svga` URL → SVGA 动效
/// 4. `*.glb` URL → 3D 模型（下载缓存后渲染）
/// 5. 其他 http(s) URL → 普通图片；空 → 兜底图标
///
/// [scale] 单礼物显示缩放（iconScale/100）：以盒子中心放大，不裁切、不影响布局（对齐安卓 graphicsLayer scale）
struct GiftIconView: View {
    let icon: String?
    var size: CGFloat = 56
    var scale: CGFloat = 1.0
    /// 3D 是否可交互（拖动旋转），舞台场景用
    var interactive3D: Bool = false

    var body: some View {
        let kind = giftRenderKindOf(icon)
        Group {
            switch kind?.0 {
            case "2d":
                Gift2DRender(id: kind!.1, size: size)
            case "3d", "glb":
                Gift3DView(source: kind!.1, interactive: interactive3D)
                    .frame(width: size, height: size)
            case "svga":
                SvgaView(url: kind!.1)
            default:
                if let icon, icon.hasPrefix("http"), let url = URL(string: icon) {
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
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
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
                        scale: CGFloat(gift.iconScale ?? 100) / 100,
                        interactive3D: true
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
