import SwiftUI

/// 大厅设计 token（对齐安卓 LobbyParts.LobbyColors：与 Noir 主题同源——黑底 + 鎏金 + 酒红）。
/// 独立成枚举而不是复用 Noir：数值以 ui/v64 原型为准，大厅有自己的微调。
enum LobbyColors {
    static let bg = Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255)
    static let panel = Color(red: 0x10/255, green: 0x0D/255, blue: 0x12/255)
    /// 🟢 入座
    static let seated = Color(red: 0x7D/255, green: 0xE3/255, blue: 0xA0/255)
    /// 🟡 罚站
    static let standing = Color(red: 0xE2/255, green: 0xB4/255, blue: 0x5E/255)
    /// ⚪ 未入座（围观）
    static let idle = Color(red: 0x8B/255, green: 0x84/255, blue: 0x96/255)
    static let gold = Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255)
    static let goldLight = Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255)
    static let goldPale = Color(red: 0xF5/255, green: 0xE3/255, blue: 0xB8/255)
    static let ivory = Color(red: 0xEF/255, green: 0xE9/255, blue: 0xDD/255)
    static let crimson = Color(red: 0xE8/255, green: 0x30/255, blue: 0x4F/255)
    static let textBody = Color(red: 0xF2/255, green: 0xE9/255, blue: 0xD8/255)
    /// 渐变尾 / 按钮深金（大厅硬编码常用值）
    static let crimsonTail = Color(red: 0xA0/255, green: 0x10/255, blue: 0x2E/255)
    static let deepGold = Color(red: 0x8A/255, green: 0x6A/255, blue: 0x2F/255)
}

/// 桌位六态颜色（对齐安卓 TableStatus 的 color/glow）
enum LobbyTableStyle {
    static func color(_ status: LobbyTableStatus) -> Color {
        switch status {
        case .occupied: return Color(red: 0xE2/255, green: 0xB4/255, blue: 0x5E/255)
        case .reserved: return Color(red: 0x63/255, green: 0xB4/255, blue: 0xDD/255)
        case .free: return Color(red: 0xED/255, green: 0xE4/255, blue: 0xD0/255)
        case .grouping: return Color(red: 0xFF/255, green: 0x3D/255, blue: 0x62/255)
        case .sharing: return Color(red: 0xA0/255, green: 0x8B/255, blue: 0xFF/255)
        case .dnd: return Color(red: 0x7D/255, green: 0x72/255, blue: 0x88/255)
        }
    }

    static func glow(_ status: LobbyTableStatus) -> Color {
        color(status).opacity(0.5)
    }
}

/// 坐席胶囊（坐席态来自 LobbySeatSession，全 App 单一来源）：
/// `C3桌 · 入座中` / `罚站围观中` / 未入座 `围观中`。
/// onClick 供暗夜大厅把「入座中」胶囊变成回门店大厅的捷径；nil = 不可点。
struct SeatPill: View {
    let seat: LobbySeatState?
    var onClick: (() -> Void)? = nil

    var body: some View {
        let state = seat?.state
        let color: Color = {
            switch state {
            case "seated": return LobbyColors.seated
            case "stand": return LobbyColors.standing
            default: return LobbyColors.idle
            }
        }()
        let text: String = {
            switch state {
            case "seated": return "\(seat?.tableNo ?? "在座") · 入座中"
            case "stand": return "罚站围观中"
            default: return "围观中"
            }
        }()
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0x10/255, green: 0x0A/255, blue: 0x0C/255).opacity(0.5))
        .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { onClick?() }
    }
}

/// 加载失败态：与「暂无数据」空态区分——失败给原因 + 重试入口
struct LobbyLoadFailed: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("加载失败：\(message)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Text("重试")
                .font(.system(size: 11.5))
                .foregroundStyle(LobbyColors.goldLight)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
                .onTapGesture { onRetry() }
        }
        .padding(.horizontal, 24)
    }
}

/// 门店虚化背景（门店大厅用）
struct BlurredStoreBackdrop: View {
    let cover: String?
    /// 压暗强度（0~1，越大越暗）
    var dim: Double = 0.9

    var body: some View {
        ZStack {
            LobbyColors.bg.ignoresSafeArea()
            if let cover, !cover.isEmpty, let url = webImageURL(cover) {
                WebImage(url: url) { LobbyColors.bg }
                    .ignoresSafeArea()
                    .blur(radius: 30)
            }
            LinearGradient(
                colors: [Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.5), LobbyColors.bg.opacity(dim)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

/// 门店无封面时的兜底背景（暗夜渐变 + 酒红晕染，避免大块空黑）
struct StoreCoverFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0x1B/255, green: 0x0A/255, blue: 0x12/255),
                    Color(red: 0x12/255, green: 0x0A/255, blue: 0x0D/255),
                    Color(red: 0x0B/255, green: 0x09/255, blue: 0x10/255),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0xC4/255, green: 0x12/255, blue: 0x30/255).opacity(0.35), .clear],
                center: .center, startRadius: 0, endRadius: 450
            )
        }
    }
}

/// 表头/区块小标题（原型 font-serif-sc + 英文斜体副标）
struct LobbySectionTitle: View {
    let title: String
    var en: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LobbyColors.ivory)
            if let en {
                Text(en)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
            if let trailing {
                Spacer()
                Text(trailing)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

/// 大厅页头（返回 + 标题 + 英文副标 + 右侧动作）
struct LobbyHeader<Trailing: View>: View {
    let title: String
    var en: String? = nil
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.05))
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture { onBack() }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                if let en {
                    Text(en)
                        .font(.system(size: 9).italic())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer()
            HStack(spacing: 8) { trailing() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// 大厅圆形图标钮（页头右侧动作）
struct LobbyIconAction: View {
    let icon: String
    var tint: Color = LobbyColors.goldLight
    let onClick: () -> Void

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.05))
            .clipShape(Circle())
            .contentShape(Circle())
            .onTapGesture { onClick() }
    }
}

/// 居中 toast（原型的 say()）：调用方 2.2s 自动清除。放在页面 ZStack 顶层，
/// 保证盖在桌位抽屉等 sheet 之上（对齐安卓 LobbyToast 的窗口级承载）。
struct LobbyToastView: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.01) // 吞掉点击穿透
                .contentShape(Rectangle())
                .allowsHitTesting(true)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(LobbyColors.ivory)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LobbyColors.panel.opacity(0.92))
                .overlay(Capsule().stroke(LobbyColors.gold.opacity(0.4), lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}

/// 取「最新一条消息」展示片段
func lobbyLatestPreview(_ msg: String?) -> String? {
    guard let msg, !msg.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return String(msg.prefix(60))
}
