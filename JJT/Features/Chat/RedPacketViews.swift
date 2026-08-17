import SwiftUI

/// 发红包（对齐安卓 RedPacketSendScreen）
/// 类型：群聊 1拼手气/2普通/3专属（指定群成员）；单聊固定普通包 1 份，无类型与个数选择
/// 金额口径：拼手气=总金额；普通=单个金额×个数；专属/单聊=金额
/// scene: 1 单聊 2 群聊；成功后回调 onSent 由聊天页发 IM 红包消息
struct RedPacketSendView: View {

    let scene: Int
    let targetId: String
    let onSent: (_ packetId: Int64, _ greeting: String, _ walletType: String, _ exclusiveToName: String?) -> Void

    @StateObject private var payGuard = PayPasswordGuard()
    @Environment(\.dismiss) private var dismiss

    @State private var packetType = 1          // 群：1 拼手气 2 普通 3 专属
    @State private var walletType = "rabbit_coin"
    @State private var amount = ""
    @State private var count = ""
    @State private var greeting = ""
    @State private var balance: Int64?
    @State private var error: String?
    @State private var sending = false
    @State private var showPaySettings = false
    @State private var showRecharge = false
    // 专属红包：群成员选人
    @State private var members: [GroupMember] = []
    @State private var exclusive: GroupMember?
    @State private var pickingMember = false
    @State private var memberFilter = ""

    private var isExclusive: Bool { scene == 2 && packetType == 3 }
    private var needCount: Bool { scene == 2 && packetType != 3 }
    private var amountValue: Int { Int(amount) ?? 0 }
    private var countValue: Int { Int(count) ?? 0 }
    /// 提交总金额：普通=单个×个数；其余=输入金额（对齐安卓 totalAmount）
    private var totalAmount: Int { scene == 2 && packetType == 2 ? amountValue * countValue : amountValue }

    /// 校验规则对齐安卓
    private var valid: Bool {
        let base: Bool
        if isExclusive {
            base = (1...20000).contains(amountValue) && exclusive != nil
        } else if scene == 2 && packetType == 2 {
            base = (1...20000).contains(amountValue) && (1...100).contains(countValue) && totalAmount <= 20000
        } else if scene == 2 {
            base = (1...20000).contains(amountValue) && (1...100).contains(countValue) && amountValue >= countValue // 拼手气：每份至少 1
        } else {
            base = (1...20000).contains(amountValue) // 单聊
        }
        return base && (balance == nil || totalAmount <= balance!)
    }

    /// 兔币余额不足时按钮可点，点了弹充值引导（对齐安卓 RechargeGuideBus；萝贝不可充值）
    private var insufficientRabbit: Bool {
        walletType == "rabbit_coin" && balance != nil && totalAmount > balance!
    }

    var body: some View {
        if pickingMember {
            memberPickPage
        } else {
            mainPage
        }
    }

    // MARK: - 主表单

