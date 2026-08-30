import SwiftUI

/// 幸运转盘（对齐安卓 WheelScreen）
/// 流程：点抽取 → 匀速空转等服务端结果 → 减速段精准落到 prizeIndex → 停稳后应用余额/已中次数 → 揭晓弹层
struct WheelView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = WheelViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var angle: Double = 0
    @State private var spinning = false
    @State private var reveal: WheelDrawResult?
    @State private var showRecords = false
    @State private var showExchange = false
    @State private var rabbitBalance: Int64 = 0

    private var activity: WheelActivityInfo? { vm.activity }
    private var prizes: [WheelPrizeItem] { activity?.prizes ?? [] }
    private var seg: Double { prizes.isEmpty ? 360 : 360 / Double(prizes.count) }
    private var ongoing: Bool { activity?.state == 1 }
    private var balance: Int64 { activity?.radishBalance ?? 0 }
    private var price: Int64 { activity?.drawPrice ?? 0 }

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            // 奢华实景背景：活动头图 + 压暗渐变（对齐安卓）
            if let cover = activity?.cover, !cover.isEmpty {
                WebImage(url: webImageURL(cover), contentMode: .fill) { Color.clear }
                    .ignoresSafeArea()
                LinearGradient(stops: [
                    .init(color: Color.black.opacity(0.42), location: 0),
                    .init(color: Color.black.opacity(0.3), location: 0.26),
                    .init(color: Color(red: 0x06/255, green: 0x05/255, blue: 0x08/255).opacity(0.88), location: 0.62),
                    .init(color: Noir.bg, location: 0.96),
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }
            WheelBackdrop()

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    balanceRow
                    wheelBody
                    prizeListSection
                    rulesSection
                }
                .padding(.bottom, 32)
            }

            // 中奖揭晓弹层
            if let reveal {
                PrizeReveal(result: reveal) { self.reveal = nil }
            }
        }
        .onAppear { vm.refresh() }
        .sheet(isPresented: $showRecords) {
            recordsSheet
                .presentationDetents([.medium, .large])
                .presentationBackground(Noir.noir)
        }
        .sheet(isPresented: $showExchange) {
            exchangeSheet
                .jjtKeyboardDismiss()
                .presentationDetents([.height(300)])
                .presentationBackground(Noir.noir2)
        }
        .onChange(of: vm.loadError) { _, e in
            if let e { jjtShowToast(e); vm.loadError = nil }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(activity?.name ?? "绯夜转盘")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text(activity?.nameEn ?? "NOIR FORTUNE WHEEL")
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Button {
                showRecords = true
                vm.loadRecords(reset: true)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 余额 + 单价

    private var balanceRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text("萝")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Noir.crimsonHot)
                Text("\(balance)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Noir.goldText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0x14/255, green: 0x0C/255, blue: 0x10/255).opacity(0.7))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
            Text("每抽 \(price) 萝贝")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - 转盘主体

    private var wheelBody: some View {
        ZStack {
            // 转动光环
            HaloSpin(spinning: spinning)
                .frame(width: 364, height: 364)
                .opacity(spinning ? 1 : 0.4)

            // 盘体（旋转）
            ZStack {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let rimR = min(size.width, size.height) / 2
                    // 外缘鎏金环
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - rimR, y: c.y - rimR, width: rimR * 2, height: rimR * 2)),
                             with: .radialGradient(
                                Gradient(stops: [
                                    .init(color: Color(red: 0x2A/255, green: 0x14/255, blue: 0x10/255), location: 0.82),
                                    .init(color: Noir.gold, location: 0.94),
                                    .init(color: Color(red: 0x6B/255, green: 0x4C/255, blue: 0x1E/255), location: 1.0),
                                ]),
                                center: c, startRadius: 0, endRadius: rimR))
                    let innerR = rimR * 158 / 168
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - innerR, y: c.y - innerR, width: innerR * 2, height: innerR * 2)),
                             with: .color(Color(red: 0x0C/255, green: 0x08/255, blue: 0x0C/255)))
                    // 扇区
                    let segR = rimR * 156 / 168
                    for (i, p) in prizes.enumerated() {
                        let taken = (p.winLimit ?? 0) > 0 && (p.myWins ?? 0) >= (p.winLimit ?? 0)
                        var sector = Path()
                        sector.move(to: c)
                        sector.addArc(center: c, radius: segR,
                                      startAngle: .degrees(Double(i) * seg - 90),
                                      endAngle: .degrees(Double(i + 1) * seg - 90), clockwise: false)
                        sector.closeSubpath()
                        let base = i % 2 == 0
                            ? Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.92)
                            : Color(red: 0x10/255, green: 0x0A/255, blue: 0x0E/255).opacity(0.95)
                        ctx.fill(sector, with: .color(base.opacity(taken ? 0.25 : 1)))
                        ctx.stroke(sector, with: .color(Noir.gold.opacity(0.4)), lineWidth: 1)
                    }
                    // 内圈金线
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - segR, y: c.y - segR, width: segR * 2, height: segR * 2)),
                               with: .color(Noir.goldLight.opacity(0.55)), lineWidth: 1.5)
                    let r62 = rimR * 62 / 168
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r62, y: c.y - r62, width: r62 * 2, height: r62 * 2)),
                               with: .color(Noir.gold.opacity(0.4)), lineWidth: 1)
                    // 轮辐铆钉
                    for i in prizes.indices {
                        let a = (Double(i) * seg - 90 + seg / 2) * .pi / 180
                        let rr = rimR * 150 / 168
                        let p = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)),
                                 with: .color(Noir.goldLight.opacity(0.8)))
                    }
                }

                // 扇区奖品（随盘旋转）
                ForEach(Array(prizes.enumerated()), id: \.element.id) { i, p in
                    let mid = Double(i) * seg + seg / 2 - 90
                    let taken = (p.winLimit ?? 0) > 0 && (p.myWins ?? 0) >= (p.winLimit ?? 0)
                    let a = mid * .pi / 180
                    let rr = 108.0
                    VStack(spacing: 4) {
                        GiftIconView(icon: p.icon, size: p.grand == true ? 26 : 21)
                        Text(p.name ?? "")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Self.prizeColor(p.color))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                        if taken {
                            Text("已达上限")
                                .font(.system(size: 7.5))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 86)
                    .rotationEffect(.degrees(mid + 90))
                    .opacity(taken ? 0.22 : 1)
                    .position(x: 170 + cos(a) * rr, y: 170 + sin(a) * rr)
                }
            }
            .frame(width: 340, height: 340)
            .rotationEffect(.degrees(angle))

            // 顶部指针
            Canvas { ctx, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(Noir.goldLight))
                ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 5, y: -5, width: 10, height: 10)),
                         with: .color(Noir.goldPale))
            }
            .frame(width: 26, height: 24)
            .offset(y: -176)

            // 中心抽取按钮
            Button { tapDraw() } label: {
                VStack(spacing: 2) {
                    Text(spinning ? "祈愿中"
                         : activity?.state == 0 ? "未开始"
                         : activity?.state == 2 ? "已结束"
                         : activity?.state == 3 ? "敬请期待" : "抽取")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Noir.goldText)
                    if ongoing {
                        Text(spinning ? "SPINNING" : "\(price) 萝贝/次")
                            .font(.system(size: 8, design: .serif))
                            .italic()
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .frame(width: 104, height: 104)
                .background(RadialGradient(stops: [
                    .init(color: Color(red: 0x4A/255, green: 0x11/255, blue: 0x20/255), location: 0),
                    .init(color: Color(red: 0x18/255, green: 0x0A/255, blue: 0x10/255), location: 0.78),
                    .init(color: Color(red: 0x18/255, green: 0x0A/255, blue: 0x10/255), location: 1),
                ], center: .center, startRadius: 0, endRadius: 52))
                .clipShape(Circle())
                .overlay(Circle().stroke(Noir.goldLight.opacity(0.8), lineWidth: 2))
                .overlay(Circle().stroke(Color(red: 0x0C/255, green: 0x08/255, blue: 0x0C/255).opacity(0.9), lineWidth: 6))
            }
            .buttonStyle(.plain)
            .disabled(!ongoing || spinning || vm.loading)
        }
        .frame(width: 340, height: 340)
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 抽奖流程（对齐安卓：空转等服务端 → 减速段落点 → 停稳应用结果 → 揭晓）

    private func tapDraw() {
        guard ongoing, !spinning else { return }
        if balance < price {
            // 萝贝不足 → 兑换引导
            Task { rabbitBalance = (try? await WalletAPI.getWallet("rabbit_coin"))?.availableAmount ?? 0 }
            showExchange = true
            return
        }
        spinning = true
        Task {
            // 匀速空转等待服务端结果，消除"点一下卡一下"
            let keepSpinning = Task {
                while !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.linear(duration: 0.9)) { angle += 360 }
                    }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
            }
            let result = await vm.draw()
            keepSpinning.cancel()
            guard let result, let prizeIndex = result.prizeIndex else {
                spinning = false
                return
            }
            // 减速段：4 整圈 + 落点补偿（起始快、缓慢停）
            let target = 360 - (Double(prizeIndex) * seg + seg / 2)
            let cur = angle.truncatingRemainder(dividingBy: 360)
            let delta = (target - cur).truncatingRemainder(dividingBy: 360) + 360
            withAnimation(.timingCurve(0.12, 0.75, 0.06, 1.0, duration: 4.2)) {
                angle += 360 * 4 + delta
            }
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            spinning = false
            // 转盘停稳后再应用余额/已中次数（达上限格子此刻才变灰）
            vm.applyDrawResult()
            reveal = result
        }
    }

    // MARK: - 奖池名录

    private var prizeListSection: some View {
        Group {
            if !prizes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom) {
                        Text("奖池名录")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Noir.ivory)
                        Spacer()
                        Text("共 \(prizes.count) 项")
                            .font(.system(size: 9, design: .serif))
                            .italic()
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    ForEach(prizes) { p in
                        let taken = (p.winLimit ?? 0) > 0 && (p.myWins ?? 0) >= (p.winLimit ?? 0)
                        HStack(spacing: 10) {
                            GiftIconView(icon: p.icon, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(p.name ?? "")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(taken ? .white.opacity(0.3) : Noir.ivory)
                                    if p.grand == true {
                                        Text("大奖")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                                            .clipShape(Capsule())
                                    }
                                }
                                if let sub = p.sub, !sub.isEmpty {
                                    Text(sub)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            }
                            Spacer()
                            if taken {
                                Text("已达上限")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.3))
                            } else if (p.winLimit ?? 0) > 0 {
                                Text("限 \(p.winLimit ?? 0) 次 · 已中 \(p.myWins ?? 0)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .opacity(taken ? 0.5 : 1)
                    }
                }
                .padding(16)
                .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0E/255).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 28)
            }
        }
    }

    // MARK: - 规则

    private var rulesSection: some View {
        Group {
            if let rules = activity?.rules, !rules.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("活动规则")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Noir.ivory)
                    Text(rules)
                        .font(.system(size: 10.5))
                        .lineSpacing(5)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        }
    }

    // MARK: - 中奖记录

    private var recordsSheet: some View {
        VStack(spacing: 0) {
            Text("中奖记录")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Noir.goldText)
                .padding(.top, 20)
                .padding(.bottom, 12)
            if vm.records.isEmpty {
                Spacer()
                Text(vm.recordsLoading ? "加载中…" : "暂无记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.records) { r in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.prizeName ?? "奖品")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Noir.ivory)
                                    if let t = r.createTime {
                                        Text(Self.fmtTime(t))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                }
                                Spacer()
                                Text(r.granted == true ? "已发放" : (r.grantRemark ?? "未发放"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(r.granted == true ? Noir.goldLight : .white.opacity(0.4))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Noir.noir2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onAppear {
                                if r.id == vm.records.last?.id { vm.loadRecords() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - 兑换引导（萝贝不足 → 兔币兑换 1:10，对齐安卓 WheelExchangeDialog）

    @State private var exchangeText = ""

    private var exchangeSheet: some View {
        let amount = Int64(exchangeText) ?? 0
        let valid = amount > 0 && amount <= rabbitBalance
        return VStack(alignment: .leading, spacing: 10) {
            Text("萝贝不足")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
                .padding(.top, 24)
            Text("本次抽取需 \(price) 萝贝，当前萝贝 \(balance)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Text("可用兔币兑换（1 兔币 = 10 萝贝）· 兔币余额 \(rabbitBalance)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            TextField("兑换兔币数量", text: $exchangeText)
                .keyboardType(.numberPad)
                .noirField()
                .onChange(of: exchangeText) { _, v in exchangeText = String(v.filter(\.isNumber).prefix(9)) }
            Text(amount > 0 ? "可获得 \(amount * 10) 萝贝" : "输入数量即兑即抽")
                .font(.system(size: 12))
                .foregroundStyle(amount > 0 ? Noir.goldLight : .white.opacity(0.3))
            if amount > rabbitBalance {
                Text("兔币余额不足")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.crimsonHot)
            }
            HStack(spacing: 12) {
                Button { showExchange = false } label: {
                    Text("取消")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { confirmExchange(amount) } label: {
                    Text("兑换并继续")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(valid
                                    ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.08)))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!valid)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
    }

    private func confirmExchange(_ amount: Int64) {
        Task {
            do {
                let got = try await WalletAPI.exchangeRadish(amount: amount)
                jjtShowToast("兑换成功，获得 \(got) 萝贝")
                showExchange = false
                exchangeText = ""
                vm.refresh()
            } catch {
                jjtShowToast(error.localizedDescription)
            }
        }
    }

    // MARK: - 工具

    static func prizeColor(_ color: String?) -> Color {
        guard let color, color.hasPrefix("#"), color.count >= 7 else { return Noir.goldLight }
        var v: UInt64 = 0
        Scanner(string: String(color.dropFirst())).scanHexInt64(&v)
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func fmtTime(_ ts: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts / 1000))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 转动光环

private struct HaloSpin: View {
    let spinning: Bool

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let period = spinning ? 0.9 : 9.0
            let deg = (t.truncatingRemainder(dividingBy: period)) / period * 360
            Circle()
                .fill(AngularGradient(colors: [.clear, Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255).opacity(0.25), .clear,
                                               Noir.crimson.opacity(0.3), .clear],
                                      center: .center))
                .rotationEffect(.degrees(deg))
        }
    }
}

// MARK: - 背景粒子（星光闪烁，对齐安卓 WheelBackdrop 简化版）

private struct WheelBackdrop: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                var rng = SeededRNG(seed: 42)
                for _ in 0..<40 {
                    let x = rng.next() * size.width
                    let y = rng.next() * size.height
                    let phase = rng.next() * 2 * .pi
                    let alpha = 0.12 + 0.1 * sin(t * 0.8 + phase)
                    let r = 0.8 + rng.next() * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                             with: .color(Noir.goldLight.opacity(max(alpha, 0.03))))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0x1000000)
    }
}

// MARK: - 中奖揭晓弹层（对齐安卓 PrizeReveal）

private struct PrizeReveal: View {
    let result: WheelDrawResult
    let onClose: () -> Void

    @State private var pop = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            // 旋转光芒
            TimelineView(.animation) { tl in
                let deg = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12 * 360
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    for i in 0..<12 {
                        var sector = Path()
                        sector.move(to: c)
                        let r = size.width / 2
                        sector.addArc(center: c, radius: r,
                                      startAngle: .degrees(Double(i) * 30 - 6),
                                      endAngle: .degrees(Double(i) * 30 + 6), clockwise: false)
                        sector.closeSubpath()
                        ctx.fill(sector, with: .color(Noir.goldLight.opacity(i % 2 == 0 ? 0.05 : 0.0)))
                    }
                }
                .rotationEffect(.degrees(deg))
            }
            .frame(width: 420, height: 420)

            VStack(spacing: 12) {
                Text(result.grand == true ? "鸿运当头" : "恭喜获得")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Noir.goldLight)
                GiftIconView(icon: result.icon, size: result.grand == true ? 88 : 72)
                Text(result.prizeName ?? "")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                if let sub = result.sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if result.granted == false, let remark = result.remark {
                    Text(remark)
                        .font(.system(size: 11))
                        .foregroundStyle(Noir.crimsonHot)
                }
                Button(action: onClose) {
                    Text("收入囊中")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .scaleEffect(pop ? 1 : 0.5)
            .opacity(pop ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.4)) { pop = true }
        }
    }
}

