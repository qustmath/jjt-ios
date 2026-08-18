import SwiftUI

/// 蜜兔会成员详情（对齐安卓 VipClubMemberDetailScreen）
/// 整页背景大图（background → clubAvatar → 相册首张，完整模式才取后两者）
/// 完整模式 = 已授权或本人；未授权显示「申请查看完整资料」
struct VipClubMemberDetailView: View {

    let userId: Int64
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var detail: VipClubMemberDetail?
    @State private var isLoading = true
    @State private var viewRequested = false
    @State private var showMyProfile = false
    @State private var showRequests = false
    @State private var previewUrl: String?

    private var fullMode: Bool {
        guard let d = detail else { return false }
        return d.hasViewPermission == true || d.isOwner == true
    }

    private var bgUrl: String? {
        guard let d = detail else { return nil }
        if let bg = d.background, !bg.isEmpty { return bg }
        if fullMode, let ca = d.clubAvatar, !ca.isEmpty { return ca }
        if fullMode, let first = d.photoAlbum?.first, !first.isEmpty { return first }
        return nil
    }

    var body: some View {
        ZStack {
            Color(red: 0x07/255, green: 0x07/255, blue: 0x08/255).ignoresSafeArea()
            // 整页背景
            if let bgUrl {
                WebImage(url: webImageURL(bgUrl), contentMode: .fill) { Color.clear }
                    .ignoresSafeArea()
            } else {
                Circle()
                    .fill(RadialGradient(colors: [Noir.gold.opacity(0.12), .clear],
                                         center: .center, startRadius: 0, endRadius: 170))
                    .frame(width: 340, height: 340)
                    .offset(y: -60)
            }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.5), location: 0),
                .init(color: .black.opacity(0.55), location: 0.35),
                .init(color: Color(red: 0x07/255, green: 0x07/255, blue: 0x08/255).opacity(0.95), location: 0.7),
                .init(color: Color(red: 0x07/255, green: 0x07/255, blue: 0x08/255), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Noir.gold)
            } else if let d = detail {
                ScrollView {
                    VStack(spacing: 0) {
                        topBar(d)
                        profileBlock(d)
                        if fullMode {
                            albumSection(d)
                            infoSection(d)
                        } else {
                            lockedSection(d)
                        }
                    }
                    .padding(.bottom, 40)
                }
            } else {
                Text("加载失败")
                    .foregroundStyle(.white.opacity(0.5))
            }

            // 写真大图预览
            if let previewUrl {
                ImagePreviewViewer(images: [previewUrl], initialIndex: 0)
                    .onTapGesture { self.previewUrl = nil }
            }
        }
        .onAppear { load() }
        .fullScreenCover(isPresented: $showMyProfile, onDismiss: { load() }) {
            VipClubMyProfileView()
        }
        .fullScreenCover(isPresented: $showRequests) {
            VipClubViewRequestsView()
        }
    }

    // MARK: - 顶栏

    private func topBar(_ d: VipClubMemberDetail) -> some View {
        HStack {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text("LAPIN DORÉ")
                .font(.system(size: 10, design: .serif))
                .italic()
                .tracking(3.5)
                .foregroundStyle(Noir.goldLight.opacity(0.7))
            Spacer()
            if d.isOwner == true {
                HStack(spacing: 8) {
                    Button { showRequests = true } label: {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 13))
                            .foregroundStyle(Noir.goldLight)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { showMyProfile = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(Noir.goldLight)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 资料块

    private func profileBlock(_ d: VipClubMemberDetail) -> some View {
        VStack(spacing: 10) {
            AppAvatar(url: d.avatar, size: 88)
                .frame(width: 88, height: 88)
                .overlay(Circle().stroke(Noir.gold.opacity(0.5), lineWidth: 1.5))
            Text(d.nickname ?? "用户\(d.userId)")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            HStack(spacing: 8) {
                if let sex = d.sex, sex > 0 {
                    tagPill(sex == 1 ? "男" : "女",
                            tint: sex == 1 ? Color(red: 0x64/255, green: 0xB5/255, blue: 0xF6/255) : Color(red: 0xFF/255, green: 0x7D/255, blue: 0x9C/255))
                }
                if let age = d.age, age > 0 {
                    tagPill("\(age) 岁", tint: Noir.goldLight)
                }
                Text("蜜兔会在册")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private func tagPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
    }

    // MARK: - 相册

    private func albumSection(_ d: VipClubMemberDetail) -> some View {
        Group {
            if let album = d.photoAlbum, !album.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("写 真")
                        .font(.system(size: 10))
                        .tracking(4)
                        .foregroundStyle(Noir.goldLight.opacity(0.7))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(album, id: \.self) { url in
                                WebImage(url: webImageURL(url), contentMode: .fill) {
                                    Color.white.opacity(0.05)
                                }
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
                                .onTapGesture { previewUrl = url }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
    }

    // MARK: - 资料字段

    private func infoSection(_ d: VipClubMemberDetail) -> some View {
        VStack(spacing: 0) {
            infoRow("想遇到的人", d.wantToMeet)
            infoRow("交友目的", d.purpose)
            infoRow("个人简介", d.bio, divider: false)
        }
        .padding(.horizontal, 20)
        .background(LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private func infoRow(_ label: String, _ value: String?, divider: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Noir.goldLight.opacity(0.6))
            Text(value?.isEmpty == false ? value! : "未填写")
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(value?.isEmpty == false ? Noir.ivory : .white.opacity(0.25))
            if divider {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    // MARK: - 未授权

    private func lockedSection(_ d: VipClubMemberDetail) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30))
                .foregroundStyle(Noir.gold.opacity(0.5))
            Text("完整资料仅对获许可的会员开放")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            if d.requesterIsMember == true {
                Button {
                    Task {
                        if (try? await VipClubAPI.requestView(targetUserId: userId)) != nil {
                            viewRequested = true
                        }
                    }
                } label: {
                    Text(viewRequested ? "已申请 · 等待批准" : "申请查看完整资料")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewRequested ? .white.opacity(0.35) : Noir.goldLight)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(Color(red: 0x14/255, green: 0x10/255, blue: 0x06/255).opacity(0.6))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Noir.gold.opacity(viewRequested ? 0.2 : 0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewRequested)
            } else {
                Text("仅蜜兔会会员可申请查看")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func load() {
        Task {
            detail = try? await VipClubAPI.memberDetail(userId: userId)
            isLoading = false
        }
    }
}
