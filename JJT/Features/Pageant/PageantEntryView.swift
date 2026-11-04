import SwiftUI
import AVKit

/// 参赛者详情宿主（对齐安卓 PageantEntryScreen）：左右滑按榜单顺序切换选手。
/// 每页独立详情状态（按作品 ID key），当前停留页才 4 秒轮询票数。
struct PageantEntryView: View {

    let entryId: Int64
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pager = PageantPagerModel()
    @State private var selection = 0

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            if pager.entries.contains(where: { $0.id == entryId }) {
                TabView(selection: $selection) {
                    ForEach(pager.entries.indices, id: \.self) { i in
                        PageantEntryPage(entryId: pager.entries[i].id, active: selection == i,
                                         onBack: { dismiss() }, vm: pager.model(for: pager.entries[i].id))
                            .tag(i)
                            .id("pageant-entry-\(pager.entries[i].id)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            } else {
                // 榜单加载期间/失败或往期深链：当前作品先显示，不被全量 entries 门控
                PageantEntryPage(entryId: entryId, active: true, onBack: { dismiss() },
                                 vm: pager.model(for: entryId))
                    .id("pageant-entry-\(entryId)")
            }
        }
        .task {
            await pager.load()
            selection = pager.entries.firstIndex { $0.id == entryId } ?? 0
        }
    }
}

@MainActor
private final class PageantPagerModel: ObservableObject {
    @Published var entries: [PageantEntry] = []
    @Published var isLoading = false
    private var models: [Int64: PageantEntryModel] = [:]

    /// 单页 → TabView 及来回翻页都复用同一作品 VM，避免结构变化触发重复首载。
    func model(for entryId: Int64) -> PageantEntryModel {
        if let existing = models[entryId] { return existing }
        let created = PageantEntryModel()
        models[entryId] = created
        return created
    }

    func load() async {
        guard !isLoading, entries.isEmpty else { return }
        isLoading = true
        entries = (try? await PageantAPI.entries()) ?? []
        isLoading = false
    }
}

// MARK: - 详情状态

@MainActor
private final class PageantEntryModel: ObservableObject {
    @Published var detail: PageantEntryDetail?
    @Published var activity: PageantActivity?
    @Published var isLoading = false
    /// 投票爆发动效：+N
    @Published var burst = 0
    /// 投票请求进行中：防连点（并发扣票会冲突）
    @Published var voting = false
    @Published var error: String?
    /// 投票贡献榜全量（打开弹层时拉取）
    @Published var voterBoard: [PageantEntryDetail.Voter] = []
    @Published var voterBoardLoading = false
    /// 我是否已隐藏投票信息（服务端为准）
    @Published var voterHidden = false
    @Published var voterHiddenBusy = false
    @Published var loadError: String?
    @Published var activityLoadFailed = false

    private var snapshotGeneration = 0
    private var snapshotInFlight = false
    private var realtimeInFlight = false
    private var lastSnapshotAt = Date.distantPast

    /// 首载/完整快照：详情与活动并行，详情先发布；操作后的强制刷新采用 latest-wins。
    func load(_ entryId: Int64, force: Bool = false) async {
        if !force {
            // 单页/TabView 切换会取消旧 .task：等待在途首载结束，成功复用、失败自动重试
            while snapshotInFlight && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if Task.isCancelled { return }
            if detail != nil && activity != nil { return }
        }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        snapshotInFlight = true
        isLoading = detail == nil
        loadError = nil
        activityLoadFailed = false
        defer {
            if generation == snapshotGeneration { snapshotInFlight = false }
        }

        async let detailResult = try? PageantAPI.entryDetail(id: entryId)
        async let activityResult = try? PageantAPI.activity()

        let d = await detailResult
        if generation == snapshotGeneration {
            if let d {
                detail = d
            } else if detail == nil {
                loadError = "作品加载失败，请检查网络后重试"
            }
            isLoading = false
        }

        let a = await activityResult
        if generation == snapshotGeneration {
            if let a {
                activity = a
                if let v = a.voterHidden { voterHidden = v }
            }
            activityLoadFailed = a == nil && activity == nil
            if d != nil && a != nil { lastSnapshotAt = Date() }
        }
    }

    /// 4 秒轻量轮询：只更新票数/名次/差票；完整快照开始后丢弃旧实时结果。
    func refreshRealtime(_ entryId: Int64) async {
        guard detail != nil, !snapshotInFlight, !realtimeInFlight else { return }
        realtimeInFlight = true
        let generation = snapshotGeneration
        defer { realtimeInFlight = false }
        guard let realtime = try? await PageantAPI.entryRealtime(id: entryId),
              generation == snapshotGeneration,
              var updated = detail,
              updated.id == realtime.entryId else { return }
        updated.votes = realtime.votes ?? updated.votes
        updated.rank = realtime.rank ?? updated.rank
        updated.gapVotes = realtime.gapVotes ?? updated.gapVotes
        detail = updated
    }

    /// 回前台/单页切 Pager：先等在途任务收尾，成功不重复、失败立即重试。
    func refreshSnapshotIfStale(_ entryId: Int64) async {
        while snapshotInFlight && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if Task.isCancelled { return }
        guard Date().timeIntervalSince(lastSnapshotAt) >= 30 else { return }
        await refreshSnapshot(entryId)
    }

