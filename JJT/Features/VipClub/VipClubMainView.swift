import SwiftUI

/// 蜜兔会介绍页（对齐安卓 VipClubMainScreen）
/// 结构：顶栏 → 门头（皇冠+品牌名） → 品牌溯源 → 尊享权益 → 进入会员殿堂 → 申请入会
struct VipClubMainView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var info: VipClubInfo?
    @State private var status: String?
    @State private var isLoading = true
    @State private var showMembers = false
    @State private var showApply = false
    @State private var showMyProfile = false

    private var isMember: Bool { status == "member" }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if isLoading {
                Spacer()
                ProgressView().tint(Noir.gold)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        brandSection
                        privilegesSection
                        enterHallButton
                        applySection
                    }
                    .padding(.bottom, 48)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 背景三层（压暗渐变 > 底图 > 深色底）全部走 .background：
        // background 不参与内容尺寸协商，scaledToFill 底图从机制上
        // 不可能再把页面撑超屏宽（此前与内容同层 ZStack 协商是溢出根因）
        .background {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.35), location: 0.3),
                .init(color: Color(red: 0x05/255, green: 0x05/255, blue: 0x07/255).opacity(0.92), location: 0.72),
                .init(color: Color(red: 0x07/255, green: 0x07/255, blue: 0x08/255), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
        .background {
            Image("MituBg")
                .resizable()
                .scaledToFill()
                .opacity(0.9)
                .ignoresSafeArea()
        }
        .background {
            Color(red: 0x07/255, green: 0x07/255, blue: 0x08/255).ignoresSafeArea()
        }
        .onAppear { load() }
        .fullScreenCover(isPresented: $showMembers) {
            VipClubMembersView()
        }
        .fullScreenCover(isPresented: $showApply, onDismiss: { load() }) {
            VipClubApplyView()
        }
        .fullScreenCover(isPresented: $showMyProfile) {
            VipClubMyProfileView()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
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
            Text("PRIVATE CLUB")
                .font(.system(size: 10))
                .tracking(4)
                .foregroundStyle(Noir.goldLight.opacity(0.7))
            Spacer()
            if isMember {
                Button { showMyProfile = true } label: {
                    Image(systemName: "person")
                        .font(.system(size: 14))
                        .foregroundStyle(Noir.goldLight)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 门头

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Color(red: 0x12/255, green: 0x0C/255, blue: 0x04/255)],
                                         center: .center, startRadius: 0, endRadius: 80))
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(Noir.goldLight.opacity(0.8), lineWidth: 1.5))
                Image(systemName: "crown")
                    .font(.system(size: 38))
                    .foregroundStyle(Noir.goldLight)
            }
            Text("蜜兔会")
                .font(.system(size: 34, weight: .black, design: .serif))
                .tracking(15)
                .foregroundStyle(Noir.goldText)
                .padding(.leading, 15)
                .padding(.top, 28)
            Text("Lapin Doré · Circle of the Few")
                .font(.system(size: 13, design: .serif))
                .italic()
                .tracking(3.2)
                .foregroundStyle(Noir.goldLight.opacity(0.85))
                .padding(.top, 12)
            HStack(spacing: 12) {
                Rectangle().fill(Noir.goldLine).frame(width: 56, height: 1)
                Text("仅 邀 约 制")
                    .font(.system(size: 10))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.5))
                Rectangle().fill(Noir.goldLine).frame(width: 56, height: 1)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - 品牌溯源

    private var brandSection: some View {
        VStack(spacing: 0) {
            Text("品 牌 溯 源")
                .font(.system(size: 10))
                .tracking(4.5)
                .foregroundStyle(Noir.goldLight.opacity(0.7))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Noir.goldLine).frame(width: 80, height: 1)
                .padding(.top, 12)
            Text(info?.description?.isEmpty == false ? info!.description! : "蜜兔会，创立于荆棘兔品牌元年，是只向极少数人敞开的暗夜社交殿堂。")
                .font(.system(size: 14, design: .serif))
                .lineSpacing(15)
                .foregroundStyle(Noir.ivory.opacity(0.9))
                .padding(.top, 20)
            Text("这里没有喧闹的广场，只有烛光、黑胶与低声的共鸣；没有泛泛之交，只有经过时间筛选的同路人。会籍不设公开售卖，唯邀请与审核可入。")
                .font(.system(size: 13, design: .serif))
                .lineSpacing(14)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 12)
        }
        .padding(24)
        .background(LinearGradient(colors: [Color(red: 0x1C/255, green: 0x14/255, blue: 0x08/255).opacity(0.82), Color(red: 0x0A/255, green: 0x08/255, blue: 0x05/255).opacity(0.88)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    // MARK: - 尊享权益

    private var privilegesSection: some View {
        VStack(spacing: 14) {
            Text("尊 享 权 益")
                .font(.system(size: 10))
                .tracking(4.5)
                .foregroundStyle(Noir.goldLight.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            privilegeItem("checkmark.shield", "专属身份标识", "蜜兔会鎏金徽章 · 全站头像金框 · 昵称鎏金特效，于人海中一眼可辨的尊贵")
            privilegeItem("phone", "一对一私人管家", "专属客户经理 7×24 小时守候，从账号到活动策划，事无巨细")
            privilegeItem("calendar", "私享暗夜派对", "每月一场仅限会员的线下私宴：古堡、酒窖、私人美术馆，只为阁下而开")
            privilegeItem("diamond", "高定礼遇工坊", "定制专属 3D 礼物与头像框，可镌刻名字，独一无二，永不复刻")
            privilegeItem("sparkles", "优先与新权", "新功能优先体验 · 广场流量加权 · 线下展会贵宾通道与专属席位")
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    private func privilegeItem(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x4A/255, green: 0x35/255, blue: 0x12/255), Color(red: 0x1C/255, green: 0x12/255, blue: 0x06/255)],
                                         center: .center, startRadius: 0, endRadius: 40))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Noir.goldLight.opacity(0.5), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Noir.goldLight)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text(desc)
                    .font(.system(size: 11.5))
                    .lineSpacing(5.5)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Color(red: 0x1E/255, green: 0x16/255, blue: 0x0A/255).opacity(0.75), Color(red: 0x0C/255, green: 0x0A/255, blue: 0x06/255).opacity(0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.22), lineWidth: 1))
    }

    // MARK: - 进入会员殿堂

    private var enterHallButton: some View {
        Button { showMembers = true } label: {
            HStack(spacing: 8) {
                Text("进入会员殿堂")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(3.7)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(LinearGradient(colors: [Noir.goldLight, Noir.gold, Noir.goldDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    // MARK: - 底部申请

    private var applySection: some View {
        VStack(spacing: 20) {
            Text("会籍每年由创始团队复核，达标者将收到鎏金邀请函\n亦可由两位在册会员联名推荐")
                .font(.system(size: 11))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))

            switch status {
            case "member":
                Text("你已是蜜兔会在册会员")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Noir.goldText)
                    .frame(maxWidth: .infinity)
            case "applied":
                Text("入会资格审核中…")
                    .font(.system(size: 14))
                    .tracking(3.7)
                    .foregroundStyle(Noir.goldLight.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(red: 0x14/255, green: 0x10/255, blue: 0x06/255).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 28)
            default:
                Button { showApply = true } label: {
                    Text("申 请 入 会 资 格 审 核")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(3.7)
                        .foregroundStyle(Noir.goldLight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(red: 0x14/255, green: 0x10/255, blue: 0x06/255).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - 数据

    private func load() {
        Task {
            info = try? await VipClubAPI.info()
            status = (try? await VipClubAPI.myStatus())?.status
            isLoading = false
        }
    }
}
