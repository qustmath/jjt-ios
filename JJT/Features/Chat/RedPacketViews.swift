import SwiftUI

/// 发红包（对齐安卓 RedPacketSendScreen 的聊天场景子集）
/// scene: 1 单聊 2 群聊；成功后回调 onSent 由聊天页发 IM 红包消息
struct RedPacketSendView: View {

    let scene: Int
    let targetId: String
    let onSent: (_ packetId: Int64, _ greeting: String, _ walletType: String) -> Void

    @StateObject private var payGuard = PayPasswordGuard()
    @Environment(\.dismiss) private var dismiss

    @State private var packetType = 1          // 1 拼手气 2 普通
    @State private var walletType = "rabbit_coin"
    @State private var amount = ""
    @State private var count = ""
    @State private var greeting = ""
    @State private var balance: Int64?
    @State private var error: String?
    @State private var showPaySettings = false
    @State private var showRecharge = false

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("发红包")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                    Text("RED PACKET")
                        .font(.system(size: 9, design: .serif))
                        .italic()
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "gem")
                        .font(.system(size: 12))
                        .foregroundStyle(Noir.gold)
                    Text(balance.map { "\($0)" } ?? "--")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Noir.goldText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                .padding(.trailing, 10)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 类型（群聊才有拼手气/普通选择；单聊固定普通）
                    if scene == 2 {
                        fieldLabel("红包类型")
                        HStack(spacing: 8) {
                            typePill(1, "拼手气")
                            typePill(2, "普通")
                        }
                    }
                    fieldLabel("钱包")
                    HStack(spacing: 8) {
                        walletPill("rabbit_coin", "兔币")
                        walletPill("radish_coin", "萝贝")
                    }
                    fieldLabel(packetType == 1 ? "总金额" : "单个金额")
                    TextField(packetType == 1 ? "总金额（\(walletTypeLabel(walletType))）" : "单个金额", text: $amount)
                        .keyboardType(.numberPad)
                        .noirField()
                    fieldLabel("个数")
                    TextField("红包个数", text: $count)
                        .keyboardType(.numberPad)
                        .noirField()
                    fieldLabel("祝福语")
                    TextField("恭喜发财，大吉大利", text: $greeting)
                        .noirField()
                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                    Button { submit() } label: {
                        Text("塞钱进红包")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            Task { balance = try await WalletAPI.getWallet(walletType).availableAmount }
        }
        .onChange(of: walletType) { _, wt in
            Task { balance = try await WalletAPI.getWallet(wt).availableAmount }
        }
        .payPasswordGuard(payGuard) { showPaySettings = true }
        .fullScreenCover(isPresented: $showPaySettings) {
            PayPasswordSettingsView()
        }
        .fullScreenCover(isPresented: $showRecharge) {
            CoinRechargeView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jjtInsufficientBalance)) { _ in
            showRecharge = true
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
    }

    private func typePill(_ type: Int, _ label: String) -> some View {
        let selected = packetType == type
        return Text(label)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : Color.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(selected
                        ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Noir.noir2))
            .clipShape(Capsule())
            .onTapGesture { packetType = type }
    }

    private func walletPill(_ type: String, _ label: String) -> some View {
        let selected = walletType == type
        return Text(label)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : Color.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(selected
                        ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Noir.noir2))
            .clipShape(Capsule())
            .onTapGesture { walletType = type }
    }

    private func submit() {
        guard let amt = Int(amount), amt > 0 else { error = "请输入金额"; return }
        guard let cnt = Int(count), cnt > 0 else { error = "请输入个数"; return }
        if scene == 2, packetType == 2, cnt > 0, amt * cnt > (balance ?? 0) {
            // 普通红包按 单个×个数 扣款，余额不足提前提示（服务端仍会校验）
        }
        error = nil
        let greet = greeting.trimmingCharacters(in: .whitespaces).isEmpty ? "恭喜发财，大吉大利" : greeting
        payGuard.require { pwd in
            let resp = try await RedPacketAPI.send(RedPacketSendReq(
                scene: scene, targetId: targetId, walletType: walletType,
                packetType: scene == 1 ? 2 : packetType,
                totalAmount: amt, totalCount: cnt,
                greeting: greet, payPassword: pwd))
            onSent(resp.packetId, greet, walletType)
        }
    }
}

