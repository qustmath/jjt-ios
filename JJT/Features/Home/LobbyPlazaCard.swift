import SwiftUI

/// 聊天室广场 · 入口卡（蜜兔会正上方，对齐安卓 LobbyEntrance；数据=门店大厅只读接口）。
/// 1.5pt 旋转金红流光边框环（3.6s/圈）+ 店内实景底图 + 实时开店/在玩角标。
struct LobbyPlazaCard: View {
    let onClick: () -> Void

    /// 今夜开店数/在玩人数（在玩 = 入座 + 围观；取不到不显示角标）
    @State private var stats: (openStores: Int, seatedMembers: Int)?

    var body: some View {
        ZStack {
            // 旋转彩色流光层：TimelineView 逐帧算角度（repeatForever 动画在首帧 state 变更后
            // 会冻在 0°——渐变五段色恰有两段深红，冻住时上下边"看起来没边框"）。
            // sweep 圆心必须对准卡片中心，画幅放大 2× 对角线防旋转露角（对齐安卓 drawBehind）
            GeometryReader { geo in
                let ext = max(geo.size.width, geo.size.height) * 2
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3.6) / 3.6
                    Rectangle()
                        .fill(AngularGradient(colors: [
                            Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255),
                            Color(red: 0x6E/255, green: 0x0F/255, blue: 0x22/255),
                            Color(red: 0xE8/255, green: 0xCF/255, blue: 0x9A/255),
                            Color(red: 0x7A/255, green: 0x11/255, blue: 0x28/255),
                            Color(red: 0xC9/255, green: 0xA4/255, blue: 0x5C/255),
                        ], center: .center))
                        .frame(width: ext, height: ext)
                        .rotationEffect(.degrees(phase * 360))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }

            // 内容层：内缩 1.5pt 露出边框环
            content
                .padding(1.5)
                .clipShape(RoundedRectangle(cornerRadius: 24.5))
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .onTapGesture { onClick() }
        .task {
            if let stores = try? await LobbyAPI.listStores(), !stores.isEmpty {
                let seated = stores.reduce(0) { $0 + ($1.seatedCount ?? 0) + ($1.standingCount ?? 0) }
                stats = (stores.count, seated)
            }
        }
    }

    private var content: some View {
        ZStack(alignment: .bottomLeading) {
            // 底图：店内实景暗调。overlay+clipped 让布局不被竖图撑破（原图 1024×1445，
            // 直接 scaledToFill 会把内容层撑到 ~494pt、盖住上下边框环）
            Color.clear
                .overlay(Image("lobby-plaza-bg").resizable().scaledToFill())
                .clipped()
            // 压暗渐变（对齐原型 200deg：上浅下重）
            LinearGradient(stops: [
                .init(color: Color(red: 0x0A/255, green: 0x06/255, blue: 0x08/255).opacity(0.35), location: 0),
                .init(color: Color(red: 0x0C/255, green: 0x07/255, blue: 0x09/255).opacity(0.55), location: 0.45),
                .init(color: Color(red: 0x08/255, green: 0x05/255, blue: 0x07/255).opacity(0.96), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // 顶部暖光渐晕
            LinearGradient(colors: [Noir.gold.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
                .frame(maxHeight: .infinity, alignment: .top)

            // 左上：实时数据角标
            if let stats {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0x7D/255, green: 0xE3/255, blue: 0xA0/255)).frame(width: 6, height: 6)
                    Text("今夜 ")
                        .font(.system(size: 9.5))
                        .foregroundStyle(LobbyColors.textBody)
                    Text("\(stats.openStores)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(LobbyColors.goldLight)
                    Text(" 家店开中 · ")
                        .font(.system(size: 9.5))
                        .foregroundStyle(LobbyColors.textBody)
                    Text("\(stats.seatedMembers)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(LobbyColors.goldLight)
                    Text(" 人在玩")
                        .font(.system(size: 9.5))
                        .foregroundStyle(LobbyColors.textBody)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55))
                .overlay(Capsule().stroke(LobbyColors.goldLight.opacity(0.5), lineWidth: 1))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }

            // 右上：LIVE 火焰角标
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1, green: 0xD9/255, blue: 0xA0/255))
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LinearGradient(colors: [Noir.crimson, Noir.crimsonDeep], startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
            .shadow(color: Noir.crimson.opacity(0.55), radius: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(14)

            // 底部：标题 + 在玩数 + 箭头
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 1, green: 0x7D/255, blue: 0x9C/255))
                        Text("NOIR LOUNGE")
                            .font(.system(size: 10).italic())
                            .kerning(3.5)
                            .foregroundStyle(LobbyColors.goldLight.opacity(0.85))
                    }
                    Spacer().frame(height: 8)
                    Text("聊天室广场")
                        .font(.system(size: 32, weight: .black, design: .serif))
                        .foregroundStyle(Noir.goldText)
                    Spacer().frame(height: 8)
                    Text("四店同开 · 入座上桌 · 组局拼桌")
                        .font(.system(size: 10.5))
                        .kerning(2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    if let stats {
                        Text("\(stats.seatedMembers)")
                            .font(.system(size: 24, design: .serif))
                            .foregroundStyle(Noir.goldText)
                        Text("今夜在玩")
                            .font(.system(size: 9))
                            .kerning(2.7)
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer().frame(height: 6)
                    }
                    Circle()
                        .stroke(LobbyColors.goldLight.opacity(0.6), lineWidth: 1)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0xF0/255, green: 0xDB/255, blue: 0xA8/255))
                        )
                }
            }
            .padding(20)
        }
    }
}