    /// 30 秒完整快照；首载仍在途时不叠加。
    func refreshSnapshot(_ entryId: Int64) async {
        guard !snapshotInFlight else { return }
        await load(entryId, force: true)
    }

    /// 拉取投票贡献榜全量（弹层打开时调用；不占用详情轮询）
    func loadVoterBoard(_ entryId: Int64) async {
        guard !voterBoardLoading else { return }
        voterBoardLoading = true
        if let list = try? await PageantAPI.entryVoters(id: entryId) {
            voterBoard = list
        } else {
            jjtShowToast("投票榜单加载失败，请稍后重试")
        }
        voterBoardLoading = false
    }

    /// 隐藏/恢复我的投票信息；成功后刷新详情与贡献榜（昵称脱敏即时生效）
    func setVoterHidden(_ entryId: Int64, hidden: Bool) async {
        guard !voterHiddenBusy else { return }
        voterHiddenBusy = true
        do {
            _ = try await PageantAPI.setVoterHidden(hidden)
            voterHidden = hidden
            jjtShowToast(hidden ? "已隐藏我的投票信息" : "已恢复我的投票信息")
            await load(entryId, force: true)
            await loadVoterBoard(entryId)
        } catch let e as APIError {
            if case .business(_, let msg) = e { jjtShowToast(msg) } else { jjtShowToast("网络异常") }
        } catch {
            jjtShowToast("网络异常")
        }
        voterHiddenBusy = false
    }

    /// 票池投票：服务端按 免费→分享→萝贝→兔币 顺序扣票。成功后刷新 + 爆发动效
    func voteFromPool(entryId: Int64, votes: Int) {
        guard !voting else { return }
        voting = true
        Task {
            do {
                _ = try await PageantAPI.votePool(PageantPoolVoteReq(entryId: entryId, votes: votes))
                burst = votes
                Task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    burst = 0
                }
                await load(entryId, force: true)
            } catch let e as APIError {
                if case .business(_, let msg) = e {
                    error = msg
                } else {
                    error = "网络异常"
                }
            } catch {
                self.error = "网络异常"
            }
            voting = false
        }
    }

    /// 购票入池：扣兔币/萝贝钱包后进票池。payPassword：兔币渠道必传（守卫调用）
    /// 失败抛异常由调用方处理（密码错误/余额不足由守卫统一处理）
    func purchase(entryId: Int64, type: String, count: Int, payPassword: String?) async throws {
        _ = try await PageantAPI.purchaseTicket(
            PageantTicketPurchaseReq(type: type, count: count, payPassword: payPassword))
        jjtShowToast("购票成功，已加入票池")
        await load(entryId, force: true)
    }

    /// 分享得机会：海报拉起系统分享 5 秒后再确认到账并提示（对齐安卓 shareEarn）
    func shareEarn(entryId: Int64) {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            do {
                _ = try await PageantAPI.shareEarn(entryId: entryId)
                jjtShowToast("分享成功，获得 1 次投票机会")
                await load(entryId, force: true)
            } catch let e as APIError {
                if case .business(_, let msg) = e { jjtShowToast(msg) }
            } catch { /* 静默 */ }
        }
    }
}

// MARK: - 单个参赛者详情页

private struct PageantEntryPage: View {

    let entryId: Int64
    let active: Bool
    let onBack: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject var vm: PageantEntryModel
    @State private var showVideoPlayer = false
    @State private var posterSharing = false
    @State private var showCarrotTask = false
    @State private var showTaskCenter = false
    @State private var showRecharge = false
    @State private var heroPage = 0
    /// 选手图片大图预览（双指缩放/左右滑，复用广场 ImagePreviewViewer）
    @State private var showImagePreview = false
    @State private var previewIndex = 0
    /// 投票贡献榜弹层
    @State private var showVoterBoard = false
    /// 点击参赛者头像打开的他人主页
    @State private var profileId: Int64?

    private var pollingID: String { "\(active)-\(scenePhase)" }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            if let detail = vm.detail {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(detail)
                        if let activity = vm.activity {
                            VoteArea(
                                activity: activity,
                                voting: vm.voting,
                                shareBusy: posterSharing,
                                onVotePool: { n in vm.voteFromPool(entryId: entryId, votes: n) },
                                onPurchase: { type, count, pwd in
                                    try await vm.purchase(entryId: entryId, type: type, count: count, payPassword: pwd)
                                },
                                onCarrotInsufficient: { showCarrotTask = true },
                                onNeedRecharge: { showRecharge = true },
                                onShare: { sharePoster(detail, activity) }
                            )
                        } else {
                            PageantActivityVotePlaceholder(failed: vm.activityLoadFailed) {
                                Task { await vm.load(entryId, force: true) }
                            }
                        }
                        voterBoardEntryCard(detail)
                        recentVoters(detail)
                        Spacer().frame(height: 40)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else if vm.isLoading || vm.loadError == nil {
                ProgressView().tint(Noir.crimson).scaleEffect(1.3)
            } else {
                VStack(spacing: 12) {
                    Text(vm.loadError ?? "作品暂不可用")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                    Button("重试") { Task { await vm.load(entryId, force: true) } }
                        .foregroundStyle(Noir.goldLight)
                }
            }

            // +N 爆发动效
            if vm.burst > 0 {
                Text("+\(vm.burst)")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Noir.crimsonHot)
                    .transition(.scale.combined(with: .opacity))
            }

