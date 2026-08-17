import SwiftUI
import PhotosUI

/// 聊天页 — 单聊/群聊（对齐安卓 ChatScreen）
/// 支持：文本 / 图片(双指缩放预览) / 礼物 / 表情包 / 红包 / 帖子分享卡片 / 引用 / 历史翻页
struct ChatView: View {

    let peerId: String
    let isGroup: Bool
    var title: String? = nil
    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = ChatViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var quote: ChatMessage?
    @State private var panel: PanelKind?
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImageUrl: String?
    @State private var showGiftPanel = false
    @State private var showRedPacketSend = false
    @State private var openPacketId: Int64?
    @State private var detailPostId: Int64?
    @State private var peerProfileId: Int64?
    /// 已滚到的最新消息 id（区分首次瞬时定位 vs 后续动画滚动）
    @State private var lastScrolledMsg: String?

    private enum PanelKind { case actions, stickers }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                messageList
                quoteBar
                inputBar
                if panel == .actions { actionPanel }
                if panel == .stickers { stickerPanel }
            }
        }
        .onAppear { vm.initIm(peerId: peerId, isGroup: isGroup) }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        // 图片预览（双指缩放，复用广场原生组件）
        .fullScreenCover(isPresented: Binding(
            get: { previewImageUrl != nil },
            set: { if !$0 { previewImageUrl = nil } }
        )) {
            if let url = previewImageUrl {
                ImagePreviewViewer(images: [url], initialIndex: 0)
            }
        }
        // 送礼面板
        .sheet(isPresented: $showGiftPanel) {
            GiftPanelSheet(
                receiverId: Int64(peerId) ?? 0,
                toName: vm.peerName ?? "TA",
                onClose: { showGiftPanel = false },
                onSent: { gift in vm.sendGiftMessage(gift: gift) }
            )
            .presentationDetents([.medium])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        // 发红包
        .sheet(isPresented: $showRedPacketSend) {
            RedPacketSendView(scene: isGroup ? 2 : 1, targetId: peerId) { packetId, greeting, walletType in
                showRedPacketSend = false
                vm.sendRedPacketMessage(packetId: packetId, greeting: greeting, walletType: walletType)
            }
            .presentationDetents([.large])
            .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
        }
        // 开红包
        .sheet(isPresented: Binding(
            get: { openPacketId != nil },
            set: { if !$0 { openPacketId = nil } }
        )) {
            if let pid = openPacketId {
                RedPacketOpenSheet(packetId: pid)
                    .presentationDetents([.medium])
                    .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
            }
        }
        // 帖子详情
        .fullScreenCover(isPresented: Binding(
            get: { detailPostId != nil },
            set: { if !$0 { detailPostId = nil } }
        )) {
            if let id = detailPostId {
                PostDetailView(postId: id)
            }
        }
        // 用户主页
        .fullScreenCover(isPresented: Binding(
            get: { peerProfileId != nil },
            set: { if !$0 { peerProfileId = nil } }
        )) {
            if let id = peerProfileId {
                UserProfileView(userId: id)
            }
        }
        .onChange(of: photoItem) { _, item in sendPickedImage(item) }
        .photosPicker(isPresented: $showSystemPicker, selection: $photoItem, matching: .images)
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
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
                if !isGroup {
                    AppAvatar(url: vm.peerAvatar, size: 34,
                              frameURL: vm.peerAvatarFrame,
                              frameScale: vm.peerAvatarFrameScale)
                        .frame(width: 34, height: 34)
                        .onTapGesture { peerProfileId = Int64(peerId) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title ?? vm.peerName ?? (isGroup ? "群聊" : "私聊"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(1)
                    if let ln = vm.peerLevelName {
                        Text("\(ln) · Lv.\(vm.peerLevelNum ?? 1)")
                            .font(.system(size: 9))
                            .foregroundStyle(Noir.gold)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Rectangle().fill(Noir.goldLine).frame(height: 1)
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.isLoadingMore {
                        ProgressView().tint(Noir.gold).scaleEffect(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                    } else if vm.hasMoreHistory {
                        Text("加载更早的消息…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .onAppear { vm.loadMoreHistory() }
                    }
                    ForEach(vm.messages) { msg in
                        messageRow(msg)
                            .id(msg.localId)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: vm.messages.last?.localId) { _, last in
                // 新消息（尾部追加）才滚到底；加载更早历史（头部前插）last 不变，不打扰阅读位置
                // 首次进会话瞬时定位到底——动画会被布局/图片加载打断而停在半空（对齐安卓 firstScroll）
                guard let last else { return }
                let first = lastScrolledMsg == nil
                lastScrolledMsg = last
                // 延迟到下一 runloop，等 LazyVStack 布局完成再滚
                DispatchQueue.main.async {
                    if first {
                        proxy.scrollTo(last, anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func messageRow(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.isMine { Spacer(minLength: 40) }
            if !msg.isMine {
                AppAvatar(url: msg.senderAvatar, size: 36,
                          frameURL: msg.senderAvatarFrame,
                          frameScale: msg.senderAvatarFrameScale)
                    .frame(width: 36, height: 36)
                    .onTapGesture { peerProfileId = Int64(msg.senderId) }
            }
            VStack(alignment: msg.isMine ? .trailing : .leading, spacing: 3) {
                if isGroup, !msg.isMine {
                    Text(msg.senderName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                if let quoteText = msg.quoteText {
                    HStack(spacing: 4) {
                        Rectangle().fill(Noir.gold.opacity(0.5)).frame(width: 2)
                        Text("\(msg.quoteSenderName ?? "")：\(quoteText)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
                bubble(msg)
            }
            if msg.isMine {
                AppAvatar(url: vm.myAvatar, size: 36,
                          frameURL: msg.senderAvatarFrame,
                          frameScale: msg.senderAvatarFrameScale)
                    .frame(width: 36, height: 36)
            }
            if !msg.isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: msg.isMine ? .trailing : .leading)
        .contentShape(Rectangle())
        .onLongPressGesture { quote = msg }
    }

    // MARK: - 气泡

    @ViewBuilder
    private func bubble(_ msg: ChatMessage) -> some View {
        switch msg.kind {
        case .text:
            Text(msg.text)
                .font(.system(size: 14.5))
                .foregroundStyle(msg.isMine ? .white : Noir.ivory)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(msg.isMine
                            ? AnyShapeStyle(LinearGradient(colors: [Noir.crimsonDeep, Noir.wine], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Noir.noir2))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        case .image:
            let thumb = msg.imageThumbUrl ?? msg.imageUrl ?? ""
            Group {
                if thumb.hasPrefix("http") || thumb.hasPrefix("/") {
                    if thumb.hasPrefix("http") {
                        AsyncImage(url: URL(string: thumb)) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Noir.noir3
                            }
                        }
                    } else if let ui = UIImage(contentsOfFile: thumb) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    }
                }
            }
            .frame(maxWidth: 180, maxHeight: 240)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                previewImageUrl = msg.imageUrl ?? msg.imageThumbUrl
            }
        case .gift:
            HStack(spacing: 10) {
                GiftIconView(icon: msg.giftIcon, size: 44, scale: CGFloat(msg.giftScale) / 100)
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.giftName ?? "礼物")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                    Text(msg.giftToName.map { "赠予 \($0) ×\(msg.giftCount)" } ?? "×\(msg.giftCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(10)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
        case .sticker:
            if let pack = msg.stickerPack, let name = msg.stickerName,
               let path = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "stickers/\(pack)"),
               let ui = UIImage(contentsOfFile: path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
            } else {
                Text("[表情]")
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.ivory)
            }
        case .redPacket:
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(red: 0xF5/255, green: 0xD0/255, blue: 0x8A/255))
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.redPacketGreeting ?? "恭喜发财，大吉大利")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(msg.redPacketToName.map { "仅 \($0) 可领取" } ?? "\(walletTypeLabel(msg.redPacketWalletType))红包")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 220, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0xC8/255, green: 0x3A/255, blue: 0x2E/255), Color(red: 0xA0/255, green: 0x20/255, blue: 0x1C/255)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { if let pid = msg.redPacketId { openPacketId = pid } }
        case .postShare:
            HStack(spacing: 10) {
                if let cover = msg.postCover, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Noir.noir3
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.postTitle ?? "分享帖子")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Noir.ivory)
                        .lineLimit(2)
                    Text("帖子")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(10)
            .frame(width: 220, alignment: .leading)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
            .onTapGesture { if let pid = msg.postId { detailPostId = pid } }
        }
    }

    // MARK: - 引用条

    @ViewBuilder
    private var quoteBar: some View {
        if let quote {
            HStack {
                Rectangle().fill(Noir.gold).frame(width: 2)
                Text("引用 \(quote.senderName.isEmpty ? "消息" : quote.senderName)：\(quote.text)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer()
                Button { self.quote = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
        }
    }

    // MARK: - 输入区

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("说点什么…", text: $input)
                .noirField()
                .onSubmit { sendText() }
            Button { sendText() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                withAnimation { panel = panel == .actions ? nil : .actions }
            } label: {
                Image(systemName: panel == .actions ? "xmark" : "plus")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255))
    }

    private func sendText() {
        let t = input
        input = ""
        vm.sendText(t, quote: quote)
        quote = nil
    }

    // MARK: - 功能面板

    private var actionPanel: some View {
        HStack(spacing: 0) {
            panelAction("photo", "图片") { panel = nil; showPhotoPicker() }
            panelAction("face.smiling", "表情") { withAnimation { panel = .stickers } }
            panelAction("gift", "礼物") { panel = nil; showGiftPanel = true }
            panelAction("envelope", "红包") { panel = nil; showRedPacketSend = true }
        }
        .padding(.vertical, 14)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255))
    }

    private func panelAction(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)],
                                             center: .center, startRadius: 0, endRadius: 26))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Noir.gold.opacity(0.32), lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Noir.goldLight)
                }
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 表情包面板

    @State private var stickerPack = "white"

    private var stickerPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(["white", "black"], id: \.self) { pack in
                    Text(pack == "white" ? "白兔" : "黑兔")
                        .font(.system(size: 12, weight: stickerPack == pack ? .bold : .regular))
                        .foregroundStyle(stickerPack == pack ? Noir.gold : .white.opacity(0.4))
                        .onTapGesture { stickerPack = pack }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            let names = StickerAssets.names(pack: stickerPack)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        if let path = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "stickers/\(stickerPack)"),
                           let ui = UIImage(contentsOfFile: path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 52)
                                .onTapGesture {
                                    vm.sendSticker(pack: stickerPack, name: name)
                                    withAnimation { panel = nil }
                                }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 180)
        }
        .padding(.top, 8)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255))
    }

    // MARK: - 图片发送

    private func showPhotoPicker() { showSystemPicker = true }
    @State private var showSystemPicker = false

    private func sendPickedImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let jpeg = ui.jpegData(compressionQuality: 0.85) else { return }
            // IM 图片消息需要本地文件路径
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("imimg_\(Int(Date().timeIntervalSince1970)).jpg")
            try? jpeg.write(to: file)
            vm.sendImage(localPath: file.path)
            photoItem = nil
        }
    }
}

// MARK: - 表情包资源

enum StickerAssets {
    /// 列出包内文件名（Resources/stickers/{pack}/*.png）
    static func names(pack: String) -> [String] {
        guard let dir = Bundle.main.url(forResource: "stickers/\(pack)", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.filter { $0.lowercased().hasSuffix(".png") }.sorted()
    }
}
