import SwiftUI

/// 兔币充值 — 套餐网格 + 自定义金额 + 拉起支付宝 + 回前台轮询（对齐安卓 CoinRechargeScreen）
/// iOS 暂不上架，沿用安卓支付渠道（聚合吧-支付宝），无需 IAP
struct CoinRechargeView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = CoinRechargeViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var customYuan = ""

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
                            packageGrid
                            customSection
                            tipText
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .jjtPageGestures()
        .onAppear { vm.loadPackages() }
        // 拿到收银台地址 → 拉起支付宝
        .onChange(of: vm.payUrl) { _, url in
            guard let url else { return }
            let scheme = "alipays://platformapi/startapp?appId=20000067&url=" +
                (url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url)
            if let u = URL(string: scheme) {
                UIApplication.shared.open(u, options: [:]) { ok in
                    vm.consumePayUrl(failed: !ok)
                }
            } else {
                vm.consumePayUrl(failed: true)
            }
        }
        // 从支付宝返回 → 轮询支付结果
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.onResumeFromPay() }
        }
        // 成功 → 提示 + 返回
        .onChange(of: vm.success) { _, ok in
            if ok {
                jjtShowToast("充值成功，兔币已到账")
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
        .alert("支付确认中", isPresented: Binding(
            get: { vm.pendingConfirm },
            set: { if !$0 { vm.consumePendingConfirm() } }
        )) {
            Button("知道了") { vm.consumePendingConfirm() }
        } message: {
            Text("暂未查询到支付结果。若已完成付款，兔币可能延迟到账，请稍后查看余额。")
        }
        .overlay {
            if vm.paying || vm.pollingResult {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView().tint(Noir.gold)
                        Text(vm.pollingResult ? "查询支付结果…" : "正在创建订单…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
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
                VStack(spacing: 2) {
                    Text("兔币充值")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("RECHARGE")
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

    // MARK: - 套餐网格

    private var packageGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(vm.packages) { pkg in
                let selected = vm.selectedPackageId == pkg.id
                Button {
                    vm.selectPackage(pkg.id)
                    customYuan = ""
                } label: {
                    VStack(spacing: 6) {
                        Text("\(pkg.payPrice ?? 0) 兔币")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundStyle(selected ? Noir.goldText : LinearGradient(colors: [Noir.ivory], startPoint: .top, endPoint: .bottom))
                        if let bonus = pkg.bonusPrice, bonus > 0 {
                            Text("赠 \(bonus)")
                                .font(.system(size: 9))
                                .foregroundStyle(Noir.crimsonHot)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .overlay(Capsule().stroke(Noir.hairlineRed, lineWidth: 1))
                        }
                        Text("¥\(String(format: "%.0f", Double(pkg.payPrice ?? 0) / 10.0))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Noir.noir2)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                        selected ? Noir.gold : Noir.hairlineGold, lineWidth: selected ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 自定义金额

    private var customSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField("自定义金额（元）", text: $customYuan)
                    .keyboardType(.decimalPad)
                    .noirField()
                    .onChange(of: customYuan) { _, v in
                        if !v.isEmpty { vm.selectedPackageId = nil }
                    }
            }

            Button {
                if let yuan = Double(customYuan), yuan > 0 {
                    vm.payCustom(coins: Int(yuan * 10))
                } else if vm.selectedPackageId != nil {
                    vm.pay()
                } else {
                    vm.error = "请选择充值套餐或输入金额"
                }
            } label: {
                Text(vm.paying ? "处理中…" : "立即充值")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.paying)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var tipText: some View {
        Text("1 元 = 10 兔币 · 支付成功即时到账\n兔币为虚拟商品，充值后不支持退款")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.25))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }
}

// MARK: - ViewModel（对齐安卓 CoinRechargeViewModel）

@MainActor
final class CoinRechargeViewModel: ObservableObject {

    @Published var packages: [CoinRechargePackage] = []
    @Published var selectedPackageId: Int64?
    @Published var isLoading = false
    @Published var paying = false
    @Published var error: String?
    @Published var success = false
    /// submit 返回的收银台地址，非空时 UI 拉起支付宝
    @Published var payUrl: String?
    /// 已拉起支付 App，回到前台时轮询支付结果
    @Published var awaitingPayResult = false
    @Published var pollingResult = false
    /// 轮询超时但可能已扣款
    @Published var pendingConfirm = false

    private var currentPayOrderId: Int64?

    func loadPackages() {
        guard packages.isEmpty else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                packages = try await CoinRechargeAPI.packages()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func selectPackage(_ id: Int64) { selectedPackageId = id }

    func pay() {
        guard let pkgId = selectedPackageId else {
            error = "请选择充值套餐"
            return
        }
        startPay(CoinRechargeCreateReq(packageId: pkgId))
    }

    /// 自定义金额（coins：兔币数，1 元 = 10 兔币）
    func payCustom(coins: Int) {
        guard coins > 0 else {
            error = "请输入正确的充值金额"
            return
        }
        startPay(CoinRechargeCreateReq(payPrice: coins))
    }

    private func startPay(_ req: CoinRechargeCreateReq) {
        paying = true
        error = nil
        Task {
            do {
                let payOrderId = try await CoinRechargeAPI.create(req)
                currentPayOrderId = payOrderId
                let submit = try await CoinRechargeAPI.submitPay(id: payOrderId)
                guard let url = submit.displayContent, !url.isEmpty else {
                    throw APIError.business(code: -1, message: "获取支付地址失败")
                }
                paying = false
                payUrl = url
                awaitingPayResult = true
            } catch {
                paying = false
                self.error = error.localizedDescription
            }
        }
    }

    /// UI 已消费 payUrl（无论拉起成功与否）
    func consumePayUrl(failed: Bool) {
        if failed {
            payUrl = nil
            awaitingPayResult = false
            error = "未能拉起支付宝，请确认已安装"
        } else {
            payUrl = nil
        }
    }

    /// 回到前台：轮询支付结果（每秒一次 ×20；sync=true 后端主动向渠道查）
    func onResumeFromPay() {
        guard awaitingPayResult, !pollingResult, let orderId = currentPayOrderId else { return }
        pollingResult = true
        Task {
            var paid = false
            for _ in 1...20 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                if let order = try? await CoinRechargeAPI.getPayOrder(id: orderId, sync: true),
                   order.status == 10 {
                    paid = true
                    break
                }
            }
            awaitingPayResult = false
            pollingResult = false
            if paid { success = true } else { pendingConfirm = true }
        }
    }

    func clearError() { error = nil }
    func consumePendingConfirm() { pendingConfirm = false }
}
