import SwiftUI

// MARK: - 运营弹窗（对齐安卓 PopupApi / PopupDialog / StartupPopup）
// 启动后拉 position=1 弹窗列表，按频次（1每次 2每日 3仅一次）过滤后弹最高优先级；
// 图片可点（linkTarget DeepLink 跳转），右上角关闭

struct PopupInfo: Decodable, Identifiable {
    let id: Int64
    let position: Int?
    let imageUrl: String?
    let linkTarget: String?
    let title: String?
    let priority: Int?
    let freqType: Int?
    let sortOrder: Int?
}

enum PopupAPI {
    static func list(position: Int) async throws -> [PopupInfo] {
        try await APIClient.shared.get("app-api/system/popup/list", query: ["position": String(position)])
    }
}

/// 弹窗频次控制（UserDefaults 本地记录，对齐安卓 PopupFreqManager）
enum PopupFreqManager {

    static func shouldShow(popupId: Int64, freqType: Int?) -> Bool {
        let d = UserDefaults.standard
        switch freqType {
        case 2: // 每日一次
            let today = Self.today()
            return d.string(forKey: "popup_\(popupId)_date") != today
        case 3: // 仅一次
            return !d.bool(forKey: "popup_\(popupId)_shown")
        default: // 1=每次启动，或未知值默认弹
            return true
        }
    }

    static func markShown(popupId: Int64, freqType: Int?) {
        let d = UserDefaults.standard
        switch freqType {
        case 2: d.set(Self.today(), forKey: "popup_\(popupId)_date")
        case 3: d.set(true, forKey: "popup_\(popupId)_shown")
        default: break
        }
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// 弹窗跳转事件（MainTabView 统一处理 DeepLink）
extension Notification.Name {
    static let jjtDeepLink = Notification.Name("jjt.deepLink")
}

/// 启动弹窗宿主：挂在 MainTabView，登录后拉取并展示
struct StartupPopupHost: View {

    @State private var popup: PopupInfo?

    var body: some View {
        ZStack {
            if let popup, let imageUrl = popup.imageUrl, !imageUrl.isEmpty {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .onTapGesture { close() }
                ZStack(alignment: .topTrailing) {
                    WebImage(url: webImageURL(imageUrl), contentMode: .fit) {
                        ProgressView().tint(Noir.gold)
                            .frame(width: 200, height: 200)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { tapImage(popup) }
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                .frame(maxWidth: 320)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: popup != nil)
        .task { await load() }
    }

    private func load() async {
        guard let list = try? await PopupAPI.list(position: 1) else { return }
        // 频次过滤后按优先级取最高（priority 大者优先；其次 sortOrder 小者）
        popup = list
            .filter { PopupFreqManager.shouldShow(popupId: $0.id, freqType: $0.freqType) }
            .sorted { ($0.priority ?? 0, -($0.sortOrder ?? 0)) > ($1.priority ?? 0, -($1.sortOrder ?? 0)) }
            .first
    }

    private func close() {
        if let popup {
            PopupFreqManager.markShown(popupId: popup.id, freqType: popup.freqType)
        }
        popup = nil
    }

    private func tapImage(_ p: PopupInfo) {
        guard let target = p.linkTarget, !target.isEmpty,
              let data = target.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        close()
        NotificationCenter.default.post(name: .jjtDeepLink, object: obj)
    }
}
