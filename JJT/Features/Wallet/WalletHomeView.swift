import SwiftUI

/// 我的钱包（聚合页）— 资产总览 + 银行卡 + 提现记录（对齐安卓 WalletHomeScreen）
struct WalletHomeView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = WalletHomeViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var walletType: String?       // 流水页（nil 关闭）
    @State private var showWithdraw = false
    @State private var showBankCards = false
    @State private var showRecharge = false

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    assetOverview
                    bankCardSection
                    withdrawSection
                    Text("提现将于 1-3 个工作日内到账")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .padding(.bottom, 24)
            }
            .refreshable { vm.load() }
        }
        .onAppear { vm.load() }
        // 流水页
        .fullScreenCover(isPresented: Binding(
            get: { walletType != nil },
            set: { if !$0 { walletType = nil } }
        ), onDismiss: { vm.load() }) {
            if let type = walletType {
                WalletView(walletType: type, onRecharge: { () -> Void in
                    walletType = nil
                    reopenAfterDismiss { showRecharge = true }
                }, onWithdraw: { () -> Void in
                    walletType = nil
                    reopenAfterDismiss { showWithdraw = true }
                })
            }
        }
        .fullScreenCover(isPresented: $showWithdraw, onDismiss: { vm.load() }) {
            WithdrawView()
        }
        .fullScreenCover(isPresented: $showBankCards, onDismiss: { vm.load() }) {
            BankCardView()
        }
        .fullScreenCover(isPresented: $showRecharge, onDismiss: { vm.load() }) {
            CoinRechargeView()
        }
        .jjtPageGestures()
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
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
            Text("我的钱包")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Text("WALLET")
                .font(.system(size: 9, design: .serif))
                .italic()
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.25))
                .padding(.bottom, -2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: - 资产总览

    private var assetOverview: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                assetCell("\(vm.user?.freeCoin ?? 0)", "兔币") { walletType = "rabbit_coin" }
                divider
                assetCell("\(vm.user?.giftCoin ?? 0)", "萝贝") { walletType = "radish_coin" }
                divider
                assetCell("¥\(vm.user?.earnings?.value ?? "0.00")", "我的收益") { walletType = "earnings" }
            }
            Button { showWithdraw = true } label: {
                Text("申 请 提 现")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255).opacity(0.7),
                                            Color(red: 0x10/255, green: 0x08/255, blue: 0x0A/255).opacity(0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.crimson.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 36)
    }

    private func assetCell(_ value: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [Noir.crimsonHot, Noir.crimson], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 银行卡

    private var bankCardSection: some View {
        VStack(spacing: 10) {
            sectionHeader("银行卡", "CARDS") {
                Button { showBankCards = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("添加")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Noir.gold)
                }
            }
            VStack(spacing: 10) {
                if vm.isLoading {
                    ProgressView().tint(Noir.gold).scaleEffect(0.9)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if vm.cards.isEmpty {
                    Text("暂未绑定银行卡")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    ForEach(vm.cards) { card in
                        bankCardRow(card)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    private func bankCardRow(_ card: BankCardInfo) -> some View {
        Button { showBankCards = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255),
                                                      Color(red: 0x14/255, green: 0x0D/255, blue: 0x04/255)],
                                             center: .center, startRadius: 0, endRadius: 28))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Noir.goldLight.opacity(0.5), lineWidth: 1))
                    Image(systemName: "building.columns")
                        .font(.system(size: 16))
                        .foregroundStyle(Noir.goldLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.bankName ?? "银行卡")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Noir.ivory)
                        Text("储蓄卡")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                        if card.isDefault == true {
                            Text("默认")
                                .font(.system(size: 8))
                                .foregroundStyle(Noir.goldLight)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Noir.gold.opacity(0.15))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                        }
                    }
                    Text("**** **** **** \(card.cardNo?.suffix(4) ?? "----")")
                        .font(.system(size: 12, design: .serif))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 提现记录

    private var withdrawSection: some View {
        VStack(spacing: 10) {
            sectionHeader("提现记录", "WITHDRAWALS")
            VStack(spacing: 0) {
                if vm.withdrawals.isEmpty {
                    Text("暂无提现记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(vm.withdrawals.enumerated()), id: \.element.id) { i, order in
                        withdrawRow(order)
                        if i < vm.withdrawals.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    private func withdrawRow(_ order: WithdrawOrder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(Noir.gold.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                let cents = order.actualAmount ?? order.amount ?? 0
                Text("¥\(fenToYuan(cents))")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text(formatWalletTime(order.createTime))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            Text(order.statusText)
                .font(.system(size: 11))
                .foregroundStyle(order.status == "SUCCESS" ? Noir.goldLight.opacity(0.9) : Noir.crimsonHot)
        }
        .padding(.vertical, 14)
    }

    // MARK: - 通用

    /// 等 cover 关闭动画结束再打开下一个页面
    private func reopenAfterDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: action)
    }

    private func sectionHeader<Action: View>(_ title: String, _ en: String,
                                             @ViewBuilder action: () -> Action = { EmptyView() }) -> some View {
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
            action()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 工具（钱包模块内共用）

/// 分 → 元（两位小数）
func fenToYuan(_ fen: Int64) -> String {
    String(format: "%.2f", Double(fen) / 100.0)
}

/// 后端时间：毫秒时间戳字符串 → yyyy-MM-dd；非纯数字原样截取前 10 位
func formatWalletTime(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "" }
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if let ms = Int64(trimmed), ms > 0 {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }
    return String(trimmed.prefix(10))
}

// MARK: - ViewModel

@MainActor
final class WalletHomeViewModel: ObservableObject {

    @Published var isLoading = true
    @Published var user: UserInfoResp?
    @Published var cards: [BankCardInfo] = []
    @Published var withdrawals: [WithdrawOrder] = []

    /// 三路并行，单项失败静默（对齐安卓 WalletHomeViewModel.load）
    func load() {
        Task {
            async let userTask = UserAPI.getUserInfo()
            async let cardsTask = WithdrawAPI.cards()
            async let listTask = WithdrawAPI.withdrawList()
            user = try? await userTask
            cards = (try? await cardsTask) ?? []
            withdrawals = Array(((try? await listTask) ?? []).prefix(5))
            isLoading = false
        }
    }
}
