import SwiftUI
import PhotosUI

/// 我的 — 暗夜奢华风（对齐安卓 ProfileScreen）
/// 结构：顶栏（扫码/设置） → 头像区（进个人主页） → 任务中心 → 我的钱包余额卡（三资产+申请提现） →
///       社交 / 我的服务 / 商城服务 网格 → 更多服务 → 页脚
struct MeView: View {

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = MeViewModel()

    @State private var editingField: EditField?
    @State private var editInput = ""
    @State private var showProfile = false
    @State private var showFriends = false
    @State private var showWallet = false
    @State private var showMemberCenter = false
    @State private var showMyEvents = false
    @State private var showSettings = false
    @State private var showAccountSecurity = false
    @State private var showRealname = false
    @State private var showAbout = false
    @State private var showMyQrCode = false
    @State private var showInvite = false
    @State private var showTaskCenter = false
    @State private var showBadgeWall = false
    @State private var showVipClub = false
    @State private var showTicketWallet = false
    @State private var showAddress = false
    @State private var showMall = false
    @State private var showOrders = false
    @State private var showCouponCenter = false
    @State private var showFavorites = false
    @State private var showPostFavorites = false
    @State private var showMyLikes = false
    // 扫码 / 建群 / 钱包资产页 / 提现
    @State private var showScan = false
    @State private var showCreateGroup = false
    @State private var assetWallet: String?
    @State private var showWithdraw = false

