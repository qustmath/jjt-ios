import SwiftUI

/// 整蛊会话级状态（对齐安卓 PrankState）：
/// 3 秒内连击同一头像 5 下 → 弹特效选择窗；点其他头像计数清零；
/// 触发后 5 秒冷却；单击 380ms 无后续 → 正常单击行为
@MainActor
final class PrankState: ObservableObject {

    @Published var effects: [PrankEffectInfo] = []
    @Published var pickerVisible = false
    /// 正在播放的特效：key + 目标头像实例 id（气泡 localId）
    @Published var playing: (key: String, targetId: String)?
    @Published var purchasing: PrankEffectInfo?
    @Published var purchasingBusy = false

    private var coolUntil: TimeInterval = 0
    private var tapMap: [String: [TimeInterval]] = [:]
    private var pendingTargetId = ""

    func loadEffects() {
        Task {
            effects = (try? await PrankAPI.list()) ?? effects
        }
    }

    /// 头像点击入口。onSingleTap = 单击行为（380ms 无后续才执行）
    func onAvatarTap(tapKey: String, targetId: String, onSingleTap: @escaping () -> Void) {
        let now = Date().timeIntervalSince1970
        if now < coolUntil { return } // 冷却中，吞掉点击
        var taps = (tapMap[tapKey] ?? []).filter { now - $0 <= 3 }
        taps.append(now)
        tapMap[tapKey] = taps
        // 点其他头像计数清零
        for key in tapMap.keys where key != tapKey { tapMap[key] = [] }

        if taps.count >= 5 {
            tapMap[tapKey] = []
            coolUntil = now + 5
            playing = nil
            pendingTargetId = targetId
            if effects.isEmpty { loadEffects() }
            withAnimation { pickerVisible = true }
            return
        }
        // 单击延迟判定
        let countAtTap = taps.count
        Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            let current = tapMap[tapKey] ?? []
            if current.count == countAtTap {
                tapMap[tapKey] = []
                onSingleTap()
            }
        }
    }

    func closePicker() { pickerVisible = false }

    /// 选择窗点特效：已解锁直接播，未解锁弹购买确认
    func onEffectClick(_ effect: PrankEffectInfo) {
        if effect.unlocked == true || (effect.price ?? 0) <= 0 {
            pickerVisible = false
            play(effect)
        } else {
            purchasing = effect
        }
    }

    func play(_ effect: PrankEffectInfo) {
        guard let key = effect.effectKey else { return }
        playing = (key, pendingTargetId)
        // 1.4s 后自动结束
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if playing?.targetId == pendingTargetId { playing = nil }
        }
    }

    /// 确认购买（3 天卡）
    func confirmPurchase() {
        guard let effect = purchasing, !purchasingBusy else { return }
        purchasingBusy = true
        Task {
            do {
                _ = try await PrankAPI.purchase(effectId: effect.id)
                purchasingBusy = false
                purchasing = nil
                pickerVisible = false
                jjtShowToast("已解锁「\(effect.name ?? "")」3 天")
                loadEffects()
                play(effect)
            } catch {
                purchasingBusy = false
                purchasing = nil
                jjtShowToast(error.localizedDescription)
            }
        }
    }
}

// MARK: - 整蛊头像（连击入口 + 特效播放层，对齐安卓 PrankAvatar）

struct PrankAvatar: View {
    let url: String?
    var size: CGFloat = 38
    var frameURL: String? = nil
    var frameScale: CGFloat = 1.0
    let tapKey: String
    let targetId: String
    @ObservedObject var prank: PrankState
    var onSingleTap: @escaping () -> Void

    @State private var fxT: Double = 0

    private var isTarget: Bool { prank.playing?.targetId == targetId }
    private var fxKey: String? { isTarget ? prank.playing?.key : nil }

