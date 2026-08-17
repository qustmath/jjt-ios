import SwiftUI

/// 礼物墙 — 网格展示（对齐安卓 GiftWallScreen）
/// userId 为 nil = 我的礼物墙
struct GiftWallView: View {

    var userId: Int64? = nil
    var onBack: (() -> Unit)? = nil

    @State private var items: [GiftWallItem] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if items.isEmpty {
                    Spacer()
                    Text("暂无礼物")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(items) { item in
                                gridItem(item)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .onAppear { load() }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
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
                    Text("礼物墙")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("GIFT WALL")
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
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    private func gridItem(_ item: GiftWallItem) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(RadialGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                                         center: .center, startRadius: 0, endRadius: 45))
                GiftIconView(
                    icon: giftDisplayIcon(item.icon, item.animationUrl),
                    size: 56,
                    scale: CGFloat(item.iconScale ?? 100) / 100
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
            Text(item.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Text("×\(item.totalCount ?? item.quantity ?? 0)")
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(Noir.goldText)
        }
    }

    private func load() {
        Task {
            if let userId {
                items = (try? await GiftAPI.userGiftWall(userId: userId)) ?? []
            } else {
                items = (try? await GiftAPI.myGiftWall()) ?? []
            }
            isLoading = false
        }
    }
}
