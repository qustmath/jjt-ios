import SwiftUI

/// 邀请好友（对齐安卓 InviteScreen）
/// 邀请码（大字号）+ 注册链接二维码 + 复制链接 + 系统分享
struct InviteView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode: String?
    @State private var qr: UIImage?
    @State private var loadError: String?

    /// 注册链接：https://register.tuxiansheng.online/?c=邀请码（对齐安卓 buildRegisterUrl）
    private var registerUrl: String {
        let base = Config.h5RegisterURL.absoluteString
        return "\(base.hasSuffix("/") ? base : base + "/")?c=\(inviteCode ?? "")"
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let inviteCode {
                    content(code: inviteCode)
                } else if loadError != nil {
                    VStack(spacing: 20) {
                        Text(loadError ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                        primaryButton("重试") { load() }
                            .padding(.horizontal, 32)
                    }
                } else {
                    ProgressView().tint(Noir.gold)
                }
                Spacer()
            }
        }
        .onAppear { load() }
        .jjtPageGestures()
    }

    // MARK: - 内容

    private func content(code: String) -> some View {
        VStack(spacing: 20) {
            // 邀请码（大字号，便于口头报码）
            VStack(spacing: 6) {
                Text("我的邀请码")
                    .font(.system(size: 12))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
                Text(code)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
            }

            // 注册链接二维码（鎏金取景框卡片）
            GoldQrCard {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                    if let qr {
                        Image(uiImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 200, height: 200)
                            .padding(14)
                    } else {
                        ProgressView().tint(Noir.gold)
                            .frame(width: 200, height: 200)
                    }
                }
                .frame(width: 228, height: 228)
            }

            Text("扫码注册，开启荆棘兔之旅")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            primaryButton("复制注册链接") {
                UIPasteboard.general.string = registerUrl
                jjtShowToast("链接已复制")
            }

            ShareLink(item: "来荆棘兔认识新朋友～ \(registerUrl)") {
                Text("分享给好友")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text("邀请好友")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 数据

    private func load() {
        loadError = nil
        Task {
            do {
                let resp = try await UserAPI.getInviteCode()
                guard let code = resp.inviteCode, !code.isEmpty else {
                    loadError = "邀请码获取失败"
                    return
                }
                inviteCode = code
                let base = Config.h5RegisterURL.absoluteString
                let url = "\(base.hasSuffix("/") ? base : base + "/")?c=\(code)"
                qr = qrCodeImage(url)
            } catch {
                loadError = "网络异常"
            }
        }
    }
}
