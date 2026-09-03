import SwiftUI

/// 礼物统一渲染（对齐安卓 GiftIcon 的 2D 子集；3D/GLB 已在 iOS 移除——解析即崩溃，见 2026-08 下线决定）——
/// 1. `gift2d:xxx` → 程序化 2D 动效（Gift2DRender）
/// 2. `*.svga` URL → SVGA 动效
/// 3. 其他 http(s) URL → 普通图片
/// 4. `gift3d:xxx` / `*.glb`（3D 礼物）→ 不解析，直接兜底图标（聊天/礼物墙收到 3D 礼物也不会触发 GLB 加载）
///
/// [scale] 单礼物显示缩放（iconScale/100）：以盒子中心放大，不裁切、不影响布局（对齐安卓 graphicsLayer scale）
struct GiftIconView: View {
    let icon: String?
    var size: CGFloat = 56
    var scale: CGFloat = 1.0

    var body: some View {
        let kind = giftRenderKindOf(icon)
        Group {
            switch kind?.0 {
            case "2d":
                Gift2DRender(id: kind!.1, size: size)
            case "svga":
                SvgaView(url: kind!.1)
            case "3d", "glb":
                // 3D 已下线：不加载 GLB，显示兜底图标
                placeholderIcon
            default:
                if let icon, icon.hasPrefix("http"), let url = URL(string: icon) {
                    WebImage(url: url, contentMode: .fit) { placeholderIcon }
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
/// 动画由 TimelineView 逐帧驱动（按墙钟时间计算进度），不依赖 withAnimation——
/// state 翻转动画在覆盖层 attach 时序下反复失效（progress 直跳终值导致全程透明），
/// TimelineView 只要可见就每帧重算，机制上不可能不动。
struct GiftSendOverlay: View {
    let gift: GiftItem
    let combo: Int
    let onDone: () -> Void

    private static let duration: Double = 2.4
    @State private var start = Date()

    // rise-fade 关键帧（对齐安卓）：0% 下60/0.6倍/透明 → 20% 全显 → 70% 上移/1.05 → 100% 消失
    private func translateY(_ p: Double) -> CGFloat {
        let p = CGFloat(p)
        switch p {
        case ..<0.2: return 60 * (1 - p / 0.2)
        case ..<0.7: return -30 * ((p - 0.2) / 0.5)
        default: return -30 - 60 * ((p - 0.7) / 0.3)
        }
    }
    private func scale(_ p: Double) -> CGFloat {
        let p = CGFloat(p)
        switch p {
        case ..<0.2: return 0.6 + 0.45 * (p / 0.2)
        case ..<0.7: return 1.05
        default: return 1
        }
    }
    private func alpha(_ p: Double) -> Double {
        switch p {
        case ..<0.2: return p / 0.2
        case ..<0.7: return 1
        default: return 1 - (p - 0.7) / 0.3
        }
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let p = min(max(tl.date.timeIntervalSince(start) / Self.duration, 0), 1)
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
                .offset(y: translateY(p))
                .scaleEffect(scale(p))
                .opacity(alpha(p))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.1) { onDone() }
        }
    }
}
