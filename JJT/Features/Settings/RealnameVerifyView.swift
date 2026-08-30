import SwiftUI

/// 实名认证（对齐安卓 VerificationScreen）
/// 已认证：脱敏信息展示；未认证：姓名 + 身份证号表单 → realname-verify
struct RealnameVerifyView: View {

    var onBack: (() -> Void)? = nil
    /// 认证成功回调（组局报名/发起阻断点用，成功后自动关闭）
    var onVerified: (() -> Void)? = nil

    @StateObject private var vm = RealnameVerifyViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if vm.loading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.realnameStatus == 1 {
                    verifiedState
                } else {
                    formState
                }
            }
        }
        .jjtKeyboardDismiss()
        .onAppear { vm.loadStatus() }
        .alert(vm.resultMsg ?? "", isPresented: Binding(
            get: { vm.resultMsg != nil },
            set: { if !$0 { vm.resultMsg = nil } }
        )) {
            Button("确定") {
                let passed = vm.realnameStatus == 1
                vm.resultMsg = nil
                if passed {
                    if let onVerified { onVerified() }
                    else if let onBack { onBack() }
                    else { dismiss() }
                }
            }
        }
    }

    // MARK: - 顶栏

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
            Text("实名认证")
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

    // MARK: - 已认证

    private var verifiedState: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x1E/255, green: 0x3A/255, blue: 0x18/255), Color(red: 0x0A/255, green: 0x14/255, blue: 0x08/255)],
                                         center: .center, startRadius: 0, endRadius: 55))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255).opacity(0.5), lineWidth: 1))
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255))
            }
            .padding(.top, 32)
            Text("已通过实名认证")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255))
                .padding(.top, 16)

            VStack(spacing: 0) {
                infoRow("姓名", vm.maskedName ?? "-")
                infoRow("身份证", vm.maskedIdCard ?? "-", divider: false)
            }
            .padding(.horizontal, 20)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Text("敏感信息已脱敏展示 · 后台加密存储")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 16)
            Spacer()
        }
    }

    private func infoRow(_ label: String, _ value: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(value)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Noir.ivory)
            }
            .padding(.vertical, 16)
            if divider {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    // MARK: - 未认证表单

    private var formState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("请填写真实身份信息")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                Text("建群、转让群主、收益提现等关键动作需完成实名")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))

                TextField("姓名", text: $vm.realName)
                    .noirField()
                    .padding(.top, 10)
                TextField("身份证号", text: $vm.idCard)
                    .keyboardType(.asciiCapable)
                    .noirField()
                    .onChange(of: vm.idCard) { _, v in
                        vm.idCard = String(v.filter { $0.isNumber || $0 == "X" || $0 == "x" }.prefix(18)).uppercased()
                    }

                Button { vm.submit() } label: {
                    Text(vm.submitting ? "提交中…" : "提交认证")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            vm.canSubmit
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canSubmit || vm.submitting)
                .padding(.top, 14)

                Text("信息仅用于实名核验（阿里云二要素），加密存储不会外泄")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }
}

// MARK: - ViewModel（对齐安卓 VerificationViewModel）

@MainActor
final class RealnameVerifyViewModel: ObservableObject {

    @Published var loading = true
    @Published var realnameStatus: Int?
    @Published var maskedName: String?
    @Published var maskedIdCard: String?
    @Published var realName = ""
    @Published var idCard = ""
    @Published var submitting = false
    @Published var resultMsg: String?

    var canSubmit: Bool {
        !realName.trimmingCharacters(in: .whitespaces).isEmpty && idCard.count >= 15
    }

    func loadStatus() {
        Task {
            if let user = try? await UserAPI.getUserInfo() {
                realnameStatus = user.realnameStatus ?? 0
                maskedName = user.realName
                maskedIdCard = user.idCardMasked
            } else {
                realnameStatus = 0
            }
            loading = false
        }
    }

    func submit() {
        guard canSubmit, !submitting else { return }
        submitting = true
        Task {
            do {
                let r = try await VerificationAPI.verify(realName: realName, idCard: idCard)
                submitting = false
                if r.passed {
                    realnameStatus = 1
                    loadStatus()
                    resultMsg = "实名认证通过"
                } else {
                    resultMsg = r.message ?? "认证失败"
                }
            } catch {
                submitting = false
                resultMsg = error.localizedDescription
            }
        }
    }
}
