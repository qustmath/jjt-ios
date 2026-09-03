import SwiftUI

/// 提现 — 金额 + 费率试算 + 选卡 + 支付密码（对齐安卓 WithdrawScreen）
struct WithdrawView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = WithdrawViewModel()
    @StateObject private var payGuard = PayPasswordGuard()
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var showPaySettings = false
    @State private var showCardManager = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 14) {
                        balanceCard
                        amountSection
                        cardSection
                        ruleText
                        submitButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .jjtPageGestures()
        .onAppear {
            vm.load()
            // 进入页面即检查：未设置支付密码直接弹「去设置」引导
            Task {
                if let status = try? await PayPasswordAPI.status(), status.hasPayPassword == false {
                    payGuard.showNotSetGuide = true
                }
            }
        }
        .onChange(of: vm.success) { _, ok in
            if ok {
                jjtShowToast("提现申请已提交，等待处理")
                if let onBack { onBack() } else { dismiss() }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 支付密码守卫（密码弹层 + 未设置引导）
        .payPasswordGuard(payGuard, hint: "本次提现 ¥\(amountText)") {
            showPaySettings = true
        }
        .sheet(isPresented: Binding(
            get: { vm.showCardPicker },
            set: { if !$0 { vm.dismissCardPicker() } }
        )) {
            cardPickerSheet
                .presentationDetents([.medium])
                .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        .fullScreenCover(isPresented: $showPaySettings) {
            PayPasswordSettingsView()
        }
        .fullScreenCover(isPresented: $showCardManager, onDismiss: { vm.reloadCards() }) {
            BankCardView()
        }
    }

    private var topBar: some View {
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
            Text("提现")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Button("银行卡") { showCardManager = true }
                .font(.system(size: 13))
                .foregroundStyle(Noir.crimsonHot)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("可提现余额（元）")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Text(fenToYuan(vm.balance))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("提现金额")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                Text("¥")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldLight)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Button("全部提现") {
                    amountText = fenToYuan(vm.balance)
                }
                .font(.system(size: 11))
                .foregroundStyle(Noir.gold)
            }
            .padding(14)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))

            // 费率试算
            if let cfg = vm.config, let yuan = Double(amountText), yuan > 0 {
                let cent = Int64((yuan * 100).rounded())
                let fee = cfg.feeOf(cent)
                let actual = max(cent - fee, 0)
                VStack(spacing: 4) {
                    feeRow("税费/手续费", "-¥\(fenToYuan(fee))")
                    feeRow("预计到账", "¥\(fenToYuan(actual))")
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func feeRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Noir.goldLight)
        }
    }

    private var cardSection: some View {
        Button { vm.showCardPickerSheet() } label: {
            HStack {
                Image(systemName: "building.columns")
                    .font(.system(size: 16))
                    .foregroundStyle(Noir.goldLight)
                if let card = vm.selectedCard {
                    Text("\(card.bankName ?? "银行卡")（尾号 \(card.cardNo?.suffix(4) ?? "----")）")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Noir.ivory)
                } else {
                    Text("选择到账银行卡")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(14)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var ruleText: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cfg = vm.config {
                if let minAmt = cfg.minAmount, minAmt > 0 {
                    ruleLine("单笔最低提现 ¥\(fenToYuan(minAmt))")
                }
                if let maxAmt = cfg.maxSingleAmount, maxAmt > 0 {
                    ruleLine("单笔上限 ¥\(fenToYuan(maxAmt))")
                }
                if let maxCnt = cfg.maxDailyCount, maxCnt > 0 {
                    ruleLine("每日最多提现 \(maxCnt) 次")
                }
            }
            ruleLine("提现将于 1-3 个工作日内到账")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleLine(_ text: String) -> some View {
        Text("· \(text)")
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.3))
    }

    private var submitButton: some View {
        Button {
            guard vm.precheck(amountYuan: amountText) else { return }
            payGuard.require { pwd in
                try await vm.applyWithPassword(amountYuan: amountText, payPassword: pwd)
            }
        } label: {
            Text(vm.submitting ? "提交中…" : "确认提现")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(vm.submitting)
        .padding(.top, 6)
    }

    private var cardPickerSheet: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack {
                Text("选择银行卡")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Button { vm.dismissCardPicker() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            }
            if vm.cardsLoading {
                ProgressView().tint(Noir.gold).padding(30)
            } else if vm.cards.isEmpty {
                Text("暂无绑定银行卡")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(30)
            } else {
                ForEach(vm.cards) { card in
                    Button { vm.selectCard(card) } label: {
                        HStack {
                            Text("\(card.bankName ?? "银行卡")（尾号 \(card.cardNo?.suffix(4) ?? "----")）")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Noir.ivory)
                            Spacer()
                            if vm.selectedCard?.id == card.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Noir.gold)
                            }
                        }
                        .padding(14)
                        .background(Noir.noir2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                vm.dismissCardPicker()
                showCardManager = true
            } label: {
                Text("管理银行卡")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.gold)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

// MARK: - ViewModel（对齐安卓 WithdrawViewModel）

@MainActor
final class WithdrawViewModel: ObservableObject {

    @Published var balance: Int64 = 0              // 收益余额（分）
    @Published var config: WithdrawConfig?
    @Published var cards: [BankCardInfo] = []
    @Published var cardsLoading = false
    @Published var selectedCard: BankCardInfo?
    @Published var showCardPicker = false
    @Published var submitting = false
    @Published var error: String?
    @Published var success = false

    func load() {
        Task {
            balance = (try? await WalletAPI.getWallet("earnings").availableAmount) ?? 0
        }
        Task {
            config = try? await WithdrawAPI.config()
        }
        reloadCards()
    }

    func reloadCards() {
        Task {
            let list = (try? await WithdrawAPI.cards()) ?? []
            cards = list
            if selectedCard == nil {
                selectedCard = list.first { $0.isDefault == true } ?? list.first
            }
        }
    }

    func showCardPickerSheet() {
        showCardPicker = true
        cardsLoading = true
        Task {
            cards = (try? await WithdrawAPI.cards()) ?? []
            cardsLoading = false
        }
    }

    func dismissCardPicker() { showCardPicker = false }
    func selectCard(_ card: BankCardInfo) {
        selectedCard = card
        showCardPicker = false
    }

    /// 本地校验（对齐安卓 precheck），通过后由 UI 弹支付密码
    func precheck(amountYuan: String) -> Bool {
        guard selectedCard != nil else { error = "请选择银行卡"; return false }
        guard let yuan = Double(amountYuan), yuan > 0 else { error = "金额格式错误"; return false }
        let cent = Int64((yuan * 100).rounded())
        if let cfg = config {
            if let minAmt = cfg.minAmount, minAmt > 0, cent < minAmt {
                error = "最低提现金额为 \(fenToYuan(minAmt)) 元"; return false
            }
            if let maxAmt = cfg.maxSingleAmount, maxAmt > 0, cent > maxAmt {
                error = "单笔提现上限为 \(fenToYuan(maxAmt)) 元"; return false
            }
            if cent - cfg.feeOf(cent) <= 0 {
                error = "扣除税费与手续费后无可到账金额"; return false
            }
        }
        if cent > balance {
            error = "提现金额不能超过可提现余额"; return false
        }
        return true
    }

    /// 支付密码确认后调用（失败抛异常交给 PayPasswordGuard 展示）
    func applyWithPassword(amountYuan: String, payPassword: String) async throws {
        guard let card = selectedCard, let yuan = Double(amountYuan) else { return }
        let cent = Int64((yuan * 100).rounded())
        submitting = true
        defer { submitting = false }
        _ = try await WithdrawAPI.apply(WithdrawReq(amount: cent, bankAccountId: card.id, payPassword: payPassword))
        success = true
    }

    func clearError() { error = nil }
}
