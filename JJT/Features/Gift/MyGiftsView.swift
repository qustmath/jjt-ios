import SwiftUI

/// 我的礼物 — 收/送 Tab + 订单卡片流（对齐安卓 MyGiftsScreen）
struct MyGiftsView: View {

    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = MyGiftsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0   // 0=收到的 1=送出的
    @State private var assignTarget: GiftOrderVO?
    @State private var pendingConfirm: (order: GiftOrderVO, user: FollowUser)?
    @State private var following: [FollowUser] = []

    private var list: [GiftOrderVO] { tab == 0 ? vm.receivedList : vm.sentList }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                tabSwitcher
                if list.isEmpty {
                    Spacer()
                    Text(vm.isLoading ? "加载中…" : "暂无记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(list) { order in
                                orderCard(order)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .onAppear { vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("确定") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 指定接收人（先买后送）
        .sheet(isPresented: Binding(
            get: { assignTarget != nil },
            set: { if !$0 { assignTarget = nil } }
        )) {
            receiverPicker
                .presentationDetents([.medium])
                .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        // 二次确认
        .alert("确认送出", isPresented: Binding(
            get: { pendingConfirm != nil },
            set: { if !$0 { pendingConfirm = nil } }
        )) {
            Button("确认送出") {
                if let p = pendingConfirm {
                    vm.assign(orderId: p.order.id, receiverId: p.user.userId, name: p.user.nickname ?? "用户\(p.user.userId)")
                    pendingConfirm = nil
                }
            }
            Button("取消", role: .cancel) { pendingConfirm = nil }
        } message: {
            if let p = pendingConfirm {
                Text("确定将「\(p.order.giftName ?? "礼物")」送给 \(p.user.nickname ?? "用户\(p.user.userId)")？")
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("我的礼物")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("MY GIFTS")
                        .font(.system(size: 9))
                        .tracking(2.7)
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabButton("收到的", active: tab == 0) { tab = 0 }
            tabButton("送出的", active: tab == 1) { tab = 1 }
        }
        .padding(4)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func tabButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .tracking(2)
                .foregroundStyle(active ? .white : .white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active
                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.clear))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 订单卡片

    private func orderCard(_ order: GiftOrderVO) -> some View {
        let isReceived = tab == 0
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(RadialGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                                         center: .center, startRadius: 0, endRadius: 40))
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
                GiftIconView(
                    icon: giftDisplayIcon(order.giftIcon, order.animationUrl),
                    size: 44,
                    scale: CGFloat(order.iconScale ?? 100) / 100
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(order.giftName ?? "礼物") ×\(order.quantity ?? 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
                let statusLabel = statusText(order.status)
                let sub: String = {
                    if !isReceived, order.status == "PAID" { return "未送出" }
                    if let name = order.counterpartyName { return "\(name) · \(statusLabel)" }
                    return statusLabel
                }()
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(!isReceived && order.status == "PAID" ? Noir.crimsonHot : Color.white.opacity(0.4))
                if let time = order.createTime, !time.isEmpty {
                    Text(String(time.prefix(10)))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            Spacer()
            // 右侧操作
            if !isReceived, order.status == "PAID" {
                miniButton("送出") { assignTarget = order }
            } else if isReceived, order.status == "SENT" {
                miniButton("接收") { vm.receive(orderId: order.id) }
            } else if isReceived, order.status == "RECEIVED" {
                Text("+\(order.revenueAmount ?? 0)")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
            } else {
                Text("\(order.payAmount ?? 0) 兔币")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
    }

    private func statusText(_ status: String?) -> String {
        switch status {
        case "PAID": return "已支付"
        case "SENT": return "已送出"
        case "RECEIVED": return "已接收"
        default: return status ?? ""
        }
    }

    private func miniButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 接收人选择

    private var receiverPicker: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            Text("送给「\(assignTarget?.giftName ?? "礼物")」")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .frame(maxWidth: .infinity, alignment: .leading)
            if following.isEmpty {
                Text("关注列表为空")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(30)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(following) { user in
                            Button {
                                if let order = assignTarget {
                                    pendingConfirm = (order, user)
                                    assignTarget = nil
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    AppAvatar(url: user.avatar, size: 36)
                                        .frame(width: 36, height: 36)
                                    Text(user.nickname ?? "用户\(user.userId)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Noir.ivory)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .onAppear {
            Task { following = (try? await FollowAPI.following(pageNo: 1, pageSize: 50).list) ?? [] }
        }
    }
}

// MARK: - ViewModel（对齐安卓 MyGiftsViewModel）

@MainActor
final class MyGiftsViewModel: ObservableObject {

    @Published var receivedList: [GiftOrderVO] = []
    @Published var sentList: [GiftOrderVO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            async let r = GiftAPI.receivedList()
            async let s = GiftAPI.sentList()
            receivedList = (try? await r) ?? []
            sentList = (try? await s) ?? []
        }
    }

    func receive(orderId: Int64) {
        Task {
            do {
                let revenue = try await GiftAPI.receive(orderId: orderId)
                jjtShowToast("接收成功！收益 \(revenue) 已到账")
                load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func assign(orderId: Int64, receiverId: Int64, name: String) {
        Task {
            do {
                _ = try await GiftAPI.assignReceiver(orderId: orderId, receiverId: receiverId)
                jjtShowToast("已送给 \(name)")
                load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
