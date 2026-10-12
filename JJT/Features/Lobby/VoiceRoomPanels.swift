import SwiftUI

/// 语音房管理面板（对齐安卓 VoiceRoomOpsSheet；数据全部现拉，不缓存）。
///
/// 抱麦入口只有两处：上麦申请列表（本面板）与公屏/麦位点人资料卡。后端没有「在房未上麦成员」
/// 列表接口（/voice-room 只暴露麦位、申请、审批三类），所以不做独立的观众列表选人。
struct VoiceRoomOpsSheet: View {

    let isHost: Bool
    let roomTitle: String
    let myUserId: Int64
    /// 外部动作计数：每 +1 重拉申请/进房列表（抱麦核销申请后列表要即时收敛）
    let refreshTick: Int
    /// 成员头像查询（房间公屏消息发送者资料；LiveKit 本身不透传头像）
    let avatarOf: (Int64) -> String?
    let onDismiss: () -> Void
    let onSeat: (Int64) -> Void
    let onMute: (Int, Bool) -> Void
    let onRole: (Int, Bool) -> Void
    let onKick: (Int64) -> Void
    let onKickFromRoom: (Int64) -> Void
    let onCloseRoom: () -> Void

    @ObservedObject private var session = VoiceRoomSession.shared
    @State private var applies: [VoiceRoomMicApply] = []
    @State private var requests: [VoiceRoomJoinRequest] = []
    @State private var loading = true
    @State private var error: String?

    /// 麦位管理：读会话里的详情（与麦位列同源；闭麦/管理麦按麦位号操作）
    private var onMicMembers: [LobbyMicItem] {
        (session.detail?.mics ?? []).filter { $0.userId != nil && $0.userId != myUserId }
    }

