import SwiftUI

// MARK: - 设计常量（对齐安卓 AchievementHallScreen）

private let HALL_CAT_META: [(key: String, name: String, color: Color)] = [
    ("general", "综合", Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255)),
    ("social", "社群", Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255)),
    ("explore", "探索", Color(red: 0x7D/255, green: 0xB8/255, blue: 0xA8/255)),
    ("egg", "彩蛋", Color(red: 0xB4/255, green: 0x8C/255, blue: 0xE0/255)),
    ("limited", "限时", Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255)),
]

/// 轨道子集：彩蛋轨 = 全部 hidden；其余轨排除 hidden（对齐安卓 railFilter）
private func hallRailFilter(_ badges: [BadgeHallItem], _ rail: String) -> [BadgeHallItem] {
    if rail == "egg" { return badges.filter { $0.hidden == true } }
    return badges.filter { $0.cat == rail && $0.hidden != true }
}

private enum HallTier { case common, rare, epic, legendary }

/// 四档推导：1-3 普通 / 4-6 稀有 / 7-9 或彩蛋 史诗 / 10 或绝版 传说（对齐安卓 tierOf）
private func hallTierOf(_ badge: BadgeHallItem) -> HallTier {
    let stages = badge.stages ?? 1
    if badge.sealed == true || stages >= 10 { return .legendary }
    if badge.hidden == true || stages >= 7 { return .epic }
    if stages >= 4 { return .rare }
    return .common
}

private func hallTierColor(_ tier: HallTier) -> Color {
    switch tier {
    case .legendary: return Noir.goldLight
    case .epic: return Color(red: 0xBA/255, green: 0x68/255, blue: 0xC8/255)
    case .rare: return Color(red: 0x64/255, green: 0xB5/255, blue: 0xF6/255)
    case .common: return Color.white.opacity(0.5)
    }
}

private let HALL_NUMERALS = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ"]

private func hallFmtCount(_ n: Int64) -> String { n >= 10000 ? "\(n / 10000)万" : "\(n)" }

/// 第 n 阶达成条件文案（对齐安卓 stageCond）
private func hallStageCond(_ badge: BadgeHallItem, _ stage: Int) -> String {
    if let template = badge.condTemplate, let targets = badge.targets,
       stage - 1 >= 0, stage - 1 < targets.count {
        return template.replacingOccurrences(of: "{n}", with: hallFmtCount(targets[stage - 1]))
    }
    return badge.description ?? ""
}

// MARK: - 成就殿堂（对齐安卓 AchievementHallScreen，图标走 URL/lucide 简化渲染）

