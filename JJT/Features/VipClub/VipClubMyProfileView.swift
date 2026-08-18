import SwiftUI
import PhotosUI

/// 我的蜜兔会档案（对齐安卓 VipClubMyProfileScreen）
/// 背景图 / 会内头像 / 写真相册（增删）/ 想遇到的人 / 交友目的 / 个人简介 → 保存
struct VipClubMyProfileView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var saving = false
    @State private var background: String?
    @State private var clubAvatar: String?
    @State private var photos: [String] = []
    @State private var wantToMeet = ""
    @State private var purpose = ""
    @State private var bio = ""
    @State private var uploading = false
    @State private var error: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadTarget: UploadTarget = .album
    @State private var showRequests = false

    private enum UploadTarget { case background, avatar, album }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            backgroundSection
                            avatarSection
                            albumSection
                            fieldLabel("想遇到的人")
                            TextField("如：成熟稳重的同行者", text: $wantToMeet)
                                .noirField()
                            fieldLabel("交友目的")
                            TextField("如：长期伴侣 / 朋友 / 玩伴", text: $purpose)
                                .noirField()
                            fieldLabel("个人简介")
                            TextEditor(text: $bio)
                                .font(.system(size: 13))
                                .foregroundStyle(Noir.ivory)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 90)
                                .padding(10)
                                .background(Noir.noir2)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
                            saveButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .onAppear { load() }
        .onChange(of: photoItem) { _, item in uploadPhoto(item) }
        .fullScreenCover(isPresented: $showRequests) {
            VipClubViewRequestsView()
        }
        .alert("提示", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("知道了") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
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
            VStack(spacing: 2) {
                Text("我的档案")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("MY PROFILE")
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Button { showRequests = true } label: {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 背景图

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("主页背景图")
            PhotosPicker(selection: Binding(
                get: { photoItem },
                set: { uploadTarget = .background; photoItem = $0 }
            ), matching: .images) {
                ZStack {
                    Color.white.opacity(0.04)
                    if let bg = background, !bg.isEmpty {
                        WebImage(url: webImageURL(bg), contentMode: .fill) { Color.clear }
                    }
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20))
                        Text(background == nil ? "上传背景图" : "更换背景图")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.hairlineGold, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(uploading)
        }
    }

    // MARK: - 会内头像

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("会内头像（不设置则用本站头像）")
            HStack(spacing: 14) {
                ZStack {
                    if let ca = clubAvatar, !ca.isEmpty {
                        WebImage(url: webImageURL(ca), contentMode: .fill) { Color.white.opacity(0.05) }
                    } else {
                        Color.white.opacity(0.05)
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                PhotosPicker(selection: Binding(
                    get: { photoItem },
                    set: { uploadTarget = .avatar; photoItem = $0 }
                ), matching: .images) {
                    Text("上传头像")
                        .font(.system(size: 12))
                        .foregroundStyle(Noir.goldLight)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(Capsule().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(uploading)
                if clubAvatar != nil {
                    Button {
                        clubAvatar = nil
                    } label: {
                        Text("移除")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 写真相册

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("写真相册")
                Spacer()
                Text("\(photos.count)/9")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(photos, id: \.self) { url in
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                WebImage(url: webImageURL(url), contentMode: .fill) {
                                    ProgressView().tint(Noir.gold)
                                }
                            }
                            .clipped()
                        Button {
                            photos.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.7))
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.hairlineGold, lineWidth: 1))
                }
                if photos.count < 9 {
                    PhotosPicker(selection: Binding(
                        get: { photoItem },
                        set: { uploadTarget = .album; photoItem = $0 }
                    ), matching: .images) {
                        ZStack {
                            Color.white.opacity(0.04)
                            if uploading {
                                ProgressView().tint(Noir.gold)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Noir.gold.opacity(0.5))
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Noir.hairlineGold, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                    .disabled(uploading)
                }
            }
        }
    }

    // MARK: - 保存

    private var saveButton: some View {
        Button { save() } label: {
            Text(saving ? "保存中…" : (uploading ? "图片上传中…" : "保存档案"))
                .font(.system(size: 14, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    !saving && !uploading
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.white.opacity(0.08))
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(saving || uploading)
        .padding(.top, 8)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Noir.ivory)
    }

    // MARK: - 数据

    private func load() {
        Task {
            if let d = try? await VipClubAPI.myProfile() {
                background = d.background
                clubAvatar = d.clubAvatar
                photos = d.photoAlbum ?? []
                wantToMeet = d.wantToMeet ?? ""
                purpose = d.purpose ?? ""
                bio = d.bio ?? ""
            }
            isLoading = false
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) {
        guard let item, !uploading else { return }
        let target = uploadTarget
        uploading = true
        Task {
            defer { uploading = false; photoItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                let url = try await APIClient.shared.uploadFile(data: data, filename: "vip_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")
                switch target {
                case .background: background = url
                case .avatar: clubAvatar = url
                case .album: photos.append(url)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            do {
                var req = VipClubProfileUpdateReq()
                req.background = background
                req.clubAvatar = clubAvatar
                if let data = try? JSONSerialization.data(withJSONObject: photos) {
                    req.photoAlbum = String(data: data, encoding: .utf8)
                }
                req.wantToMeet = wantToMeet.isEmpty ? nil : wantToMeet
                req.purpose = purpose.isEmpty ? nil : purpose
                req.bio = bio.isEmpty ? nil : bio
                _ = try await VipClubAPI.updateMyProfile(req)
                saving = false
                jjtShowToast("档案已保存")
                if let onBack { onBack() } else { dismiss() }
            } catch {
                saving = false
                self.error = error.localizedDescription
            }
        }
    }
}

/// 查看申请（谁想看我的档案，对齐安卓 VipClubViewRequestsScreen）
struct VipClubViewRequestsView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var requests: [VipClubViewRequest] = []
    @State private var handled: Set<Int64> = []
    @State private var isLoading = true
    @State private var error: String?

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
                    Text("查看申请")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                Rectangle().fill(Noir.goldLine).frame(height: 1)

                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if requests.isEmpty {
                    Spacer()
                    Text("暂无查看申请")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(requests) { req in
                                requestRow(req)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .onAppear { load() }
        .alert("提示", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("知道了") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func requestRow(_ req: VipClubViewRequest) -> some View {
        let done = handled.contains(req.requestId)
        return HStack(spacing: 12) {
            AppAvatar(url: req.avatar, size: 44)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.nickname ?? "用户\(req.requesterId)")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Text("申请查看你的完整资料")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            if done {
                Text("已处理")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                HStack(spacing: 12) {
                    Button { handle(req, approved: true) } label: {
                        Text("同意")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Color(red: 0x66/255, green: 0xBB/255, blue: 0x6A/255).opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { handle(req, approved: false) } label: {
                        Text("拒绝")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Noir.crimsonHot)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Noir.crimsonHot.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.hairlineGold, lineWidth: 1))
    }

    private func load() {
        Task {
            requests = (try? await VipClubAPI.incomingViewRequests())?.list ?? []
            isLoading = false
        }
    }

    private func handle(_ req: VipClubViewRequest, approved: Bool) {
        Task {
            do {
                _ = try await VipClubAPI.handleViewRequest(requestId: req.requestId, approved: approved)
                handled.insert(req.requestId)
                jjtShowToast(approved ? "已同意" : "已拒绝")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
