import SwiftUI

/// 胡萝卜粉（任务体系点缀色，对齐安卓 CarrotPink #ff7d9c）
private let CarrotPink = Color(red: 0xFF/255, green: 0x7D/255, blue: 0x9C/255)

/// 任务中心（对齐安卓 TaskCenterScreen）
/// 结构：顶栏 → 萝贝余额卡 → 签到卡 → 每日任务组 → 累积任务组
struct TaskCenterView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = TaskCenterViewModel()
    @Environment(\.dismiss) private var dismiss

    private var daily: [TaskItem] { vm.tasks.filter { $0.type == "DAILY" } }
    private var cumulative: [TaskItem] { vm.tasks.filter { $0.type != "DAILY" } }

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 0) {
                        balanceCard
                        signInCard
                        taskGroup(title: "每日任务", en: "DAILY", icon: "calendar", tint: CarrotPink, tasks: daily)
                        taskGroup(title: "累积任务", en: "CUMULATIVE", icon: "moon.stars", tint: Noir.gold, tasks: cumulative)
                        Text("每日任务 0 点重置 · 累积任务长期有效")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.25))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                            .padding(.bottom, 24)
                    }
                }
                .refreshable { vm.load() }
            }
        }
        .onAppear { vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("确定") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .onChange(of: vm.toast) { _, t in
            if let t { jjtShowToast(t); vm.toast = nil }
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
            }
            Spacer()
            VStack(spacing: 2) {
                Text("任务中心")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("TASK CENTER · EARN CARROTS")
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

    // MARK: - 萝贝余额卡

    private var balanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("萝 币 余 额")
                    .font(.system(size: 9))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.4))
                HStack(spacing: 4) {
                    Text("🥕")
                        .font(.system(size: 18))
                    Text("\(vm.carrotBalance)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(CarrotPink)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("完成任务获得萝贝")
                Text("萝贝送礼可累计消费层级")
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.35))
        }
        .padding(16)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.55), Color(red: 0x0E/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 签到卡

    private var signInCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("每日签到")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text("已连续签到 \(vm.continuousDays) 天 · 签到 +5 萝贝")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button { vm.signIn() } label: {
                Text(vm.signedToday ? "已签到" : "签到")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(vm.signedToday ? .white.opacity(0.35) : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(vm.signedToday
                                ? AnyShapeStyle(Color.white.opacity(0.05))
                                : AnyShapeStyle(LinearGradient(colors: [Noir.crimsonHot, CarrotPink], startPoint: .leading, endPoint: .trailing)))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.signedToday)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 任务分组

    private func taskGroup(title: String, en: String, icon: String, tint: Color, tasks: [TaskItem]) -> some View {
        let done = tasks.filter { $0.status == "CLAIMED" || ($0.currentCount ?? 0) >= ($0.threshold ?? 0) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text(en)
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
                if !tasks.isEmpty {
                    Text("\(done)/\(tasks.count) 已达成")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 4)
            if tasks.isEmpty {
                Text(vm.isLoading ? "加载中…" : "暂无任务")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.textFaint)
                    .padding(.leading, 4)
            } else {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    // MARK: - 任务行

    private func taskRow(_ task: TaskItem) -> some View {
        let threshold = task.threshold ?? 0
        let progress = min(task.currentCount ?? 0, threshold)
        let done = (task.currentCount ?? 0) >= threshold
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CarrotPink.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(CarrotPink.opacity(0.4), lineWidth: 1))
                Image(systemName: Self.taskIcon(task.name ?? ""))
                    .font(.system(size: 14))
                    .foregroundStyle(CarrotPink)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.name ?? "")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Noir.ivory)
                    if let amount = task.rewardAmount, amount > 0 {
                        Text("🥕+\(amount)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(CarrotPink)
                    }
                    if task.rewardBadgeId != nil {
                        Text("🏅\(vm.badgeNames[task.rewardBadgeId!] ?? "勋章")")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Noir.gold)
                            .lineLimit(1)
                    }
                }
                if let desc = task.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                // 细进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(CarrotPink)
                            .frame(width: threshold > 0 ? geo.size.width * CGFloat(progress) / CGFloat(threshold) : 0)
                    }
                }
                .frame(height: 3.5)
                .padding(.top, 4)
            }
            VStack(spacing: 4) {
                Text("\(progress)/\(threshold)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                switch task.status {
                case "CLAIMABLE":
                    Button { vm.claim(task) } label: {
                        Text("领取")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(LinearGradient(colors: [Noir.crimsonHot, CarrotPink], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                case "CLAIMED":
                    Text("✓ 已领取")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                default:
                    Text(done ? "待结算" : "进行中")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    /// 按任务名映射图标（对齐安卓 taskIcon）
    private static func taskIcon(_ name: String) -> String {
        if name.contains("签到") || name.contains("登录") || name.contains("归巢") || name.contains("约定") || name.contains("月相") { return "calendar" }
        if name.contains("浏览") || name.contains("漫步") || name.contains("广场") { return "safari" }
        if name.contains("私聊") || name.contains("密语") { return "bubble.left" }
        if name.contains("发帖") || name.contains("动态") || name.contains("一笔") || name.contains("笔耕") { return "square.and.pencil" }
        if name.contains("礼物") || name.contains("馈赠") || name.contains("慷慨") { return "gift" }
        if name.contains("打卡") { return "mappin" }
        if name.contains("粉丝") || name.contains("拥趸") { return "flame" }
        if name.contains("羁绊") { return "link" }
        if name.contains("认证") { return "checkmark.shield" }
        if name.contains("资料") { return "person" }
        if name.contains("关注") { return "person.badge.plus" }
        return "sparkles"
    }
}

// MARK: - ViewModel（对齐安卓 TaskViewModel）

@MainActor
final class TaskCenterViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var tasks: [TaskItem] = []
    @Published var signedToday = false
    @Published var continuousDays = 0
    @Published var carrotBalance: Int64 = 0
    @Published var badgeNames: [Int64: String] = [:]
    @Published var error: String?
    @Published var toast: String?

    func load() {
        isLoading = true
        Task {
            async let taskList = TaskAPI.taskList()
            async let status = TaskAPI.signInStatus()
            tasks = (try? await taskList) ?? []
            if let s = try? await status {
                signedToday = s.signedToday
                continuousDays = s.continuousDays
            }
            isLoading = false
            await loadBadgeNames()
            await loadCarrot()
        }
    }

    /// 萝贝余额（radish_coin 钱包，独立容错）
    private func loadCarrot() async {
        if let w = try? await WalletAPI.getWallet("radish_coin") {
            carrotBalance = w.availableAmount ?? 0
        }
    }

    /// 任务奖励涉及的勋章名（从勋章墙取，对齐安卓 loadBadgeInfos）
    private func loadBadgeNames() async {
        let ids = Set(tasks.compactMap(\.rewardBadgeId))
        guard !ids.isEmpty else { return }
        if let wall = try? await BadgeAPI.badgeWall() {
            for b in wall where ids.contains(b.id) {
                badgeNames[b.id] = b.name
            }
        }
    }

    func signIn() {
        Task {
            do {
                let r = try await TaskAPI.signIn()
                signedToday = true
                continuousDays = r.continuousDays
                toast = "签到成功！连续\(r.continuousDays)天，+\(r.rewardAmount)萝贝"
                load() // 刷新任务进度（签到任务可能变成可领取）
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func claim(_ task: TaskItem) {
        Task {
            do {
                _ = try await TaskAPI.claim(taskId: task.taskId)
                toast = "「\(task.name ?? "")」奖励已领取"
                load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
