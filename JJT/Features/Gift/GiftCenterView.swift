import SwiftUI

/// 礼物中心 — 暗夜奢华风（对齐安卓 GiftCenterScreen）
/// receiverId 为 nil = 先买后送（确认弹窗内选接收人或稍后指定）
struct GiftCenterView: View {

    var receiverId: Int64? = nil
    var receiverName: String? = nil
    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = GiftCenterViewModel()
    @StateObject private var payGuard = PayPasswordGuard()
    @Environment(\.dismiss) private var dismiss

    @State private var confirmGift: GiftItem?
    @State private var showPaySettings = false
    @State private var showRecharge = false

    /// 只展示 2D 礼物（3D/GLB 已在 iOS 下线，不再解析）
    private var displayGifts: [GiftItem] {
        vm.gifts.filter { giftRenderKindOf(giftDisplayIcon($0.icon, $0.animationUrl)).map { giftKindGroupOf($0.0) } == "2d" }
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 0) {
                        if let sel = vm.selected {
                            stage(sel)
                        }
                        giftGrid
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { vm.load() }
        .onChange(of: vm.gifts.map(\.id)) { _, _ in
            if vm.selected == nil || !(displayGifts.contains { $0.id == vm.selected?.id }) {
                vm.selected = displayGifts.first
            }
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 确认送出（选接收人/数量/总价）
        .sheet(item: $confirmGift) { gift in
            GiftConfirmSheet(gift: gift, fixedReceiverId: receiverId, fixedReceiverName: receiverName) { rid, qty in
                confirmGift = nil
                send(gift, receiverId: rid, quantity: qty)
            }
            .presentationDetents([.medium])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        .payPasswordGuard(payGuard) { showPaySettings = true }
        .fullScreenCover(isPresented: $showPaySettings) {
            PayPasswordSettingsView()
        }
        .fullScreenCover(isPresented: $showRecharge, onDismiss: { vm.refreshBalance() }) {
            CoinRechargeView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jjtInsufficientBalance)) { _ in
            showRecharge = true
        }
    }

    // MARK: - 顶栏

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
                    Text(receiverId != nil ? "送礼物" : "礼物中心")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Text("GIFT ATELIER")
                        .font(.system(size: 9))
                        .tracking(2.7)
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                // 兔币余额
                HStack(spacing: 6) {
                    Image(systemName: "gem")
                        .font(.system(size: 12))
                        .foregroundStyle(Noir.gold)
                    Text(vm.balance.map { "\($0)" } ?? "--")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    // MARK: - 主展示台

    private func stage(_ gift: GiftItem) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Noir.crimson.opacity(0.3), .clear],
                                         center: .center, startRadius: 0, endRadius: 72))
                    .frame(width: 144, height: 144)
                GiftIconView(
                    icon: (gift.animationUrl?.isEmpty == false ? gift.animationUrl : gift.icon),
                    size: 160,
                    scale: CGFloat(gift.iconScale ?? 100) / 100
                )
            }
            .frame(height: 176)
            Text(gift.name)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Noir.ivory)
            if let desc = gift.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
            }
            HStack(spacing: 6) {
                Image(systemName: "gem")
                    .font(.system(size: 12))
                    .foregroundStyle(Noir.gold)
                Text("\(gift.priceRabbit ?? 0) 兔币")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
            }
            .padding(.top, 12)
            Button { confirmGift = gift } label: {
                Text("送 出")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(RadialGradient(colors: [Color(red: 0x2A/255, green: 0x0A/255, blue: 0x14/255), Noir.noir],
                                   center: .center, startRadius: 0, endRadius: 300))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 礼物网格

    private var giftGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(displayGifts) { gift in
                let selected = vm.selected?.id == gift.id
                VStack(spacing: 4) {
                    GiftIconView(
                        icon: giftDisplayIcon(gift.icon, gift.animationUrl),
                        size: 52,
                        scale: CGFloat(gift.iconScale ?? 100) / 100
                    )
                    .frame(height: 60)
                    Text(gift.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Text("\(gift.priceRabbit ?? 0) 币")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.goldText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Noir.crimson.opacity(0.12) : Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                    selected ? Noir.crimson.opacity(0.6) : Color.white.opacity(0.05), lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { vm.selected = gift }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - 送出

    private func send(_ gift: GiftItem, receiverId: Int64?, quantity: Int) {
        payGuard.require { pwd in
            _ = try await GiftAPI.send(SendGiftReq(
                giftId: gift.id, receiverId: receiverId, quantity: quantity,
                scene: receiverId != nil ? "profile" : "buy", payPassword: pwd))
            vm.balance = (vm.balance ?? 0) - Int64((gift.priceRabbit ?? 0) * quantity)
            // 全屏赠送动效：窗口级覆盖（对齐安卓全屏 Dialog）
            JJTWindowOverlay.show(GiftSendOverlay(gift: gift, combo: 1) { JJTWindowOverlay.dismiss() })
            jjtShowToast(receiverId != nil ? "礼物已送出" : "购买成功，可在我的礼物中送出")
        }
    }
}

// MARK: - 确认送出弹层（选接收人 / 数量 / 总价）

struct GiftConfirmSheet: View {

    let gift: GiftItem
    let fixedReceiverId: Int64?
    let fixedReceiverName: String?
    let onConfirm: (Int64?, Int) -> Void

    @State private var quantity = 1
    @State private var selectedUser: FollowUser?
    @State private var laterMode = false
    @State private var showPicker = false
    @State private var following: [FollowUser] = []
    @State private var pickerLoading = false
    @Environment(\.dismiss) private var dismiss

    private var effectiveReceiverId: Int64? { fixedReceiverId ?? selectedUser?.userId }
    private var canSend: Bool { effectiveReceiverId != nil || laterMode }
    private var totalPrice: Int { (gift.priceRabbit ?? 0) * quantity }

    var body: some View {
        VStack(spacing: 14) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack {
                Text(gift.name)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            }

            // 接收人
            Button {
                if fixedReceiverId == nil { pickReceiver() }
            } label: {
                HStack(spacing: 8) {
                    if effectiveReceiverId != nil {
                        if let avatar = selectedUser?.avatar {
                            AppAvatar(url: avatar, size: 28)
                                .frame(width: 28, height: 28)
                        }
                        Text(selectedUser?.nickname ?? fixedReceiverName ?? "用户 \(fixedReceiverId ?? 0)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Noir.ivory)
                    } else {
                        Text("点击选择接收人")
                            .font(.system(size: 14))
                            .foregroundStyle(Noir.goldLight)
                    }
                    Spacer()
                    if fixedReceiverId == nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // 稍后指定（仅从礼物中心进入时）
            if fixedReceiverId == nil {
                Button {
                    laterMode.toggle()
                    if laterMode { selectedUser = nil }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: laterMode ? "checkmark.square.fill" : "square")
                            .foregroundStyle(laterMode ? Noir.crimson : .white.opacity(0.4))
                        Text("稍后指定接收人")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            // 数量
            HStack(spacing: 8) {
                Text("数量：")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                Button { if quantity > 1 { quantity -= 1 } } label: {
                    Text("-").font(.system(size: 18)).foregroundStyle(Noir.goldLight)
                        .frame(width: 32, height: 32)
                }
                Text("\(quantity)")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Noir.goldText)
                    .frame(minWidth: 32)
                Button { if quantity < 99 { quantity += 1 } } label: {
                    Text("+").font(.system(size: 18)).foregroundStyle(Noir.goldLight)
                        .frame(width: 32, height: 32)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("合计：")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(totalPrice) 兔币")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                }
            }

            Button { onConfirm(effectiveReceiverId, quantity) } label: {
                Text(laterMode ? "确认购买（稍后送）" : effectiveReceiverId != nil ? "确认送出" : "请先选接收人")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        canSend
                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        // 接收人选择（关注列表）
        .sheet(isPresented: $showPicker) {
            receiverPicker
                .presentationDetents([.medium])
                .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
    }

    private func pickReceiver() {
        showPicker = true
        guard following.isEmpty else { return }
        pickerLoading = true
        Task {
            following = (try? await FollowAPI.following(pageNo: 1, pageSize: 50).list) ?? []
            pickerLoading = false
        }
    }

    private var receiverPicker: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            Text("选择接收人")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .frame(maxWidth: .infinity, alignment: .leading)
            if pickerLoading {
                ProgressView().tint(Noir.gold).padding(30)
            } else if following.isEmpty {
                Text("关注列表为空")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(30)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(following) { user in
                            Button {
                                selectedUser = user
                                laterMode = false
                                showPicker = false
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
    }
}

// MARK: - ViewModel

@MainActor
final class GiftCenterViewModel: ObservableObject {

    @Published var gifts: [GiftItem] = []
    @Published var selected: GiftItem?
    @Published var balance: Int64?
    @Published var isLoading = false
    @Published var error: String?

    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                gifts = try await GiftAPI.giftList()
            } catch {
                self.error = error.localizedDescription
            }
        }
        refreshBalance()
    }

    func refreshBalance() {
        Task {
            balance = try await WalletAPI.getWallet("rabbit_coin").availableAmount
        }
    }

    func clearError() { error = nil }
}
