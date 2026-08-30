import SwiftUI

/// 账号安全（对齐安卓 AccountSecurityScreen）
/// 主菜单：修改密码（短信 scene=3）/ 支付密码（复用 PayPasswordSettingsView）/ 修改手机号（两步：验旧 scene=2 → 绑新）
struct AccountSecurityView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = AccountSecurityViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showPayPassword = false
    @State private var passwordDraft = ""
    @State private var passwordVisible = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    if vm.flow == nil {
                        mainMenu
                    } else {
                        flowForm
                    }
                }
            }
        }
        .jjtKeyboardDismiss()
        .onAppear { vm.load() }
        .fullScreenCover(isPresented: $showPayPassword) {
            PayPasswordSettingsView()
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("知道了") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .alert(vm.successMsg ?? "", isPresented: Binding(
            get: { vm.successMsg != nil },
            set: { if !$0 { vm.dismissSuccess() } }
        )) {
            Button("确定") { vm.dismissSuccess() }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button {
                if vm.flow != nil { vm.flow = nil }
                else if let onBack { onBack() }
                else { dismiss() }
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
            Text("账号安全")
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

    // MARK: - 主菜单

    private var mainMenu: some View {
        VStack(spacing: 0) {
            menuRow("修改密码", "lock", subtitle: "用于修改登录密码") { vm.flow = .password }
            menuRow("支付密码", "checkmark.shield", subtitle: "提现、发红包、兔币消费前需验证") { showPayPassword = true }
            menuRow("修改手机号", "phone", subtitle: "当前手机号 \(maskPhone(vm.mobile))", divider: false) { vm.flow = .mobile }
        }
        .padding(.horizontal, 20)
        .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func menuRow(_ title: String, _ icon: String, subtitle: String,
                         divider: Bool = true, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(Noir.gold.opacity(0.7))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.white.opacity(0.85))
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.3))
                    }
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

    // MARK: - 修改表单

    @ViewBuilder
    private var flowForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vm.flow == .password ? "修改密码" : "修改手机号")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .padding(.top, 8)

            if vm.flow == .password {
                passwordForm
            } else if vm.mobileStep == 0 {
                mobileStep1
            } else {
                mobileStep2
            }

            Button { vm.flow = nil } label: {
                Text("取消")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    /// 修改密码：新密码 + 验证码（发至当前绑定手机，scene=3）
    private var passwordForm: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Group {
                    if passwordVisible {
                        TextField("新密码", text: $passwordDraft)
                    } else {
                        SecureField("新密码", text: $passwordDraft)
                    }
                }
                .noirField()
                Button(passwordVisible ? "隐藏" : "显示") { passwordVisible.toggle() }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 44)
            }
            codeRow(code: $vm.smsCode) { vm.sendSmsCode(mobile: vm.mobile) }
            primaryButton("确认修改", enabled: !vm.smsCode.isEmpty && !passwordDraft.isEmpty) {
                vm.submitPassword(passwordDraft)
            }
        }
    }

    /// 修改手机号第一步：验证旧手机（scene=2）
    private var mobileStep1: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("验证当前手机号")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Noir.ivory)
            Text("短信将发送至 \(maskPhone(vm.mobile))")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            codeRow(code: $vm.oldPhoneCode) { vm.sendSmsCode(mobile: vm.mobile) }
            primaryButton("下一步", enabled: !vm.oldPhoneCode.isEmpty) { vm.goMobileStep2() }
        }
    }

    /// 修改手机号第二步：新手机号 + 验证码（发至新手机，scene=2）
    private var mobileStep2: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置新手机号")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Noir.ivory)
            TextField("新手机号", text: $vm.newMobile)
                .keyboardType(.numberPad)
                .noirField()
                .onChange(of: vm.newMobile) { _, v in vm.newMobile = String(v.filter(\.isNumber).prefix(11)) }
            codeRow(code: $vm.smsCode) { vm.sendSmsCode(mobile: vm.newMobile) }
            primaryButton("确认修改", enabled: vm.newMobile.count == 11 && !vm.smsCode.isEmpty) {
                vm.submitMobile()
            }
        }
    }

    // MARK: - 通用件

    private func codeRow(code: Binding<String>, onSend: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            TextField("短信验证码", text: code)
                .keyboardType(.numberPad)
                .noirField()
            Button(vm.countdown > 0 ? "\(vm.countdown)s" : "获取验证码", action: onSend)
                .font(.system(size: 13))
                .foregroundStyle(vm.countdown > 0 ? Noir.textFaint : Noir.gold)
                .frame(width: 96)
                .disabled(vm.countdown > 0 || vm.smsSending)
        }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(vm.submitting ? "提交中…" : title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    enabled && !vm.submitting
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.white.opacity(0.08))
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || vm.submitting)
        .padding(.top, 10)
    }
}

// MARK: - ViewModel（对齐安卓 AccountSecurityViewModel）

@MainActor
final class AccountSecurityViewModel: ObservableObject {

    enum Flow { case password, mobile }

    @Published var mobile = ""
    @Published var flow: Flow?
    @Published var mobileStep = 0
    @Published var smsCode = ""
    @Published var oldPhoneCode = ""
    @Published var newMobile = ""
    @Published var smsSending = false
    @Published var countdown = 0
    @Published var submitting = false
    @Published var error: String?
    @Published var successMsg: String?

    private var countdownTask: Task<Void, Never>?

    func load() {
        Task {
            if let user = try? await UserAPI.getUserInfo() {
                mobile = user.mobile ?? ""
            }
        }
    }

    func sendSmsCode(mobile: String) {
        guard !mobile.isEmpty else { error = "请先输入手机号"; return }
        guard countdown == 0, !smsSending else { return }
        smsSending = true
        error = nil
        // scene: 修改密码=3，修改手机号=2（对齐安卓）
        let scene = flow == .password ? 3 : 2
        Task {
            do {
                _ = try await AccountSecurityAPI.sendSmsCode(mobile: mobile, scene: scene)
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

    func goMobileStep2() {
        guard !oldPhoneCode.isEmpty else { error = "请输入验证码"; return }
        mobileStep = 1
        smsCode = ""
        countdown = 0
    }

    func submitPassword(_ newPassword: String) {
        guard !smsCode.isEmpty else { error = "请输入验证码"; return }
        guard !newPassword.isEmpty else { error = "请输入新密码"; return }
        submit {
            _ = try await AccountSecurityAPI.updatePassword(password: newPassword, code: self.smsCode)
            return "密码修改成功"
        }
    }

    func submitMobile() {
        guard !smsCode.isEmpty else { error = "请输入验证码"; return }
        guard !newMobile.isEmpty else { error = "请输入新手机号"; return }
        submit {
            _ = try await AccountSecurityAPI.updateMobile(mobile: self.newMobile, code: self.smsCode, oldCode: self.oldPhoneCode)
            return "手机号修改成功"
        }
    }

    private func submit(_ work: @escaping () async throws -> String) {
        guard !submitting else { return }
        submitting = true
        error = nil
        Task {
            do {
                let msg = try await work()
                submitting = false
                successMsg = msg
            } catch {
                submitting = false
                self.error = error.localizedDescription
            }
        }
    }

    /// 成功弹窗关闭后回主菜单（手机号变更时刷新展示）
    func dismissSuccess() {
        successMsg = nil
        flow = nil
        mobileStep = 0
        smsCode = ""
        oldPhoneCode = ""
        newMobile = ""
        load()
    }
}