    /// 房间成员（未上麦者；LiveKit 实时视图）——移出房间入口。
    /// 角标=下方实际渲染的行数（此前 +1 把自己算进角标但列表不渲染自己）
    private var roomOnlyMembers: [VoiceRoomPeer] {
        let onMicUserIds = Set((session.detail?.mics ?? []).compactMap { $0.userId })
        return session.peers.filter { $0.userId != myUserId && !onMicUserIds.contains($0.userId) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                Text("房间管理 · \(roomTitle)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LobbyColors.ivory)
                Text(isHost ? "你是房主：可抱麦 / 闭麦 / 指定管理麦 / 关闭房间" : "你是管理麦：可抱麦 / 闭麦")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)

                if loading {
                    HStack(spacing: 8) {
                        ProgressView().tint(LobbyColors.gold).scaleEffect(0.7)
                        Text("加载中…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.top, 12)
                } else if let error {
                    Text("加载失败：\(error)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(LobbyColors.crimson.opacity(0.8))
                        .padding(.top, 12)
                } else {
                    // ── 上麦申请 ──
                    sectionHeader("上麦申请", count: applies.count)
                    if applies.isEmpty {
                        hint("暂无上麦申请 · 有人申请上麦时出现在这里")
                    } else {
                        ForEach(applies) { a in
                            HStack(spacing: 10) {
                                AppAvatar(url: a.avatar, size: 32)
                                Text(a.nickname ?? "用户\(a.userId ?? 0)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(LobbyColors.ivory)
                                    .lineLimit(1)
                                Spacer()
                                SmallAction(label: "抱上麦", primary: true) {
                                    if let uid = a.userId { onSeat(uid) }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 8)
                        }
                    }

                    // ── 进房申请 ──
                    sectionHeader("进房申请", count: requests.count)
                    if requests.isEmpty {
                        hint("暂无进房申请 · 审批制房间的申请会出现在这里")
                    } else {
                        ForEach(requests) { r in
                            HStack(spacing: 10) {
                                AppAvatar(url: r.avatar, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.nickname ?? "用户\(r.userId ?? 0)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(LobbyColors.ivory)
                                        .lineLimit(1)
                                    if let content = r.applyContent, !content.isEmpty {
                                        Text(content)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.white.opacity(0.4))
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                SmallAction(label: "拒绝", primary: false) {
                                    if let id = r.requestId {
                                        session.runAction {
                                            try await session.handleJoinRequest(requestId: id, agree: false, reason: nil)
                                            await loadAll()
                                        }
                                    }
                                }
                                SmallAction(label: "同意", primary: true) {
                                    if let id = r.requestId {
                                        session.runAction {
                                            try await session.handleJoinRequest(requestId: id, agree: true, reason: nil)
                                            await loadAll()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 8)
                        }
                    }

                    // ── 麦位管理（闭麦 / 强制下麦） ──
                    sectionHeader("麦位管理", count: onMicMembers.count)
                    if onMicMembers.isEmpty {
                        hint("麦上暂时只有你自己")
                    } else {
                        ForEach(onMicMembers) { m in
                            guard let seatNo = m.seatNo else { continue }
                            HStack(spacing: 8) {
                                Text("\(seatNo)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .frame(width: 18, alignment: .leading)
                                AppAvatar(url: m.avatar, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.nickname ?? "用户\(m.userId ?? 0)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(LobbyColors.ivory)
                                        .lineLimit(1)
                                    Text(m.muted == true ? "已闭麦" : "可发言")
                                        .font(.system(size: 9))
                                        .foregroundStyle(m.muted == true ? .white.opacity(0.35) : LobbyColors.seated)
                                }
                                Spacer()
                                SmallAction(label: m.muted == true ? "开麦" : "闭麦", primary: m.muted != true) {
                                    onMute(seatNo, m.muted != true)
                                }
                                // 强制下麦：房主/管理麦可把别人移下麦位；自己走主栏下麦
                                if m.userId != myUserId {
                                    SmallAction(label: "下麦", primary: false) {
                                        if let uid = m.userId { onKick(uid) }
                                    }
                                }
                                // 设管理麦入口暂隐藏（服务端 mic/role 能力保留；产品节奏另行放开）
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 8)
                        }
                    }

                    // ── 房间成员（未上麦者）——移出房间入口 ──
                    sectionHeader("房间成员", count: roomOnlyMembers.count)
                    if roomOnlyMembers.isEmpty {
                        hint("其他未上麦成员会出现在这里")
                    } else {
                        ForEach(roomOnlyMembers) { p in
                            HStack(spacing: 10) {
                                AppAvatar(url: avatarOf(p.userId), size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((p.name?.isEmpty == false) ? p.name! : "用户\(p.userId)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(LobbyColors.ivory)
                                        .lineLimit(1)
                                    Text("未上麦")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                Spacer()
                                SmallAction(label: "移出", primary: false) { onKickFromRoom(p.userId) }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 8)
                        }
                    }

                    if isHost {
                        Text("关闭房间（所有人退出）")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LobbyColors.crimson)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.05))
                            .overlay(Capsule().stroke(LobbyColors.crimson.opacity(0.5), lineWidth: 1))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                            .onTapGesture { onCloseRoom() }
                            .padding(.top, 16)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .task { await loadAll() }
        .onChange(of: refreshTick) { _, newValue in
            // 外部动作（抱麦等）完成后重载：申请被核销要立即从列表消失
            if newValue > 0 {
                Task { await loadAll() }
            }
        }
    }

    private func loadAll() async {
        loading = true
        error = nil
        do {
            applies = try await VoiceRoomSession.shared.listMicApplications()
            requests = try await VoiceRoomSession.shared.listJoinRequests()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(LobbyColors.ivory)
            if count > 0 {
                // 固定尺寸正圆（数字徽标必须是正圆）
                Text(count > 9 ? "9+" : "\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(LobbyColors.crimson))
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(.white.opacity(0.3))
    }
}

/// 面板内小按钮（抱上麦/同意/闭麦等）
private struct SmallAction: View {
    let label: String
    let primary: Bool
    let onClick: () -> Void

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(primary ? .white : LobbyColors.goldLight)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                } else {
                    Capsule().fill(.white.opacity(0.05))
                        .overlay(Capsule().stroke(Noir.gold.opacity(0.35), lineWidth: 1))
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { onClick() }
    }
}

/// 开小房间（对齐安卓 VoiceRoomCreateSheet；门槛全在服务端：本店入座 + 实名 + 一人一店在营上限）。
/// 建成功后直接进房——服务端已把房主加进 IM 群，房间页的 join 会回 already。
struct VoiceRoomCreateSheet: View {

    let storeId: Int64
    let onDismiss: () -> Void
    let onCreated: (Int64) -> Void

    @State private var title = ""
    @State private var selectedTags: Set<String> = []
    @State private var mode = "public"
    @State private var busy = false
    @State private var error: String?
    private let tagPool = ["微醺", "桌游", "黑胶", "密语", "拼酒"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            Text("开一个小房间")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LobbyColors.ivory)
            Text("开房门槛：本店入座 + 实名认证 + 一人一店一间在营（服务端校验）")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)

            // 房间名
            TextField("今晚聊点什么（≤32 字）", text: $title)
                .font(.system(size: 12))
                .foregroundStyle(LobbyColors.ivory)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 12)
                .onChange(of: title) { _, v in
                    if v.count > 32 { title = String(v.prefix(32)) }
                }

            // 标签（选填，多选）
            Text("标签（选填，多选）")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 12)
            HStack(spacing: 6) {
                ForEach(tagPool.prefix(3), id: \.self) { t in
                    SelectChip(label: t, selected: selectedTags.contains(t)) {
                        toggleTag(t)
                    }
                }
            }
            .padding(.top, 6)
            HStack(spacing: 6) {
                ForEach(tagPool.dropFirst(3), id: \.self) { t in
                    SelectChip(label: t, selected: selectedTags.contains(t)) {
                        toggleTag(t)
                    }
                }
            }
            .padding(.top, 6)

            // 进房方式：邀请制暂不放开（服务端 mode=invite 能力保留，仅创建入口隐藏）
            Text("进房方式")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 12)
            HStack(spacing: 6) {
                ForEach([("public", "公开"), ("approval", "审批制")], id: \.0) { wire, label in
                    SelectChip(label: label, selected: mode == wire) { mode = wire }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)

            // 提交
            Button(action: create) {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    }
                    Text(busy ? "开房中…" : "开房并进入")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background {
                    if busy || title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Capsule().fill(LinearGradient(colors: [Color(red: 0x5A/255, green: 0x5A/255, blue: 0x62/255), Color(red: 0x3A/255, green: 0x3A/255, blue: 0x42/255)], startPoint: .leading, endPoint: .trailing))
                    } else {
                        Capsule().fill(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                    }
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 16)

            Text("开房门槛由服务端校验（未入座本店 / 未实名 / 已有在营房间）")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // 开房失败弹窗（面板底部一行小红字不显眼，改弹窗明示：未入座/未实名/在营上限）
        .alert("开不了房间", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("\(error ?? "")\n开房门槛：本店入座 + 实名认证 + 一人一店一间在营")
        }
    }

    private func toggleTag(_ t: String) {
        if selectedTags.contains(t) {
            selectedTags.remove(t)
        } else {
            selectedTags.insert(t)
        }
    }

    private func create() {
        guard !busy, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                let tags = selectedTags.sorted().joined(separator: ",")
                let id = try await VoiceRoomAPI.createRoom(
                    storeId: storeId,
                    title: title.trimmingCharacters(in: .whitespaces),
                    tags: tags.isEmpty ? nil : tags,
                    mode: mode)
                onCreated(id)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

/// 表演区小房间列表（对齐安卓 RoomListSheet；20s 轮询刷新，进房失败由房间页自动退回列表）。
/// 预览入口保留可达性（roomId=-1 的壳）。
struct VoiceRoomListSheet: View {

    let storeId: Int64
    let rooms: [LobbyVoiceRoom]
    /// 外部触发的刷新（宿主页 20s 轮询 / 打开面板即刷）
    let onRefresh: () -> Void
    let onEnter: (LobbyVoiceRoom) -> Void
    let onPreview: () -> Void
    let onCreate: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                HStack(spacing: 8) {
                    Text("表演区小房间")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LobbyColors.ivory)
                    Text("\(rooms.count) 间在营")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                }

                if rooms.isEmpty {
                    VStack(spacing: 12) {
                        Text("今晚暂无小房间 · 开一个吧")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                        HStack(spacing: 8) {
                            Button {
                                onCreate()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "mic").font(.system(size: 11))
                                    Text("开小房间")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                onPreview()
                            } label: {
                                Text("预览界面")
                                    .font(.system(size: 11))
                                    .foregroundStyle(LobbyColors.goldLight)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .overlay(Capsule().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 12)
                } else {
                    ForEach(rooms) { room in
                        roomRow(room)
                            .padding(.top, 8)
                    }
                    // 开房入口
                    Button {
                        onCreate()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mic")
                                .font(.system(size: 11))
                                .foregroundStyle(LobbyColors.goldLight)
                            Text("开小房间")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(LobbyColors.goldLight)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(Capsule().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }

                Text("开房门槛：本店入座 + 实名 + 一人一店一间在营；进房后即可语音与公屏")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .task {
            onRefresh()
            // 20s 轮询刷新（保持列表新鲜）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                onRefresh()
            }
        }
    }

    private func roomRow(_ room: LobbyVoiceRoom) -> some View {
        HStack(spacing: 10) {
            AppAvatar(url: nil, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.title ?? "未命名房间")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(LobbyColors.ivory)
                    .lineLimit(1)
                Text("\(room.ownerNickname ?? "") · \(voiceRoomModeLabel(room.mode)) · 麦上 \(room.micOccupied ?? 0)/\(room.micTotal ?? 8)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "mic").font(.system(size: 10))
                Text("进房")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [LobbyColors.crimson, LobbyColors.crimsonTail], startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { onEnter(room) }
    }
}