// MARK: - ViewModel（对齐安卓 WheelViewModel）

@MainActor
final class WheelViewModel: ObservableObject {

    @Published var loading = true
    @Published var activity: WheelActivityInfo?
    @Published var loadError: String?
    @Published var lastResult: WheelDrawResult?
    @Published var records: [WheelRecordItem] = []
    @Published var recordsTotal: Int64 = 0
    @Published var recordsLoading = false

    func refresh() {
        loading = true
        Task {
            do {
                activity = try await WheelAPI.activity()
                loading = false
            } catch {
                loading = false
                loadError = error.localizedDescription
            }
        }
    }

    /// 抽奖：先请求服务端出结果，再交给界面播转盘动画（动画目标 = result.prizeIndex）
    /// 注意：不在这里更新余额/已中次数——等转盘动画停稳后由 applyDrawResult() 应用
    func draw() async -> WheelDrawResult? {
        do {
            let result = try await WheelAPI.draw()
            lastResult = result
            return result
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    /// 转盘动画结束后应用抽奖结果：余额 + 已中次数（达上限格子此时才变灰）
    func applyDrawResult() {
        guard let result = lastResult, var act = activity else { return }
        act.radishBalance = result.radishBalance
        act.prizes = act.prizes?.map { p in
            var p = p
            if p.id == result.prizeId, result.granted == true {
                p.myWins = (p.myWins ?? 0) + 1
            }
            return p
        }
        activity = act
    }

    func loadRecords(reset: Bool = false) {
        guard !recordsLoading else { return }
        recordsLoading = true
        Task {
            let pageNo = reset ? 1 : records.count / 20 + 1
            if let page = try? await WheelAPI.recordPage(pageNo: pageNo) {
                recordsTotal = page.total ?? 0
                records = reset ? (page.list ?? []) : records + (page.list ?? [])
            }
            recordsLoading = false
        }
    }
}
