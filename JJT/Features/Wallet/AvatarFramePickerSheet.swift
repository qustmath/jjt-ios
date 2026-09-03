import SwiftUI

/// 头像框选择弹层（共享：会员中心 / 个人主页点头像更换，对齐安卓 AvatarFrameSheet）。
/// 选项 = 不佩戴 + 默认框 + 我持有的 + 段位专属（未解锁带锁）；当前佩戴项高亮。
struct AvatarFramePickerSheet: View {

    let options: AvatarFrameOptions?
    let saving: Bool
    let onSelect: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                HStack {
                    Text("更换头像框")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.ivory)
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                }

                // 摘下
                frameOption(url: "", name: "不佩戴", locked: false)

                if let defaults = options?.defaults, !defaults.isEmpty {
                    frameGroupTitle("默认")
                    ForEach(defaults) { f in
                        frameOption(url: f.url, name: f.name, locked: false)
                    }
                }
                if let owned = options?.owned, !owned.isEmpty {
                    frameGroupTitle("我持有的")
                    ForEach(owned) { f in
                        frameOption(url: f.url, name: f.name ?? "头像框", locked: false)
                    }
                }
                if let tiers = options?.tiers, !tiers.isEmpty {
                    frameGroupTitle("段位专属")
                    ForEach(tiers) { f in
                        frameOption(url: f.url, name: f.name, locked: f.unlocked != true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
    }

    // MARK: - 头像框预览（SVGA 动效 / 静态图）

    private func framePreview(url: String, size: CGFloat) -> some View {
        Group {
            if url.lowercased().hasSuffix(".svga") {
                SvgaView(url: url)
            } else if let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func frameGroupTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .tracking(3)
            .foregroundStyle(Noir.gold.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func frameOption(url: String, name: String, locked: Bool) -> some View {
        let isCurrent = (options?.current ?? "") == url
        let isSvga = url.lowercased().hasSuffix(".svga")
        return Button {
            guard !locked, !saving else { return }
            onSelect(url)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Noir.noir3).frame(width: 40, height: 40)
                    if !url.isEmpty {
                        framePreview(url: url, size: 46)
                    } else {
                        Image(systemName: "nosign")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .frame(width: 40, height: 40)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                if isSvga {
                    Text("动效")
                        .font(.system(size: 8))
                        .foregroundStyle(Noir.crimsonHot)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(Capsule().stroke(Noir.hairlineRed, lineWidth: 1))
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                } else if isCurrent {
                    Text("佩戴中")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.goldLight)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                isCurrent ? Noir.gold.opacity(0.6) : Noir.hairlineGold, lineWidth: 1))
            .opacity(locked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }
}
