import SwiftUI

/// 支付密码守卫（对齐安卓 PayPasswordGuard）：资金操作前统一入口。
///
/// 用法：
/// ```swift
/// @StateObject private var payGuard = PayPasswordGuard()
/// // 视图上挂修饰符：
/// .payPasswordGuard(payGuard, onNeedSetPassword: { showPaySettings = true })
/// // 触发点：
/// payGuard.require { pwd in _ = try await WithdrawAPI.apply(...) }
/// ```
/// action 抛异常时：密码错误/锁定 → 弹窗内展示服务端文案可重试；
/// 未设置（code=1004021000）→ 弹「去设置」引导；成功 → 自动关闭。
@MainActor
final class PayPasswordGuard: ObservableObject {

    @Published var visible = false
    @Published var errorText: String?
    @Published var submitting = false
    @Published var showNotSetGuide = false

    private var action: ((String) async throws -> Void)?

    /// 资金操作入口：先查状态——未设置 → 「去设置」引导；已设置 → 弹密码框。
    /// 状态查询失败兜底弹输入框，由后端校验把守。
    func require(_ action: @escaping (String) async throws -> Void) {
        self.action = action
        errorText = nil
        Task {
            let notSet: Bool
            do {
                notSet = try await PayPasswordAPI.status().hasPayPassword == false
            } catch {
                notSet = false
            }
            if notSet { showNotSetGuide = true } else { visible = true }
        }
    }

    func submit(_ pwd: String) {
        guard let act = action, !submitting else { return }
        submitting = true
        errorText = nil
        Task {
            do {
                try await act(pwd)
                visible = false
            } catch let e as APIError {
                if case .business(let code, _) = e, code == PAY_PASSWORD_NOT_SET_CODE {
                    visible = false
                    showNotSetGuide = true
                } else {
                    errorText = e.errorDescription
                }
            } catch {
                errorText = error.localizedDescription
            }
            submitting = false
        }
    }

    func dismiss() { if !submitting { visible = false } }
    func dismissNotSetGuide() { showNotSetGuide = false }
}

/// 守卫弹窗挂载修饰符（密码输入弹层 + 未设置引导 alert）
struct PayPasswordGuardModifier: ViewModifier {
    @ObservedObject var payGuard: PayPasswordGuard
    var hint: String? = nil
    let onNeedSetPassword: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if payGuard.visible {
                    PayPasswordSheet(
                        hint: hint,
                        errorText: payGuard.errorText,
                        submitting: payGuard.submitting,
                        onSubmit: { payGuard.submit($0) },
                        onDismiss: { payGuard.dismiss() }
                    )
                }
            }
            .alert("未设置支付密码", isPresented: Binding(
                get: { payGuard.showNotSetGuide },
                set: { if !$0 { payGuard.dismissNotSetGuide() } }
            )) {
                Button("去设置") {
                    payGuard.dismissNotSetGuide()
                    onNeedSetPassword()
                }
                Button("取消", role: .cancel) { payGuard.dismissNotSetGuide() }
            } message: {
                Text("提现、发红包、兔币消费等资金操作需要先设置支付密码")
            }
    }
}

extension View {
    func payPasswordGuard(_ payGuard: PayPasswordGuard, hint: String? = nil,
                          onNeedSetPassword: @escaping () -> Void) -> some View {
        modifier(PayPasswordGuardModifier(payGuard: payGuard, hint: hint, onNeedSetPassword: onNeedSetPassword))
    }
}

/// 支付密码输入弹层：6 位数字，输满自动提交（对齐安卓 PayPasswordDialog）
struct PayPasswordSheet: View {

    var title: String = "请输入支付密码"
    var hint: String? = nil
    var errorText: String? = nil
    var submitting: Bool = false
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var pwd = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { if !submitting { onDismiss() } }

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Noir.ivory)
                if let hint {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 6)
                }

                // 6 格密码显示 + 隐藏输入框
                ZStack {
                    TextField("", text: $pwd)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .onChange(of: pwd) { _, v in
                            let digits = String(v.filter(\.isNumber).prefix(6))
                            if digits != v { pwd = digits }
                            if digits.count == 6, !submitting { onSubmit(digits) }
                        }
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { idx in
                            let filled = idx < pwd.count
                            let isNext = idx == pwd.count
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            errorText != nil ? Noir.crimsonHot.opacity(0.7)
                                                : isNext ? Noir.gold.opacity(0.7)
                                                : Color.white.opacity(0.12),
                                            lineWidth: 1)
                                )
                                .overlay(
                                    Circle()
                                        .fill(filled ? Noir.ivory : .clear)
                                        .frame(width: 10, height: 10)
                                )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }
                }
                .padding(.top, 20)

                ZStack {
                    if submitting {
                        ProgressView().tint(Noir.gold).scaleEffect(0.8)
                    } else if let errorText {
                        Text(errorText)
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                }
                .frame(height: 18)
                .padding(.top, 14)

                Button("取消") { onDismiss() }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .disabled(submitting)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.hairlineGold, lineWidth: 1))
            .padding(.horizontal, 32)
        }
        .onAppear { focused = true }
        // 出错时清空重输
        .onChange(of: errorText) { _, v in if v != nil { pwd = "" } }
    }
}