    private var mainPage: some View {
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
                    // 类型（群聊：拼手气/普通/专属；单聊固定普通包，不展示类型）
                    if scene == 2 {
                        fieldLabel("红包类型")
                        HStack(spacing: 8) {
                            typePill(1, "拼手气")
                            typePill(2, "普通")
                            typePill(3, "专属")
                        }
                    }
                    fieldLabel("钱包")
                    HStack(spacing: 8) {
                        walletPill("rabbit_coin", "兔币")
                        walletPill("radish_coin", "萝贝")
                    }
                    // 专属红包：指定领取人
                    if isExclusive {
                        fieldLabel("发给谁")
                        Button { pickingMember = true } label: {
                            HStack {
                                Text(exclusive?.nickname ?? "选择群成员")
                                    .font(.system(size: 14))
                                    .foregroundStyle(exclusive != nil ? Noir.ivory : .white.opacity(0.3))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .noirField()
                        }
                        .buttonStyle(.plain)
                    }
                    fieldLabel(scene == 2 && packetType == 1 ? "总金额" : (scene == 2 && packetType == 2 ? "单个金额" : "金额"))
                    TextField(scene == 2 && packetType == 1 ? "总金额（\(walletTypeLabel(walletType))）" : "0", text: $amount)
                        .keyboardType(.numberPad)
                        .noirField()
                        .onChange(of: amount) { _, v in amount = String(v.filter(\.isNumber).prefix(5)) }
                    // 个数：群聊非专属才有（单聊固定 1 份）
                    if needCount {
                        fieldLabel("个数")
                        TextField("红包个数", text: $count)
                            .keyboardType(.numberPad)
                            .noirField()
                            .onChange(of: count) { _, v in count = String(v.filter(\.isNumber).prefix(3)) }
                        Text("本群共 \(members.count + 1) 人")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    fieldLabel("祝福语")
                    TextField("恭喜发财，大吉大利", text: $greeting)
                        .noirField()
                        .onChange(of: greeting) { _, v in greeting = String(v.prefix(32)) }
                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                    if insufficientRabbit {
                        Text("兔币余额不足（当前 \(balance ?? 0)）")
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                    // 底部大金额（对齐安卓）
                    HStack(alignment: .bottom, spacing: 5) {
                        Text("\(totalAmount)")
                            .font(.system(size: 36, weight: .black, design: .serif))
                            .foregroundStyle(Noir.goldText)
                        Text(walletTypeLabel(walletType))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.bottom, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    Button { tapSubmit() } label: {
                        Text(sending ? "发送中…" : "塞钱进红包")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(valid && !sending ? .white : .white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                Capsule().fill(
                                    valid && !sending
                                        ? LinearGradient(colors: [Color(red: 0x9E/255, green: 0x1B/255, blue: 0x1B/255), Color(red: 0xC4/255, green: 0x38/255, blue: 0x2E/255)],
                                                         startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!(valid && !sending) && !insufficientRabbit)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            loadBalance()
            loadMembersIfNeeded()
        }
        .onChange(of: walletType) { _, _ in loadBalance() }
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

    // MARK: - 指定领取人（对齐安卓 MemberPickPage：搜索 + 成员列表）

    private var memberPickPage: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack {
                Button { pickingMember = false } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Noir.ivory)
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text("指定领取人")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            TextField("搜索成员", text: $memberFilter)
                .noirField()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            let shown = memberFilter.isEmpty ? members
                : members.filter { ($0.nickname ?? "").localizedCaseInsensitiveContains(memberFilter) }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(shown) { m in
                        HStack(spacing: 10) {
                            AppAvatar(url: m.avatar, size: 36)
                                .frame(width: 36, height: 36)
                            Text(m.nickname ?? "用户\(m.userId)")
                                .font(.system(size: 14))
                                .foregroundStyle(Noir.ivory)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Noir.noir2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { exclusive = m; pickingMember = false }
                    }
                }
                .padding(.horizontal, 16)
            }
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

    // MARK: - 数据加载与提交

    private func loadBalance() {
        Task { balance = try await WalletAPI.getWallet(walletType).availableAmount }
    }

    /// 群聊：IM groupId → 内部 id → 成员列表（排除自己），供专属红包选人 / 「本群共 N 人」
    private func loadMembersIfNeeded() {
        guard scene == 2 else { return }
        Task {
            guard let info = try? await GroupAPI.get(imGroupId: targetId),
                  let all = try? await GroupAPI.members(groupId: info.id) else { return }
            let myId = TokenManager.shared.userId
            members = all.filter { $0.userId != myId }
        }
    }

    private func tapSubmit() {
        if insufficientRabbit && !valid {
            showRecharge = true
            return
        }
        guard valid else { return }
        error = nil
        let greet = greeting.trimmingCharacters(in: .whitespaces).isEmpty ? "恭喜发财，大吉大利" : greeting
        payGuard.require { pwd in
            sending = true
            defer { sending = false }
            let resp = try await RedPacketAPI.send(RedPacketSendReq(
                scene: scene, targetId: targetId, walletType: walletType,
                packetType: scene == 1 ? 2 : packetType,
                totalAmount: totalAmount, totalCount: needCount ? countValue : 1,
                exclusiveUserId: isExclusive ? exclusive?.userId : nil,
                greeting: greet, payPassword: pwd))
            onSent(resp.packetId, greet, walletType, isExclusive ? exclusive?.nickname : nil)
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