    var body: some View {
        ZStack {
            AppAvatar(url: url, size: size, frameURL: frameURL, frameScale: frameScale)
                .frame(width: size, height: size)
                .modifier(PrankShakeModifier(key: fxKey, t: fxT))

            // 特效层（相对本头像定位，可溢出不被裁剪）
            if let fxKey {
                switch fxKey {
                case "shatter": ShatterFx(size: size, url: url)
                case "slap": SlapFx(size: size)
                case "wax": WaxFx(size: size)
                default: EmptyView() // shake 仅本体颤动
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            prank.onAvatarTap(tapKey: tapKey, targetId: targetId, onSingleTap: onSingleTap)
        }
        .onChange(of: isTarget) { _, v in
            if v {
                fxT = 0
                withAnimation(.linear(duration: 1.4)) { fxT = 1 }
            }
        }
    }
}

/// shake / slap 的本体颤动修饰（对齐安卓 PrankAvatar graphicsLayer）
private struct PrankShakeModifier: ViewModifier {
    let key: String?
    let t: Double

    func body(content: Content) -> some View {
        switch key {
        case "shake":
            let decay = 1 - t * 0.5
            content
                .offset(x: sin(t * 60) * 3.5 * decay, y: cos(t * 47) * 2 * decay)
                .rotationEffect(.degrees(sin(t * 55) * 3 * decay))
        case "slap":
            let s = 1 - abs(sin(t * 18)) * 0.12 * (1 - t)
            content
                .rotationEffect(.degrees(sin(t * 18) * 12 * (1 - t)))
                .scaleEffect(s)
        default:
            content
        }
    }
}

// MARK: - 特效动画（按头像尺寸渲染，对齐安卓 PrankOverlay 简化移植）

/// 碎裂：6 块多边形切片飞散
private struct ShatterFx: View {
    let size: CGFloat
    let url: String?

    @State private var p: Double = 0

    private static let shards: [(poly: [CGPoint], dx: CGFloat, dy: CGFloat, rot: Double)] = [
        ([CGPoint(x: 0, y: 0), CGPoint(x: 0.55, y: 0), CGPoint(x: 0.40, y: 0.45), CGPoint(x: 0, y: 0.30)], -20, -24, -38),
        ([CGPoint(x: 0.55, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 0.35), CGPoint(x: 0.40, y: 0.45)], 22, -26, 30),
        ([CGPoint(x: 0, y: 0.30), CGPoint(x: 0.40, y: 0.45), CGPoint(x: 0.30, y: 1), CGPoint(x: 0, y: 1)], -24, 22, -24),
        ([CGPoint(x: 0.40, y: 0.45), CGPoint(x: 0.65, y: 0.55), CGPoint(x: 0.60, y: 1), CGPoint(x: 0.30, y: 1)], -3, 28, 12),
        ([CGPoint(x: 0.40, y: 0.45), CGPoint(x: 1, y: 0.35), CGPoint(x: 1, y: 0.70), CGPoint(x: 0.65, y: 0.55)], 26, 4, 44),
        ([CGPoint(x: 0.65, y: 0.55), CGPoint(x: 1, y: 0.70), CGPoint(x: 1, y: 1), CGPoint(x: 0.60, y: 1)], 20, 25, -16),
    ]

    var body: some View {
        ForEach(Array(Self.shards.enumerated()), id: \.offset) { i, shard in
            let sp = min(max((p * 1400 - Double(i) * 40) / 1200, 0), 1)
            if sp > 0 && sp < 1 {
                Polygon(points: shard.poly.map { CGPoint(x: $0.x * size, y: $0.y * size) })
                    .fill(Color(red: 0x1A/255, green: 0x0C/255, blue: 0x10/255))
                    .overlay(Polygon(points: shard.poly.map { CGPoint(x: $0.x * size, y: $0.y * size) })
                        .stroke(Noir.goldLight.opacity(0.6), lineWidth: 0.8))
                    .frame(width: size, height: size)
                    .offset(x: shard.dx * sp, y: shard.dy * sp)
                    .rotationEffect(.degrees(shard.rot * sp))
                    .opacity(sp < 0.7 ? 1 : 1 - (sp - 0.7) / 0.3)
            }
        }
        .onAppear { withAnimation(.linear(duration: 1.4)) { p = 1 } }
    }
}

/// 拍打：红色掌印闪现
private struct SlapFx: View {
    let size: CGFloat
    @State private var p: Double = 0

    var body: some View {
        Text("🖐️")
            .font(.system(size: size * 0.7))
            .rotationEffect(.degrees(-25 + 25 * p))
            .scaleEffect(0.5 + 0.7 * min(p * 3, 1))
            .opacity(p < 0.6 ? 1 : 1 - (p - 0.6) / 0.4)
            .onAppear { withAnimation(.linear(duration: 1.4)) { p = 1 } }
    }
}

/// 蜡滴：蜡烛 + 滴落
private struct WaxFx: View {
    let size: CGFloat
    @State private var p: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("🕯️")
                .font(.system(size: size * 0.5))
                .opacity(min(p * 3, 1))
            Circle()
                .fill(Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255))
                .frame(width: 5, height: 5)
                .offset(y: p * size * 0.8)
                .opacity(p > 0.15 && p < 0.9 ? 1 : 0)
        }
        .offset(y: -size * 0.4)
        .onAppear { withAnimation(.linear(duration: 1.4)) { p = 1 } }
    }
}

private struct Polygon: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for pt in points.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }
}

// MARK: - 特效选择窗 + 购买确认（对齐安卓 PrankOverlay）

struct PrankOverlayHost: View {
    @ObservedObject var prank: PrankState

    var body: some View {
        ZStack {
            if prank.pickerVisible {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { prank.closePicker() }
                VStack(spacing: 14) {
                    Text("选择整蛊特效")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .tracking(2)
                        .foregroundStyle(Noir.goldText)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(prank.effects) { effect in
                            effectCell(effect)
                        }
                    }
                }
                .padding(20)
                .frame(width: 300)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: prank.pickerVisible)
        .alert("解锁特效", isPresented: Binding(
            get: { prank.purchasing != nil },
            set: { if !$0 { prank.purchasing = nil } }
        )) {
            Button("确认解锁") { prank.confirmPurchase() }
            Button("取消", role: .cancel) { prank.purchasing = nil }
        } message: {
            if let e = prank.purchasing {
                Text("「\(e.name ?? "")」\(e.price ?? 0) 兔币 / 3 天，确认解锁？")
            }
        }
    }

    private func effectCell(_ effect: PrankEffectInfo) -> some View {
        let emoji: String = {
            switch effect.effectKey {
            case "shatter": return "💥"
            case "shake": return "📳"
            case "slap": return "🖐️"
            case "wax": return "🕯️"
            default: return "✨"
            }
        }()
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                                         center: .center, startRadius: 0, endRadius: 30))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
                Text(emoji)
                    .font(.system(size: 19))
            }
            Text(effect.name ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
            Text(effect.nameEn ?? "")
                .font(.system(size: 7, design: .serif))
                .italic()
                .tracking(2)
                .foregroundStyle(.white.opacity(0.3))
            if (effect.price ?? 0) <= 0 {
                Text("免费")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0x7B/255, green: 0xD8/255, blue: 0x8F/255))
            } else if effect.unlocked == true {
                Text("已解锁·剩\(prankRemainDays(effect.expireTime))天")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.goldLight)
            } else {
                Text("🔒 \(effect.price ?? 0)兔币/3天")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.5), Color(red: 0x10/255, green: 0x08/255, blue: 0x0A/255).opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { prank.onEffectClick(effect) }
    }
}