struct AchievementHallView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = AchievementHallViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var rail = "general"
    @State private var filter = "all" // all / got / not
    @State private var detailId: Int64?

    private var badges: [BadgeHallItem] { vm.hall?.badges ?? [] }
    private var detail: BadgeHallItem? { badges.first { $0.id == detailId } }
    private var railBadges: [BadgeHallItem] {
        var list = hallRailFilter(badges, rail)
        switch filter {
        case "got": list = list.filter { ($0.stage ?? 0) > 0 }
        case "not": list = list.filter { ($0.stage ?? 0) == 0 }
        default: break
        }
        return list.sorted { ($0.stage ?? 0) > 0 && ($1.stage ?? 0) == 0 }
    }

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if vm.isLoading || vm.hall == nil {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else {
                    totalCard
                    mountSlots
                    HStack(alignment: .top, spacing: 0) {
                        catRail
                        badgeList
                    }
                    .padding(.top, 12)
                }
            }
        }
        .onAppear { vm.load() }
        .sheet(item: Binding(
            get: { detail.map { HallDetailTarget(id: $0.id) } },
            set: { detailId = $0?.id }
        )) { _ in
            if let d = detail {
                detailSheet(d)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Noir.noir)
            }
        }
    }

    private struct HallDetailTarget: Identifiable { let id: Int64 }

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
            }
            Spacer()
            VStack(spacing: 2) {
                Text("成就殿堂")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("HALL OF THORNS · \(vm.hall?.totalStages ?? 0)")
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 总积分卡

    private var totalCard: some View {
        HStack(spacing: 0) {
            statCell("\(vm.hall?.totalScore ?? 0)", "成就分")
            Divider().background(Color.white.opacity(0.1)).frame(height: 34)
            statCell("\(vm.hall?.litStages ?? 0)/\(vm.hall?.totalStages ?? 0)", "点亮阶位")
            Divider().background(Color.white.opacity(0.1)).frame(height: 34)
            statCell("🥕\(vm.hall?.carrotBalance ?? 0)", "萝贝余额")
        }
        .padding(.vertical, 14)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.5), Color(red: 0x0E/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 挂载槽（5 槽，点已挂载勋章可卸下）

    private var mountSlots: some View {
        let mountedIds = vm.hall?.mountedIds ?? []
        return HStack(spacing: 14) {
            Text("挂载")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .tracking(2)
                .foregroundStyle(Noir.goldText)
            ForEach(0..<5, id: \.self) { i in
                let badge = i < mountedIds.count ? badges.first { $0.id == mountedIds[i] } : nil
                ZStack {
                    Circle()
                        .fill(Noir.noir2)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(
                            badge != nil ? Noir.gold.opacity(0.6) : Color.white.opacity(0.12),
                            style: badge != nil ? StrokeStyle(lineWidth: 1.5) : StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    if let badge {
                        HallMedalIcon(badge: badge, size: 34)
                            .onTapGesture { vm.toggleMount(badge) }
                    }
                }
            }
            Spacer()
            Text("\(mountedIds.count)/5")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 左侧分类轨

    private var catRail: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(HALL_CAT_META, id: \.key) { meta in
                    let list = hallRailFilter(badges, meta.key)
                    let got = list.reduce(0) { $0 + ($1.stage ?? 0) }
                    let total = list.reduce(0) { $0 + ($1.stages ?? 0) }
                    let active = rail == meta.key
                    Button {
                        rail = meta.key
                        filter = "all"
                    } label: {
                        VStack(spacing: 3) {
                            Text(meta.name)
                                .font(.system(size: 12, weight: active ? .bold : .medium, design: .serif))
                                .foregroundStyle(active ? meta.color : .white.opacity(0.45))
                            Text("\(got)/\(total)")
                                .font(.system(size: 8.5))
                                .foregroundStyle(active ? meta.color.opacity(0.8) : .white.opacity(0.25))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(active ? meta.color.opacity(0.12) : Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(active ? meta.color.opacity(0.5) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 74)
    }

    // MARK: - 右侧清单

    private var badgeList: some View {
        ScrollView {
            VStack(spacing: 10) {
                catProgressCard
                let rows = stride(from: 0, to: railBadges.count, by: 3).map {
                    Array(railBadges[$0..<min($0 + 3, railBadges.count)])
                }
                ForEach(rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 6) {
                        ForEach(rows[rowIdx]) { badge in
                            medalCell(badge)
                        }
                        if rows[rowIdx].count < 3 {
                            ForEach(0..<(3 - rows[rowIdx].count), id: \.self) { _ in
                                Spacer().frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                if railBadges.isEmpty {
                    Text("该分类暂无勋章")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 30)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 30)
        }
    }

    private var catProgressCard: some View {
        let list = hallRailFilter(badges, rail)
        let got = list.reduce(0) { $0 + ($1.stage ?? 0) }
        let total = list.reduce(0) { $0 + ($1.stages ?? 0) }
        let meta = HALL_CAT_META.first { $0.key == rail }
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(meta?.name ?? "")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text("已点亮 \(got)/\(total) 阶")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            HStack(spacing: 6) {
                filterPill("all", "全部")
                filterPill("got", "已点亮")
                filterPill("not", "未点亮")
            }
        }
        .padding(12)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.hairlineGold, lineWidth: 1))
    }

    private func filterPill(_ key: String, _ label: String) -> some View {
        let active = filter == key
        return Button { filter = key } label: {
            Text(label)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Noir.goldLight : .white.opacity(0.35))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? Noir.gold.opacity(0.15) : Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Noir.gold.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func medalCell(_ badge: BadgeHallItem) -> some View {
        let catColor = HALL_CAT_META.first { $0.key == badge.cat }?.color ?? Noir.gold
        let lit = (badge.stage ?? 0) > 0
        let concealed = badge.hidden == true && !lit
        return VStack(spacing: 0) {
            if concealed {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    Text("?")
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.bottom, 6)
                Text("未知彩蛋")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.25))
            } else {
                ZStack(alignment: .topTrailing) {
                    HallMedalIcon(badge: badge, size: 44)
                        .saturation(lit ? 1 : 0)
                        .opacity(lit ? 1 : 0.45)
                    if badge.sealed == true {
                        Text("绝版")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0D/255))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(LinearGradient(colors: [Noir.gold, Noir.goldLight], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                            .offset(x: 8, y: -4)
                    }
                }
                .padding(.bottom, 6)
                // 名称 + 阶（罗马数字跟在名称后面）
                HStack(spacing: 3) {
                    Text(badge.name ?? "")
                        .font(.system(size: 9.5))
                        .foregroundStyle(lit ? Noir.ivory.opacity(0.85) : .white.opacity(0.3))
                        .lineLimit(1)
                    if lit, let s = badge.stage, s > 0, s <= 10 {
                        Text(HALL_NUMERALS[s - 1])
                            .font(.system(size: 8.5, weight: .semibold, design: .serif))
                            .foregroundStyle(catColor)
                    }
                }
                // 十阶微进度（对齐安卓 MedalCell 段位分段条）
                if (badge.stages ?? 1) > 1 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(badge.stages ?? 1, 10), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i < (badge.stage ?? 0) ? catColor : Color.white.opacity(0.1))
                                .frame(width: 7, height: 3)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(lit ? catColor.opacity(0.07) : Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(lit ? catColor.opacity(0.33) : Color.white.opacity(0.07), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            // 点未知彩蛋：可能惊醒「琥珀里的虫」（对齐安卓）
            if concealed { EggTrigger.report("unknown") }
            detailId = badge.id
        }
    }

    // MARK: - 勋章详情弹层

    private func detailSheet(_ badge: BadgeHallItem) -> some View {
        let tier = hallTierOf(badge)
        let cur = badge.stage ?? 0
        let total = badge.stages ?? 1
        return ScrollView {
            VStack(spacing: 14) {
                HallMedalIcon(badge: badge, size: 72)
                    .saturation(cur > 0 ? 1 : 0)
                    .opacity(cur > 0 ? 1 : 0.5)
                    .padding(.top, 28)
                Text(badge.hidden == true && cur == 0 ? "？？？" : (badge.name ?? ""))
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text("\(badge.rarity ?? "COMMON") · +\(badge.score ?? 0) 成就分 · 🥕\(badge.reward ?? 0)")
                    .font(.system(size: 11))
                    .foregroundStyle(hallTierColor(tier))
                if let desc = badge.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                // 阶位列表
                VStack(spacing: 0) {
                    ForEach(1...max(total, 1), id: \.self) { s in
                        HStack(spacing: 10) {
                            Text(s <= 10 ? HALL_NUMERALS[s - 1] : "\(s)")
                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                .foregroundStyle(s <= cur ? Noir.goldLight : .white.opacity(0.25))
                                .frame(width: 24)
                            Text(hallStageCond(badge, s))
                                .font(.system(size: 11.5))
                                .foregroundStyle(s <= cur ? Noir.ivory : .white.opacity(0.35))
                            Spacer()
                            if s <= cur {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Noir.gold)
                            }
                        }
                        .padding(.vertical, 9)
                        if s < total {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.hairlineGold, lineWidth: 1))
                .padding(.horizontal, 20)
                // 进度
                if cur < total, (badge.progress ?? 0) > 0 {
                    Text("当前进度：\(hallFmtCount(badge.progress ?? 0))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
                // 挂载/卸下（仅已点亮可挂载）
                if cur > 0 {
                    Button { vm.toggleMount(badge) } label: {
                        Text(badge.mounted == true ? "从头像卸下" : "挂载到头像侧边")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 32)
        }
    }
}

// MARK: - 勋章图标（URL / lucide: / 占位）

struct HallMedalIcon: View {
    let badge: BadgeHallItem
    var size: CGFloat = 44

    var body: some View {
        if let icon = badge.icon, icon.hasPrefix("http") {
            WebImage(url: webImageURL(icon), contentMode: .fit) {
                placeholder
            }
            .frame(width: size, height: size)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: sfSymbol(badge.icon))
            .font(.system(size: size * 0.55))
            .foregroundStyle(hallTierColor(hallTierOf(badge)))
            .frame(width: size, height: size)
    }

    /// lucide:xxx → SF Symbol 近似映射（对齐安卓 lucideRes 的常用项）
    private func sfSymbol(_ icon: String?) -> String {
        guard let icon, icon.hasPrefix("lucide:") else { return "medal" }
        let name = String(icon.dropFirst("lucide:".count))
        let map = [
            "heart": "heart.fill", "star": "star.fill", "crown": "crown.fill",
            "flame": "flame.fill", "gift": "gift.fill", "moon": "moon.fill",
            "sun": "sun.max.fill", "zap": "bolt.fill", "users": "person.2.fill",
            "message": "bubble.left.fill", "camera": "camera.fill", "map-pin": "mappin",
            "shield": "shield.fill", "gem": "diamond.fill", "sparkles": "sparkles",
            "egg": "egg.fill", "ticket": "ticket.fill", "music": "music.note",
        ]
        return map[name] ?? "medal.fill"
    }
}

// MARK: - ViewModel（对齐安卓 AchievementHallViewModel）

@MainActor
final class AchievementHallViewModel: ObservableObject {

    @Published var isLoading = true
    @Published var hall: AchievementHallResp?

    private var eggRolled = false

    func load() {
        Task {
            hall = try? await BadgeAPI.achievementHall()
            isLoading = false
        }
        // 踏入成就殿堂 →「荆棘低语」；低概率随机掉落（对齐安卓 maybeTriggerEgg 20%）
        EggTrigger.report("hall")
        if !eggRolled {
            eggRolled = true
            if Int.random(in: 0..<100) < 20 {
                Task {
                    if let egg = try? await BadgeAPI.triggerEgg() {
                        EggBus.emit(egg)
                        hall = try? await BadgeAPI.achievementHall()
                    }
                }
            }
        }
    }

    /// 挂载/卸下（乐观更新 + 失败回滚，对齐安卓 toggleMount）
    func toggleMount(_ badge: BadgeHallItem) {
        guard let hall else { return }
        let target = !(badge.mounted ?? false)
        // 乐观翻转
        var badges = hall.badges ?? []
        if let idx = badges.firstIndex(where: { $0.id == badge.id }) {
            var b = badges[idx]
            b = BadgeHallItem(id: b.id, cat: b.cat, name: b.name, description: b.description,
                              icon: b.icon, rarity: b.rarity, stages: b.stages, targets: b.targets,
                              condTemplate: b.condTemplate, score: b.score, reward: b.reward,
                              hidden: b.hidden, sealed: b.sealed, stage: b.stage,
                              stageDates: b.stageDates, progress: b.progress, mounted: target)
            badges[idx] = b
        }
        var ids = hall.mountedIds ?? []
        if target {
            ids.append(badge.id)
            ids = Array(ids.suffix(5))
            // 挂满 5 枚 →「缝里的光」（对齐安卓）
            if ids.count >= 5 { EggTrigger.report("mount-full") }
        } else {
            ids.removeAll { $0 == badge.id }
        }
        self.hall = AchievementHallResp(totalScore: hall.totalScore, litStages: hall.litStages,
                                        totalStages: hall.totalStages, carrotBalance: hall.carrotBalance,
                                        mountedIds: ids, cats: hall.cats, badges: badges)
        Task {
            do {
                if badge.mounted == true {
                    _ = try await BadgeAPI.unmount(badgeId: badge.id)
                } else {
                    _ = try await BadgeAPI.mount(badgeId: badge.id)
                }
                jjtShowToast(target ? "已挂载到头像侧边" : "已从头像卸下")
                NotificationCenter.default.post(name: .jjtBadgesChanged, object: nil)
            } catch {
                jjtShowToast(error.localizedDescription)
            }
            // 回源真实状态
            self.hall = try? await BadgeAPI.achievementHall()
        }
    }
}
