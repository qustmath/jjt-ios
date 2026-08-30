import SwiftUI

/// 钱包流水页 — 余额卡 + 流水分页（对齐安卓 WalletScreen）
/// walletType: rabbit_coin 兔币 / radish_coin 萝贝 / earnings 收益（分）
struct WalletView: View {

    let walletType: String
    var onBack: (() -> Void)? = nil
    /// 兔币钱包显示「充值」
    var onRecharge: (() -> Void)? = nil
    /// 收益钱包显示「提现」
    var onWithdraw: (() -> Void)? = nil

    @StateObject private var vm = WalletViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showExchange = false

    private static let titles: [String: (String, String)] = [
        "rabbit_coin": ("兔币", "RABBIT COIN"),
        "radish_coin": ("萝贝", "RADISH"),
        "earnings": ("我的收益", "EARNINGS"),
    ]

    private var isEarnings: Bool { walletType == "earnings" }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar

                if vm.isLoading, vm.transactions.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            balanceCard
                            ForEach(vm.transactions) { tx in
                                transactionRow(tx)
                                Rectangle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
                            }
                            if vm.isLoading {
                                ProgressView().tint(Noir.gold)
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                            } else if vm.hasMore {
                                Color.clear.frame(height: 1)
                                    .onAppear { vm.load(walletType: walletType) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { vm.refresh(walletType: walletType) }
        .sheet(isPresented: $showExchange) {
            RadishExchangeSheet(rabbitBalance: vm.rabbitBalance ?? 0) { amount in
                do {
                    let got = try await vm.exchangeRadish(amount)
                    showExchange = false
                    jjtShowToast("兑换成功，获得 \(got) 萝贝")
                } catch {
                    jjtShowToast(error.localizedDescription)
                }
            }
            .jjtKeyboardDismiss()
            .presentationDetents([.height(280)])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
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
                let t = Self.titles[walletType] ?? ("钱包明细", "WALLET")
                VStack(spacing: 2) {
                    Text(t.0)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text(t.1)
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

    // MARK: - 余额卡

    @ViewBuilder
    private var balanceCard: some View {
        let latestBalance = vm.balance ?? vm.transactions.first?.balanceAfter ?? 0
        switch walletType {
        case "rabbit_coin":
            balanceCardView(label: "兔币余额", value: "\(latestBalance)",
                            actionText: onRecharge != nil ? "充值" : nil) { onRecharge?() }
        case "radish_coin":
            balanceCardView(label: "萝贝余额", value: "\(latestBalance)", actionText: "兑换") {
                Task { await vm.loadRabbitBalance() }
                showExchange = true
            }
        case "earnings":
            balanceCardView(label: "可提现余额（元）", value: fenToYuan(latestBalance),
                            actionText: onWithdraw != nil ? "提现" : nil) { onWithdraw?() }
        default:
            EmptyView()
        }
    }

    private func balanceCardView(label: String, value: String, actionText: String?,
                                 action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
            }
            Spacer()
            if let actionText {
                Button(action: action) {
                    Text(actionText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(LinearGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Noir.wine, Color(red: 0x0A/255, green: 0x08/255, blue: 0x05/255)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .cornerFrame(Noir.goldLight.opacity(0.5), margin: 10, arm: 14)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 流水行

    private func transactionRow(_ tx: WalletTransaction) -> some View {
        let isIncome = tx.direction == 1
        let amountStr: String = {
            let prefix = isIncome ? "+" : "-"
            if isEarnings {
                return "\(prefix)\(fenToYuan(tx.amount ?? 0))元"
            }
            return "\(prefix)\(tx.amount ?? 0)"
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.remark ?? tx.bizType ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Noir.ivory)
                Text(formatTxTime(tx.createTime))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Text(amountStr)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isIncome ? AnyShapeStyle(Noir.goldText) : AnyShapeStyle(Color.white.opacity(0.55)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func formatTxTime(_ ms: Int64?) -> String {
        guard let ms, ms > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }
}

// MARK: - 兔币兑换萝贝弹层

struct RadishExchangeSheet: View {

    let rabbitBalance: Int64
    /// 确认兑换（挂起；失败抛异常由调用方提示）
    let onConfirm: (Int64) async throws -> Void

    @State private var amountText = ""
    @State private var submitting = false
    @Environment(\.dismiss) private var dismiss

    private var amount: Int64? { Int64(amountText) }
    private var valid: Bool { (amount ?? 0) > 0 && (amount ?? 0) <= rabbitBalance }

    var body: some View {
        VStack(spacing: 16) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("兔币兑换萝贝")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Text("1 兔币 = 10 萝贝 · 兔币余额 \(rabbitBalance)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            }

            HStack {
                TextField("输入兔币数量", text: $amountText)
                    .keyboardType(.numberPad)
                    .noirField()
                Button("全部") { amountText = "\(rabbitBalance)" }
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.gold)
            }

            if let amount, amount > 0 {
                Text("可获得 \(amount * 10) 萝贝")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.goldLight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard let amount, valid, !submitting else { return }
                submitting = true
                Task {
                    try? await onConfirm(amount)
                    submitting = false
                }
            } label: {
                Text("确认兑换")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        valid
                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!valid || submitting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

// MARK: - ViewModel

@MainActor
final class WalletViewModel: ObservableObject {

    @Published var transactions: [WalletTransaction] = []
    @Published var balance: Int64?
    /// 兑换弹窗用：兔币余额
    @Published var rabbitBalance: Int64?
    @Published var isLoading = false
    @Published var hasMore = true
    private var pageNo = 0
    private var loadedType: String?

    /// 首次/刷新：清页码重载
    func refresh(walletType: String) {
        guard loadedType != walletType else { return }
        loadedType = walletType
        pageNo = 0
        hasMore = true
        transactions = []
        load(walletType: walletType)
        Task { balance = try await WalletAPI.getWallet(walletType).availableAmount }
    }

    /// 翻页（pageNo=0 表示首页）
    func load(walletType: String) {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let next = pageNo + 1
        Task {
            defer { isLoading = false }
            do {
                let result = try await WalletAPI.transactions(walletType, pageNo: next)
                let list = result.list ?? []
                transactions = next == 1 ? list : transactions + list
                pageNo = next
                hasMore = list.count >= 20
            } catch {
                jjtShowToast(error.localizedDescription)
            }
        }
    }

    func loadRabbitBalance() async {
        rabbitBalance = try? await WalletAPI.getWallet("rabbit_coin").availableAmount
    }

    /// 兔币兑换萝贝，返回获得的萝贝数
    func exchangeRadish(_ amount: Int64) async throws -> Int64 {
        let got = try await WalletAPI.exchangeRadish(amount: amount)
        // 刷新流水与余额
        if let type = loadedType {
            loadedType = nil
            refresh(walletType: type)
        }
        return got
    }
}