            // 投票贡献榜弹层（全量投票人；隐藏/恢复入口在我的行）
            if showVoterBoard {
                PageantVoterBoardOverlay(
                    targetNickname: vm.detail?.nickname ?? "TA",
                    voters: vm.voterBoard,
                    loading: vm.voterBoardLoading,
                    myHidden: vm.voterHidden,
                    busy: vm.voterHiddenBusy,
                    onDismiss: { showVoterBoard = false },
                    onUserClick: { id in
                        showVoterBoard = false
                        profileId = id
                    },
                    onSetHidden: { hidden in
                        Task { await vm.setVoterHidden(entryId, hidden: hidden) }
                    }
                )
            }
        }
        .task { await vm.load(entryId) }
        .onChange(of: showVoterBoard) { _, open in
            if open { Task { await vm.loadVoterBoard(entryId) } }
        }
        // 仅当前页且前台 active：独立 4 秒轻量票数与 30 秒完整快照，回前台按新旧补一轮
        .task(id: pollingID) {
            guard active, scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await vm.refreshRealtime(entryId)
            }
        }
        .task(id: pollingID) {
            guard active, scenePhase == .active else { return }
            await vm.refreshSnapshotIfStale(entryId)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await vm.refreshSnapshot(entryId)
            }
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("知道了") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        // 萝贝不足：完成任务引导（与安卓 CarrotTaskDialog 同文案/同按钮）
        .overlay {
            if showCarrotTask {
                PageantCarrotTaskDialog(
                    onCancel: { showCarrotTask = false },
                    onGoTasks: {
                        showCarrotTask = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showTaskCenter = true }
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showTaskCenter) { TaskCenterView() }
        .fullScreenCover(isPresented: $showRecharge, onDismiss: {
            // 充值回来刷新票池/余额
            Task { await vm.load(entryId, force: true) }
        }) { CoinRechargeView() }
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let video = vm.detail?.video, let url = webImageURL(video) {
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea()
                    Button { showVideoPlayer = false } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.top, 20)
                }
            }
        }
        // 图片大图预览（从当前停留页进入）
        .fullScreenCover(isPresented: $showImagePreview) {
            ImagePreviewViewer(images: vm.detail?.images ?? [], initialIndex: previewIndex)
        }
        // 点击参赛者头像进入其主页
        .fullScreenCover(isPresented: Binding(
            get: { profileId != nil },
            set: { if !$0 { profileId = nil } }
        )) {
            if let id = profileId {
                UserProfileView(userId: id)
            }
        }
    }

    // MARK: - 作品大图区（图片+视频同一轮播；视频页多一个播放按钮）

    private func hero(_ detail: PageantEntryDetail) -> some View {
        let images = detail.images ?? []
        let hasVideo = !(detail.video ?? "").isEmpty
        let pageTotal = images.count + (hasVideo ? 1 : 0)

        return ZStack(alignment: .topLeading) {
            TabView(selection: $heroPage) {
                ForEach(images.indices, id: \.self) { i in
                    AsyncImage(url: webImageURL(images[i])) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Noir.noir3
                        }
                    }
                    .tag(i)
                    .contentShape(Rectangle())
                    // 单击图片 → 大图预览（双指缩放/双击放大，左右滑切图）
                    .onTapGesture { previewIndex = i; showImagePreview = true }
                }
                if hasVideo {
                    ZStack {
                        AsyncImage(url: webImageURL(detail.videoCover)) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir3 }
                        }
                        Button { showVideoPlayer = true } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .tag(images.count)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 380)

            // 顶部渐变
            LinearGradient(colors: [Noir.noir.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)
            // 返回（ScrollView ignoresSafeArea 顶到 y=0，让出状态栏/灵动岛高度）
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .padding(.leading, 20)
            .padding(.top, JJTMetrics.topSafeInset + 20)
            // 名次角标
            HStack {
                Spacer()
                Text("N°\(detail.rank ?? 0)")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                    .padding(.trailing, 20)
                    .padding(.top, JJTMetrics.topSafeInset + 20)
            }

            // 底部渐变 + 作者卡 + 票数
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    AppAvatar(url: detail.avatar, size: 48,
                              frameURL: detail.avatarFrame,
                              frameScale: CGFloat(detail.avatarFrameScale ?? 1.0))
                        .contentShape(Circle())
                        .onTapGesture { profileId = detail.userId }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(detail.nickname ?? "用户\(detail.userId)")
                                .font(.system(size: 21, weight: .bold, design: .serif))
                                .foregroundStyle(Noir.ivory)
                            ActivityVipChip(
                                vipLevel: detail.vipLevel,
                                vipLevelColor: detail.vipLevelColor,
                                levelInTier: detail.levelInTier,
                                fontSize: 9,
                                showLevel: false
                            )
                            if detail.rank == 1 {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Noir.goldPale)
                            }
                            if detail.mine == true {
                                Text("我的作品")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Noir.crimsonHot)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Noir.crimsonHot.opacity(0.2)))
                            }
                        }
                        if let line = detail.line, !line.isEmpty {
                            Text("“\(line)”")
                                .font(.system(size: 11).italic())
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                HStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 6) {
                        Text("\(detail.votes ?? 0)")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                            .foregroundStyle(Noir.goldText)
                        Text("实时票数")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    if (detail.rank ?? 1) > 1 {
                        Text("距上一名还差 \(detail.gapVotes ?? 0) 票")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.top, 12)
            }
            .padding(20)
            .background(
                LinearGradient(colors: [.clear, Noir.noir], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
        }
        .frame(height: 380)
    }

    // MARK: - 给 TA 投票的榜单（贡献榜入口）

    private func voterBoardEntryCard(_ detail: PageantEntryDetail) -> some View {
        Button { showVoterBoard = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Noir.gold.opacity(0.1))
                    Circle().stroke(Noir.gold.opacity(0.4), lineWidth: 1)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Noir.goldLight)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text("给 \(detail.nickname ?? "TA") 投票的榜单")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    Text("贡献榜 · 查看全部投票人")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer(minLength: 6)

                if let top = detail.topVoters, !top.isEmpty {
                    HStack(spacing: -10) {
                        ForEach(Array(top.prefix(3).enumerated()), id: \.offset) { i, voter in
                            AppAvatar(url: voter.avatar, size: 30,
                                      frameURL: voter.avatarFrame,
                                      frameScale: CGFloat(voter.avatarFrameScale ?? 1.0))
                                .background(Circle().fill(Noir.noir2))
                                .zIndex(Double(3 - i))
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Noir.hairlineGold, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    // MARK: - 最近投票人

    @ViewBuilder
    private func recentVoters(_ detail: PageantEntryDetail) -> some View {
        let voters = detail.recentVoters ?? []
        if !voters.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text("最近投票")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text("RECENT VOTERS")
                        .font(.system(size: 9, design: .serif).italic())
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.bottom, 12)

                let visibleRows = min(voters.count, 5)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(voters.enumerated()), id: \.offset) { i, voter in
                            HStack(spacing: 12) {
                                AppAvatar(url: voter.avatar, size: 36,
                                          frameURL: voter.avatarFrame,
                                          frameScale: CGFloat(voter.avatarFrameScale ?? 1.0))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(voter.nickname ?? "神秘人")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Noir.ivory)
                                            .lineLimit(1)
                                        if voter.hidden == true {
                                            Image(systemName: "eye.slash")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.3))
                                        }
                                        ActivityVipChip(
                                            vipLevel: voter.vipLevel,
                                            vipLevelColor: voter.vipLevelColor,
                                            levelInTier: voter.levelInTier,
                                            fontSize: 8,
                                            showLevel: true
                                        )
                                    }
                                    Text(voter.timeText ?? "")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                Spacer()
                                Text("+\(voter.votes ?? 1) 票")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Noir.crimsonHot)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 60)
                            if i < voters.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(visibleRows * 61 - 1))
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.hairlineGold, lineWidth: 1))

                if voters.count > 5 {
                    Text("上下滑动查看全部 \(voters.count) 位投票人")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }

    // MARK: - 分享拉票海报（合成 → 系统分享 → 5 秒后确认得票机会）

    private func sharePoster(_ detail: PageantEntryDetail, _ activity: PageantActivity) {
        guard !posterSharing else { return }
        posterSharing = true
        Task {
            defer { posterSharing = false }
            // 二维码用「邀请好友」的注册码：拉新归因给分享者（对齐安卓）
            let inviteCode = (try? await UserAPI.getInviteCode())?.inviteCode ?? ""
            let base = Config.h5RegisterURL.absoluteString
            let qrContent = "\(base.hasSuffix("/") ? base : base + "/")?c=\(inviteCode)"
            guard let poster = await PageantPoster.generate(activity: activity, detail: detail, qrContent: qrContent) else {
                jjtShowToast("海报生成失败")
                return
            }
            presentShare(image: poster)
            vm.shareEarn(entryId: entryId)
        }
    }

    private func presentShare(image: UIImage) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        top.present(vc, animated: true)
    }
}

