import PhotosUI
import SwiftUI

/// 暗夜大厅：全城门店总览（对齐安卓 NightLobbyScreen，原型 ui/v64 /lobby）。
///
/// 两个视图：
/// - feed：实时消息流（聚合群读流，带门店前缀）+ 门店卡片列表（默认）
/// - immersive：沉浸式双层（门店背景 + 无框聊天流，左右滑动切店，按当前浏览门店发言）
///
/// 坐席态来自 LobbySeatSession（全 App 单一来源）；本页在前台时兼作定位心跳宿主。
struct NightLobbyView: View {

    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = LobbyHomeViewModel()
    @ObservedObject private var seatSession = LobbySeatSession.shared
    @ObservedObject private var imSession = LobbyImSession.shared

    @State private var immersive = false
    @State private var idx = 0
    @State private var cardUser: LobbyChatMessage?
    @State private var reportTarget: LobbyChatMessage?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var sending = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var giftNav: LobbyNavTarget?
    @State private var chatNav: LobbyNavTarget?
    @State private var storeNav: StoreNav?

    struct StoreNav: Identifiable {
        let storeId: Int64
        var id: Int64 { storeId }
    }

    /// 资料卡动作的页面跳转载体（fullScreenCover(item:) 要求 Identifiable）
    struct LobbyNavTarget: Identifiable {
        let userId: Int64
        let nickname: String?
        var id: Int64 { userId }
    }