    private enum EditField: Identifiable {
        case nickname, mark
        var id: Int { hashValue }
        var title: String { self == .nickname ? "修改昵称" : "编辑签名" }
    }

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            // 氛围光晕
            Circle()
                .fill(RadialGradient(colors: [Noir.crimson.opacity(0.15), .clear],
                                     center: .center, startRadius: 0, endRadius: 160))
                .frame(width: 288, height: 288)
                .offset(x: 96, y: -280)

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    avatarSection
                    taskCard
                    walletCard
                    gridSection(title: "社交", en: "SOCIAL", items: [
                        GridItem("好友", "person.2") { showFriends = true },
                        GridItem("群聊", "bubble.left.and.bubble.right") { showCreateGroup = true },
                        GridItem("我的组局", "calendar") { showMyEvents = true },
                        GridItem("蜜兔会", "crown", gold: true) { showVipClub = true },
                    ])
                    gridSection(title: "我的服务", en: "SERVICES", items: [
                        GridItem("我的钱包", "wallet.pass", gold: true) { showWallet = true },
                        GridItem("收藏", "star") { showPostFavorites = true },
                        GridItem("我的点赞", "heart") { showMyLikes = true },
                        GridItem("票夹", "ticket", gold: true) { showTicketWallet = true },
                        GridItem("历史记录", "clock.arrow.circlepath") { comingSoon() },
                        GridItem("排行榜", "trophy") { comingSoon() },
                    ])
                    gridSection(title: "商城服务", en: "BOUTIQUE", items: [
                        GridItem("商城", "storefront") { showMall = true },
                        GridItem("我的订单", "bag") { showOrders = true },
                        GridItem("收货地址", "mappin") { showAddress = true },
                        GridItem("优惠券", "ticket") { showCouponCenter = true },
                        GridItem("我的收藏", "heart") { showFavorites = true },
                    ])
                    moreSection
                    footer
                }
            }
            .refreshable { vm.load() }

            if vm.isLoading, vm.user == nil {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Noir.bg.opacity(0.6))
            }
        }
        .onAppear { vm.load() }
        // 成就殿堂挂载/卸下勋章后刷新挂载行（TabView 页面常驻，onAppear 不一定再触发）
        .onReceive(NotificationCenter.default.publisher(for: .jjtBadgesChanged)) { _ in
            vm.load()
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        .alert(editingField?.title ?? "", isPresented: Binding(
            get: { editingField != nil },
            set: { if !$0 { editingField = nil } }
        )) {
            TextField("请输入", text: $editInput)
            Button("保存") { commitEdit() }
            Button("取消", role: .cancel) { editingField = nil }
        }
        .fullScreenCover(isPresented: $showProfile) {
            UserProfileView(userId: TokenManager.shared.userId ?? 0)
        }
        .fullScreenCover(isPresented: $showFriends, onDismiss: { vm.load() }) {
            FriendListView()
        }
        .fullScreenCover(isPresented: $showWallet, onDismiss: { vm.load() }) {
            WalletHomeView()
        }
        .fullScreenCover(isPresented: $showMemberCenter, onDismiss: { vm.load() }) {
            MemberCenterView()
        }
        .fullScreenCover(isPresented: $showMyEvents) {
            GroupEventListView(mode: "my")
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView()
        }
        .fullScreenCover(isPresented: $showCreateGroup) {
            CreateGroupView()
        }
        // 钱包资产流水页（兔币/萝贝/收益，对齐安卓 onAssetClick）
        .fullScreenCover(isPresented: Binding(
            get: { assetWallet != nil },
            set: { if !$0 { assetWallet = nil } }
        )) {
            if let type = assetWallet {
                WalletView(walletType: type)
            }
        }
        // 申请提现（对齐安卓 onWithdrawClick）
        .fullScreenCover(isPresented: $showWithdraw, onDismiss: { vm.load() }) {
            WithdrawView()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showAccountSecurity, onDismiss: { vm.load() }) {
            AccountSecurityView()
        }
        .fullScreenCover(isPresented: $showRealname) {
            RealnameVerifyView()
        }
        .fullScreenCover(isPresented: $showAbout) {
            AboutView()
        }
        .fullScreenCover(isPresented: $showMyQrCode) {
            MyQrCodeView()
        }
        .fullScreenCover(isPresented: $showInvite) {
            InviteView()
        }
        .fullScreenCover(isPresented: $showTaskCenter, onDismiss: { vm.load() }) {
            TaskCenterView()
        }
        .fullScreenCover(isPresented: $showBadgeWall) {
            BadgeWallView()
        }
        .fullScreenCover(isPresented: $showVipClub) {
            VipClubMainView()
        }
        .fullScreenCover(isPresented: $showTicketWallet) {
            TicketWalletView()
        }
        .fullScreenCover(isPresented: $showAddress) {
            AddressListView()
        }
        .fullScreenCover(isPresented: $showMall) {
            MallHomeView()
        }
        .fullScreenCover(isPresented: $showOrders) {
            OrderListView()
        }
        .fullScreenCover(isPresented: $showCouponCenter) {
            CouponCenterView()
        }
        .fullScreenCover(isPresented: $showFavorites) {
            FavoriteView()
        }
        .fullScreenCover(isPresented: $showPostFavorites) {
            PostInteractionListView(kind: .favorite)
        }
        .fullScreenCover(isPresented: $showMyLikes) {
            PostInteractionListView(kind: .like)
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Text("MY NOIR")
                .font(.system(size: 10, weight: .medium, design: .serif))
                .italic()
                .tracking(3)
                .foregroundStyle(Noir.gold.opacity(0.6))
            Spacer()
            iconButton("qrcode.viewfinder") { showScan = true }
            iconButton("gearshape") { showSettings = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
                .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.leading, 10)
    }

    // MARK: - 头像区

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                // 头像（对齐安卓：我的页不可直接改头像，整行点击进个人主页，改头像/头像框在个人中心）
                AppAvatar(url: vm.user?.avatar, size: 88,
                          frameURL: vm.user?.avatarFrame,
                          frameScale: vm.user?.avatarFrameScale.map { CGFloat($0) } ?? 1.25)
                    .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 4) {
                    // 昵称 + 段位徽章 / 升级VIP
                    HStack(spacing: 8) {
                        Text(vm.user?.nickname ?? "未设置")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(1)
                            .onTapGesture {
                                editInput = vm.user?.nickname ?? ""
                                editingField = .nickname
                            }
                        if let level = vm.user?.level, let name = level.name, !name.isEmpty {
                            vipBadge(level)
                        } else {
                            upgradeBadge
                        }
                    }
                    // 签名
                    HStack(spacing: 6) {
                        Text("“\((vm.user?.mark?.isEmpty == false) ? vm.user!.mark! : "这个人很神秘，什么都没留下")”")
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .onTapGesture {
                        editInput = vm.user?.mark ?? ""
                        editingField = .mark
                    }
                    // 挂载勋章
                    if !vm.mountedBadges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(vm.mountedBadges.prefix(5), id: \.id) { badge in
                                badgeIcon(badge)
                            }
                        }
                        .padding(.top, 2)
                        .onTapGesture { showBadgeWall = true }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .contentShape(Rectangle())
            .onTapGesture { showProfile = true }

            Text("点击头像进入个人主页")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.leading, 24)
        }
    }

    private func vipBadge(_ level: UserLevelInfo) -> some View {
        let color = Noir.tierColor(level.color)
        return HStack(spacing: 4) {
            Image(systemName: "crown")
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text("\(level.name ?? "") · Lv.\(level.levelInTier ?? 1)")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.65), lineWidth: 1))
        .onTapGesture { showMemberCenter = true }
    }

    private var upgradeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown")
                .font(.system(size: 10))
            Text("升级VIP")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing))
        .clipShape(Capsule())
        .onTapGesture { showMemberCenter = true }
    }

    private func badgeIcon(_ badge: BadgeHallItem) -> some View {
        Group {
            if let icon = badge.icon, icon.hasPrefix("http"), let url = URL(string: icon) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "medal")
                            .foregroundStyle(Noir.gold.opacity(0.6))
                    }
                }
            } else {
                Image(systemName: "medal")
                    .foregroundStyle(Noir.gold.opacity(0.6))
            }
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - 任务中心卡

    private var taskCard: some View {
        cardRow(
            background: LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.65),
                                                Color(red: 0x12/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
            border: Noir.gold.opacity(0.4)
        ) {
            HStack {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255),
                                                      Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                                             center: .center, startRadius: 0, endRadius: 30))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Noir.gold.opacity(0.45), lineWidth: 1))
                    Image(systemName: "target")
                        .font(.system(size: 17))
                        .foregroundStyle(Noir.goldLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("任务中心")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(Noir.ivory)
                        if vm.taskClaimable > 0 {
                            Text("\(vm.taskClaimable) 可领取")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(LinearGradient(colors: [Noir.crimson, Color(red: 0x8A/255, green: 0x0C/255, blue: 0x22/255)],
                                                           startPoint: .leading, endPoint: .trailing))
                                .clipShape(Capsule())
                        }
                    }
                    Text("今日任务 \(vm.taskDailyDone)/\(vm.taskDailyTotal) · 赢萝贝解锁勋章")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Noir.goldLight.opacity(0.55), lineWidth: 1))
            }
        } onTap: { showTaskCenter = true }
    }

    // MARK: - 我的钱包余额卡（对齐安卓：兔币/萝贝/收益三资产 + 申请提现）

    private var walletCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                assetCell(value: "\(vm.user?.freeCoin ?? 0)", label: "兔币", divider: false) { assetWallet = "rabbit_coin" }
                assetCell(value: "\(vm.user?.giftCoin ?? 0)", label: "萝贝", divider: true) { assetWallet = "radish_coin" }
                assetCell(value: "¥\(vm.user?.earnings?.value ?? "0.00")", label: "我的收益", divider: true) { assetWallet = "earnings" }
            }
            Button { showWithdraw = true } label: {
                Text("申 请 提 现")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(LinearGradient(
                        colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                        startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.7), Color(red: 0x10/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.crimson.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func assetCell(value: String, label: String, divider: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if divider { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 图标网格分区

    private struct GridItem {
        let name: String
        let icon: String
        let gold: Bool
        let action: () -> Void

        init(_ name: String, _ icon: String, gold: Bool = false, action: @escaping () -> Void) {
            self.name = name
            self.icon = icon
            self.gold = gold
            self.action = action
        }
    }

    private func gridSection(title: String, en: String, items: [GridItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, en: en)
            VStack(spacing: 10) {
                ForEach(0..<(items.count + 3) / 4, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { col in
                            let idx = row * 4 + col
                            if idx < items.count {
                                gridCell(items[idx])
                            } else {
                                Spacer().frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(glassBrush)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
    }

    private func gridCell(_ item: GridItem) -> some View {
        Button(action: item.action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: item.gold
                                ? [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Color(red: 0x14/255, green: 0x0D/255, blue: 0x04/255)]
                                : [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                            center: .center, startRadius: 0, endRadius: 32))
                        .frame(width: 46, height: 46)
                        .overlay(Circle().stroke(
                            item.gold ? Noir.goldLight.opacity(0.6) : Noir.gold.opacity(0.32), lineWidth: 1))
                    Image(systemName: item.icon)
                        .font(.system(size: 19))
                        .foregroundStyle(Noir.goldLight)
                }
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 更多服务

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "更多服务", en: "MORE")
            VStack(spacing: 0) {
                moreRow("实名认证", "checkmark.shield") { showRealname = true }
                moreRow("我的二维码", "qrcode") { showMyQrCode = true }
                moreRow("邀请好友", "person.badge.plus") { showInvite = true }
                moreRow("账号安全", "lock") { showAccountSecurity = true }
                moreRow("设置", "gearshape") { showSettings = true }
                moreRow("关于我们", "info.circle", divider: false) { showAbout = true }
                // 退出登录在设置页（对齐安卓，不在更多服务重复）
            }
            .padding(.horizontal, 20)
            .background(glassBrush)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
    }

    private func moreRow(_ title: String, _ icon: String, tint: Color? = nil, divider: Bool = true,
                         action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(tint ?? Noir.gold.opacity(0.7))
                        .frame(width: 20)
                    Text(title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(tint ?? Color.white.opacity(0.85))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if divider {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    // MARK: - 通用件

    private var glassBrush: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func sectionHeader(title: String, en: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Text(en)
                .font(.system(size: 9, design: .serif))
                .italic()
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.25))
                .padding(.bottom, 2)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func cardRow<Content: View>(
        background: LinearGradient, border: Color,
        @ViewBuilder content: () -> Content, onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            content()
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var footer: some View {
        Text("JINGJI RABBIT · NOIR SOCIAL CLUB")
            .font(.system(size: 9, design: .serif))
            .italic()
            .tracking(2.7)
            .foregroundStyle(.white.opacity(0.2))
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 32)
    }

    // MARK: - 动作

    private func comingSoon(_ name: String? = nil) {
        jjtShowToast((name ?? "功能") + "建设中，敬请期待")
    }

    private func commitEdit() {
        guard let field = editingField else { return }
        let value = editInput.trimmingCharacters(in: .whitespacesAndNewlines)
        editingField = nil
        switch field {
        case .nickname:
            guard !value.isEmpty, value != vm.user?.nickname else { return }
            vm.update(UpdateUserReq(nickname: value))
        case .mark:
            guard value != vm.user?.mark else { return }
            vm.update(UpdateUserReq(mark: value))
        }
    }
}

#Preview {
    MeView().environmentObject(AppState())
}