/// 活动未回时只占位/禁用投票区，不阻塞作品详情。
private struct PageantActivityVotePlaceholder: View {
    let failed: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if failed {
                Text("活动信息加载失败")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Button("重试", action: onRetry)
                    .foregroundStyle(Noir.goldLight)
            } else {
                ProgressView().tint(Noir.crimson)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - 投票贡献榜弹层（对齐安卓 VoterBoardDialog）

private struct PageantVoterBoardOverlay: View {
    let targetNickname: String
    let voters: [PageantEntryDetail.Voter]
    let loading: Bool
    let myHidden: Bool
    let busy: Bool
    let onDismiss: () -> Void
    let onUserClick: (Int64) -> Void
    let onSetHidden: (Bool) -> Void

    /// nil=不弹确认；true=确认隐藏；false=确认恢复
    @State private var hidePrompt: Bool?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("投票贡献榜")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(Noir.ivory)
                        Text("支持 \(targetNickname) 的全部投票人")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 20)
                .padding(.trailing, 14)
                .padding(.top, 18)

                Spacer().frame(height: 10)

                if loading && voters.isEmpty {
                    ProgressView().tint(Noir.crimson)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                } else if voters.isEmpty {
                    Text("还没有人投票")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(voters.enumerated()), id: \.offset) { i, voter in
                                voterRow(voter, rank: i + 1)
                                if i < voters.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.05))
                                        .frame(height: 1)
                                        .padding(.leading, 58)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }
            }
            .frame(maxWidth: .infinity)
            .background(LinearGradient(
                colors: [
                    Color(red: 0x1B / 255, green: 0x0C / 255, blue: 0x12 / 255),
                    Color(red: 0x0A / 255, green: 0x07 / 255, blue: 0x0B / 255),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.gold.opacity(0.42), lineWidth: 1))
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            .onTapGesture { /* 消费卡片内点击，避免穿透到遮罩关闭 */ }

            if let hide = hidePrompt {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { hidePrompt = nil }
                hideConfirmCard(hide: hide)
            }
        }
    }

    private func voterRow(_ voter: PageantEntryDetail.Voter, rank: Int) -> some View {
        let mine = voter.mine == true
        let hidden = voter.hidden == true
        let clickable = mine || (!hidden && voter.userId != nil)
        return Button {
            if mine {
                hidePrompt = !(voter.hidden ?? myHidden)
            } else if !hidden, let uid = voter.userId {
                onUserClick(uid)
            }
        } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(rank <= 3 ? Noir.goldPale : Color.white.opacity(0.3))
                    .frame(width: 26)
                AppAvatar(url: voter.avatar, size: 42,
                          frameURL: voter.avatarFrame,
                          frameScale: CGFloat(voter.avatarFrameScale ?? 1.0))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(voter.nickname ?? "神秘人")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(1)
                        if hidden {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    ActivityVipChip(
                        vipLevel: voter.vipLevel,
                        vipLevelColor: voter.vipLevelColor,
                        levelInTier: voter.levelInTier,
                        fontSize: 8.5,
                        showLevel: true
                    )
                }
                Spacer()
                if mine {
                    Text(hidden ? "点击恢复" : "点击隐藏")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
    }

    private func hideConfirmCard(hide: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color(red: 0xFF / 255, green: 0x7D / 255, blue: 0x9C / 255).opacity(0.1))
                Circle().stroke(Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0xB5 / 255).opacity(0.33), lineWidth: 1)
                Image(systemName: "eye.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(Noir.goldLight)
            }
            .frame(width: 56, height: 56)

            Text(hide ? "隐藏我的投票信息？" : "恢复我的投票信息？")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .padding(.top, 16)

            Text(hide
                 ? "隐藏后仅显示昵称首字与 VIP 等级\n任何人不能从榜单跳转你的个人主页"
                 : "恢复后展示完整昵称与头像\n其他人可从榜单进入你的个人主页")
                .font(.system(size: 12))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 10)

            HStack(spacing: 10) {
                Button { hidePrompt = nil } label: {
                    Text("取消")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    onSetHidden(hide)
                    hidePrompt = nil
                } label: {
                    Group {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Text(hide ? "确认隐藏" : "确认恢复")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(LinearGradient(
                        colors: [Color(red: 0xD9 / 255, green: 0x04 / 255, blue: 0x29 / 255), Noir.crimsonDeep, Noir.wine],
                        startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .background(LinearGradient(
            colors: [
                Color(red: 0x1B / 255, green: 0x0C / 255, blue: 0x12 / 255),
                Color(red: 0x0A / 255, green: 0x07 / 255, blue: 0x0B / 255),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.gold.opacity(0.42), lineWidth: 1))
        .padding(.horizontal, 34)
        .contentShape(Rectangle())
        .onTapGesture { /* 消费卡片内点击 */ }
    }
}

// MARK: - 投票区：预热期倒计时 / 票池面板（对齐安卓 VoteArea / VoteSection）

/// 购票单次张数上限：与服务端购票 @Max(100) 对齐（投票不再设单次固定上限）
private let pageantMaxVotesPerRequest = 100

/// 投票区入口：活动未开始（start_time 在将来）时显示秒级开启倒计时，报名/展示不受影响
private struct VoteArea: View {

    let activity: PageantActivity
    let voting: Bool
    let shareBusy: Bool
    let onVotePool: (Int) -> Void
    let onPurchase: (String, Int, String?) async throws -> Void
    let onCarrotInsufficient: () -> Void
    let onNeedRecharge: () -> Void
    let onShare: () -> Void

    @State private var nowMs = Int64(Date().timeIntervalSince1970 * 1000)

    private var startMs: Int64? { activity.startTime }
    private var open: Bool {
        guard let startMs else { return true }
        return nowMs >= startMs
    }

    var body: some View {
        Group {
            if open {
                VoteSection(
                    activity: activity,
                    voting: voting,
                    shareBusy: shareBusy,
                    onVotePool: onVotePool,
                    onPurchase: onPurchase,
                    onCarrotInsufficient: onCarrotInsufficient,
                    onNeedRecharge: onNeedRecharge,
                    onShare: onShare
                )
            } else {
                VoteOpeningCard(startTime: startMs ?? 0, nowMs: nowMs)
            }
        }
        // 未开启时秒级刷新倒计时，到点自动切投票面板
        .task(id: open) {
            guard !open else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            }
        }
    }
}

// MARK: - 票池投票面板（对齐 app-ui v117 / 安卓 VoteSection）

/// 下单页渠道（sheet(item:) 用：type=rabbit/carrot）
private struct PageantOrderType: Identifiable {
    let id: String
}

/// 单面板：顶部「目前剩余 X 张票」+ 数量步进 + 红色投票按钮；下方 兔币购票 / 萝贝购票 / 分享获票 三行玻璃票档。
/// 票池票数来自服务端（购票/分享后即时入池），投票时按 免费→分享→萝贝→兔币 顺序扣票。
private struct VoteSection: View {
    let activity: PageantActivity
    let voting: Bool
    let shareBusy: Bool
    let onVotePool: (Int) -> Void
    let onPurchase: (String, Int, String?) async throws -> Void
    let onCarrotInsufficient: () -> Void
    let onNeedRecharge: () -> Void
    let onShare: () -> Void

    @State private var qty = 1
    @State private var orderType: PageantOrderType?
    /// 票数不足：提示加票，确认后打开兔币购票
    @State private var showBuyPrompt = false

    private var freeLeft: Int { activity.freeLeft ?? 0 }
    private var shareChances: Int { activity.shareChances ?? 0 }
    private var carrotTickets: Int { activity.carrotTickets ?? 0 }
    private var rabbitTickets: Int { activity.rabbitTickets ?? 0 }
    private var total: Int {
        activity.totalTickets ?? (freeLeft + shareChances + carrotTickets + rabbitTickets)
    }
    private var carrotPrice: Int64 { activity.carrotPrice ?? 20 }
    private var rabbitPrice: Int64 { activity.rabbitPrice ?? 10 }
    private var carrotBalance: Int64 { activity.carrotBalance ?? 0 }
    private var rabbitBalance: Int64 { activity.rabbitBalance ?? 0 }
    private var carrotPurchaseLeft: Int { activity.carrotPurchaseLeft ?? 0 }
    private var rabbitPurchaseLeft: Int { activity.rabbitPurchaseLeft ?? 0 }
    private var shareCap: Int { activity.shareDailyCap ?? 0 }
    private var shareLeft: Int { max(shareCap - (activity.myShareEarned ?? 0), 0) }

    var body: some View {
        panel
            .padding(.horizontal, 20)
            .padding(.top, 16)
            // 下单页：购买几张、总金额、余额是否充足
            .sheet(item: $orderType) { order in
                PageantPurchaseSheet(
                    type: order.id,
                    price: order.id == "rabbit" ? rabbitPrice : carrotPrice,
                    balance: order.id == "rabbit" ? rabbitBalance : carrotBalance,
                    purchaseLeft: order.id == "rabbit" ? rabbitPurchaseLeft : carrotPurchaseLeft,
                    onConfirm: onPurchase,
                    onCarrotInsufficient: onCarrotInsufficient,
                    onNeedRecharge: onNeedRecharge
                )
                .presentationDetents([.height(470)])
                .presentationBackground(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1A / 255))
            }
            // 票数不足 → 引导加票（确认后打开兔币购票半屏）
            .alert("票数不足", isPresented: $showBuyPrompt) {
                Button("去购票") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        orderType = PageantOrderType(id: "rabbit")
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(total <= 0
                     ? "当前没有可用的票。\n是否增加票数？购买兔币票后可继续为 TA 投票。"
                     : "当前最多可投 \(total) 张票。\n是否增加票数？购买兔币票后可投更多。")
            }
            // 余量变化（投票/购票/轮询）后收敛输入，避免显示超过实际剩余
            .onChange(of: total) { _, newTotal in
                if qty > newTotal { qty = max(newTotal, 1) }
            }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("目前剩余")
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.ivory)
                        Text("\(total)")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(Noir.goldLight)
                        Text("张票")
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.ivory)
                    }
                    Text("免费 \(freeLeft) · 分享 \(shareChances) · 萝贝 \(carrotTickets) · 兔币 \(rabbitTickets)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                QtyStepper(value: $qty, max: total, enabled: total > 0,
                           onOverflow: { showBuyPrompt = true })
                Spacer().frame(width: 8)
                PageantPoolVoteButton(dimmed: total <= 0) {
                    if total <= 0 {
                        showBuyPrompt = true
                    } else {
                        onVotePool(min(max(qty, 1), total))
                    }
                }
            }

            Spacer().frame(height: 14)

            // 兔币购票
            VoteTicketRow(
                title: "兔币购票",
                hint: rabbitPurchaseLeft > 0
                    ? "今日还可购 \(rabbitPurchaseLeft) 张 · 单价 \(rabbitPrice) 兔币"
                    : "今日兔币购票已用完",
                value: "\(rabbitPrice) 兔币",
                sub: "每 1 张选票",
                enabled: rabbitPurchaseLeft > 0,
                texture: "vote_glass_rabbit"
            ) { orderType = PageantOrderType(id: "rabbit") }

            Spacer().frame(height: 12)

            // 萝贝购票
            VoteTicketRow(
                title: "萝贝购票",
                hint: carrotPurchaseLeft > 0
                    ? "今日还可购 \(carrotPurchaseLeft) 张 · 单价 \(carrotPrice) 萝贝"
                    : "今日萝贝购票已用完",
                value: "\(carrotPrice) 萝贝",
                sub: "每 1 张选票",
                enabled: carrotPurchaseLeft > 0,
                texture: "vote_glass_carrot"
            ) {
                // 余额连 1 张都买不起：直接弹「萝贝不足 → 去做任务」
                if carrotBalance < carrotPrice {
                    onCarrotInsufficient()
                } else {
                    orderType = PageantOrderType(id: "carrot")
                }
            }

            // 分享获票（渠道关闭时整行隐藏）
            if shareCap > 0 {
                Spacer().frame(height: 12)
                VoteTicketRow(
                    title: "分享获票",
                    hint: shareLeft > 0
                        ? "今日还可分享 \(shareLeft) 次" + (shareChances > 0 ? " · 已有 \(shareChances) 张分享票" : "")
                        : "今日分享机会已用完",
                    value: "免费 +1 票",
                    sub: "每次分享获得",
                    enabled: shareLeft > 0 && !shareBusy,
                    texture: "vote_glass_share"
                ) { onShare() }
            }

            Spacer().frame(height: 12)
            Text("我的兔币 \(rabbitBalance) · 萝贝 \(carrotBalance)")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity)
            Text("余额不足自动引导充值")
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(16)
        .background(LinearGradient(
            colors: [
                Color(red: 0x3A / 255, green: 0x0A / 255, blue: 0x16 / 255).opacity(0.78),
                Color(red: 0x10 / 255, green: 0x08 / 255, blue: 0x0A / 255).opacity(0.92),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.crimson.opacity(0.42), lineWidth: 1))
    }
}

