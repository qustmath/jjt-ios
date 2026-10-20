import AVKit
import SwiftUI

/// 店长视频抽屉（v75 2 列网格）：店长在管理台上传的门店视频，仅展示最近 7 天
/// （窗口过滤在 StoreLobbyViewModel）。点击进全屏播放。
struct LobbyVideoSheet: View {

    let videos: [LobbyVideo]

    @State private var playing: LobbyVideo?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                HStack(spacing: 8) {
                    Text("店长 LIVE")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(LobbyColors.ivory)
                    Text("STORE VIDEOS")
                        .font(.system(size: 9).italic())
                        .kerning(2.2)
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                    HStack(spacing: 3) {
                        Circle().fill(LobbyColors.crimson).frame(width: 5, height: 5)
                        Text("\(videos.count) 场")
                            .font(.lobbyNumber(9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                if videos.isEmpty {
                    Text("最近 7 天暂无店长视频")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .background(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 12)
                } else {
                    // 2 列网格（v75）
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(videos) { v in
                            LobbyVideoCard(video: v) { playing = v }
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .fullScreenCover(item: $playing) { video in
            LobbyVideoPlayerView(video: video)
        }
    }
}

/// 视频卡：OSS 封面（无封面给暗底）+ LIVE 徽标 + 时长角标 + 标题
struct LobbyVideoCard: View {
    let video: LobbyVideo
    let onClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if let cover = video.videoCover, !cover.isEmpty, let url = webImageURL(cover) {
                    WebImage(url: url) { Color(red: 0x14/255, green: 0x10/255, blue: 0x18/255) }
                        .frame(height: 96)
                } else {
                    Color(red: 0x14/255, green: 0x10/255, blue: 0x18/255)
                        .frame(height: 96)
                }
                LinearGradient(
                    colors: [Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.05),
                             Color(red: 0x08/255, green: 0x08/255, blue: 0x0B/255).opacity(0.55)],
                    startPoint: .top, endPoint: .bottom)
                VStack {
                    HStack {
                        LobbyLiveBadge(withDot: true)
                        Spacer()
                    }
                    .padding(5)
                    Spacer()
                    HStack {
                        Spacer()
                        if let sec = video.durationSec, sec > 0 {
                            Text("\(sec)s")
                                .font(.lobbyNumber(7.5))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.black.opacity(0.6)))
                                .padding(5)
                        }
                    }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(LobbyColors.gold.opacity(0.3), lineWidth: 1))

            Text(video.title ?? "")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
    }
}

/// 全屏播放（对齐安卓 playingVideo Dialog：黑底等比留黑边 + 左上返回 + 标题）。
/// AVPlayer 播完停帧不清屏；离开页面即停。
struct LobbyVideoPlayerView: View {
    let video: LobbyVideo

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text(video.title ?? "店长 LIVE")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .onAppear {
            guard let urlStr = video.video, let url = URL(string: urlStr) else { return }
            let p = AVPlayer(url: url)
            p.actionAtItemEnd = .pause
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
