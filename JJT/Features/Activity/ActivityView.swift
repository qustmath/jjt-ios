import SwiftUI

/// 活动详情（对齐安卓 ActivityScreen）
/// TICKET：before未开始 / claim领票中 / open验票中 / expired已落幕；领票 → 票根卡（验票）→ 验票成功弹奖励勋章
/// SIGNUP_PHOTO（报名审核制，v74 原型）：居中标题 → 流程条 → 会员风采横滑 → 「我的报名」分隔线 → 报名三态
struct ActivityView: View {

    let activityId: Int64
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var activity: ActivityInfo?
    @State private var loading = true
    @State private var acting = false
    @State private var error: String?
    @State private var rewardShow: ActivityInfo?
    @State private var showBadgeWall = false
    /// 会员风采横滑区（报名制：墙第 1 页前 10 条，过滤本人待审）
    @State private var wallPreview: [WallItem] = []
    /// 已通过者点「重新报名」：本地切回表单态
    @State private var forceForm = false
    @State private var showWall = false

    private var isSignupMode: Bool { activity?.signupMode == "photo" }
    private var theme: ActivityTheme { parseActivityTheme(activity?.theme) }

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            // 活动头图背景 + 压暗（报名制明显更暗，头图只留氛围；票务保持原有清透）
            if let cover = activity?.cover, !cover.isEmpty {
                WebImage(url: webImageURL(cover), contentMode: .fill) { Color.clear }
                    .ignoresSafeArea()
                if isSignupMode {
                    LinearGradient(stops: [
                        .init(color: Noir.bg.opacity(0.85), location: 0),
                        .init(color: Noir.bg.opacity(0.96), location: 0.45),
                        .init(color: Noir.bg, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                } else {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: Noir.bg.opacity(0.85), location: 0.5),
                        .init(color: Noir.bg, location: 0.85),
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                }
            }
            // 报名制：主题装饰字符水印（对齐原型右上角氛围）
            if isSignupMode && !theme.deco.isEmpty {
                Text(theme.deco)
                    .font(.system(size: 96))
                    .foregroundStyle(.white.opacity(0.07))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 56)
                    .padding(.trailing, -24)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar
                if loading {
                    Spacer()
                    ProgressView().tint(isSignupMode ? theme.accent : Noir.gold)
                    Spacer()
                } else if let a = activity {
                    ScrollView {
                        VStack(spacing: 0) {
                            if isSignupMode {
                                // ===== 报名制（v74 原型顺序）：居中头 → 流程条 → 会员风采 → 我的报名分隔线 → 三态 =====
                                SignupHeaderView(a: a, theme: theme)
                                ActivitySignupFlowStrip(theme: theme, my: a.mySignup, forceForm: forceForm)
                                    .padding(.horizontal, 20)
                                if a.wallEnabled == true && !wallPreview.isEmpty {
                                    SignupShowcaseSection(
                                        theme: theme,
                                        items: wallPreview,
                                        onAllClick: { showWall = true }
                                    )
                                }
                                ActivitySignupMineDivider(theme: theme)
                                ActivitySignupSection(
                                    activity: a,
                                    theme: theme,
                                    rules: a.rules,
                                    forceForm: forceForm,
                                    onResign: { forceForm = true },
                                    onWallClick: { showWall = true },
                                    onRefresh: { refresh() }
                                )
                            } else {
                                headerBlock(a)
                                actionBlock(a)
                                rulesBlock(a)
                            }
                            footerBlock(a)
                        }
                        .padding(.bottom, 40)
                    }
                } else {
                    Spacer()
                    Text("活动不存在或已下线")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
            }

            // 验票成功奖励弹层
            if let rewardShow {
                rewardDialog(rewardShow)
            }
        }
        .onAppear {
            if activity == nil { load() }
        }
        .fullScreenCover(isPresented: $showBadgeWall) {
            BadgeWallView()
        }
        .fullScreenCover(isPresented: $showWall) {
            ActivitySignupWallView(activityId: activityId, onJoin: { showWall = false })
        }
        .onChange(of: showWall) { _, shown in
            // 从穿搭墙返回：重拉详情（审核后三态必须翻转，三态真源=服务端 mySignup）
            if !shown { refresh() }
        }
        .alert("提示", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("知道了") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .jjtPageGestures()
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSignupMode ? Noir.ivory : Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(
                        isSignupMode ? theme.accent.opacity(0.35) : Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            if isSignupMode {
                // 报名制：顶栏中央 EN 小字（主题色）
                Text(activity?.nameEn ?? "")
                    .font(.system(size: 10))
                    .italic()
                    .tracking(3)
                    .foregroundStyle(theme.accent.opacity(0.7))
            } else {
                Text(activity?.nameEn ?? "NIGHT BANQUET")
                    .font(.system(size: 9, design: .serif))
                    .italic()
                    .tracking(3)
                    .foregroundStyle(Noir.goldLight.opacity(0.7))
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 票务头部（TICKET 保持原样）

    private func headerBlock(_ a: ActivityInfo) -> some View {
        VStack(spacing: 10) {
            Text(a.name ?? "活动")
                .font(.system(size: 26, weight: .black, design: .serif))
                .tracking(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Noir.goldText)
            if let sub = a.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            phaseBadge(a)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func phaseBadge(_ a: ActivityInfo) -> some View {
        let (text, color): (String, Color) = {
            switch a.phase {
            case "claim": return ("领票进行中 · \(fmtActivityDay(a.claimEnd)) 截止", Noir.goldLight)
            case "open": return ("验票进行中", Noir.crimsonHot)
            case "expired": return ("本期已落幕", .white.opacity(0.35))
            default: return ("尚未开始", .white.opacity(0.45))
            }
        }()
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - 操作区（领票按钮 / 票根卡）

    @ViewBuilder
    private func actionBlock(_ a: ActivityInfo) -> some View {
        if let ticket = a.myTicket {
            ticketStubCard(ticket, activity: a)
        } else {
            VStack(spacing: 12) {
                if a.canClaim == true {
                    Button { claim() } label: {
                        Text(acting ? "领 取 中 …" : "领 取 入 场 券")
                            .font(.system(size: 15, weight: .bold))
                            .tracking(4)
                            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(LinearGradient(colors: [Noir.goldLight, Noir.gold, Noir.goldDeep],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(acting)
                } else {
                    Text(acting ? "领 取 中 …" : (a.phase == "before" ? "尚 未 开 始" : "本期夜宴已落幕"))
                        .font(.system(size: 13))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.3))
                }
                if let badge = a.rewardBadgeName, !badge.isEmpty {
                    Text("参与活动可点亮限定勋章「\(badge)」")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.goldLight.opacity(0.6))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
    }

    /// 票根卡（对齐安卓 TicketStubCard：虚线票根 + 验票钮）
    private func ticketStubCard(_ ticket: TicketInfo, activity a: ActivityInfo) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("我 的 入 场 券")
                    .font(.system(size: 9))
                    .tracking(4)
                    .foregroundStyle(Noir.goldLight.opacity(0.7))
                Text("Nº \(ticket.ticketNo ?? "-")")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Noir.goldText)
                Text("领取于 \(fmtActivityDay(ticket.claimTime))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.vertical, 18)
            // 虚线分割
            HStack(spacing: 6) {
                ForEach(0..<18, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 8, height: 1)
                }
            }
            .padding(.horizontal, 16)
            Group {
                switch ticket.status {
                case 1:
                    Text("已 入 场 · 期 待 下 次 相 遇")
                        .font(.system(size: 12))
                        .tracking(2)
                        .foregroundStyle(Noir.gold)
                        .padding(.vertical, 16)
                case 2:
                    Text("已 失 效")
                        .font(.system(size: 12))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.vertical, 16)
                default:
                    if ticket.canRedeem == true {
                        Button { redeem() } label: {
                            Text(acting ? "验 票 中 …" : "验 票 入 场")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(3)
                                .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(acting)
                        .padding(14)
                    } else {
                        Text("待 入 场")
                            .font(.system(size: 12))
                            .tracking(2)
                            .foregroundStyle(Noir.goldLight.opacity(0.7))
                            .padding(.vertical, 16)
                    }
                }
            }
        }
        .background(Noir.noir2.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }

    // MARK: - 规则与页脚

    private func rulesBlock(_ a: ActivityInfo) -> some View {
        Group {
            if let rules = a.rules, !rules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("活 动 细 则")
                        .font(.system(size: 10))
                        .tracking(4)
                        .foregroundStyle(Noir.goldLight.opacity(0.7))
                    Text(rules)
                        .font(.system(size: 12))
                        .lineSpacing(6)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 28)
            }
        }
    }

    private func footerBlock(_ a: ActivityInfo) -> some View {
        Group {
            if let footer = a.footerText, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 10))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
            }
        }
    }

    // MARK: - 验票成功奖励弹层（对齐安卓 RewardDialog）

    private func rewardDialog(_ reward: ActivityInfo) -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("验票成功")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Noir.goldLight)
                if let icon = reward.rewardBadgeIcon, !icon.isEmpty {
                    WebImage(url: webImageURL(icon), contentMode: .fit) {
                        Image(systemName: "medal.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Noir.goldLight)
                    }
                    .frame(width: 72, height: 72)
                } else {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Noir.goldLight)
                        .frame(width: 72, height: 72)
                }
                Text("限定勋章「\(reward.rewardBadgeName ?? "")」")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                if (reward.rewardCoin ?? 0) > 0 {
                    Text("+\(reward.rewardCoin ?? 0) 萝贝")
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.gold)
                }
                HStack(spacing: 12) {
                    Button { showBadgeWall = true } label: {
                        Text("查看勋章墙")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.goldLight)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .overlay(Capsule().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { self.rewardShow = nil } label: {
                        Text("太好了")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(LinearGradient(colors: [Noir.crimson, Noir.wine], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 280)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: - 数据

    private func load() {
        Task {
            if let a = try? await ActivityAPI.get(id: activityId) {
                applyDetail(a)
            }
            loading = false
        }
    }

    /// 静默刷新（从穿搭墙/后台审核返回时重拉，三态以服务端为准）
    private func refresh() {
        Task {
            if let a = try? await ActivityAPI.get(id: activityId) {
                applyDetail(a)
            }
        }
    }

    /// 详情落状态；报名身份（id/status）变化时退出本地「重新报名」表单态
    private func applyDetail(_ detail: ActivityInfo) {
        let oldKey = signupKey(activity?.mySignup)
        let newKey = signupKey(detail.mySignup)
        if oldKey != newKey { forceForm = false }
        activity = detail
        fetchWallPreview(detail)
    }

    private func signupKey(_ s: SignupInfo?) -> String {
        guard let s else { return "none" }
        return "\(s.id)-\(s.status ?? -1)"
    }

    /// 会员风采横滑区：墙第 1 页前 10 条；该区语义是「已通过审核」，过滤掉本人待审（空则整区隐藏）
    private func fetchWallPreview(_ a: ActivityInfo) {
        guard a.signupMode == "photo", a.wallEnabled == true else { return }
        Task {
            if let wall = try? await ActivityAPI.signupWall(id: a.id, pageNo: 1, pageSize: 10) {
                wallPreview = (wall.list ?? []).filter { $0.pending != true }
            }
        }
    }

    private func claim() {
        guard !acting else { return }
        acting = true
        Task {
            do {
                _ = try await ActivityAPI.claim(id: activityId)
                acting = false
                jjtShowToast("入场券已收入票夹")
                activity = try? await ActivityAPI.get(id: activityId)
            } catch {
                acting = false
                self.error = error.localizedDescription
            }
        }
    }

    private func redeem() {
        guard !acting else { return }
        acting = true
        Task {
            do {
                let a = try await ActivityAPI.redeem(id: activityId)
                acting = false
                activity = a
                rewardShow = a
            } catch {
                acting = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - 报名制活动页头（v74 原型：居中排版 + 主题渐变大字标题）

private struct SignupHeaderView: View {
    let a: ActivityInfo
    let theme: ActivityTheme

    var body: some View {
        VStack(spacing: 0) {
            if let sub = a.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 10))
                    .tracking(4)
                    .foregroundStyle(theme.accent)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 8)
            }
            // 渐变 = 亮 accent → accent → accent2（对齐原型「浅金→主题色→深色」三段）
            Text(a.name ?? "")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(LinearGradient(
                    colors: [lerpColor(.white, theme.accent, 0.5), theme.accent, theme.accent2],
                    startPoint: .top, endPoint: .bottom))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 20)
    }
}

/// 颜色线性插值（对齐安卓 lerp，白色→主题色 50%）
func lerpColor(_ from: Color, _ to: Color, _ t: CGFloat) -> Color {
    let a = UIColor(from)
    let b = UIColor(to)
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    return Color(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t)
}

// MARK: - 「报名通过 · 会员风采」横滑区（v74 原型）

private struct SignupShowcaseSection: View {
    let theme: ActivityTheme
    let items: [WallItem]
    let onAllClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 13))
                            .foregroundStyle(activityPassGreen)
                        Text("报名通过 · 会员风采")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Noir.ivory)
                    }
                    Text("以下会员报名已通过审核 · 获得入店凭证")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                Button(action: onAllClick) {
                    HStack(spacing: 2) {
                        Text("全部会员")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            Spacer().frame(height: 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        SignupShowcaseCard(item: item, theme: theme)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onAllClick)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 24)
    }
}

/// 会员风采横滑卡：138×188 大图 + 底部渐变（昵称/造型名/点赞数）+ 左上「已通过」角标
private struct SignupShowcaseCard: View {
    let item: WallItem
    let theme: ActivityTheme

    var body: some View {
        ZStack {
            WebImage(url: webImageURL(item.img), contentMode: .fill) { Color.white.opacity(0.05) }
            // 上下压暗（上浅下重，保底部信息可读）
            LinearGradient(stops: [
                .init(color: .black.opacity(0.05), location: 0),
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.92), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // 左上：已通过角标
            VStack {
                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 7))
                            .foregroundStyle(activityPassGreen)
                        Text("已通过")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(activityPassGreen)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(activityPassGreen.opacity(0.5), lineWidth: 1))
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            // 底部：昵称 + 造型名 + 点赞数
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.nickname ?? "")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    if let look = item.look, !look.isEmpty {
                        Text("「\(look)」")
                            .font(.system(size: 8.5))
                            .foregroundStyle(theme.accent.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer().frame(height: 4)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.accent)
                        Text("\(item.likes ?? 0)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 138, height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.35), lineWidth: 1))
    }
}
