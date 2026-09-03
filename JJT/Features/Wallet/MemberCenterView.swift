import SwiftUI

/// 会员中心（荆棘冠冕）— 对齐安卓 MemberCenterScreen（ADR 0007 段位化模型）
/// 段位列表 + 层内等级点亮矩阵（点未点亮格 → 购买弹窗）+ 头像框更换 + 外显段位佩戴
struct MemberCenterView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = MemberCenterViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showFrameSheet = false
    @State private var benefitsTier: MemberTierConfig?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if let my = vm.page?.my, my.tier != nil {
                                currentTierCard(my)
                            } else {
                                uncrownedCard
                            }
                            frameCard
                            tierList
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear { vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 段位权益说明
        .alert(benefitsTier?.name ?? "段位权益", isPresented: Binding(
            get: { benefitsTier != nil },
            set: { if !$0 { benefitsTier = nil } }
        )) {
            Button("知道了") { benefitsTier = nil }
        } message: {
            Text(benefitsTier?.benefits ?? "暂无权益说明")
        }
        // 购买弹窗
        .sheet(isPresented: Binding(
            get: { vm.purchaseTarget != nil },
            set: { if !$0 { vm.closePurchase() } }
        )) {
            purchaseSheet
                .presentationDetents([.medium])
                .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        // 头像框更换弹层
        .sheet(isPresented: $showFrameSheet) {
            frameSheet
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        .jjtPageGestures()
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Noir.goldLight)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("会员中心")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("THORNY CROWN")
                        .font(.system(size: 8.5, design: .serif))
                        .italic()
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    // MARK: - 当前层级卡

    private func currentTierCard(_ my: MyLevelInfo) -> some View {
        let color = Noir.tierColor(my.displayTierColor)
        return VStack(spacing: 10) {
            HStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(my.displayTierName ?? "会员")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(color)
                    Text("Lv.\(my.levelInTier ?? 1) · 累计消费 \(my.totalRabbitCoinCost ?? 0) 兔币")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(my.rabbitCoinBalance ?? 0)")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                    Text("兔币余额")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.7),
                                            Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.45), lineWidth: 1))
        .cornerFrame(color.opacity(0.5), margin: 8, arm: 12)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// 未加冕引导卡
    private var uncrownedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown")
                .font(.system(size: 28))
                .foregroundStyle(Noir.gold.opacity(0.6))
            Text("尚未加冕")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
            Text("点亮下方段位，开启会员尊荣与专属头像框")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 头像框卡

    private var frameCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Noir.noir3)
                    .frame(width: 52, height: 52)
                if let cur = vm.frameOptions?.current, !cur.isEmpty {
                    framePreview(url: cur, size: 60)
                } else {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("头像框")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Text(vm.frameOptions?.current?.isEmpty == false ? "已佩戴" : "未佩戴")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            Button { showFrameSheet = true } label: {
                Text("更换")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 段位列表

    private var tierList: some View {
        VStack(spacing: 12) {
            ForEach(vm.page?.tiers ?? []) { tier in
                tierRow(tier)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func tierRow(_ tier: MemberTierConfig) -> some View {
        let color = Noir.tierColor(tier.color)
        let myOrdinal = vm.page?.my?.ordinal ?? 0
        let start = tier.startOrdinal ?? 0
        // 本层已点亮的等级数
        let lit = max(0, min(tier.levelCount, myOrdinal - start + 1))
        let attained = myOrdinal >= start + tier.levelCount - 1 || lit >= tier.levelCount
        let wearing = vm.page?.my?.effectiveDisplayTier == tier.tier

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: attained ? "crown.fill" : "crown")
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(tier.name)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .foregroundStyle(color)
                        if let en = tier.enName {
                            Text(en)
                                .font(.system(size: 8.5, design: .serif))
                                .italic()
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    Text("\(tier.levelCount) 级 · \(tier.pricePerLevel) 兔币/级")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                // 权益说明
                Button {
                    // 彩蛋「第七层梦境」：冠冕之路点开「月冕」层级（tier 7，对齐安卓）
                    if tier.tier == 7 { EggTrigger.report("tier7") }
                    benefitsTier = tier
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                // 佩戴外显（已达成本层才显示）
                if lit > 0 {
                    Button {
                        vm.setDisplayTier(wearing ? nil : tier.tier)
                    } label: {
                        Text(wearing ? "佩戴中" : "佩戴")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(wearing ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : Noir.goldLight)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(wearing
                                        ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Color.clear))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 层内等级点亮矩阵（点未点亮格 → 查看差额；付费升级已停用，仅展示）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(0..<max(tier.levelCount, 0), id: \.self) { idx in
                    let lv = idx + 1
                    let isLit = lv <= lit
                    Circle()
                        .fill(isLit ? color : Color.white.opacity(0.08))
                        .frame(height: 12)
                        .onTapGesture {
                            if !isLit { vm.openPurchase(tier: tier.tier, level: lv) }
                        }
                }
            }

            // 层内进度条（对齐安卓）
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0x8B/255, green: 0x0A/255, blue: 0x1E/255), Noir.crimsonHot, Noir.goldLight],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(maxWidth: tier.levelCount > 0 ? .infinity : 0)
                        .scaleEffect(x: tier.levelCount > 0 ? CGFloat(lit) / CGFloat(tier.levelCount) : 0, anchor: .leading)
                }
                .clipShape(Capsule())
                .padding(.top, 4)

            HStack {
                Text("已点亮 \(lit)/\(tier.levelCount)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                // 仅展示距离下一级/下一层级所需兔币（对齐安卓，不再提示购买）
                let nextTier = (vm.page?.tiers ?? []).first { ($0.startOrdinal ?? 0) > myOrdinal }
                if lit < tier.levelCount {
                    nextCostText("距离下一等级还需 ", cost: tier.pricePerLevel)
                } else if let nextTier {
                    nextCostText("距离下一层级「\(nextTier.name)」还需 ", cost: nextTier.pricePerLevel)
                }
            }
            .padding(.top, 5)
        }
        .padding(14)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.25), lineWidth: 1))
    }

    /// 「距离下一级还需 X 兔币」仅展示文案（对齐安卓）
    private func nextCostText(_ prefix: String, cost: Int64) -> some View {
        HStack(spacing: 0) {
            Text(prefix)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
            Text("\(cost)")
                .font(.system(size: 10.5, weight: .semibold, design: .serif))
                .foregroundStyle(Noir.goldText)
            Text(" 兔币")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - 升级差额弹窗（付费升级已停用，仅展示差额明细，对齐安卓 PurchaseDialog）

    private var purchaseSheet: some View {
        VStack(spacing: 14) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack {
                Text("升级差额")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Button { vm.closePurchase() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            }

            if vm.feeLoading {
                ProgressView().tint(Noir.gold).padding(40)
            } else if let fee = vm.feeInfo, let target = vm.purchaseTarget {
                let tierName = vm.page?.tiers?.first { $0.tier == target.tier }?.name ?? "T\(target.tier)"
                Text("升级至 \(tierName) · Lv.\(target.level)")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 6) {
                    ForEach(Array((fee.items ?? []).enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text("\(item.name) ×\(item.count) 级")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text("\(item.count) × \(item.pricePerLevel) = \(item.subtotal)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4)
                    HStack {
                        Text("还需消费")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Noir.ivory)
                        Spacer()
                        Text("\(fee.total ?? 0) 兔币")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Noir.goldText)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // 付费升级已停用，弹窗仅展示差额
                Button { vm.closePurchase() } label: {
                    Text("我知道了")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Noir.goldLight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - 头像框弹层

    private var frameSheet: some View {
        AvatarFramePickerSheet(
            options: vm.frameOptions,
            saving: vm.frameSaving,
            onSelect: { vm.selectFrame(url: $0) { showFrameSheet = false } },
            onClose: { showFrameSheet = false }
        )
    }

    // MARK: - 头像框预览（SVGA 动效 / 静态图）

    private func framePreview(url: String, size: CGFloat) -> some View {
        Group {
            if url.lowercased().hasSuffix(".svga") {
                SvgaView(url: url)
            } else if let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

}

// MARK: - ViewModel（对齐安卓 MemberCenterViewModel）

@MainActor
final class MemberCenterViewModel: ObservableObject {

    @Published var isLoading = true
    @Published var page: MemberLevelPage?
    @Published var frameOptions: AvatarFrameOptions?
    @Published var frameSaving = false
    @Published var purchaseTarget: (tier: Int, level: Int)?
    @Published var feeInfo: UpgradeFeeInfo?
    @Published var feeLoading = false
    @Published var error: String?

    func load() {
        Task {
            do {
                page = try await MemberLevelAPI.levelPage()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        loadFrameOptions()
    }

    /// 点未点亮格：查看升级差额（付费升级已停用，弹窗仅展示，对齐安卓）
    func openPurchase(tier: Int, level: Int) {
        purchaseTarget = (tier, level)
        feeInfo = nil
        feeLoading = true
        Task {
            do {
                feeInfo = try await MemberLevelAPI.upgradeFee(targetTier: tier, targetLevel: level)
                feeLoading = false
            } catch {
                feeLoading = false
                purchaseTarget = nil
                self.error = error.localizedDescription
            }
        }
    }

    func closePurchase() {
        purchaseTarget = nil
        feeInfo = nil
        feeLoading = false
    }

    /// 佩戴/取消佩戴外显段位
    func setDisplayTier(_ tier: Int?) {
        Task {
            do {
                _ = try await MemberLevelAPI.setDisplayTier(tier)
                load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func loadFrameOptions() {
        Task {
            frameOptions = try? await AvatarFrameAPI.options()
        }
    }

    /// 更换头像框（url 为空串 = 摘下）
    func selectFrame(url: String, onDone: @escaping () -> Void) {
        guard !frameSaving else { return }
        frameSaving = true
        Task {
            defer { frameSaving = false }
            do {
                _ = try await UserAPI.updateUserInfo(UpdateUserReq(avatarFrame: url))
                jjtShowToast(url.isEmpty ? "已摘下头像框" : "已更换头像框")
                loadFrameOptions()
                onDone()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
