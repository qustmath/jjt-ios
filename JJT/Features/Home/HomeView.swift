import SwiftUI

/// 首页 — 暗夜奢华风（对齐安卓 HomeScreen.kt）
/// 结构：顶栏 → 状态行 → 全出血轮播 → 滚动播报 → 蜜兔会入口 →
///       功能目录横滑排 → 今日心动 → 组局日程 → 广场动态 → 页脚
struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @State private var toast: String?
    @State private var city: String?
    @State private var appearedOnce = false
    // 蜜兔会动画：呼吸辉光 / 图上流光 / 徽章扫光（对齐安卓 marquee-glow / shine-sweep / vip-sheen）
    @State private var mituGlow = false
    @State private var mituShine = false
    @State private var badgeSheen = false

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            ambientGlows

            ScrollView {
                VStack(spacing: 0) {
                    header
                    statusRow

                    if !vm.banners.isEmpty {
                        HeroCarousel(banners: vm.banners, onTap: handleBannerTap)
                    }

                    ticker

                    Spacer().frame(height: 20)
                    mituEntrance.padding(.horizontal, 20)

                    Spacer().frame(height: 32)
                    SectionTitle(en: "THE MENU", title: "暗夜目录", hint: "左右滑动 →")
                    Spacer().frame(height: 16)
                    entryRail

                    Spacer().frame(height: 36)
                    SectionTitle(en: "TONIGHT", title: "今日心动", actionText: "去匹配") { showToast("敬请期待") }
                    Spacer().frame(height: 16)
                    tonightRecommend

                    if !vm.hotGroupEvents.isEmpty {
                        Spacer().frame(height: 36)
                        SectionTitle(en: "SCHEDULE", title: "组局日程", actionText: "全部") { showToast("敬请期待") }
                        Spacer().frame(height: 4)
                        partyScheduleList
                    }

                    if !vm.latestPosts.isEmpty {
                        Spacer().frame(height: 36)
                        SectionTitle(en: "MOMENTS", title: "广场动态", actionText: "进广场") { switchTab(1) }
                        Spacer().frame(height: 4)
                        momentsList
                    }

                    footer
                }
            }
            .refreshable { vm.load(force: true) }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Noir.noir3.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 100)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            // 对齐安卓 LifecycleStartEffect：首次进入加载，之后每次回到首页都刷新
            if appearedOnce { vm.load(force: true) } else { vm.load() }
            appearedOnce = true
            // 城市定位（拒绝/失败不显示位置块，对齐安卓）
            if city == nil {
                Task { city = await CityLocator.shared.currentCity() }
            }
        }
    }

    /// 切换主 Tab（0 首页 1 广场 2 密语 3 我的），对齐安卓 navigateToTab
    private func switchTab(_ tag: Int) {
        NotificationCenter.default.post(name: .jjtSwitchTab, object: tag)
    }

    /// banner 点击：解析 linkTarget DeepLink（{"t":"wheel"} / {"t":"activity","aid":N}）。
    /// 转盘/活动页 iOS 端未迁移，先提示；页面就绪后在此接线。
    private func handleBannerTap(_ banner: BannerInfo) {
        guard let target = banner.linkTarget, !target.isEmpty,
              let data = target.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["t"] is String else { return }
        showToast("敬请期待")
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: - 氛围光晕

    private var ambientGlows: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Noir.crimson.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 144))
                .frame(width: 288, height: 288)
                .offset(x: -96, y: -260)
            Circle()
                .fill(RadialGradient(colors: [Noir.gold.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 128))
                .frame(width: 256, height: 256)
                .offset(x: 130, y: 180)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255), Color(red: 0x12/255, green: 0x06/255, blue: 0x0A/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().stroke(Noir.gold.opacity(0.6), lineWidth: 1))
                    Text("棘")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("荆棘兔")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .tracking(3.4)
                        .foregroundStyle(Noir.ivory)
                    Text("NOIR SOCIAL CLUB")
                        .font(.system(size: 8.5, design: .serif).italic())
                        .tracking(2.1)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer()
            // 铃铛 → 密语 tab（对齐安卓 navigateToTab("messages")；未读红点待 IM SDK 接入后补）
            Button { switchTab(2) } label: {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.05))
                        .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                    Image(systemName: "bell")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - 状态行（城市定位 + 时间，对齐安卓 StatusRow）

    private var statusRow: some View {
        HStack {
            if let city {
                HStack(spacing: 2) {
                    Image(systemName: "location")
                        .font(.system(size: 9))
                        .foregroundStyle(Noir.textDim)
                    Text(city)
                        .font(.system(size: 9.5))
                        .tracking(1.4)
                        .foregroundStyle(Noir.textDim)
                }
            } else {
                Spacer().frame(width: 1)
            }
            Spacer()
            Text(statusTime)
                .font(.system(size: 9.5, design: .serif))
                .tracking(1.4)
                .foregroundStyle(Noir.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var statusTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE HH:mm"
        return f.string(from: Date()).uppercased()
    }

    // MARK: - 滚动播报（与安卓同为硬编码文案）

    private static let tickerLines = [
        "夜蔷 送出「荆棘之心」×1", "绯瞳 发起 古堡烛光暗夜茶会", "银蚀 与 鸦先生 匹配成功",
        "蜜兔会 释出 3 个鎏金席位", "鸦先生 的黑胶之夜 报名破 30 人", "棘小兔 已陪伴 12,408 个深夜",
    ]

    private var ticker: some View {
        MarqueeText(text: Self.tickerLines.map { "◆ \($0)" }.joined(separator: "　　") + "　　")
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.4))
            .overlay(alignment: .top) { Rectangle().fill(Noir.gold.opacity(0.15)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Noir.gold.opacity(0.15)).frame(height: 1) }
    }

    // MARK: - 蜜兔会 · 独立奢华入口

    private var mituEntrance: some View {
        Button { showToast("敬请期待") } label: {
            ZStack {
                Image("MituBg")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()
                // 底部压暗
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color(red: 0x0A/255, green: 0x08/255, blue: 0x04/255).opacity(0.45), location: 0.45),
                    .init(color: Color(red: 0x06/255, green: 0x05/255, blue: 0x03/255).opacity(0.95), location: 1.0),
                ], startPoint: .top, endPoint: .bottom)

                // 图上流光（斜切光带扫过，2.6s 周期，对齐安卓 shine-sweep）
                GeometryReader { geo in
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Noir.goldLight.opacity(0.28), location: 0.35),
                        .init(color: Noir.goldPale.opacity(0.45), location: 0.5),
                        .init(color: Noir.goldLight.opacity(0.28), location: 0.65),
                        .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width / 3, height: geo.size.height * 3)
                    .rotationEffect(.degrees(-18))
                    .offset(x: mituShine ? geo.size.width * 1.4 : -geo.size.width * 0.5, y: -geo.size.height)
                }
                .allowsHitTesting(false)

                // 仅邀约制 徽章（vip-sheen 白色扫光 2.8s）
                VStack {
                    HStack {
                        Text("仅 邀 约 制")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(2.4)
                            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .overlay {
                                GeometryReader { g in
                                    LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: g.size.width * 0.4, height: g.size.height * 3)
                                        .rotationEffect(.degrees(-18))
                                        .offset(x: badgeSheen ? g.size.width * 1.3 : -g.size.width * 0.5, y: -g.size.height)
                                }
                                .clipShape(Capsule())
                                .allowsHitTesting(false)
                            }
                            .padding(20)
                        Spacer()
                    }
                    Spacer()
                }

                // 底部内容
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Noir.goldPale)
                                Text("LAPIN DORÉ")
                                    .font(.system(size: 10, design: .serif).italic())
                                    .tracking(3.5)
                                    .foregroundStyle(Noir.goldLight.opacity(0.85))
                            }
                            Text("蜜兔会")
                                .font(.system(size: 32, weight: .black, design: .serif))
                                .foregroundStyle(Noir.goldText)
                            Text("全球 300 席 · 少数人的暗夜殿堂")
                                .font(.system(size: 10.5))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("300")
                                .font(.system(size: 24, design: .serif))
                                .foregroundStyle(Noir.goldText)
                            Text("尊贵席位")
                                .font(.system(size: 9))
                                .tracking(2.7)
                                .foregroundStyle(Noir.textDim)
                            ZStack {
                                Circle().stroke(Noir.goldLight.opacity(0.6), lineWidth: 1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(red: 0xF0/255, green: 0xDB/255, blue: 0xA8/255))
                            }
                            .frame(width: 36, height: 36)
                        }
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(LinearGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255), Color(red: 0x06/255, green: 0x05/255, blue: 0x03/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.goldLight.opacity(0.45), lineWidth: 1))
            .cornerFrame(Noir.goldLight.opacity(0.9))
            // 金色呼吸外阴影（对齐安卓 marquee-glow：快亮慢暗）
            .shadow(color: Noir.gold.opacity(mituGlow ? 0.5 : 0.16), radius: mituGlow ? 30 : 14)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeIn(duration: 0.9).repeatForever(autoreverses: true)) { mituGlow = true }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { mituShine = true }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: false)) { badgeSheen = true }
        }
    }

    // MARK: - 功能目录 · 横滑排

    private struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let en: String
        let icon: String
        /// 有主 tab 对应页的直达目标；nil = 页面未迁移（对齐安卓对应页面后接线）
        let tab: Int?
    }

    private let entries: [Entry] = [
        .init(name: "礼物中心", en: "Atelier", icon: "giftcard", tab: nil),
        .init(name: "组局", en: "Gather", icon: "person.3", tab: nil),
        .init(name: "群聊", en: "Channel", icon: "bubble.left.and.bubble.right", tab: nil),
        .init(name: "广场动态", en: "Square", icon: "flame", tab: 1),
        .init(name: "匹配", en: "Match", icon: "heart", tab: nil),
        .init(name: "AI伴侣", en: "Companion", icon: "sparkles", tab: nil),
        .init(name: "属性测试", en: "Persona", icon: "testtube.2", tab: nil),
        .init(name: "商城", en: "Boutique", icon: "bag", tab: nil),
    ]

    private var entryRail: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(entries) { e in
                        Button {
                            if let tab = e.tab { switchTab(tab) } else { showToast("敬请期待") }
                        } label: {
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(RadialGradient(stops: [
                                            .init(color: Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), location: 0.0),
                                            .init(color: Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255), location: 0.75),
                                            .init(color: Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255), location: 1.0),
                                        ], center: .center, startRadius: 0, endRadius: 27))
                                        .overlay(Circle().stroke(Noir.gold.opacity(0.35), lineWidth: 1))
                                    Image(systemName: e.icon)
                                        .font(.system(size: 21))
                                        .foregroundStyle(Noir.goldLight)
                                }
                                .frame(width: 54, height: 54)
                                Spacer().frame(height: 8)
                                Text(e.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(e.en)
                                    .font(.system(size: 8, design: .serif).italic())
                                    .tracking(1.1)
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            // 右侧渐隐，暗示还有更多
            LinearGradient(colors: [.clear, Noir.bg], startPoint: .leading, endPoint: .trailing)
                .frame(width: 48)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 今日心动（mock 数据，与安卓一致，待推荐接口接入）

    private struct RecommendUser: Identifiable {
        let id: Int
        let name: String
        let vip: Int
        let tag: String
        let isMitu: Bool
        let cover: String
    }

    private let recommendMock: [RecommendUser] = [
        .init(id: 1, name: "夜蔷", vip: 8, tag: "哥特", isMitu: false, cover: "https://picsum.photos/seed/jjt-u1/264/380"),
        .init(id: 2, name: "绯瞳", vip: 6, tag: "洛丽塔", isMitu: true, cover: "https://picsum.photos/seed/jjt-u2/264/380"),
        .init(id: 3, name: "银蚀", vip: 9, tag: "暗黑", isMitu: false, cover: "https://picsum.photos/seed/jjt-u3/264/380"),
        .init(id: 4, name: "鸦先生", vip: 7, tag: "复古", isMitu: true, cover: "https://picsum.photos/seed/jjt-u4/264/380"),
        .init(id: 5, name: "雾隐", vip: 5, tag: "极简", isMitu: false, cover: "https://picsum.photos/seed/jjt-u5/264/380"),
        .init(id: 6, name: "烬", vip: 4, tag: "朋克", isMitu: false, cover: "https://picsum.photos/seed/jjt-u6/264/380"),
    ]

    private var tonightRecommend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(recommendMock.enumerated()), id: \.element.id) { index, user in
                    // 安卓跳用户主页；iOS 用户主页未迁移，先提示
                    Button { showToast("敬请期待") } label: {
                        ZStack(alignment: .topLeading) {
                            WebImage(url: webImageURL(user.cover)) {
                                Color.white.opacity(0.05)
                            }
                            .frame(width: 132, height: 190)
                            .clipped()
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.25), location: 0.35),
                                .init(color: .black.opacity(0.95), location: 1.0),
                            ], startPoint: .top, endPoint: .bottom)

                            Text("N°\(index + 1)")
                                .font(.system(size: 13, design: .serif))
                                .foregroundStyle(Noir.goldText)
                                .padding(.leading, 10)
                                .padding(.top, 8)
                            if user.isMitu {
                                HStack {
                                    Spacer()
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Noir.goldPale)
                                        .padding(.top, 10)
                                        .padding(.trailing, 10)
                                }
                            }

                            VStack {
                                Spacer()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                        .font(.system(size: 16, weight: .bold, design: .serif))
                                        .foregroundStyle(Noir.ivory)
                                    Text("VIP\(user.vip) · \(user.tag)")
                                        .font(.system(size: 9))
                                        .tracking(1)
                                        .foregroundStyle(.white.opacity(0.45))
                                    Rectangle()
                                        .fill(LinearGradient(colors: [Noir.crimson, .clear], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 24, height: 1.5)
                                        .padding(.top, 4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                        }
                        .frame(width: 132, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - 组局日程

    private var partyScheduleList: some View {
        VStack(spacing: 0) {
            ForEach(vm.hotGroupEvents.prefix(3)) { event in
                Button { showToast("敬请期待") } label: {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            let (date, week) = Self.formatEventDate(event.eventTime)
                            Text(date)
                                .font(.system(size: 21, design: .serif))
                                .foregroundStyle(Noir.goldText)
                            Text(week)
                                .font(.system(size: 9, design: .serif).italic())
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title ?? "")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(Noir.ivory)
                                .lineLimit(1)
                            Text([
                                event.location,
                                "\(event.currentCount ?? 0)/\(event.participantLimit ?? 0) 席",
                                (event.rabbitCoinPrice ?? 0) == 0 ? "免费" : "\(event.rabbitCoinPrice ?? 0) 兔币",
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.35))
                                .lineLimit(1)
                        }
                        Spacer()
                        ZStack {
                            Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(width: 32, height: 32)
                        .padding(.leading, 12)
                    }
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
    }

    /// "2026-07-26 19:00" → ("07.26", "SAT")；解析失败回退原文
    private static func formatEventDate(_ raw: String?) -> (String, String) {
        guard let raw, raw.count >= 10 else { return ("--.--", "") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: String(raw.prefix(10))) else { return (String(raw.prefix(10)), "") }
        f.dateFormat = "MM.dd"
        let mmdd = f.string(from: date)
        f.dateFormat = "EEE"
        return (mmdd, f.string(from: date).uppercased())
    }

    // MARK: - 广场动态

    private var momentsList: some View {
        VStack(spacing: 0) {
            ForEach(vm.latestPosts.prefix(3)) { post in
                // 安卓进广场；iOS 切到广场 tab
                Button { switchTab(1) } label: {
                    HStack(spacing: 12) {
                        WebImage(url: webImageURL(post.avatar)) {
                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Noir.gold.opacity(0.4))
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(post.nickname ?? "用户") · \(Self.formatLikes(post.likeCount)) 赞")
                                .font(.system(size: 10))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("“\(post.content ?? "")”")
                                .font(.system(size: 13.5, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        Spacer()
                        if let img = post.images?.first {
                            WebImage(url: webImageURL(img)) {
                                Color.white.opacity(0.05)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private static func formatLikes(_ count: Int?) -> String {
        let c = count ?? 0
        return c > 999 ? String(format: "%.1fk", Double(c) / 1000) : "\(c)"
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Noir.goldLine)
                .frame(width: 64, height: 1)
                .padding(.bottom, 8)
            Text("JINGJI RABBIT · EST. MMXXIV")
                .font(.system(size: 9, design: .serif).italic())
                .tracking(3.1)
                .foregroundStyle(.white.opacity(0.25))
            Text("圈 子 文 化 的 奠 基 人")
                .font(.system(size: 9))
                .tracking(2.7)
                .foregroundStyle(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 96)
    }
}

// MARK: - 区块标题

private struct SectionTitle: View {
    let en: String
    let title: String
    var hint: String? = nil
    var actionText: String? = nil
    var onAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(en)
                    .font(.system(size: 10, design: .serif).italic())
                    .tracking(3)
                    .foregroundStyle(Noir.gold.opacity(0.6))
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
            }
            Spacer()
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.25))
            }
            if let actionText {
                Button(action: onAction) {
                    HStack(spacing: 2) {
                        Text(actionText)
                            .font(.system(size: 11))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Noir.crimsonHot)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 全出血轮播

private struct HeroCarousel: View {
    let banners: [BannerInfo]
    let onTap: (BannerInfo) -> Void

    @State private var index = 0
    private let timer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            TabView(selection: $index) {
                ForEach(banners.indices, id: \.self) { i in
                    WebImage(url: webImageURL(banners[i].imageUrl)) {
                        Noir.noir2
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(banners[i]) }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onReceive(timer) { _ in
                withAnimation { index = (index + 1) % banners.count }
            }

            // 渐变蒙版
            LinearGradient(stops: [
                .init(color: Noir.noir.opacity(0.55), location: 0.00),
                .init(color: .clear, location: 0.30),
                .init(color: .clear, location: 0.55),
                .init(color: Noir.noir.opacity(0.96), location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            // 左侧竖排英文
            HStack {
                Text("TONIGHT'S SELECTION")
                    .font(.system(size: 10, design: .serif))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14)
                    .padding(.leading, 14)
                Spacer()
            }
            .allowsHitTesting(false)

            // 底部文案
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("荆棘兔 · 精选")
                            .font(.system(size: 10))
                            .tracking(4)
                            .foregroundStyle(Noir.goldLight)
                        Text(banners[index].title ?? "")
                            .font(.system(size: 40, weight: .black, design: .serif))
                            .lineSpacing(4)
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.leading, 40)
                .padding(.trailing, 96)
                .padding(.bottom, 24)
            }
            .allowsHitTesting(false)

            // 页码 + 进度条
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Noir.goldText)
                    HStack(spacing: 4) {
                        ForEach(banners.indices, id: \.self) { i in
                            Rectangle()
                                .fill(i == index ? Noir.goldLight : Color.white.opacity(0.18))
                                .frame(width: 20, height: 2)
                        }
                    }
                    Text(String(format: "%02d", banners.count))
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .cornerFrame(Noir.gold.opacity(0.7))
    }
}

// MARK: - 滚动播报（无限横向跑马灯）

private struct MarqueeText: View {
    let text: String

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            line
            line
        }
        .offset(x: offset)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onAppear { start() }
    }

    private var line: some View {
        Text(text)
            .font(.system(size: 10.5))
            .tracking(1)
            .foregroundStyle(Noir.gold.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                if textWidth == 0 { textWidth = $0 }
            }
    }

    private func start() {
        guard textWidth > 0 else {
            // 等宽度测量完成后启动
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { start() }
            return
        }
        offset = 0
        withAnimation(.linear(duration: Double(textWidth) / 30).repeatForever(autoreverses: false)) {
            offset = -textWidth
        }
    }
}

#Preview {
    HomeView()
}
