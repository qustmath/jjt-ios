import SwiftUI

/// 支付密码设置/修改页（对齐安卓 PayPasswordSettingsScreen）
/// 流程（均需短信验证，scene=6 强制发至绑定手机号）：
///  - 设置：短信验证码 → 新密码 → 确认新密码
///  - 修改：原密码 → 短信验证码 → 新密码 → 确认新密码
struct PayPasswordSettingsView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = PayPasswordSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var oldPwd = ""
    @State private var smsCode = ""
    @State private var newPwd = ""
    @State private var confirmPwd = ""

    private var canSubmit: Bool {
        let baseOK = smsCode.count >= 4 && newPwd.count == 6 && newPwd == confirmPwd
        return vm.hasPayPassword ? (oldPwd.count == 6 && baseOK) : baseOK
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if vm.loading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            statusCard

                            if vm.hasPayPassword {
                                SecureField("原支付密码（6 位数字）", text: $oldPwd)
                                    .keyboardType(.numberPad)
                                    .noirField()
                                    .onChange(of: oldPwd) { _, v in oldPwd = String(v.filter(\.isNumber).prefix(6)) }
                            }

                            HStack(spacing: 10) {
                                TextField("短信验证码", text: $smsCode)
                                    .keyboardType(.numberPad)
                                    .noirField()
                                Button(vm.countdown > 0 ? "\(vm.countdown)s" : "获取验证码") {
                                    vm.sendSmsCode()
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(vm.countdown > 0 ? Noir.textFaint : Noir.gold)
                                .frame(width: 96)
                                .disabled(vm.countdown > 0 || vm.smsSending)
                            }

                            SecureField("新支付密码（6 位数字）", text: $newPwd)
                                .keyboardType(.numberPad)
                                .noirField()
                                .onChange(of: newPwd) { _, v in newPwd = String(v.filter(\.isNumber).prefix(6)) }

                            SecureField("确认新密码", text: $confirmPwd)
                                .keyboardType(.numberPad)
                                .noirField()
                                .onChange(of: confirmPwd) { _, v in confirmPwd = String(v.filter(\.isNumber).prefix(6)) }

                            if !confirmPwd.isEmpty, newPwd != confirmPwd {
                                Text("两次输入的密码不一致")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Noir.crimsonHot)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button { vm.submit(old: vm.hasPayPassword ? oldPwd : nil, newPwd: newPwd, smsCode: smsCode) } label: {
                                Text(vm.submitting ? "提交中…" : (vm.hasPayPassword ? "确认修改" : "确认设置"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        canSubmit
                                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Color.white.opacity(0.08))
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSubmit || vm.submitting)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
            }
        }
        .jjtPageGestures()
        .onAppear { vm.load() }
        .onChange(of: vm.done) { _, done in
            if done {
                jjtShowToast(vm.hasPayPassword ? "支付密码修改成功" : "支付密码设置成功")
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
            Text("支付密码")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.hasPayPassword ? "lock.shield" : "exclamationmark.shield")
                .font(.system(size: 20))
                .foregroundStyle(vm.hasPayPassword ? Noir.goldLight : Noir.crimsonHot)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.hasPayPassword ? "已设置支付密码" : "未设置支付密码")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Text(vm.mobile.isEmpty ? "验证码将发送至绑定手机号" : "验证码发送至 \(vm.mobile)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
        }
        .padding(14)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
    }
}

// MARK: - ViewModel（对齐安卓 PayPasswordSettingsViewModel）

@MainActor
final class PayPasswordSettingsViewModel: ObservableObject {

    @Published var loading = true
    @Published var hasPayPassword = false
    @Published var mobile = ""
    @Published var submitting = false
    @Published var smsSending = false
    @Published var countdown = 0
    @Published var error: String?
    @Published var done = false

    private var countdownTask: Task<Void, Never>?

    func load() {
        Task {
            do {
                hasPayPassword = try await PayPasswordAPI.status().hasPayPassword == true
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
            // 绑定手机号（展示用；失败静默）
            if let user = try? await UserAPI.getUserInfo(), let m = user.mobile {
                mobile = m
            }
        }
    }

    func sendSmsCode() {
        guard countdown == 0, !smsSending else { return }
        smsSending = true
        error = nil
        Task {
            do {
                _ = try await PayPasswordAPI.sendSmsCode()
                smsSending = false
                startCountdown()
            } catch {
                smsSending = false
                self.error = error.localizedDescription
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task {
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
        }
    }

    func submit(old: String?, newPwd: String, smsCode: String) {
        guard !submitting else { return }
        submitting = true
        error = nil
        Task {
            do {
                if let old {
                    _ = try await PayPasswordAPI.update(old: old, new: newPwd, smsCode: smsCode)
                } else {
                    _ = try await PayPasswordAPI.set(password: newPwd, smsCode: smsCode)
                }
                submitting = false
                done = true
            } catch {
                submitting = false
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
