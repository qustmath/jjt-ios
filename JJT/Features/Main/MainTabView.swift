import SwiftUI

extension Notification.Name {
    /// 切换主 Tab（object 为 tag Int：0 主页 1 广场 2 密语 3 我的），对齐安卓 navigateToTab
    static let jjtSwitchTab = Notification.Name("jjtSwitchTab")
    /// 全局轻提示（object 为提示文本 String）
    static let jjtToast = Notification.Name("jjtToast")
}

/// 任意页面弹轻提示（对齐安卓 Toast / ErrorBus）
func jjtShowToast(_ text: String) {
    NotificationCenter.default.post(name: .jjtToast, object: text)
}

/// 主界面：主页 / 广场 / [+] / 密语 / 我的（对齐安卓 Noir TabBar：
/// 深底 #0C0C10 + 顶部鎏金发丝线 + 中央酒红渐变发布圆钮）
struct MainTabView: View {

    @State private var selection = 0
    @State private var toast: String?
    @State private var showCreatePost = false

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                HomeView().tag(0)
                SquareView().tag(1)
                ConversationListView().tag(2)
                MeView().tag(3)
            }
            // 分页容器：左右滑跟手切换主 tab（对齐安卓 HorizontalPager）
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 底部留出导航条高度，内容不被遮挡
            .safeAreaInset(edge: .bottom, spacing: 0) { noirTabBar }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Noir.noir3.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 120)
                        .transition(.opacity)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jjtSwitchTab)) { note in
            if let tag = note.object as? Int {
                withAnimation { selection = tag }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jjtToast)) { note in
            if let text = note.object as? String {
                showToast(text)
            }
        }
        .fullScreenCover(isPresented: $showCreatePost) { CreatePostView() }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: - 自定义导航条

    private var noirTabBar: some View {
        VStack(spacing: 0) {
            // 顶部鎏金发丝线
            Rectangle()
                .fill(Noir.goldLine)
                .frame(height: 1)

            HStack(spacing: 0) {
                tabButton(index: 0, label: "主页", icon: "house")
                tabButton(index: 1, label: "广场", icon: "flame")
                publishButton
                tabButton(index: 2, label: "密语", icon: "message")
                tabButton(index: 3, label: "我的", icon: "person")
            }
            .frame(height: 64)
        }
        .background(
            Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(index: Int, label: String, icon: String) -> some View {
        let selected = selection == index
        let color: Color = selected ? Noir.crimsonHot : Color.white.opacity(0.35)
        return Button { selection = index } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                Text(label)
                    .font(.system(size: 10, weight: selected ? .medium : .regular))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 中央发布按钮（酒红渐变圆钮）
    private var publishButton: some View {
        Button { showCreatePost = true } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(stops: [
                        .init(color: Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), location: 0.0),
                        .init(color: Noir.crimsonDeep, location: 0.6),
                        .init(color: Noir.wine, location: 1.0),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 占位页（逐页迁移安卓功能时替换）
struct PlaceholderPage: View {
    let title: String
    let en: String
    let icon: String

    var body: some View {
        ZStack {
            Noir.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Noir.gold.opacity(0.6))
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                Text("\(en) · 建设中")
                    .font(.system(size: 11))
                    .tracking(3)
                    .foregroundStyle(Noir.textTertiary)
            }
        }
    }
}
