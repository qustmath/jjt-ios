import SwiftUI

// ════════════════════════════════════════════════════════════
// 2D 动效礼物（1:1 移植安卓 Gift2DRender：纯 SVG 路径 + 动画）
// id: rose / heart2d / wine / crown2d / mask
// ════════════════════════════════════════════════════════════

struct Gift2DRender: View {
    let id: String
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let c = GiftClocks.at(context.date.timeIntervalSince1970)
            Group {
                switch id {
                case "rose": NoirRose(size: size, c: c)
                case "heart2d": ThornHeart(size: size, c: c)
                case "wine": BloodWine(size: size, c: c)
                case "crown2d": NightCrown(size: size, c: c)
                case "mask": PhantomMask(size: size, c: c)
                default: NoirRose(size: size, c: c)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// 动画时钟（对齐安卓 rememberGiftClocks 各通道周期）
struct GiftClocks {
    let heartbeat: CGFloat   // 1.6s
    let floaty: CGFloat      // 3.2s
    let sway: CGFloat        // 2.6s
    let swirl: CGFloat       // 3.0s → 0..360
    let bloom: CGFloat       // 2.4s 往返
    let petal: CGFloat       // 2.8s
    let glint: CGFloat       // 1.8s
    let shine: CGFloat       // 2.6s
    let drip: CGFloat        // 2.2s

    static func at(_ t: TimeInterval) -> GiftClocks {
        func loop(_ period: Double) -> CGFloat { CGFloat((t / period).truncatingRemainder(dividingBy: 1)) }
        func pingpong(_ period: Double) -> CGFloat {
            let x = (t / period).truncatingRemainder(dividingBy: 2)
            return CGFloat(x < 1 ? x : 2 - x)
        }
        return GiftClocks(
            heartbeat: loop(1.6), floaty: loop(3.2), sway: loop(2.6),
            swirl: CGFloat(t.truncatingRemainder(dividingBy: 3.0) / 3.0) * 360,
            bloom: pingpong(2.4), petal: loop(2.8), glint: loop(1.8),
            shine: loop(2.6), drip: loop(2.2)
        )
    }
}

// MARK: - Canvas 辅助

private extension GraphicsContext {
    /// 绕任意轴心旋转绘制（Compose rotate(deg, pivot) 等价）
    func drawRotated(degrees: CGFloat, pivot: CGPoint, draw: (inout GraphicsContext) -> Void) {
        drawLayer { ctx in
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: .degrees(degrees))
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
            draw(&ctx)
        }
    }
}

private func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
}

private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}

// MARK: - 星形闪光

private struct GlintStar: View {
    let size: CGFloat
    let t: CGFloat
    let leftFrac: CGFloat
    let topFrac: CGFloat
    let color: Color

    var body: some View {
        let a = sin(t * .pi)
        Canvas { ctx, sz in
            let k = sz.width * 0.13 / 12
            let star = SVGPathParser.parse("M6 0 L7.4 4.6 L12 6 L7.4 7.4 L6 12 L4.6 7.4 L0 6 L4.6 4.6Z", scale: k)
            ctx.opacity = max(0, min(1, a))
            ctx.translateBy(x: sz.width * 0.13 / 2, y: sz.width * 0.13 / 2)
            let s = 0.4 + 0.8 * a
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -sz.width * 0.13 / 2, y: -sz.width * 0.13 / 2)
            ctx.fill(star, with: .color(color))
        } symbols: { EmptyView() }
        .frame(width: size * 0.13, height: size * 0.13)
        .offset(x: size * leftFrac, y: size * topFrac)
        .allowsHitTesting(false)
    }
}

// MARK: - 暗夜玫瑰

private struct NoirRose: View {
    let size: CGFloat
    let c: GiftClocks

    var body: some View {
        let s = 0.75 + 0.31 * c.bloom
        let a = 0.7 + 0.3 * c.bloom
        ZStack {
            Canvas { ctx, sz in
                let k = sz.width / 100
                func p(_ v: CGFloat) -> CGFloat { v * k }
                ctx.opacity = a
                ctx.drawRotated(degrees: 0, pivot: .zero) { $0.scaleBy(x: s, y: s) ; drawRose(&$0, p: p) }
            } symbols: { EmptyView() }
            PetalView(size: size, t: c.petal, delayFrac: 0.14, leftFrac: 0.55, topFrac: 0.12,
                      color: Color(red: 0xA3/255, green: 0x12/255, blue: 0x2D/255), sizeFrac: 0.14)
            PetalView(size: size, t: c.petal, delayFrac: 0.57, leftFrac: 0.35, topFrac: 0.08,
                      color: Color(red: 0x7A/255, green: 0x0A/255, blue: 0x1C/255), sizeFrac: 0.11)
        }
        .frame(width: size, height: size)
    }

