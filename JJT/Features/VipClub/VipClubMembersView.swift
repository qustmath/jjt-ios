import SwiftUI

/// 会员殿堂（蜜兔会会员列表，对齐安卓 VipClubMembersScreen）
/// 两列封面卡片流：封面 + 渐变蒙版 + 交友意向预览 + 授权标记
struct VipClubMembersView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var members: [VipClubMember] = []
    @State private var total: Int64 = 0
    @State private var isLoading = true
    @State private var detailUserId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                Text("在册成员 \(members.count)\(total > Int64(members.count) ? " / \(total)" : "") 位 · 申请许可后可查看完整资料")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if members.isEmpty {
                    Spacer()
                    Text("暂无成员")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(members) { member in
                                memberCard(member)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .onAppear { load() }
        .fullScreenCover(item: Binding(
            get: { detailUserId.map { T(id: $0) } },
            set: { detailUserId = $0?.id }
        )) { t in
            VipClubMemberDetailView(userId: t.id)
        }
        .jjtPageGestures()
    }

    private struct T: Identifiable { let id: Int64 }

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
                Text("会员殿堂")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("THE HALL")
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

    private func memberCard(_ m: VipClubMember) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 封面（无封面用头像，再无则金晕占位）
            if let cover = m.coverUrl, !cover.isEmpty {
                WebImage(url: webImageURL(cover), contentMode: .fill) { placeholder(m) }
            } else {
                placeholder(m)
            }
            // 渐变蒙版
            LinearGradient(stops: [
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.85), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // 信息
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(m.nickname ?? "用户\(m.userId)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    if m.hasViewPermission == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Noir.goldLight)
                    }
                }
                if let w = m.wantToMeet, !w.isEmpty {
                    Text("想遇到：\(w)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let sex = m.sex, sex > 0 {
                        Text(sex == 1 ? "男" : "女")
                            .font(.system(size: 8.5))
                            .foregroundStyle(sex == 1 ? Color(red: 0x64/255, green: 0xB5/255, blue: 0xF6/255) : Color(red: 0xFF/255, green: 0x7D/255, blue: 0x9C/255))
                    }
                    if let age = m.age, age > 0 {
                        Text("\(age)岁")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { detailUserId = m.userId }
    }

    private func placeholder(_ m: VipClubMember) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0x2A/255, green: 0x1A/255, blue: 0x0C/255), Color(red: 0x12/255, green: 0x0A/255, blue: 0x10/255)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            AppAvatar(url: m.avatar, size: 72)
        }
    }

    private func load() {
        Task {
            if let page = try? await VipClubAPI.members() {
                total = page.total ?? 0
                members = page.list ?? []
            }
            isLoading = false
        }
    }
}