/// 开红包弹层（对齐安卓 RedPacketSheet：状态 → 开 → 结果/领取记录）
struct RedPacketOpenSheet: View {

    let packetId: Int64

    @State private var status: RedPacketStatusResp?
    @State private var openResult: RedPacketOpenResp?
    @State private var detail: RedPacketDetailResp?
    @State private var opening = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            if let s = status {
                // 发送者
                HStack(spacing: 10) {
                    AppAvatar(url: s.senderAvatar, size: 36)
                        .frame(width: 36, height: 36)
                    Text("\(s.senderNickname ?? "用户\(s.senderId)") 的红包")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Noir.ivory)
                    Spacer()
                }
                Text(s.greeting ?? "恭喜发财，大吉大利")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Noir.goldText)

                if let result = openResult {
                    // 领取结果
                    resultView(result)
                } else if s.canOpen {
                    Button { open() } label: {
                        Text(opening ? "開" : "開")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(Color(red: 0x8B/255, green: 0x0A/255, blue: 0x1E/255))
                            .frame(width: 84, height: 84)
                            .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .top, endPoint: .bottom))
                            .clipShape(Circle())
                    }
                    .disabled(opening)
                    .padding(.vertical, 10)
                } else {
                    Text(statusHint(s))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 16)
                }

                // 领取记录
                if let d = detail, let claims = d.claims, !claims.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已领取 \(d.totalCount - d.remainCount)/\(d.totalCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(claims) { claim in
                            HStack(spacing: 10) {
                                AppAvatar(url: claim.avatar, size: 26)
                                    .frame(width: 26, height: 26)
                                Text(claim.nickname ?? "用户\(claim.userId)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                if claim.luckiest {
                                    Text("手气最佳")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Noir.gold)
                                }
                                Text("\(claim.amount) \(walletTypeLabel(d.walletType))")
                                    .font(.system(size: 12, design: .serif))
                                    .foregroundStyle(Noir.goldText)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                ProgressView().tint(Noir.gold).padding(40)
            }
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.crimsonHot)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .onAppear { load() }
    }

    private func statusHint(_ s: RedPacketStatusResp) -> String {
        if s.opened { return "你已领取过" }
        switch s.status {
        case 2: return "红包已领完"
        case 3: return "红包已过期"
        default:
            if let ex = s.exclusiveNickname { return "仅 \(ex) 可领取" }
            return "暂不可领取"
        }
    }

    @ViewBuilder
    private func resultView(_ result: RedPacketOpenResp) -> some View {
        switch result.result {
        case 1:
            VStack(spacing: 6) {
                Text("\(result.amount ?? 0)")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                Text("\(walletTypeLabel(status?.walletType))已存入钱包")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.vertical, 10)
        case 2: Text("你已领取过").foregroundStyle(.white.opacity(0.5))
        case 3: Text("手慢了，红包已领完").foregroundStyle(.white.opacity(0.5))
        case 4: Text("红包已过期").foregroundStyle(.white.opacity(0.5))
        default: Text("无权领取").foregroundStyle(.white.opacity(0.5))
        }
    }

    private func load() {
        Task {
            do {
                status = try await RedPacketAPI.status(packetId: packetId)
                detail = try? await RedPacketAPI.detail(packetId: packetId)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func open() {
        guard !opening else { return }
        opening = true
        Task {
            defer { opening = false }
            do {
                openResult = try await RedPacketAPI.open(packetId: packetId)
                detail = try? await RedPacketAPI.detail(packetId: packetId)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