/// 顶部投票按钮：复用 UI 稿红色底图，票池为空置灰（仍可点：弹加票提示）
private struct PageantPoolVoteButton: View {
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 底：酒红渐变（贴图缺失/加载前也不空）
                Capsule().fill(LinearGradient(
                    colors: [Color(red: 0xD9 / 255, green: 0x04 / 255, blue: 0x29 / 255), Noir.crimsonDeep, Noir.wine],
                    startPoint: .leading, endPoint: .trailing))
                Image("vote_red_button")
                    .resizable()
                    .frame(width: 68, height: 40)
                    .saturation(dimmed ? 0 : 1)
                    .opacity(dimmed ? 0.5 : 1)
                Text("投票")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dimmed ? Color.white.opacity(0.5) : Color.white)
            }
            .frame(width: 68, height: 40)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PageantPressStyle(scale: 0.94))
    }
}

/// 票档行：玻璃底图 + 左侧标题/提示 + 右侧价格，整行可点。
/// 额度用完/今日购票上限时整行去饱和压暗。
private struct VoteTicketRow: View {

    let title: String
    let hint: String
    let value: String
    let sub: String
    let enabled: Bool
    let texture: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 底：玻璃渐变（贴图缺失/加载前也不空）
                Capsule().fill(LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.07)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(texture)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .saturation(enabled ? 1 : 0)
                    .opacity(enabled ? 1 : 0.45)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.35))
                        Text(hint)
                            .font(.system(size: 9))
                            .foregroundStyle(enabled ? Color.white.opacity(0.7) : Color.white.opacity(0.25))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(value)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(enabled
                                             ? Color(red: 0xFF / 255, green: 0xE2 / 255, blue: 0xA1 / 255)
                                             : Color.white.opacity(0.3))
                        Text(sub)
                            .font(.system(size: 9))
                            .foregroundStyle(enabled ? Color.white.opacity(0.65) : Color.white.opacity(0.22))
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(enabled ? 0.12 : 0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PageantPressStyle(scale: 0.972))
        .disabled(!enabled)
    }
}

