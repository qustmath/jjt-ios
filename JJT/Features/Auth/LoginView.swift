import SwiftUI

/// 登录页：密码 / 短信验证码 两种方式（Noir 黑金风）
struct LoginView: View {

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = AuthViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Noir.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    modeSwitcher
                        .padding(.top, 28)
                    form
                        .padding(.top, 24)
                    Spacer()
                    registerLink
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .jjtKeyboardDismiss()
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 10) {
            Text("荆棘兔")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
            Text("JING JI TU")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .tracking(6)
                .foregroundStyle(Noir.textTertiary)
        }
        .padding(.top, 72)
    }

    // MARK: - 方式切换

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeTab("密码登录", active: vm.mode == .password) { vm.mode = .password }
            modeTab("验证码登录", active: vm.mode == .sms) { vm.mode = .sms }
        }
        .padding(4)
        .background(Noir.card)
        .clipShape(Capsule())
    }

    private func modeTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Noir.gold : Noir.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? Color.white.opacity(0.07) : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 表单

    private var form: some View {
        VStack(spacing: 14) {
            TextField("手机号", text: $vm.mobile)
                .keyboardType(.numberPad)
                .noirField()

            if vm.mode == .password {
                SecureField("密码", text: $vm.password)
                    .noirField()
            } else {
                HStack(spacing: 10) {
                    TextField("验证码", text: $vm.smsCode)
                        .keyboardType(.numberPad)
                        .noirField()
                    Button(vm.countdown > 0 ? "\(vm.countdown)s" : "获取验证码") {
                        Task { await vm.sendCode() }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(vm.countdown > 0 ? Noir.textTertiary : Noir.gold)
                    .frame(width: 96)
                }
            }

            if let msg = vm.errorMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.crimson)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    if let resp = await vm.login() {
                        appState.didLogin(resp)
                    }
                }
            } label: {
                if vm.isLoading {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("登 录")
                }
            }
            .buttonStyle(NoirPrimaryButtonStyle(enabled: vm.canSubmit && !vm.isLoading))
            .disabled(!vm.canSubmit || vm.isLoading)
            .padding(.top, 8)
        }
    }

    // MARK: - 注册入口（H5 邀请注册页）

    private var registerLink: some View {
        HStack(spacing: 4) {
            Text("还没有账号？")
                .foregroundStyle(Noir.textTertiary)
            Button("邀请码注册") { openURL(Config.h5RegisterURL) }
                .foregroundStyle(Noir.gold)
        }
        .font(.system(size: 13))
    }
}

#Preview {
    LoginView().environmentObject(AppState())
}