    private func drawRose(_ ctx: inout GraphicsContext, p: (CGFloat) -> CGFloat) {
        // 花茎
        ctx.stroke(SVGPathParser.parse("M50 62 C48 76 47 86 50 98", scale: 1).applying(CGAffineTransform(scaleX: p(1), y: p(1))),
                   with: .linearGradient(Gradient(colors: [Color(red: 0x4C/255, green: 0x7A/255, blue: 0x3F/255),
                                                            Color(red: 0x2E/255, green: 0x4A/255, blue: 0x26/255)]),
                                         startPoint: CGPoint(x: p(50), y: p(62)), endPoint: CGPoint(x: p(50), y: p(98))),
                   style: StrokeStyle(lineWidth: p(3.5)))
        // 叶
        ctx.fill(SVGPathParser.parse("M50 82 C42 78 36 80 32 86 C39 88 46 88 50 82Z", scale: p(1)),
                 with: .color(Color(red: 0x3A/255, green: 0x5C/255, blue: 0x2F/255)))
        // 外层花瓣 ×6
        let roseGradient = Gradient(colors: [Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255),
                                             Color(red: 0xA3/255, green: 0x12/255, blue: 0x2D/255),
                                             Color(red: 0x4A/255, green: 0x05/255, blue: 0x12/255)])
        for r in [0, 60, 120, 180, 240, 300] {
            ctx.drawRotated(degrees: CGFloat(r), pivot: CGPoint(x: p(50), y: p(46))) { c in
                c.opacity = 0.95
                c.fill(ellipse(p(31), p(28), p(38), p(24)),
                       with: .radialGradient(roseGradient, center: CGPoint(x: p(50), y: p(40)),
                                             startRadius: 0.01, endRadius: p(26)))
            }
        }
        // 内层花瓣 ×6
        for r in [30, 90, 150, 210, 270, 330] {
            ctx.drawRotated(degrees: CGFloat(r), pivot: CGPoint(x: p(50), y: p(46))) { c in
                c.opacity = 0.95
                c.fill(ellipse(p(38), p(34.5), p(24), p(15)),
                       with: .color(Color(red: 0xD8/255, green: 0x23/255, blue: 0x46/255)))
            }
        }
        ctx.fill(circle(p(50), p(46), p(6.5)), with: .color(Color(red: 0x6D/255, green: 0x0A/255, blue: 0x1D/255)))
        ctx.fill(circle(p(50), p(46), p(3)), with: .color(Color(red: 0x3D/255, green: 0x05/255, blue: 0x11/255)))
    }
}

// MARK: - 飘落花瓣

private struct PetalView: View {
    let size: CGFloat
    let t: CGFloat
    let delayFrac: CGFloat
    let leftFrac: CGFloat
    let topFrac: CGFloat
    let color: Color
    let sizeFrac: CGFloat

    var body: some View {
        let tt = (t + delayFrac).truncatingRemainder(dividingBy: 1)
        let alpha = tt < 0.15 ? tt / 0.15 : 1 - tt
        let dx = -14 * tt
        let dy = -8 + 54 * tt
        Canvas { ctx, sz in
            ctx.opacity = max(0, min(1, alpha))
            ctx.drawRotated(degrees: -160 * tt, pivot: CGPoint(x: sz.width / 2, y: sz.height / 2)) { c in
                c.fill(ellipse(0, sz.height * 0.2, sz.width, sz.height * 0.6), with: .color(color))
            }
        } symbols: { EmptyView() }
        .frame(width: size * sizeFrac, height: size * sizeFrac)
        .offset(x: size * leftFrac + dx * (size / 100), y: size * topFrac + dy * (size / 100))
        .allowsHitTesting(false)
    }
}

// MARK: - 荆棘之心

private struct ThornHeart: View {
    let size: CGFloat
    let c: GiftClocks

