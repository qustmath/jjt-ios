import SwiftUI

/// 我的票夹（对齐安卓 TicketWalletScreen）：跨活动入场券聚合，点击进活动页
struct TicketWalletView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var tickets: [TicketInfo] = []
    @State private var loading = true
    @State private var activityId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
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
                    Text("我的票夹")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                Rectangle().fill(Noir.goldLine).frame(height: 1)

                if loading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if tickets.isEmpty {
                    Spacer()
                    Text("暂无入场券")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(tickets) { ticket in
                                ticketRow(ticket)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .onAppear { load() }
        .fullScreenCover(item: Binding(
            get: { activityId.map { T(id: $0) } },
            set: { activityId = $0?.id }
        )) { t in
            ActivityView(activityId: t.id)
        }
    }

    private struct T: Identifiable { let id: Int64 }

    private func ticketRow(_ ticket: TicketInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Noir.noir3)
                if let cover = ticket.activityCover, !cover.isEmpty {
                    WebImage(url: webImageURL(cover), contentMode: .fill) { Color.clear }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.activityName ?? "活动")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.ivory)
                Text("Nº \(ticket.ticketNo ?? "-")")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.gold)
                Text("领取于 \(fmtActivityDay(ticket.claimTime))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            statusText(ticket)
        }
        .padding(14)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { activityId = ticket.activityId }
    }

    @ViewBuilder
    private func statusText(_ ticket: TicketInfo) -> some View {
        switch ticket.status {
        case 1:
            Text("已入场")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Noir.gold)
        case 2:
            Text("已失效")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.3))
        default:
            if ticket.canRedeem == true {
                Text("可验票 →")
                    .font(.system(size: 11))
                    .tracking(1)
                    .foregroundStyle(Noir.crimsonHot)
            } else {
                Text("待入场")
                    .font(.system(size: 11))
                    .tracking(1)
                    .foregroundStyle(Noir.goldLight.opacity(0.7))
            }
        }
    }

    private func load() {
        Task {
            tickets = (try? await ActivityAPI.ticketPage())?.list ?? []
            loading = false
        }
    }
}