    var body: some View {
        ZStack {
            LobbyColors.bg.ignoresSafeArea()

            if immersive && !vm.stores.isEmpty {
                immersiveView
            } else {
                feedView
            }

            // 浮层群：资料卡 / 举报 / toast（ZStack 顶层，保证盖在后续 sheet 之上）
            if let u = cardUser { userCard(u) }
            if let msg = reportTarget { reportSheet(msg) }
            if let t = toast { LobbyToastView(text: t) }

            // 本店/全门店礼物动效接收端补播：暗夜大厅听聚合群副本
            LobbyGiftBroadcastOverlay(listenGroupId: imSession.aggregateGroupId,
                                      myUserId: TokenManager.shared.userId ?? -1)
        }
        .task { await initialLoad() }
        .task { await LobbySeatSession.shared.heartbeatLoop() }
        // 门店卡入座/围观数轮询：坐席播报只发门店群，暗夜大厅只听聚合群收不到他人坐席变化，
        // 真值只能周期拉——页面可见期间 15s 一刷（仅空列表才显示 loading，轮询不闪屏）
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                await vm.load()
            }
        }
        .onAppear { LobbyImSession.shared.start() }
        .onDisappear { LobbyImSession.shared.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .jjtLobbySeatChanged)) { _ in
            // 入座/换桌/离桌后刷新门店卡片（入座数与「全城 N 人入座中」会变）
            Task { await vm.load() }
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            sendPickedImage(item)
        }
        .fullScreenCover(item: $giftNav) { nav in
            GiftCenterView(receiverId: nav.userId, receiverName: nav.nickname)
        }
        .fullScreenCover(item: $chatNav) { nav in
            ChatView(peerId: String(nav.userId), isGroup: false, title: nav.nickname)
        }
        .fullScreenCover(item: $storeNav) { nav in
            StoreLobbyView(storeId: nav.storeId)
        }
        .lobbyPageEnter()
    }

    // MARK: - 状态派生

    private var aggregateMessages: [LobbyChatMessage] {
        guard let gid = imSession.aggregateGroupId, !gid.isEmpty else { return [] }
        return imSession.messages.filter { $0.groupId == gid }
    }

    /// 沉浸视图的发言目标 = 当前浏览门店的直播群（切店换群）
    private var targetGroupId: String? {
        guard immersive, vm.stores.indices.contains(idx) else { return nil }
        return vm.stores[idx].avchatroomId
    }

    /// 失败文案的坐席态判据：看入座的是不是「当前正在发言的这家店」——
    /// 后端口径是非本店入座视同罚站受限
    private var targetSeated: Bool {
        seatSession.seat?.state == "seated" && seatSession.seat?.storeId == targetStoreId
    }

    private var targetStoreId: Int64? {
        guard immersive, vm.stores.indices.contains(idx) else { return nil }
        return vm.stores[idx].id
    }

    /// 入座中的胶囊即回对应门店大厅的捷径；罚站/围观无可去的店，不给点击
    private var seatedStoreEntry: (() -> Void)? {
        guard seatSession.isSeated, let sid = seatSession.seat?.storeId else { return nil }
        return { storeNav = StoreNav(storeId: sid) }
    }

    private func initialLoad() async {
        await vm.load()
        await LobbySeatSession.shared.refresh()
        // 门店 ID→店名表（全城流历史行「店名」前缀渲染用）
        LobbyImSession.shared.seedStoreNames(
            Dictionary(vm.stores.compactMap { s in s.name.map { (s.id, $0) } },
                       uniquingKeysWith: { _, new in new })
        )
        // 暗夜大厅：先补 IM 登录（大厅原本不登 IM），再拉聚合群 ID 并加入，
        // 随后拉最近 50 条历史前插（loadHistory 自身幂等）
        await LobbyImSession.shared.ensureImReady()
        await LobbyImSession.shared.loadAggregateGroupId()
        LobbyImSession.shared.ensureAggregateJoined()
        await LobbyImSession.shared.loadHistory(LobbyImSession.shared.aggregateGroupId)
    }

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toast = msg
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: - 视图 A：实时消息流 + 门店卡片列表

    private var feedView: some View {
        VStack(spacing: 0) {
            // 四宫格沉浸视图入口已撤下（对齐安卓 f78a091，产品节奏另行放开）
            LobbyHeader(title: "暗夜大厅", en: "GLOBAL LOUNGE", onBack: { dismiss() }) {
                SeatPill(seat: seatSession.seat, onClick: seatedStoreEntry)
            }

            if vm.loading && vm.stores.isEmpty {
                ZStack {
                    ProgressView().tint(LobbyColors.gold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.stores.isEmpty && vm.error != nil {
                // 加载失败与「暂无营业中的门店」是两回事：失败给重试
                ZStack {
                    LobbyLoadFailed(message: vm.error ?? "", onRetry: { Task { await vm.load() } })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        liveStreamSection
                            .padding(.horizontal, 16)
                        Spacer().frame(height: 16)

                        HStack(alignment: .bottom, spacing: 8) {
                            Text("今夜门店")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(LobbyColors.ivory)
                            Text("\(vm.stores.count) 家店开中 · 上下滑动浏览")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .padding(.horizontal, 20)
                        Spacer().frame(height: 10)

                        if vm.stores.isEmpty {
                            Text("暂无营业中的门店")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                        // 门店卡简报数据源：全城流按 storeId 归店取最新一条用户消息
                        //（消息列表时间升序，后写覆盖即最新；实时副本与历史行都带 storeId）；
                        // 流内没有的店回退后端 latestMessage 纯文本（无身份）
                        let latestByStore: [Int64: LobbyChatMessage] = {
                            var map: [Int64: LobbyChatMessage] = [:]
                            for m in aggregateMessages where m.isUserMessage {
                                if let sid = m.storeId { map[sid] = m }
                            }
                            return map
                        }()
                        ForEach(vm.stores) { store in
                            LobbyStoreCardView(
                                store: store,
                                isMine: seatSession.seat?.storeId == store.id,
                                latest: latestByStore[store.id],
                                onEnter: { storeNav = StoreNav(storeId: store.id) },
                                onUserClick: { cardUser = $0 }
                            )
                            .padding(.horizontal, 16)
                            Spacer().frame(height: 16)
                        }

                        if !vm.stores.isEmpty {
                            enterStoreCTA
                            Spacer().frame(height: 12)
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.3))
                                Text("全城 \(vm.stores.reduce(0) { $0 + ($1.seatedCount ?? 0) + ($1.standingCount ?? 0) }) 人在玩")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    /// 全城实时滚动（聚合群读流，副本带门店前缀）
    private var liveStreamSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(LobbyColors.crimson)
                .clipShape(Capsule())
                Text("全城实时滚动")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                Spacer()
                Text("各店公屏同步")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.25))
            }
            LobbyChatList(
                messages: aggregateMessages,
                showStorePrefix: true,
                style: .feed,
                emptyText: "全城公屏暂无消息 · 进门店大厅开个场 ✨",
                fadeTop: true,
                onUserClick: { cardUser = $0 },
                onMessageLongPress: { msg in
                    if msg.canReport(myUserId: TokenManager.shared.userId ?? -1) { reportTarget = msg }
                }
            )
            .frame(height: 300)
            .background(.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var enterStoreCTA: some View {
        Button {
            if let first = vm.stores.first { storeNav = StoreNav(storeId: first.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "storefront")
                    .font(.system(size: 14))
                Text("进入门店大厅")
                    .font(.system(size: 13, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - 视图 B：沉浸式双层

    private var immersiveView: some View {
        let storeIdx = min(idx, vm.stores.count - 1)
        let store = vm.stores[storeIdx]
        return ZStack {
            LobbyColors.bg.ignoresSafeArea()

            // 后层：门店背景
            if let cover = store.cover, !cover.isEmpty, let url = webImageURL(cover) {
                WebImage(url: url) { LobbyColors.bg }
                    .ignoresSafeArea()
            }
            LinearGradient(
                stops: [
                    .init(color: lobbyDim(0.55), location: 0),
                    .init(color: lobbyDim(0.25), location: 0.3),
                    .init(color: lobbyDim(0.55), location: 0.62),
                    .init(color: lobbyDim(0.97), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                LobbyHeader(title: "暗夜大厅", en: "GLOBAL LOUNGE", onBack: { dismiss() }) {
                    LobbyIconAction(icon: "square.grid.2x2.fill") { immersive = false }
                    SeatPill(seat: seatSession.seat, onClick: seatedStoreEntry)
                }
                Spacer()
            }

            // 门店切换圆点
            HStack(spacing: 6) {
                ForEach(Array(vm.stores.enumerated()), id: \.element.id) { i, _ in
                    Capsule()
                        .fill(i == idx ? LobbyColors.goldLight : .white.opacity(0.2))
                        .frame(width: i == idx ? 16 : 6, height: 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 86)

            // 门店信息层（看门店态前移显现）
            if immersiveStoreMode {
                storeInfoLayer(store)
            }

            // 前层：无框聊天流 + 发言条
            if !immersiveStoreMode {
                VStack(spacing: 0) {
                    Spacer()
                    LobbyChatList(
                        messages: aggregateMessages,
                        showStorePrefix: true,
                        style: .immersive,
                        emptyText: "全城公屏暂无消息 ✨",
                        fadeTop: true,
                        dimmed: { $0.storeId != vm.stores[storeIdx].id },
                        onUserClick: { cardUser = $0 },
                        onMessageLongPress: { msg in
                            if msg.canReport(myUserId: TokenManager.shared.userId ?? -1) { reportTarget = msg }
                        }
                    )
                    .frame(height: 260)
                    .padding(.horizontal, 12)
                    Spacer().frame(height: 10)
                    LobbySpeechInput(
                        hint: "向\(store.name ?? "本店")说点什么…",
                        sending: sending,
                        onSendText: { sendTextToTarget($0) },
                        onSendSticker: { pack, name in
                            Task {
                                if let err = await LobbyImSession.shared.sendSticker(
                                    groupId: targetGroupId, pack: pack, name: name, seatedInStore: targetSeated) {
                                    showToast(err)
                                }
                            }
                        },
                        onPickImage: { showPicker = true },
                        onGift: nil,
                        onVoiceStop: { handleVoiceStop($0) },
                        onError: { showToast($0) }
                    )
                    .padding(.horizontal, 16)
                    Spacer().frame(height: 20)
                }
            }

            // 右侧切换区
            HStack {
                Spacer()
                immersiveModeToggle
                    .padding(.trailing, 0)
            }
        }
        .gesture(
            // 水平拖动切店（阈值 60pt）
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) >= 60 else { return }
                    if dx < 0, idx < vm.stores.count - 1 { idx += 1 }
                    if dx > 0, idx > 0 { idx -= 1 }
                }
        )
        .task(id: targetGroupId) {
            if let gid = targetGroupId {
                LobbyImSession.shared.ensureStoreJoined(gid)
            }
        }
    }

    @State private var immersiveStoreMode = false

    private var immersiveModeToggle: some View {
        VStack(spacing: 5) {
            Image(systemName: immersiveStoreMode ? "message" : "person.2")
                .font(.system(size: 13))
                .foregroundStyle(LobbyColors.goldLight)
            Text(immersiveStoreMode ? "回\n聊\n天" : "看\n门\n店")
                .font(.system(size: 8.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 18)
        .background(Color(red: 0x12/255, green: 0x0C/255, blue: 0x0E/255).opacity(0.6))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .stroke(LobbyColors.gold.opacity(0.35), lineWidth: 1)
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { immersiveStoreMode.toggle() }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func storeInfoLayer(_ store: LobbyStoreCard) -> some View {
        VStack(spacing: 0) {
            Text(store.name ?? "")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(LobbyColors.ivory)
            Spacer().frame(height: 8)
            Text(store.area ?? "")
                .font(.system(size: 11).italic())
                .foregroundStyle(LobbyColors.goldLight.opacity(0.8))
            Spacer().frame(height: 18)
            HStack(spacing: 6) {
                Circle().fill(LobbyColors.seated).frame(width: 8, height: 8)
                Text("\(store.seatedCount ?? 0)")
                    .font(.system(size: 20))
                    .foregroundStyle(LobbyColors.seated)
                Text("入座")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer().frame(height: 28)
            Button {
                storeNav = StoreNav(storeId: store.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "storefront").font(.system(size: 14))
                    Text("进入门店大厅")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer().frame(height: 16)
            Text("← 左右滑动切换门店 →")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 发送管道

    private func sendTextToTarget(_ text: String) {
        sending = true
        Task {
            let err = await LobbyImSession.shared.sendText(groupId: targetGroupId, text: text, seatedInStore: targetSeated)
            sending = false
            if let err { showToast(err) }
        }
    }

    private func handleVoiceStop(_ r: LobbyVoiceRecorder.Result) {
        guard let path = r.path else {
            if let e = r.error { showToast(e) }
            return
        }
        sending = true
        Task {
            let err = await LobbyImSession.shared.sendVoice(groupId: targetGroupId, path: path, seconds: r.seconds, seatedInStore: targetSeated)
            sending = false
            if let err { showToast(err) }
        }
    }

    private func sendPickedImage(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let jpeg = ui.jpegData(compressionQuality: 0.85) else {
                showToast("图片读取失败，换一张试试")
                return
            }
            // IM 图片消息需要本地文件路径
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("lobby_img_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
            do {
                try jpeg.write(to: file)
            } catch {
                showToast("图片读取失败，换一张试试")
                return
            }
            sending = true
            let err = await LobbyImSession.shared.sendImage(groupId: targetGroupId, path: file.path, seatedInStore: targetSeated)
            sending = false
            if let err { showToast(err) }
        }
    }

    // MARK: - 浮层

    private func userCard(_ u: LobbyChatMessage) -> some View {
        LobbyUserCard(
            userId: u.senderId,
            nickname: u.nickname,
            avatar: u.avatar,
            tableNo: u.tableNo,
            seated: u.seatState == "seated",
            isSelf: u.senderId == (TokenManager.shared.userId ?? -1),
            onDismiss: { cardUser = nil },
            onGift: { cardUser = nil; giftNav = LobbyNavTarget(userId: u.senderId, nickname: u.nickname) },
            onChat: { cardUser = nil; chatNav = LobbyNavTarget(userId: u.senderId, nickname: u.nickname) },
            onFollow: {
                cardUser = nil
                Task {
                    do {
                        _ = try await FollowAPI.friendApply(userId: u.senderId)
                        showToast("好友申请已发送")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            },
            onInviteShare: {
                cardUser = nil
                showToast("邀请拼桌请到门店大厅「我的桌」里发起")
            },
            onDrink: { cardUser = nil; giftNav = LobbyNavTarget(userId: u.senderId, nickname: u.nickname) },
            onReport: {
                cardUser = nil
                if u.canReport(myUserId: TokenManager.shared.userId ?? -1) { reportTarget = u }
            }
        )
    }

    private func reportSheet(_ msg: LobbyChatMessage) -> some View {
        LobbyReportSheet(
            onDismiss: { reportTarget = nil },
            onSubmit: { reason in
                reportTarget = nil
                Task {
                    do {
                        try await LobbyImSession.shared.report(msgId: msg.msgId, reason: reason, detail: nil)
                        showToast("举报已提交，平台会核查处置")
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
            }
        )
    }
}

private func lobbyDim(_ alpha: Double) -> Color {
    Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(alpha)
}

/// 门店卡片（暗夜大厅 feed；对齐安卓 StoreCard）：
/// 入座/围观双数 + 我的门店金胶囊 + 全城流简报行（带会员身份，点整行开资料卡）
struct LobbyStoreCardView: View {
    let store: LobbyStoreCard
    let isMine: Bool
    let latest: LobbyChatMessage?
    let onEnter: () -> Void
    let onUserClick: (LobbyChatMessage) -> Void

    @ObservedObject private var cardStore = MemberCardStore.shared

    var body: some View {
        let seated = store.seatedCount ?? 0
        let standing = store.standingCount ?? 0
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let cover = store.cover, !cover.isEmpty, let url = webImageURL(cover) {
                    WebImage(url: url) { StoreCoverFallback() }
                        .frame(height: 180)
                } else {
                    // 门店未配封面时的兜底（生产多数门店 cover 为空）：暗夜渐变，不显示空黑块
                    StoreCoverFallback()
                        .frame(height: 180)
                }
                LinearGradient(
                    colors: [Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.15), Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.9)],
                    startPoint: .top, endPoint: .bottom
                )
                HStack(spacing: 6) {
                    if isMine {
                        // 我的门店金胶囊（原型 bound 徽标）：金渐变底 + 深字
                        Text("我的门店")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(LinearGradient(colors: [Color(red: 0xF5/255, green: 0xE3/255, blue: 0xB8/255),
                                                                Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255)],
                                                       startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    if seated > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "record.circle").font(.system(size: 9)).foregroundStyle(.white)
                            Text("开局中").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LobbyColors.crimson)
                        .clipShape(Capsule())
                    }
                }
                .padding(12)
                VStack(alignment: .leading, spacing: 2) {
                    Spacer()
                    Text(store.name ?? "未命名门店")
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(LobbyColors.ivory)
                        .lineLimit(1)
                    Text(store.area ?? "")
                        .font(.system(size: 9).italic())
                        .foregroundStyle(LobbyColors.goldLight.opacity(0.75))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .contentShape(Rectangle())
            .onTapGesture { onEnter() }

            HStack(spacing: 0) {
                // 入座/围观双数（原型 v75 口径：绿点入座 + 金点围观）
                Circle().fill(LobbyColors.seated).frame(width: 7, height: 7)
                Spacer().frame(width: 6)
                Text("\(seated)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LobbyColors.seated)
                Spacer().frame(width: 3)
                Text("入座")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer().frame(width: 16)
                Circle().fill(LobbyColors.standing).frame(width: 7, height: 7)
                Spacer().frame(width: 6)
                Text("\(standing)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LobbyColors.standing)
                Spacer().frame(width: 3)
                Text("围观")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "storefront").font(.system(size: 10))
                    Text("进入大厅")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture { onEnter() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 简报行：全城流最新一条带会员身份，直角边框，点整行开资料卡；
            // 流内无该店消息时回退后端 latestMessage 纯文本
            if let msg = latest {
                briefingRow(msg)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else if let preview = lobbyLatestPreview(store.latestMessage) {
                Text(preview)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Noir.gold.opacity(0.15), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(Color(red: 0x0D/255, green: 0x0B/255, blue: 0x0F/255))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(
            isMine ? Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255).opacity(0.55) : Noir.gold.opacity(0.28),
            lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .task(id: latest?.senderId) {
            if let sid = latest?.senderId, sid > 0 {
                MemberCardStore.shared.fetchMissing([sid])
            }
        }
    }

    private func briefingRow(_ msg: LobbyChatMessage) -> some View {
        let card = cardStore.card(msg.senderId)
        return HStack(spacing: 0) {
            LobbyMemberAvatar(userId: msg.senderId, fallbackAvatar: msg.avatar, size: 26, frameScale: 1)
            Spacer().frame(width: 8)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(memberDisplayName(card, msg.nickname))
                        .font(.system(size: 10))
                        .foregroundStyle(LobbyColors.goldLight.opacity(0.8))
                        .lineLimit(1)
                    // 身份行顺序（用户口径）：昵称 → 等级 → 桌号，必须同一行
                    if card?.vipName?.isEmpty == false {
                        Spacer().frame(width: 4)
                        LobbyVipChip(vipName: card?.vipName, vipColor: card?.vipColor, levelInTier: card?.levelInTier)
                    }
                    if let tableNo = msg.tableNo, !tableNo.isEmpty {
                        Spacer().frame(width: 4)
                        Text("· \(tableNo)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(lobbyBriefingPreview(msg))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer().frame(width: 8)
            Text(lobbyChatTime(msg.timeSec))
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 0).stroke(Noir.gold.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onUserClick(msg) }
    }
}

/// 简报行文案：文本原样，其余类型给占位（语音/图片/表情也可当「最新一条」）
private func lobbyBriefingPreview(_ msg: LobbyChatMessage) -> String {
    switch msg.kind {
    case .text: return msg.text ?? ""
    case .sticker: return "[表情]"
    case .voice: return msg.voiceSeconds > 0 ? "[语音] \(msg.voiceSeconds)s" : "[语音]"
    case .image: return "[图片]"
    case .system: return ""
    }
}
