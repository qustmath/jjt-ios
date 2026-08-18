import SwiftUI

/// 支付页 — 对齐安卓 PayConfirmScreen 精简版：
/// 提交支付（channelCode=juheba_alipay）→ 拉起支付宝收银台 → 返回 App 轮询结果
struct PayView: View {

    let payOrderId: Int64
    let priceFen: Int
    /// 金额明细预览（结算页传入；订单详情过来时也可能带）
    var totalFen: Int? = nil
    var rabbitCoinFen: Int? = nil
    var radishCoinFen: Int? = nil
    /// 支付完成（成功或用户放弃返回）回调
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: PayStatus = .idle
    @State private var errorMessage: String?

    private enum PayStatus { case idle, submitting, waitingResult, success, failed }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss(); onFinish() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Noir.goldLight)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                    }
                    Spacer()
                    Text("收银台")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                switch status {
                case .success:
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Noir.gold)
                        Text("支付成功")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(Noir.ivory)
                        Button { dismiss(); onFinish() } label: {
                            Text("完成")
                        }
                        .buttonStyle(NoirPrimaryButtonStyle())
                        .padding(.horizontal, 60)
                        .padding(.top, 10)
                    }
                case .waitingResult:
                    VStack(spacing: 14) {
                        ProgressView().tint(Noir.gold)
                        Text("请在支付宝完成支付…")
                            .font(.system(size: 14))
                            .foregroundStyle(Noir.ivory)
                        Text("支付完成后返回 App 自动确认")
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.textDim)
                        Button("我已完成支付") { pollResult() }
                            .foregroundStyle(Noir.crimsonHot)
                            .padding(.top, 8)
                    }
                default:
                    VStack(spacing: 14) {
                        // 金额明细预览（对齐安卓收银台：总额/抵扣/实付一目了然）
                        VStack(spacing: 8) {
                            if let totalFen {
                                previewLine("订单总额", "¥\(fenToYuan(totalFen))")
                            }
                            if let r = rabbitCoinFen, r > 0 {
                                previewLine("兔币抵扣", "-¥\(fenToYuan(r))", highlight: true)
                            }
                            if let r = radishCoinFen, r > 0 {
                                previewLine("萝贝抵扣", "-¥\(fenToYuan(r))", highlight: true)
                            }
                            previewLine("现金支付", "¥\(fenToYuan(priceFen))", bold: true)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.hairlineGold, lineWidth: 1))
                        .padding(.horizontal, 40)

                        Text("支付宝")
                            .font(.system(size: 14))
                            .foregroundStyle(Noir.ivory)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Noir.crimsonHot)
                        }
                        Button { submitPay() } label: {
                            Text(status == .submitting ? "提交中…" : "去支付")
                        }
                        .buttonStyle(NoirPrimaryButtonStyle(enabled: status != .submitting))
                        .disabled(status == .submitting)
                        .padding(.horizontal, 60)
                        .padding(.top, 10)
                    }
                }

                Spacer()
                Spacer()
            }
        }
        // 从支付宝返回 App → 立即轮询一次支付结果（对齐充值页做法）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, status == .waitingResult { pollResult() }
        }
    }

    private func previewLine(_ label: String, _ value: String, highlight: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: bold ? 16 : 12, weight: bold ? .bold : .regular))
                .foregroundStyle(highlight ? Noir.crimsonHot : (bold ? Noir.goldLight : Noir.ivory))
        }
    }

    // MARK: - 支付动作

    private struct PaySubmitReq: Encodable {
        let id: Int64
        let channelCode: String
    }
    private struct PaySubmitResp: Decodable {
        let status: Int?
        let displayContent: String?
    }
    private struct PayOrderInfo: Decodable {
        let id: Int64
        let status: Int?
    }

    private func submitPay() {
        status = .submitting
        Task {
            do {
                let resp: PaySubmitResp = try await APIClient.shared.post(
                    "app-api/pay/order/submit",
                    body: PaySubmitReq(id: payOrderId, channelCode: "juheba_alipay"))
                // 收银台地址 → alipays:// scheme 拉起支付宝 App（对齐充值页做法），失败回退浏览器
                if let content = resp.displayContent {
                    let scheme = "alipays://platformapi/startapp?appId=20000067&url=" +
                        (content.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? content)
                    if let u = URL(string: scheme), await UIApplication.shared.canOpenURL(u) {
                        await UIApplication.shared.open(u)
                    } else if let u = URL(string: content) {
                        await UIApplication.shared.open(u)
                    }
                }
                status = .waitingResult
                pollResult()
            } catch {
                status = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 轮询支付结果（status: 0 待支付 / 10 成功 / 20 关闭）
    private func pollResult() {
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let info: PayOrderInfo = try? await APIClient.shared.get(
                    "app-api/pay/order/get",
                    query: ["id": "\(payOrderId)", "sync": "true"]) {
                    if info.status == 10 {
                        status = .success
                        return
                    }
                    if info.status == 20 {
                        status = .idle
                        errorMessage = "支付已取消"
                        return
                    }
                }
            }
            status = .waitingResult
        }
    }
}
