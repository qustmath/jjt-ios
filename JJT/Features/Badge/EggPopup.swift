import SwiftUI

// MARK: - 彩蛋总线（对齐安卓 EggBus / EggTrigger）

extension Notification.Name {
    static let jjtEggUnlocked = Notification.Name("jjt.eggUnlocked")
}

enum EggBus {
    static func emit(_ egg: EggUnlockResp) {
        NotificationCenter.default.post(name: .jjtEggUnlocked, object: egg)
    }
}

/// 彩蛋触发器：同一 key 只上报一次；失败静默并移除标记（下次可重试，对齐安卓 EggTrigger）
enum EggTrigger {
    private static var reported: Set<String> = []

    static func report(_ key: String) {
        guard !reported.contains(key) else { return }
        reported.insert(key)
        Task {
            do {
                if let egg = try await BadgeAPI.triggerEgg(key: key) {
                    await MainActor.run { EggBus.emit(egg) }
                }
            } catch {
                reported.remove(key)
            }
        }
    }
}

/// 根部挂载的全局彩蛋弹窗（对齐安卓 EggPopup 根部监听）
struct EggPopupHost: View {

    @State private var egg: EggUnlockResp?

    var body: some View {
        ZStack {
            if let egg {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .onTapGesture { self.egg = nil }
                VStack(spacing: 14) {
                    Text("隐藏彩蛋解锁")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Color(red: 0xB4/255, green: 0x8C/255, blue: 0xE0/255))
                    if let icon = egg.icon, icon.hasPrefix("http") {
                        WebImage(url: webImageURL(icon), contentMode: .fit) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 34))
                                .foregroundStyle(Noir.goldLight)
                        }
                        .frame(width: 72, height: 72)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(Noir.goldLight)
                            .frame(width: 72, height: 72)
                    }
                    Text(egg.name)
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                    Text("+\(egg.score) 成就分 · 🥕\(egg.reward)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Button { self.egg = nil } label: {
                        Text("太好了")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }
                .padding(.vertical, 24)
                .frame(width: 280)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: egg != nil)
        .onReceive(NotificationCenter.default.publisher(for: .jjtEggUnlocked)) { note in
            if let e = note.object as? EggUnlockResp {
                withAnimation { egg = e }
            }
        }
    }
}