    var body: some View {
        let hb = c.heartbeat
        let s: CGFloat = hb < 0.14 ? 1 + 0.14 * (hb / 0.14)
            : hb < 0.28 ? 1.14 - 0.17 * ((hb - 0.14) / 0.14)
            : hb < 0.42 ? 0.97 + 0.13 * ((hb - 0.28) / 0.14)
            : hb < 0.7 ? 1.1 - 0.1 * ((hb - 0.42) / 0.28)
            : 1
        ZStack {
            Canvas { ctx, sz in
                let k = sz.width / 100
                func p(_ v: CGFloat) -> CGFloat { v * k }
                ctx.scaleBy(x: s, y: s)
                let heartGradient = Gradient(colors: [Color(red: 0xFF/255, green: 0x4D/255, blue: 0x6A/255),
                                                      Color(red: 0xCF/255, green: 0x12/255, blue: 0x33/255),
                                                      Color(red: 0x8E/255, green: 0x11/255, blue: 0x26/255)])
                ctx.fill(SVGPathParser.parse("M50 84 C20 62 10 44 14 30 C18 17 34 14 43 24 C47 28 50 33 50 33 C50 33 53 28 57 24 C66 14 82 17 86 30 C90 44 80 62 50 84Z", scale: p(1)),
                         with: .radialGradient(heartGradient, center: CGPoint(x: p(42), y: p(35)),
                                               startRadius: 0.01, endRadius: p(75)))
                // 荆棘缠绕
                ctx.stroke(SVGPathParser.parse("M30 30 C26 24 20 24 17 28 M70 30 C74 24 80 24 83 28", scale: p(1)),
                           with: .color(Color(red: 0x2A/255, green: 0x2A/255, blue: 0x30/255)),
                           style: StrokeStyle(lineWidth: p(3.4), lineCap: .round))
                // 荆棘刺
                ctx.fill(SVGPathParser.parse("M22 44 l-7 -3 5 7z M78 44 l7 -3 -5 7z M50 80 l-4 8 4 -3 4 3z", scale: p(1)),
                         with: .color(Color(red: 0x1C/255, green: 0x1C/255, blue: 0x22/255)))
                // 高光
                ctx.drawRotated(degrees: -18, pivot: CGPoint(x: p(38), y: p(34))) { c in
                    c.fill(ellipse(p(31), p(29.5), p(14), p(9)), with: .color(.white.opacity(0.28)))
                }
            } symbols: { EmptyView() }
            // 滴落的血光
            let dripA = c.drip < 0.3 ? c.drip / 0.3 : 1 - (c.drip - 0.3) / 0.7
            Canvas { ctx, sz in
                ctx.fill(ellipse(0, 0, sz.width, sz.height),
                         with: .linearGradient(Gradient(colors: [Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255),
                                                                  Color(red: 0x7A/255, green: 0x0A/255, blue: 0x1C/255)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
            } symbols: { EmptyView() }
            .frame(width: 5, height: 9)
            .opacity(max(0, min(1, dripA)))
            .offset(y: (-4 + 20 * c.drip) * (size / 100))
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 血钻红酒

private struct BloodWine: View {
    let size: CGFloat
    let c: GiftClocks

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let k = sz.width / 100
                func p(_ v: CGFloat) -> CGFloat { v * k }
                let bowl = "M28 14 C28 48 38 58 50 58 C62 58 72 48 72 14 Z"
                ctx.fill(SVGPathParser.parse(bowl, scale: p(1)),
                         with: .color(Color(red: 0x14/255, green: 0x08/255, blue: 0x0C/255).opacity(0.55)))
                ctx.stroke(SVGPathParser.parse(bowl, scale: p(1)),
                           with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: p(1.6)))
                // 酒液（旋转液面）
                ctx.drawRotated(degrees: c.swirl, pivot: CGPoint(x: p(50), y: p(44))) { c in
                    c.opacity = 0.92
                    c.fill(SVGPathParser.parse("M33 34 C40 30 46 38 50 34 C54 30 60 38 67 34 L67 44 C67 52 58 54 50 54 C42 54 33 52 33 44 Z", scale: p(1)),
                           with: .linearGradient(Gradient(colors: [Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255),
                                                                    Color(red: 0x5C/255, green: 0x0A/255, blue: 0x16/255)]),
                                                 startPoint: CGPoint(x: p(50), y: p(30)), endPoint: CGPoint(x: p(50), y: p(54))))
                    c.fill(ellipse(p(42), p(38.4), p(8), p(3.2)), with: .color(Color(red: 0xFF/255, green: 0x78/255, blue: 0x8C/255).opacity(0.5)))
                }
                // 杯身高光
                ctx.stroke(SVGPathParser.parse("M28 14 C28 48 38 58 50 58 C62 58 72 48 72 14", scale: p(1)),
                           with: .linearGradient(Gradient(colors: [.white.opacity(0.05), .white.opacity(0.22), .white.opacity(0.05)]),
                                                 startPoint: CGPoint(x: p(28), y: 0), endPoint: CGPoint(x: p(72), y: 0)),
                           style: StrokeStyle(lineWidth: p(1.2)))
                // 杯梗杯座
                ctx.fill(Path(CGRect(x: p(48.4), y: p(58), width: p(3.2), height: p(24))), with: .color(.white.opacity(0.3)))
                ctx.fill(ellipse(p(34), p(81.4), p(32), p(7.2)), with: .color(.white.opacity(0.18)))
                ctx.stroke(ellipse(p(34), p(81.4), p(32), p(7.2)), with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: p(1)))
                // 杯口血钻
                let gemA = 1 - 0.6 * (0.5 + 0.5 * sin(c.heartbeat * 2 * .pi))
                ctx.fill(circle(p(72), p(14), p(4)), with: .color(Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255).opacity(gemA)))
            } symbols: { EmptyView() }
            GlintStar(size: size, t: c.glint, leftFrac: 0.24, topFrac: 0.18, color: .white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 暗夜王冠

private struct NightCrown: View {
    let size: CGFloat
    let c: GiftClocks

    var body: some View {
        let dy = -10 * sin(c.floaty * .pi)
        let rot = -2 + 4 * c.floaty
        ZStack {
            Canvas { ctx, sz in
                let k = sz.width / 100
                func p(_ v: CGFloat) -> CGFloat { v * k }
                let crownGradient = Gradient(colors: [Color(red: 0xF0/255, green: 0xDB/255, blue: 0xA8/255),
                                                      Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255),
                                                      Color(red: 0x7A/255, green: 0x5C/255, blue: 0x26/255)])
                let outline = "M18 66 L14 34 L32 50 L50 24 L68 50 L86 34 L82 66 Z"
                ctx.fill(SVGPathParser.parse(outline, scale: p(1)),
                         with: .linearGradient(crownGradient, startPoint: CGPoint(x: p(50), y: p(24)), endPoint: CGPoint(x: p(50), y: p(66))))
                ctx.stroke(SVGPathParser.parse(outline, scale: p(1)),
                           with: .color(Color(red: 0x5A/255, green: 0x43/255, blue: 0x18/255)), style: StrokeStyle(lineWidth: p(1.4)))
                // 冠带
                let band = Path(roundedRect: CGRect(x: p(18), y: p(66), width: p(64), height: p(9)), cornerRadius: p(3))
                ctx.fill(band, with: .linearGradient(crownGradient, startPoint: CGPoint(x: p(50), y: p(66)), endPoint: CGPoint(x: p(50), y: p(75))))
                ctx.stroke(band, with: .color(Color(red: 0x5A/255, green: 0x43/255, blue: 0x18/255)), style: StrokeStyle(lineWidth: p(1.2)))
                // 红宝石
                let ruby = Color(red: 0xC4/255, green: 0x12/255, blue: 0x30/255)
                let darkRuby = Color(red: 0x8B/255, green: 0x0A/255, blue: 0x1E/255)
                ctx.fill(circle(p(50), p(24), p(4.6)), with: .color(ruby))
                ctx.stroke(circle(p(50), p(24), p(4.6)), with: .color(Color(red: 0xF0/255, green: 0xDB/255, blue: 0xA8/255)), style: StrokeStyle(lineWidth: p(1)))
                ctx.fill(circle(p(14), p(34), p(3.4)), with: .color(darkRuby))
                ctx.fill(circle(p(86), p(34), p(3.4)), with: .color(darkRuby))
                ctx.fill(circle(p(32), p(70.5), p(3)), with: .color(ruby))
                ctx.fill(circle(p(50), p(70.5), p(3.6)), with: .color(Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255)))
                ctx.fill(circle(p(68), p(70.5), p(3)), with: .color(ruby))
                // 黑钻
                let diamond = "M50 44 l7 8 -7 10 -7 -10z"
                ctx.fill(SVGPathParser.parse(diamond, scale: p(1)), with: .color(Color(red: 0x1C/255, green: 0x1C/255, blue: 0x22/255)))
                ctx.stroke(SVGPathParser.parse(diamond, scale: p(1)),
                           with: .color(Color(red: 0xF0/255, green: 0xDB/255, blue: 0xA8/255)), style: StrokeStyle(lineWidth: p(0.9)))
            } symbols: { EmptyView() }
            GlintStar(size: size, t: c.glint, leftFrac: 0.46, topFrac: 0.12, color: Color(red: 0xF5/255, green: 0xE3/255, blue: 0xB8/255))
            GlintStar(size: size, t: (c.glint + 0.5).truncatingRemainder(dividingBy: 1), leftFrac: 0.12, topFrac: 0.40, color: .white)
        }
        .frame(width: size, height: size)
        .offset(y: dy * (size / 100))
        .rotationEffect(.degrees(rot))
    }
}

// MARK: - 魅影面具

private struct PhantomMask: View {
    let size: CGFloat
    let c: GiftClocks

