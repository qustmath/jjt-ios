import SwiftUI

/// 设置主页（对齐安卓 SettingsScreen：关于我们 / 崩溃日志 / 退出登录）
/// 崩溃日志 → 打开诊断面板（Bugly 上报测试 + 图片实测，替代安卓 CrashLogScreen）
struct SettingsView: View {

    var onBack: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAbout = false
    @State private var showDiagnostics = false
    @State private var showLogoutConfirm = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                VStack(spacing: 0) {
                    menuRow("关于我们", "info.circle") { showAbout = true }
                    menuRow("崩溃诊断", "ladybug", subtitle: "异常上报测试 / 图片加载实测", divider: false) { showDiagnostics = true }
                }
                .padding(.horizontal, 20)
                .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                Button { showLogoutConfirm = true } label: {
                    Text("退出登录")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .confirmationDialog("确定退出登录吗？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { appState.logout() }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet()
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
            Text("设置")
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

    private func menuRow(_ title: String, _ icon: String, subtitle: String? = nil,
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
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.3))
                        }
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
}
