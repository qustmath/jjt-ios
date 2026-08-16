import SwiftUI

extension Notification.Name {
    /// 切换主 Tab（object 为 tag Int：0 首页 1 广场 2 密语 3 我的），对齐安卓 navigateToTab
    static let jjtSwitchTab = Notification.Name("jjtSwitchTab")
}

/// 主界面：首页 / 广场 / 密语 / 我的（对齐安卓四个主 Tab）
struct MainTabView: View {

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            SquareView()
                .tabItem { Label("广场", systemImage: "square.grid.2x2") }
                .tag(1)
            PlaceholderPage(title: "密语", en: "MESSAGES", icon: "bubble.left.and.bubble.right")
                .tabItem { Label("密语", systemImage: "bubble.left.and.bubble.right") }
                .tag(2)
            MeView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(3)
        }
        .tint(Noir.gold)
        .onReceive(NotificationCenter.default.publisher(for: .jjtSwitchTab)) { note in
            if let tag = note.object as? Int {
                withAnimation { selection = tag }
            }
        }
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