    var body: some View {
        let rot = -4 + 8 * (0.5 + 0.5 * sin(c.sway * 2 * .pi - .pi / 2))
        ZStack {
            Canvas { ctx, sz in
                let k = sz.width / 100
                func p(_ v: CGFloat) -> CGFloat { v * k }
                ctx.drawRotated(degrees: rot, pivot: CGPoint(x: p(50), y: 0)) { c in
                    let mask = "M14 40 C14 26 30 18 50 18 C70 18 86 26 86 40 C86 54 74 60 64 58 C58 57 54 52 50 52 C46 52 42 57 36 58 C26 60 14 54 14 40Z"
                    c.fill(SVGPathParser.parse(mask, scale: p(1)),
                           with: .linearGradient(Gradient(colors: [Color(red: 0x2A/255, green: 0x2A/255, blue: 0x32/255),
                                                                    Color(red: 0x10/255, green: 0x10/255, blue: 0x14/255),
                                                                    Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255)]),
                                                 startPoint: CGPoint(x: p(14), y: p(18)), endPoint: CGPoint(x: p(86), y: p(58))))
                    c.stroke(SVGPathParser.parse(mask, scale: p(1)),
                             with: .color(Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255)), style: StrokeStyle(lineWidth: p(1.6)))
                    // 眼洞
                    c.fill(SVGPathParser.parse("M26 38 C30 33 40 33 44 38 C40 43 30 43 26 38Z", scale: p(1)), with: .color(Color(red: 0x05/255, green: 0x05/255, blue: 0x08/255)))
                    c.fill(SVGPathParser.parse("M56 38 C60 33 70 33 74 38 C70 43 60 43 56 38Z", scale: p(1)), with: .color(Color(red: 0x05/255, green: 0x05/255, blue: 0x08/255)))
                    c.stroke(SVGPathParser.parse("M28 37.4 C31 34 39 34 42 37.4", scale: p(1)),
                             with: .color(Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255).opacity(0.9)), style: StrokeStyle(lineWidth: p(1.2)))
                    c.stroke(SVGPathParser.parse("M58 37.4 C61 34 69 34 72 37.4", scale: p(1)),
                             with: .color(Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255).opacity(0.9)), style: StrokeStyle(lineWidth: p(1.2)))
                    // 额饰
                    let crest = "M50 18 l4 7 -4 5 -4 -5z"
                    c.fill(SVGPathParser.parse(crest, scale: p(1)), with: .color(Color(red: 0xC4/255, green: 0x12/255, blue: 0x30/255)))
                    c.stroke(SVGPathParser.parse(crest, scale: p(1)),
                             with: .color(Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255)), style: StrokeStyle(lineWidth: p(0.8)))
                    // 右侧羽饰
                    c.fill(SVGPathParser.parse("M84 34 C92 24 96 14 94 6 C88 12 82 22 80 32Z", scale: p(1)),
                           with: .color(Color(red: 0x8B/255, green: 0x0A/255, blue: 0x1E/255).opacity(0.95)))
                    c.fill(SVGPathParser.parse("M80 30 C86 18 88 10 86 4 C81 11 76 20 75 30Z", scale: p(1)),
                           with: .color(Color(red: 0x5C/255, green: 0x0A/255, blue: 0x16/255).opacity(0.9)))
                }
            } symbols: { EmptyView() }
            // 流光扫过（圆形轮廓内）
            let px = -40 + 160 * min(c.shine / 0.6, 1)
            Canvas { ctx, sz in
                let w = sz.width
                let bandW = w / 3
                let cx = px * (w / 100) - bandW
                ctx.translateBy(x: cx + bandW / 2, y: sz.height / 2)
                ctx.rotate(by: .degrees(-18))
                ctx.translateBy(x: -(cx + bandW / 2), y: -sz.height / 2)
                ctx.fill(Path(CGRect(x: cx, y: -w, width: bandW, height: w * 3)),
                         with: .linearGradient(Gradient(colors: [.clear, Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255).opacity(0.35), .clear]),
                                               startPoint: CGPoint(x: cx, y: 0), endPoint: CGPoint(x: cx + bandW, y: 0)))
            } symbols: { EmptyView() }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }
}
