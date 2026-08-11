import SwiftUI

/// 我的：骨架版（用户 ID + 退出登录），后续迁移安卓 Me 页完整功能
struct MeView: View {

    @EnvironmentObject private var appState: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Noir.background.ignoresSafeArea()
                List {
                    Section {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Noir.gold.opacity(0.7))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("用户 \(TokenManager.shared.userId.map(String.init) ?? "-")")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Noir.textPrimary)
                                Text("个人主页功能建设中")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Noir.textTertiary)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section {
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Text("退出登录")
                                .foregroundStyle(Noir.crimson)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("我的")
            .confirmationDialog("确定退出登录吗？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { appState.logout() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

#Preview {
    MeView().environmentObject(AppState())
}
