import SwiftUI

/// 暗夜选美主页（对齐安卓 PageantHomeScreen）：
/// 顶栏（今日可投） → 舞台 Hero（倒计时） → 参赛要求 → 我要参选 →
/// 前三甲 → 全部参赛者 → 投票播报 → 我的资产
struct PageantHomeView: View {

    @StateObject private var vm = PageantHomeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEntrySheet = false
    @State private var openEntryId: Int64?
    /// 每分钟刷新倒计时
    @State private var nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            if vm.isLoading, vm.activity == nil {
                ProgressView().tint(Noir.crimson).scaleEffect(1.3)
            } else if vm.notStarted {
                Text("选美活动筹备中，敬请期待")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            } else if let activity = vm.activity {
                content(activity)
            }
        }
        .task { vm.load() }
        // 5 秒轮询：榜单票数/播报实时更新（静默刷新不闪加载态）
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                vm.refresh()
            }
        }
        // 每分钟走一次倒计时
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            }
        }
        // 参选/编辑半屏
        .sheet(isPresented: $showEntrySheet, onDismiss: { vm.refresh() }) {
            PageantEntrySheet()
                .presentationDetents([.large])
                .presentationBackground(Noir.noir)
        }
        // 参赛者详情（左右滑切选手）
        .fullScreenCover(isPresented: Binding(
            get: { openEntryId != nil },
            set: { if !$0 { openEntryId = nil } }
        )) {
            if let id = openEntryId {
                PageantEntryView(entryId: id)
            }
        }
    }

    // MARK: - 主体

    private func content(_ activity: PageantActivity) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar(activity)
                heroStage(activity)
                rulesCard(activity)
                enterButton(activity)
                podium
                allEntriesHeader
                entriesGrid
                liveFeed
                Text("我的萝贝 \(activity.carrotBalance ?? 0) · 兔币 \(activity.rabbitBalance ?? 0)")
                    .font(.system(size: 10))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    /// 今日可投 = 萝贝剩余 + 兔币剩余 + 分享机会余量
    private func todayLeft(_ a: PageantActivity) -> Int {
        let carrotLeft = (a.carrotDaily ?? 0) - (a.myCarrotUsed ?? 0)
        let rabbitLeft = (a.rabbitDaily ?? 0) - (a.myRabbitUsed ?? 0)
        let shareChances = (a.myShareEarned ?? 0) - (a.myShareUsed ?? 0)
        return max(carrotLeft + rabbitLeft + shareChances, 0)
    }

    // MARK: - 顶栏

    private func topBar(_ activity: PageantActivity) -> some View {
        HStack {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("暗夜选美")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text("NOIR PAGEANT")
                        .font(.system(size: 9, design: .serif).italic())
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "ticket")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.goldLight)
                Text("今日可投 \(todayLeft(activity))")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.goldLight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Noir.gold.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Noir.gold.opacity(0.45), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - 舞台 Hero

    private func heroStage(_ activity: PageantActivity) -> some View {
        let notStarted = (activity.startTime ?? 0) > nowMs
        let targetMs = notStarted ? activity.startTime : activity.endTime
        let remainMs = max((targetMs ?? 0) - nowMs, 0)
        let days = remainMs / 86_400_000
        let hours = (remainMs / 3_600_000) % 24

        return ZStack(alignment: .topLeading) {
            // 舞台背景：后台配置优先
            if let cover = activity.cover, !cover.isEmpty {
                AsyncImage(url: webImageURL(cover)) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir2 }
                }
            } else {
                Noir.noir2
            }
            // 压暗渐变
            LinearGradient(stops: [
                .init(color: Noir.noir.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.35),
                .init(color: Noir.noir.opacity(0.94), location: 1),
            ], startPoint: .top, endPoint: .bottom)

            // 届次徽章
            Text(activity.seasonTag ?? "首届 · 荆棘之夜")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .padding(16)

            // 底部文案
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(activity.nameEn ?? "WHO WEARS THE CROWN")
                    .font(.system(size: 10, design: .serif).italic())
                    .tracking(3)
                    .foregroundStyle(Noir.goldLight.opacity(0.85))
                Text(activity.name ?? "荆棘王座之选")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(Noir.goldText)
                    .padding(.top, 6)
                HStack(spacing: 0) {
                    if targetMs != nil {
                        Text("\(days)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Noir.crimsonHot)
                        Text(" 天 ")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(hours)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Noir.crimsonHot)
                        Text(notStarted ? " 小时后开启" : " 小时后落幕")
                            .font(.system(size: 10))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("  |  ")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Text(activity.rewardText ?? "")
                        .font(.system(size: 10))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 10)
            }
            .padding(20)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 参赛要求

    @ViewBuilder
    private func rulesCard(_ activity: PageantActivity) -> some View {
        let lines = (activity.rules ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text("参赛要求")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text("RULES")
                        .font(.system(size: 9, design: .serif).italic())
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.bottom, 12)
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Noir.gold).frame(width: 4, height: 4).padding(.top, 6)
                        Text(line)
                            .font(.system(size: 11))
                            .lineSpacing(5)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.hairlineGold, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - 我要参选

    private func enterButton(_ activity: PageantActivity) -> some View {
        let notStarted = (activity.startTime ?? 0) > nowMs
        return Button { showEntrySheet = true } label: {
            Text(notStarted
                 ? "活动未开始 · 敬请期待"
                 : (activity.myEntryId != nil ? "编辑我的参赛作品" : "我要参选 · 上传我的暗夜之姿"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(notStarted ? .white.opacity(0.45) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(LinearGradient(
                    colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                    startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .disabled(notStarted)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 前三甲（按票数取；选手列表整体按报名时间倒序）

    @ViewBuilder
    private var podium: some View {
        let top3 = vm.entries.filter { $0.auditStatus == 1 }
            .sorted { ($0.votes ?? 0) > ($1.votes ?? 0) }
            .prefix(3)
        if top3.count == 3 {
            HStack(alignment: .bottom, spacing: 12) {
                podiumCard(top3[1], rank: 2, height: 120)
                podiumCard(top3[0], rank: 1, height: 152)
                podiumCard(top3[2], rank: 3, height: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
    }

    private func podiumCard(_ entry: PageantEntry, rank: Int, height: CGFloat) -> some View {
        let isChampion = rank == 1
        return VStack(spacing: 0) {
            if isChampion {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Noir.goldPale)
                    .padding(.bottom, 4)
            }
            ZStack(alignment: .topLeading) {
                entryCover(entry)
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                Text("N°\(rank)")
                    .font(.system(size: isChampion ? 15 : 14, weight: .semibold, design: .serif))
                    .foregroundStyle(isChampion ? Noir.goldText : AnyShapeStyle(Color.white.opacity(0.7)))
                    .padding(.leading, 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Spacer()
                    Text(entry.nickname ?? "用户\(entry.userId)")
                        .font(.system(size: isChampion ? 15 : 13, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    Text("\(entry.votes ?? 0) 票")
                        .font(.system(size: isChampion ? 12 : 11, weight: .semibold, design: .serif))
                        .foregroundStyle(isChampion ? Noir.goldText : AnyShapeStyle(Noir.gold))
                }
                .padding(10)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                isChampion ? Noir.goldPale.opacity(0.75) : Noir.gold.opacity(0.4),
                lineWidth: isChampion ? 1.5 : 1))
            .contentShape(Rectangle())
            .onTapGesture { openEntryId = entry.id }
        }
        .frame(maxWidth: .infinity)
    }

    /// 作品封面：视频显示封面图，否则第一张图
    private func entryCover(_ entry: PageantEntry) -> some View {
        let url = (entry.video?.isEmpty == false) ? entry.videoCover : entry.images?.first
        return AsyncImage(url: webImageURL(url)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir3 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - 全部参赛者

    private var allEntriesHeader: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text("全部参赛者")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Text("ALL ENTRIES")
                .font(.system(size: 9, design: .serif).italic())
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
            Text("\(vm.entries.count) 人登台")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var entriesGrid: some View {
        // 双列网格（后端已按报名时间倒序返回）
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(vm.entries) { entry in
                entryCard(entry)
            }
        }
        .padding(.horizontal, 20)
    }

    private func entryCard(_ entry: PageantEntry) -> some View {
        let mine = entry.mine == true
        let pending = entry.auditStatus == 0 // 审核中（仅本人可见）
        return ZStack(alignment: .topTrailing) {
            entryCover(entry)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.3), location: 0.4),
                .init(color: .black.opacity(0.95), location: 1),
            ], startPoint: .top, endPoint: .bottom)

            // 审核中遮罩（机审未通过待人工复核，仅本人可见）
            if pending {
                Color.black.opacity(0.55)
                VStack(spacing: 4) {
                    Text("审核中")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Noir.goldLight)
                    Text("人工复核通过后公开展示")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            // 参赛号（右上角，中性小字）
            if let no = entry.entryNo {
                Text(String(format: "%03d号", no))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
                    .padding(8)
            }
            if mine {
                VStack {
                    HStack {
                        Text("我的作品")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Noir.crimsonHot))
                            .padding(8)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // 底部：票数 → 签名 → 头像昵称
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text("\(entry.votes ?? 0) 票")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Noir.crimsonHot)
                if let line = entry.line, !line.isEmpty {
                    Text("“\(line)”")
                        .font(.system(size: 9.5).italic())
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                HStack(spacing: 6) {
                    AppAvatar(url: entry.avatar, size: 18,
                              frameURL: entry.avatarFrame, frameScale: CGFloat(entry.avatarFrameScale ?? 1.15))
                        .frame(width: 22, height: 22)
                    Text(entry.nickname ?? "用户\(entry.userId)")
                        .font(.system(size: 13.5, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
            mine ? Noir.crimsonHot.opacity(0.55) : Noir.gold.opacity(0.25),
            lineWidth: mine ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { if !pending { openEntryId = entry.id } }
    }

    // MARK: - 投票播报

    @ViewBuilder
    private var liveFeed: some View {
        if !vm.feed.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text("投票播报")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text("LIVE FEED")
                        .font(.system(size: 9, design: .serif).italic())
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.bottom, 12)
                VStack(spacing: 0) {
                    ForEach(Array(vm.feed.prefix(6).enumerated()), id: \.offset) { i, item in
                        HStack(spacing: 8) {
                            Circle().fill(Noir.gold).frame(width: 4, height: 4)
                            Text("\(item.voterNickname ?? "神秘人") 给 \(item.ownerNickname ?? "神秘选手") 投了 \(item.votes ?? 1) 票")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                            Spacer()
                            Text(item.timeText ?? "")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .padding(.vertical, 10)
                        if i < min(vm.feed.count, 6) - 1 {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
    }
}

// MARK: - ViewModel（5 秒轮询静默刷新）

@MainActor
final class PageantHomeViewModel: ObservableObject {
    @Published var activity: PageantActivity?
    @Published var entries: [PageantEntry] = []
    @Published var feed: [PageantFeedItem] = []
    @Published var isLoading = false
    @Published var notStarted = false

    func load() {
        guard !isLoading, activity == nil else { return }
        isLoading = true
        Task {
            async let a = PageantAPI.activity()
            async let e = PageantAPI.entries()
            async let f = PageantAPI.feed()
            activity = try? await a
            entries = (try? await e) ?? []
            feed = (try? await f) ?? []
            // 无在办活动（后端约定 404/空）→ 筹备中
            notStarted = activity == nil
            isLoading = false
        }
    }

    /// 轮询静默刷新（不动 isLoading，不闪加载态）
    func refresh() {
        Task {
            if let a = try? await PageantAPI.activity() { activity = a }
            if let e = try? await PageantAPI.entries() { entries = e }
            if let f = try? await PageantAPI.feed() { feed = f }
        }
    }
}
