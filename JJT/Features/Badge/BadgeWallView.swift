import SwiftUI

/// 稀有度颜色（对齐安卓 rarityColor）
func rarityColor(_ rarity: String?) -> Color {
    switch rarity {
    case "RARE": return Color(red: 0x64/255, green: 0xB5/255, blue: 0xF6/255)
    case "EPIC": return Color(red: 0xBA/255, green: 0x68/255, blue: 0xC8/255)
    case "LEGENDARY": return Noir.goldLight
    default: return Color.white.opacity(0.5)
    }
}

/// 勋章墙（对齐安卓 BadgeWallScreen）：userId 为 nil = 我的勋章墙（含未获得+进度）
struct BadgeWallView: View {

    var userId: Int64? = nil
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var badges: [BadgeItem] = []
    @State private var isLoading = true
    @State private var error: String?

    private var ownedCount: Int { badges.filter(\.owned).count }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                statsHeader
                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if badges.isEmpty {
                    Spacer()
                    Text("暂无勋章")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                            ForEach(badges) { badge in
                                badgeCell(badge)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onAppear { load() }
        .alert("提示", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("确定") { error = nil }
        } message: {
            Text(error ?? "")
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
            VStack(spacing: 2) {
                Text(userId == nil ? "我的勋章" : "ta的勋章")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("BADGE WALL")
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statsHeader: some View {
        VStack(spacing: 4) {
            Text("\(ownedCount) / \(badges.count)")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
            Text("已获得勋章")
                .font(.system(size: 11))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(16)
    }

    private func badgeCell(_ badge: BadgeItem) -> some View {
        let tint = rarityColor(badge.rarity)
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Noir.noir2)
                    .frame(width: 76, height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(badge.owned ? tint.opacity(0.7) : Noir.hairlineGold,
                                lineWidth: badge.owned ? 1.5 : 1))
                if let icon = badge.icon, icon.hasPrefix("http") {
                    WebImage(url: webImageURL(icon), contentMode: .fit) {
                        Image(systemName: "medal")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.15))
                    }
                    .frame(width: 56, height: 56)
                    // 未获得：灰度（对齐安卓 GrayScaleMatrix）
                    .saturation(badge.owned ? 1 : 0)
                    .opacity(badge.owned ? 1 : 0.6)
                } else {
                    Image(systemName: "medal")
                        .font(.system(size: 28))
                        .foregroundStyle(badge.owned ? tint : .white.opacity(0.2))
                }
            }
            Text(badge.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(badge.owned ? Noir.ivory : .white.opacity(0.35))
                .lineLimit(1)
            if badge.owned {
                Text("已获得")
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
            } else if let p = badge.progress, let t = badge.threshold, t > 0 {
                Text("\(p)/\(t)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private func load() {
        isLoading = true
        Task {
            do {
                if let userId {
                    badges = try await BadgeAPI.userBadgeWall(userId: userId)
                } else {
                    badges = try await BadgeAPI.badgeWall()
                }
                isLoading = false
            } catch {
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }
}