/// 购票下单页：购买几张、应付总额、余额是否充足；余额不足给充值（兔币）/任务（萝贝）引导
private struct PageantPurchaseSheet: View {

    let type: String
    let price: Int64
    let balance: Int64
    let purchaseLeft: Int
    let onConfirm: (String, Int, String?) async throws -> Void
    let onCarrotInsufficient: () -> Void
    let onNeedRecharge: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var payGuard = PayPasswordGuard()
    @State private var count = 1
    @State private var submitting = false
    @State private var errorText: String?
    @State private var showPaySettings = false

    private var isRabbit: Bool { type == "rabbit" }
    private var label: String { isRabbit ? "兔币" : "萝贝" }
    private var maxCount: Int { max(min(purchaseLeft, pageantMaxVotesPerRequest), 1) }
    private var total: Int64 { Int64(count) * price }
    private var enough: Bool { balance >= total }

    var body: some View {
        VStack(spacing: 0) {
            Text("购买\(label)票")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Noir.ivory)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 4)
            Text("\(price) \(label)/张 · 今日还可购买 \(purchaseLeft) 张")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(height: 16)
            HStack {
                Text("购买数量")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                QtyStepper(value: $count, max: maxCount, enabled: !submitting)
            }

            Spacer().frame(height: 16)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Spacer().frame(height: 12)
            HStack {
                Text("应付")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(total) \(label)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Noir.goldLight)
            }
            Spacer().frame(height: 6)
            HStack {
                Text("当前余额")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("\(balance) \(label)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer().frame(height: 6)
            Text(enough ? "余额充足" : "余额不足，还差 \(total - balance) \(label)")
                .font(.system(size: 11))
                .foregroundStyle(enough
                                 ? Color(red: 0x7B / 255, green: 0xC6 / 255, blue: 0x7E / 255)
                                 : Noir.crimsonHot)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(height: 16)
            Button(action: submit) {
                Group {
                    if submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("确认购买 · \(total) \(label)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color(red: 0xC4 / 255, green: 0x12 / 255, blue: 0x30 / 255)))
            }
            .buttonStyle(.plain)
            .disabled(!enough || submitting || purchaseLeft <= 0)
            .opacity(enough ? 1 : 0.45)

            if !enough {
                Button {
                    dismissThen(isRabbit ? onNeedRecharge : onCarrotInsufficient)
                } label: {
                    Text(isRabbit ? "余额不足，去充值" : "余额不足，去做任务")
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.crimsonHot)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.crimsonHot)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .onReceive(NotificationCenter.default.publisher(for: .jjtInsufficientBalance)) { _ in
            // 兔币余额不足：守卫已关密码弹窗，这里退出下单页并转充值
            dismissThen(onNeedRecharge)
        }
        .payPasswordGuard(payGuard) { showPaySettings = true }
        .fullScreenCover(isPresented: $showPaySettings) { PayPasswordSettingsView() }
    }

    /// 先关下单页再执行页面级动作（充值/任务弹窗由详情页呈现，避免跨 presentation 冲突）
    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { action() }
    }

    private func submit() {
        guard !submitting, enough, purchaseLeft > 0 else { return }
        errorText = nil
        if isRabbit {
            // 兔币购票是真金消费，先验支付密码（守卫内部处理未设置/余额不足）
            payGuard.require { pwd in
                try await onConfirm(type, count, pwd)
                dismiss()
            }
        } else {
            submitting = true
            Task {
                do {
                    try await onConfirm(type, count, nil)
                    dismiss()
                } catch let e as APIError {
                    if case .business(let code, _) = e, code == WALLET_INSUFFICIENT_BALANCE_CODE {
                        dismissThen(onCarrotInsufficient)
                    } else if case .business(_, let msg) = e {
                        errorText = msg
                    } else {
                        errorText = "网络异常"
                    }
                } catch {
                    errorText = "网络异常"
                }
                submitting = false
            }
        }
    }
}

/// 投票尚未开启：秒级倒计时（天/时/分/秒），报名与作品展示照常开放
private struct VoteOpeningCard: View {

    let startTime: Int64
    let nowMs: Int64

    var body: some View {
        let remain = max(startTime - nowMs, 0)
        let days = remain / 86_400_000
        let hours = (remain / 3_600_000) % 24
        let minutes = (remain / 60_000) % 60
        let seconds = (remain / 1_000) % 60

        VStack(alignment: .leading, spacing: 0) {
            Text("投票尚未开启")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Spacer().frame(height: 6)
            Text("距投票开启还有")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            Spacer().frame(height: 14)
            HStack(spacing: 8) {
                CountdownCell(value: "\(days)", unit: "天")
                CountdownCell(value: String(format: "%02d", hours), unit: "时")
                CountdownCell(value: String(format: "%02d", minutes), unit: "分")
                CountdownCell(value: String(format: "%02d", seconds), unit: "秒")
            }
            Spacer().frame(height: 14)
            Text("报名与作品展示已开放，先上传你的暗夜之姿攒人气")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(
            colors: [
                Color(red: 0x3A / 255, green: 0x0A / 255, blue: 0x16 / 255).opacity(0.78),
                Color(red: 0x10 / 255, green: 0x08 / 255, blue: 0x0A / 255).opacity(0.92),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.crimson.opacity(0.42), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

private struct CountdownCell: View {

    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldLight)
            Text(unit)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
    }
}

/// 萝贝不足：完成任务可获得免费萝贝，「是，去任务」跳任务中心（对齐 UI 稿 / 安卓 CarrotTaskDialog）
private struct PageantCarrotTaskDialog: View {

    let onCancel: () -> Void
    let onGoTasks: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0xFF / 255, green: 0x7D / 255, blue: 0x9C / 255).opacity(0.1))
                    Circle()
                        .stroke(Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0xB5 / 255).opacity(0.33), lineWidth: 1)
                    Image(systemName: "carrot.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0xB5 / 255))
                }
                .frame(width: 56, height: 56)

                Spacer().frame(height: 16)
                Text("萝贝不足")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Spacer().frame(height: 10)
                Text("完成任务可以获得更多免费萝贝\n是否前往任务页面？")
                    .font(.system(size: 12))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.45))

                Spacer().frame(height: 20)
                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button(action: onGoTasks) {
                        Text("是，去任务")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(LinearGradient(
                                colors: [Color(red: 0xD9 / 255, green: 0x04 / 255, blue: 0x29 / 255), Noir.crimsonDeep, Noir.wine],
                                startPoint: .leading, endPoint: .trailing)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .background(LinearGradient(
                colors: [
                    Color(red: 0x1B / 255, green: 0x0C / 255, blue: 0x12 / 255),
                    Color(red: 0x0A / 255, green: 0x07 / 255, blue: 0x0B / 255),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Noir.gold.opacity(0.42), lineWidth: 1))
            .padding(.horizontal, 36)
        }
    }
}

// MARK: - 数量步进器（对齐安卓 QtyStepper）

private struct QtyStepper: View {
    @Binding var value: Int
    let max: Int
    var enabled: Bool = true
    /// 到达上限仍点 + 时回调（投票区用来弹「票数不足」；购票不传）
    var onOverflow: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            stepperBtn("-") { value = Swift.max(value - 1, 1) }
                .disabled(!enabled || value <= 1)
            Text("\(value)")
                .font(.system(size: 16))
                .foregroundStyle(enabled ? Noir.ivory : Noir.ivory.opacity(0.3))
                .frame(width: 40)
            stepperBtn("+") {
                if value >= Swift.max(max, 1) {
                    onOverflow?()
                } else {
                    value += 1
                }
            }
        }
    }

    private func stepperBtn(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(enabled ? 0.6 : 0.2))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white.opacity(enabled ? 0.15 : 0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 按压回弹（对齐安卓 press scale 120ms）
private struct PageantPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
