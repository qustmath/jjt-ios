import SwiftUI
import UIKit

/// 帖子分享面板（对齐安卓 PostShareSheet）：
/// 发送给 App 内好友（IM 自定义 post_share 卡片消息 + 好友选择器）/ 系统分享（纯文本）。
/// 每次成功分享后上报分享计数（取消/失败不上报）。
struct PostShareSheet: View {

    let post: PostInfo
    let onClose: () -> Void

    @State private var showFriendPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("分享帖子")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Noir.ivory)
                .padding(.bottom, 12)

            optionRow(label: "发送给好友", desc: "以卡片形式发送到私聊") {
                showFriendPicker = true
            }
            optionRow(label: "系统分享", desc: "分享标题与正文文本") {
                let text = [post.title, post.content].compactMap { $0 }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                // 系统分享面板回调成功才算一次分享（取消不上报）
                presentSystemShare(text: text) { completed in
                    if completed { Self.reportShare(post.id) }
                    onClose()
                }
            }
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .sheet(isPresented: $showFriendPicker) {
            FriendPickerSheet(post: post) {
                showFriendPicker = false
                onClose()
            }
            .presentationDetents([.medium])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        }
    }

    private func optionRow(label: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 发送帖子卡片（IM 自定义消息，聊天页渲染为可点击卡片）——供好友选择器调用
    static func sendToFriend(post: PostInfo, friend: FollowUser) async throws {
        let cover = post.images?.first ?? post.videoCover ?? ""
        let payload: [String: Any] = [
            "type": "post_share",
            "postId": post.id,
            "title": post.title ?? "",
            "cover": cover,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await ImManager.shared.sendCustom(String(decoding: data, as: UTF8.self), to: "\(friend.userId)", isGroup: false)
        // 分享成功回调：上报分享计数（取消/失败不走到这里，不上报）
        reportShare(post.id)
    }

    /// 分享上报（fire-and-forget：每次成功分享计一次；失败不影响分享流程）
    static func reportShare(_ postId: Int64) {
        Task { _ = try? await SocialAPI.share(postId: postId) }
    }

    private func presentSystemShare(text: String, completion: @escaping (Bool) -> Void) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            completion(false)
            return
        }
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
}

/// 好友选择器：互关好友列表，点选即发送帖子卡片（对齐安卓 FriendPickerSheet）
private struct FriendPickerSheet: View {

    let post: PostInfo
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var friends: [FollowUser]?
    @State private var sendingTo: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("发送给好友")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Noir.ivory)
                .padding(.bottom, 12)

            if let friends {
                if friends.isEmpty {
                    Text("暂无互关好友")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(friends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
            } else {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
            }
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .task {
            friends = (try? await FollowAPI.friends().list) ?? []
        }
    }

    private func friendRow(_ friend: FollowUser) -> some View {
        Button {
            guard sendingTo == nil else { return }
            sendingTo = friend.userId
            Task {
                do {
                    try await PostShareSheet.sendToFriend(post: post, friend: friend)
                    sendingTo = nil
                    jjtShowToast("已分享给 \(friend.nickname ?? "好友")")
                    onSent()
                    dismiss()
                } catch {
                    sendingTo = nil
                    jjtShowToast("分享失败，请稍后再试")
                }
            }
        } label: {
            HStack(spacing: 12) {
                AppAvatar(url: friend.avatar, size: 38,
                          frameURL: friend.avatarFrame, frameScale: CGFloat(friend.avatarFrameScale ?? 1.2))
                    .frame(width: 42, height: 42)
                Text(friend.nickname ?? "用户\(friend.userId)")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if sendingTo == friend.userId {
                    ProgressView().tint(Noir.crimson).scaleEffect(0.8)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sendingTo != nil)
    }
}
