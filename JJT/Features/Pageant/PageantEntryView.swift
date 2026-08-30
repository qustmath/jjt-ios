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
            if pager.isLoading {
                ProgressView().tint(Noir.crimson).scaleEffect(1.3)
            } else if pager.entries.isEmpty {
                Text("暂无参赛作品")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                TabView(selection: $selection) {
                    ForEach(pager.entries.indices, id: \.self) { i in
                        PageantEntryPage(entryId: pager.entries[i].id, active: selection == i, onBack: { dismiss() })
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
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
    /// 投票请求进行中：防连点（并发扣钱包会冲突）
    @Published var voting = false
    @Published var error: String?
    /// 余额不足信号（页面监听后弹充值引导）
    @Published var needRecharge = false

    func load(_ entryId: Int64) async {
        isLoading = true
        detail = try? await PageantAPI.entryDetail(id: entryId)
        activity = try? await PageantAPI.activity()
        isLoading = false
    }

    /// 轮询静默刷新（不动 isLoading，不闪加载态）
    func refreshSilent(_ entryId: Int64) async {
        guard let d = try? await PageantAPI.entryDetail(id: entryId) else { return }
        detail = d
        if let a = try? await PageantAPI.activity() { activity = a }
    }

    /// 投票。payPassword：rabbit 渠道必传。成功后刷新 + 爆发动效
    func vote(entryId: Int64, voteType: String, votes: Int, payPassword: String? = nil) {
        guard !voting else { return }
        voting = true
        Task {
            do {
                _ = try await PageantAPI.vote(PageantVoteReq(entryId: entryId, voteType: voteType, votes: votes, payPassword: payPassword))
                burst = votes
                Task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    burst = 0
                }
                await load(entryId)
            } catch let e as APIError {
                if case .business(let code, _) = e, code == WALLET_INSUFFICIENT_BALANCE_CODE {
                    needRecharge = true
                } else if case .business(_, let msg) = e {
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

    /// 投票（抛异常版，供支付密码守卫调用：密码错误/余额不足由守卫统一处理）
    func voteAsync(entryId: Int64, voteType: String, votes: Int, payPassword: String) async throws {
        _ = try await PageantAPI.vote(PageantVoteReq(entryId: entryId, voteType: voteType, votes: votes, payPassword: payPassword))
        burst = votes
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            burst = 0
        }
        await load(entryId)
    }

    /// 分享得机会：海报拉起系统分享 5 秒后再确认到账并提示（对齐安卓 shareEarn）
    func shareEarn(entryId: Int64) {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            do {
                _ = try await PageantAPI.shareEarn(entryId: entryId)
                jjtShowToast("分享成功，获得 1 次投票机会")
                await load(entryId)
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

    @StateObject private var vm = PageantEntryModel()
    @StateObject private var payGuard = PayPasswordGuard()
    @State private var showVideoPlayer = false
    @State private var posterSharing = false
    @State private var showRecharge = false
    @State private var showPaySettings = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            if let detail = vm.detail, let activity = vm.activity {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(detail)
                        VoteSection(
                            detail: detail,
                            activity: activity,
                            voting: vm.voting,
                            shareBusy: posterSharing,
                            onVoteCarrot: { n in vm.vote(entryId: entryId, voteType: "carrot", votes: n) },
                            onVoteRabbit: { n in
                                payGuard.require { pwd in
                                    try await vm.voteAsync(entryId: entryId, voteType: "rabbit", votes: n, payPassword: pwd)
                                }
                            },
                            onVoteShare: { vm.vote(entryId: entryId, voteType: "share", votes: 1) },
                            onShare: { sharePoster(detail, activity) }
                        )
                        recentVoters(detail)
                        Spacer().frame(height: 40)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else {
                ProgressView().tint(Noir.crimson).scaleEffect(1.3)
            }

            // +N 爆发动效
            if vm.burst > 0 {
                Text("+\(vm.burst)")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Noir.crimsonHot)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task { await vm.load(entryId) }
        // 当前停留页 4 秒轮询：别人的投票实时可见（静默刷新）
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if active { await vm.refreshSilent(entryId) }
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
        .onChange(of: vm.needRecharge) { _, need in
            if need { vm.needRecharge = false; showRecharge = true }
        }
        .payPasswordGuard(payGuard) { showPaySettings = true }
        .fullScreenCover(isPresented: $showPaySettings) { PayPasswordSettingsView() }
        .fullScreenCover(isPresented: $showRecharge) { CoinRechargeView() }
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
    }

    // MARK: - 作品大图区（图片+视频同一轮播；视频页多一个播放按钮）

    private func hero(_ detail: PageantEntryDetail) -> some View {
        let images = detail.images ?? []
        let hasVideo = !(detail.video ?? "").isEmpty
        let pageTotal = images.count + (hasVideo ? 1 : 0)

        return ZStack(alignment: .topLeading) {
            TabView {
                ForEach(images.indices, id: \.self) { i in
                    AsyncImage(url: webImageURL(images[i])) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Noir.noir3
                        }
                    }
                    .tag(i)
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
            // 返回
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
            .padding(.top, 20)
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
                    .padding(.top, 20)
            }

            // 底部渐变 + 作者卡 + 票数
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    AppAvatar(url: detail.avatar, size: 48)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(detail.nickname ?? "用户\(detail.userId)")
                                .font(.system(size: 21, weight: .bold, design: .serif))
                                .foregroundStyle(Noir.ivory)
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
                VStack(spacing: 0) {
                    ForEach(Array(voters.enumerated()), id: \.offset) { i, voter in
                        HStack(spacing: 12) {
                            AppAvatar(url: voter.avatar, size: 36)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voter.nickname ?? "神秘人")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Noir.ivory)
                                Text(voter.timeText ?? "")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            Spacer()
                            Text("+\(voter.votes ?? 1) 票")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Noir.crimsonHot)
                        }
                        .padding(.vertical, 12)
                        if i < voters.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.hairlineGold, lineWidth: 1))
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

// MARK: - 投票区：萝贝卡 → 耗尽切加票面板（对齐安卓 VoteSection）

private struct VoteSection: View {

    let detail: PageantEntryDetail
    let activity: PageantActivity
    let voting: Bool
    let shareBusy: Bool
    let onVoteCarrot: (Int) -> Void
    let onVoteRabbit: (Int) -> Void
    let onVoteShare: () -> Void
    let onShare: () -> Void

    @State private var carrotQty = 1
    @State private var rabbitQty = 1

    private var carrotDaily: Int { activity.carrotDaily ?? 5 }
    private var rabbitDaily: Int { activity.rabbitDaily ?? 5 }
    private var shareCap: Int { activity.shareDailyCap ?? 2 }
    private var carrotLeft: Int { max(carrotDaily - (activity.myCarrotUsed ?? 0), 0) }
    private var rabbitLeft: Int { max(rabbitDaily - (activity.myRabbitUsed ?? 0), 0) }
    private var shareChances: Int { max((activity.myShareEarned ?? 0) - (activity.myShareUsed ?? 0), 0) }
    private var shareLeft: Int { max(shareCap - (activity.myShareEarned ?? 0), 0) }

    var body: some View {
        VStack(spacing: 0) {
            if carrotLeft > 0 {
                carrotCard
            } else {
                exhaustedPanel
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// 萝贝投票卡
    private var carrotCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("萝贝投票")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Noir.ivory)
                        Text("\(activity.carrotPrice ?? 20) 萝贝/票")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                    Text("今日剩余 \(carrotLeft)/\(carrotDaily) 次 · 我的萝贝 \(activity.carrotBalance ?? 0)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                QtyStepper(value: $carrotQty, max: carrotLeft)
            }
            Button {
                let n = min(carrotQty, carrotLeft)
                onVoteCarrot(n)
            } label: {
                Text("为TA投出 \(min(carrotQty, carrotLeft)) 票 · 消耗 \(min(carrotQty, carrotLeft) * Int(activity.carrotPrice ?? 20)) 萝贝")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient(
                        colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                        startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .disabled(voting)
            .padding(.top, 14)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.7), Color(red: 0x10/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.crimson.opacity(0.4), lineWidth: 1))
    }

    /// 萝贝耗尽 → 加票面板（分享得票 + 兔币投票）
    private var exhaustedPanel: some View {
        VStack(spacing: 0) {
            Text("今日萝贝投票已用完")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .frame(maxWidth: .infinity)
            Text("还可以通过以下方式继续为TA加票")
                .font(.system(size: 10))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            // 分享得票卡
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("分享得票")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Noir.ivory)
                            Text("+1 次机会")
                                .font(.system(size: 12))
                                .foregroundStyle(Noir.crimsonHot)
                        }
                        Text("今日还可分享 \(shareLeft) 次" + (shareChances > 0 ? " · 已有 \(shareChances) 次机会可用" : ""))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                    Text("免费")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.goldLight)
                }
                HStack(spacing: 10) {
                    Button { onShare() } label: {
                        Text(shareBusy ? "生成海报…" : (shareLeft > 0 ? "去分享" : "今日分享已用完"))
                            .font(.system(size: 12))
                            .foregroundStyle(shareLeft > 0 ? Noir.goldLight : .white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(Capsule().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(shareLeft <= 0 || shareBusy)
                    Button { onVoteShare() } label: {
                        Text(shareChances > 0 ? "用机会投 1 票" : "暂无投票机会")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(shareChances > 0 ? .white : .white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(shareChances > 0
                                ? LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color(red: 0x3A/255, green: 0x3A/255, blue: 0x3A/255), Color(red: 0x2A/255, green: 0x2A/255, blue: 0x2A/255)], startPoint: .leading, endPoint: .trailing)))
                    }
                    .buttonStyle(.plain)
                    .disabled(shareChances <= 0 || voting)
                }
            }
            .padding(14)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
            .padding(.top, 16)

            // 兔币投票卡
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("兔币投票")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Noir.ivory)
                            Text("\(activity.rabbitPrice ?? 10) 兔币/票")
                                .font(.system(size: 12))
                                .foregroundStyle(Noir.crimsonHot)
                        }
                        Text("今日剩余 \(rabbitLeft)/\(rabbitDaily) 次 · 我的兔币 \(activity.rabbitBalance ?? 0)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                    QtyStepper(value: $rabbitQty, max: max(rabbitLeft, 1))
                }
                Button {
                    let n = min(rabbitQty, rabbitLeft)
                    onVoteRabbit(n)
                } label: {
                    Text(rabbitLeft > 0
                         ? "投出 \(min(rabbitQty, rabbitLeft)) 票 · 消耗 \(min(rabbitQty, rabbitLeft) * Int(activity.rabbitPrice ?? 10)) 兔币"
                         : "今日兔币投票已达上限")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rabbitLeft > 0 ? .white : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(rabbitLeft > 0
                            ? LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color(red: 0x3A/255, green: 0x3A/255, blue: 0x3A/255), Color(red: 0x2A/255, green: 0x2A/255, blue: 0x2A/255)], startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.plain)
                .disabled(rabbitLeft <= 0 || voting)
                .padding(.top, 10)
                Text("兔币不足将自动前往充值 · 1元 = 10兔币 = 100萝贝")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(14)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
            .padding(.top, 12)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.55), Color(red: 0x10/255, green: 0x08/255, blue: 0x0A/255).opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 数量步进器（对齐安卓 QtyStepper）

private struct QtyStepper: View {
    @Binding var value: Int
    let max: Int

    var body: some View {
        HStack(spacing: 0) {
            stepperBtn("-") { value = Swift.max(value - 1, 1) }
            Text("\(value)")
                .font(.system(size: 16))
                .foregroundStyle(Noir.ivory)
                .frame(width: 36)
            stepperBtn("+") { value = Swift.min(value + 1, Swift.max(max, 1)) }
        }
    }

    private func stepperBtn(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }}
