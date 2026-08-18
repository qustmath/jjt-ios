import SwiftUI

/// 关于我们（对齐安卓 AboutScreen：品牌头 + 版本号 + 应用介绍 + 协议占位）
struct AboutView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// 版本 + build 号（如 1.0.0 (41)）：TestFlight 各包营销版本号相同，
    /// 只有 build 号能区分——反馈问题前以此页为准确认实际安装的包
    private var versionName: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 0) {
                        brandHeader
                        aboutSection
                        agreementSection
                    }
                }
            }
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
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text("关于我们")
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

    // MARK: - 品牌头部

    private var brandHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0x3A/255, green: 0x0A/255, blue: 0x16/255), Color(red: 0x12/255, green: 0x06/255, blue: 0x0A/255)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(Noir.gold.opacity(0.6), lineWidth: 1.5))
                Text("棘")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
            }
            Text("荆棘兔")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .tracking(6)
                .foregroundStyle(Noir.ivory)
                .padding(.top, 16)
            Text("NOIR SOCIAL CLUB")
                .font(.system(size: 10, design: .serif))
                .italic()
                .tracking(3)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 6)
            Text("V \(versionName)")
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(Noir.goldText)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - 应用介绍

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("关于荆棘兔")
            Text("荆棘兔是一款面向年轻潮流人群的社交交友平台，致力于打造真实、有趣、安全的社交空间。" +
                 "在这里，你可以通过广场分享生活点滴，发布图文笔记记录美好瞬间；" +
                 "可以与志趣相投的朋友畅聊互动，建立真诚的社交关系；" +
                 "可以参与属性测试探索个性、加入群聊和组局拓展圈子。" +
                 "我们严格保护用户隐私，倡导文明交流、遵纪守法。请勿发布违法违规内容，" +
                 "共同维护清朗的网络环境。我们将竭诚为您提供优质的服务与体验。")
                .font(.system(size: 13))
                .lineSpacing(9)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 协议与政策（对齐安卓，占位待 H5）

    private var agreementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("协议与政策")
            VStack(spacing: 0) {
                agreementRow("服务协议")
                agreementRow("隐私政策", divider: false)
            }
            .padding(.horizontal, 20)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 32)
    }

    private func agreementRow(_ title: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17))
                    .foregroundStyle(Noir.gold.opacity(0.7))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.vertical, 16)
            if divider {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Rectangle()
                .fill(Noir.goldLine)
                .frame(width: 40, height: 1)
        }
    }
}
