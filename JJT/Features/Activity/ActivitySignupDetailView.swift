import SwiftUI

// MARK: - 报名详情页（对齐安卓 ActivitySignupDetailScreen v1.4）
// 全屏出血大图多页横滑 + 底部信息区（头像带框进主页 + 昵称/段位 + 造型名）+ 喜欢与昵称同行右侧。
// 可见性同墙：他人待审/被拒接口按不存在报错（服务端拦截，App 不做隐藏逻辑）。

@MainActor
final class ActivitySignupDetailModel: ObservableObject {
    @Published var item: WallItem?
    @Published var loading = true
    @Published var theme = ActivityTheme()
    /// 本地点赞乐观态（进入时以服务端实时数据为准）
    @Published var likedOverride: (Bool, Int64)?

    func load(signupId: Int64, activityId: Int64) async {
        do {
            item = try await ActivityAPI.signupGet(signupId: signupId)
            likedOverride = nil
        } catch {
            jjtShowToast(error.localizedDescription)
        }
        loading = false
        // 主题令牌：按所属活动详情解析（后台富化，失败静默回退默认暗夜金）
        if activityId > 0, let activity = try? await ActivityAPI.get(id: activityId) {
            theme = parseActivityTheme(activity.theme)
        }
    }

    /// 点赞：乐观更新 + 服务端幂等 + 失败回滚
    func like() async {
        guard let item else { return }
        let (liked, likes) = display()
        if liked { return }
        likedOverride = (true, likes + 1)
        do {
            try await ActivityAPI.signupLike(signupId: item.id)
        } catch {
            likedOverride = nil
            jjtShowToast(error.localizedDescription)
        }
    }

    func display() -> (Bool, Int64) {
        if let likedOverride { return likedOverride }
        return (item?.liked == true, item?.likes ?? 0)
    }
}

struct ActivitySignupDetailView: View {
    let signupId: Int64
    let activityId: Int64

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ActivitySignupDetailModel()
    @State private var pageIndex = 0
    @State private var viewerIndex = 0
    @State private var showViewer = false
    @State private var profileTarget: WallDetailTarget?

    private var photos: [String] {
        guard let item = model.item else { return [] }
        let list = (item.imgs?.isEmpty == false ? item.imgs : item.img.map { [$0] }) ?? []
        return list.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.loading {
                ProgressView().tint(model.theme.accent)
            } else if let item = model.item, !photos.isEmpty {
                // 全屏出血大图（Crop），每页点击进预览放大细看
                TabView(selection: $pageIndex) {
                    ForEach(photos.indices, id: \.self) { i in
                        WebImage(url: webImageURL(photos[i]), contentMode: .fill) { Color.black }
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewerIndex = i
                                showViewer = true
                            }
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // 顶部/底部压暗渐变
                VStack {
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 300)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 顶部中央：穿搭墙标题小字 + 多图页码（单图不显；放标题下方，避让右下角点赞）
                VStack(spacing: 8) {
                    Text(model.theme.resolvedWallTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 22)
                    if photos.count > 1 {
                        Text("\(pageIndex + 1)/\(photos.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }

                // 底部信息区：头像（带框，可点进主页）+ 昵称/段位 + 造型名；「喜欢」与昵称同一行高度、靠右
                VStack {
                    Spacer()
                    HStack(alignment: .top, spacing: 0) {
                        HStack(spacing: 10) {
                            AppAvatar(
                                url: item.avatar,
                                size: 38,
                                frameURL: item.avatarFrame,
                                frameScale: CGFloat(item.avatarFrameScale ?? 1.2)
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.nickname ?? "")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    ActivityVipChip(
                                        vipLevel: item.vipLevel,
                                        vipLevelColor: item.vipLevelColor,
                                        levelInTier: item.levelInTier,
                                        fontSize: 9
                                    )
                                }
                                if let look = item.look, !look.isEmpty {
                                    Text("「\(look)」")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let uid = item.userId, uid > 0 { profileTarget = WallDetailTarget(id: uid) }
                        }
                        Spacer(minLength: 8)
                        // 喜欢：与昵称同行高度、靠右
                        Button {
                            Task { await model.like() }
                        } label: {
                            let liked = model.display()
                            VStack(spacing: 3) {
                                Image(systemName: liked.0 ? "heart.fill" : "heart")
                                    .font(.system(size: 27))
                                    .foregroundStyle(liked.0 ? model.theme.accent : .white)
                                Text(liked.1 > 999 ? String(format: "%.1fk", Double(liked.1) / 1000) : "\(liked.1)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.bottom, 26)
                }
            }

            // 左上返回钮（34 黑圆，全项目同款）
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                    .padding(.top, 14)
                    Spacer()
                }
                Spacer()
            }

            // 右上角：本人条目角标（我的报名 / 审核中）
            if model.item?.mine == true {
                VStack {
                    HStack {
                        Spacer()
                        DetailBadgeView(
                            text: model.item?.pending == true ? "审核中" : "我的报名",
                            color: model.item?.pending == true ? Noir.crimsonHot : model.theme.accent
                        )
                        .padding(.trailing, 14)
                        .padding(.top, 18)
                    }
                    Spacer()
                }
            }
        }
        .task { await model.load(signupId: signupId, activityId: activityId) }
        .fullScreenCover(isPresented: $showViewer) {
            ImagePreviewViewer(images: photos, initialIndex: viewerIndex)
        }
        .fullScreenCover(item: $profileTarget) { target in
            UserProfileView(userId: target.id)
        }
        .jjtPageGestures()
    }
}

/// 沉浸式角标（我的报名 / 审核中）
private struct DetailBadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }
}
