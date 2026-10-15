import SwiftUI
import PhotosUI

// MARK: - 报名三态（对齐安卓 ActivitySignupSection）
// 未报名（规则卡+上传+提交）/ 审核中 / 已通过（入店凭证卡）/ 已拒绝（原因+重报）。
// 布局对齐 v74 原型；颜色/装饰/文案一律从 ActivityTheme 令牌取，不写死活动皮肤。

/// SignupInfo.status：0待审 1通过 2拒绝
enum SignupStatus {
    static let pending = 0
    static let approved = 1
    static let rejected = 2
}

/// 穿搭照上限（仅图片，不支持视频；与服务端 MAX_SIGNUP_IMGS 一致）
let maxSignupPhotos = 6

// MARK: - 表单模型

@MainActor
final class ActivitySignupFormModel: ObservableObject {
    struct Photo: Identifiable {
        let id = UUID()
        let image: UIImage
        var url: String?
        var failed = false
        var uploading = false
    }

    @Published var photos: [Photo] = []
    @Published var look = ""
    @Published var submitting = false
    /// 本人昵称（凭证卡展示，后台富化：失败静默）
    @Published var nickname: String?

    func loadNickname() {
        Task {
            if let u = try? await UserAPI.getUserInfo() {
                nickname = u.nickname
            }
        }
    }

    /// 加入选中照片：超上限截断并提示；逐张上传（对齐 iOS 参赛上传范式：选图即传）
    func addPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let room = maxSignupPhotos - photos.count
        if room <= 0 {
            jjtShowToast("最多上传 \(maxSignupPhotos) 张")
            return
        }
        if items.count > room {
            jjtShowToast("最多上传 \(maxSignupPhotos) 张，多余照片未加入")
        }
        for item in items.prefix(room) {
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                let photo = Photo(image: img, uploading: true)
                photos.append(photo)
                await upload(id: photo.id)
            }
        }
    }

    func removePhoto(_ id: UUID) { photos.removeAll { $0.id == id } }

    func retryUpload(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }), !photos[i].uploading else { return }
        photos[i].failed = false
        photos[i].uploading = true
        Task { await upload(id: id) }
    }

    private func upload(id: UUID) async {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        let image = photos[i].image
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            markFailed(id); return
        }
        do {
            let url = try await APIClient.shared.uploadFile(
                data: data, filename: "signup_\(id.uuidString.prefix(8)).jpg", mime: "image/jpeg")
            if let j = photos.firstIndex(where: { $0.id == id }) {
                photos[j].url = url
                photos[j].uploading = false
            }
        } catch {
            markFailed(id)
        }
    }

    private func markFailed(_ id: UUID) {
        if let j = photos.firstIndex(where: { $0.id == id }) {
            photos[j].failed = true
            photos[j].uploading = false
        }
    }

    func setLook(_ s: String) { look = String(s.prefix(64)) }

    var canSubmit: Bool {
        !photos.isEmpty && !submitting && !photos.contains { $0.uploading }
    }

    /// 提交报名：全部照片已上传成功才可提交；成功后由调用方刷新活动详情（三态真源是服务端 mySignup）
    func submit(activityId: Int64, onSubmitted: @escaping () -> Void) {
        if submitting { return }
        guard !photos.isEmpty else {
            jjtShowToast("先选择穿搭照")
            return
        }
        guard !photos.contains(where: { $0.uploading }) else {
            jjtShowToast("照片上传中，请稍候")
            return
        }
        let urls = photos.compactMap { $0.url }
        guard urls.count == photos.count else {
            jjtShowToast("有照片上传失败，请点击重试")
            return
        }
        submitting = true
        let lookText = look.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await ActivityAPI.signup(id: activityId, imgs: urls, look: lookText.isEmpty ? nil : lookText)
                submitting = false
                onSubmitted()
            } catch {
                submitting = false
                jjtShowToast(error.localizedDescription)
            }
        }
    }
}

// MARK: - 三态主体

struct ActivitySignupSection: View {
    let activity: ActivityInfo
    let theme: ActivityTheme
    var rules: String?
    var forceForm: Bool = false
    var onResign: () -> Void = {}
    var onWallClick: () -> Void = {}
    var onRefresh: () -> Void = {}

    @StateObject private var form = ActivitySignupFormModel()

    private var my: SignupInfo? { activity.mySignup }

    var body: some View {
        VStack(spacing: 0) {
            if let my, my.status == SignupStatus.pending, !forceForm {
                PendingCard(theme: theme, my: my, onWallClick: onWallClick)
            } else if let my, my.status == SignupStatus.approved, !forceForm {
                PassCard(
                    theme: theme, my: my, nickname: form.nickname,
                    onWallClick: onWallClick, onResign: onResign
                )
            } else {
                if let my, my.status == SignupStatus.rejected {
                    RejectedReasonCard(reason: my.rejectReason)
                    Spacer().frame(height: 16)
                }
                SignupRulesCard(theme: theme, rules: rules)
                SignupFormArea(
                    theme: theme,
                    form: form,
                    submitText: my != nil ? "重新提交报名 · 等待审核" : "提交报名 · 等待审核",
                    onSubmit: { form.submit(activityId: activity.id, onSubmitted: onRefresh) }
                )
            }
        }
        .padding(.horizontal, 20)
        .onAppear { form.loadNickname() }
    }
}

// MARK: - 流程条（活动页头部渲染，v74 原型）

struct ActivitySignupFlowStrip: View {
    let theme: ActivityTheme
    let my: SignupInfo?
    var forceForm: Bool = false

    private var step: Int {
        guard let my else { return 0 }
        if my.status == SignupStatus.pending, !forceForm { return 1 }
        if my.status == SignupStatus.approved, !forceForm { return 2 }
        return 0
    }

    private let items: [(icon: String, label: String)] = [
        ("photo.badge.plus", "上传穿搭"),
        ("clock", "等待审核"),
        ("checkmark.seal", "凭证入店"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 {
                    // 分隔线与步骤图标圆圈水平居中：容器高 32（=圆圈）内垂直居中；两侧各 10 等距
                    Spacer().frame(width: 10)
                    Rectangle().fill(theme.accent.opacity(0.3))
                        .frame(width: 20, height: 1)
                        .frame(width: 20, height: 32, alignment: .center)
                    Spacer().frame(width: 10)
                }
                let reached = step >= i
                let current = step == i
                let approvedDone = my?.status == SignupStatus.approved && !forceForm && i == 2
                let mark = approvedDone ? activityPassGreen : theme.accent
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(mark.opacity(current ? 0.2 : 0.08))
                            .overlay(Circle().stroke(mark.opacity(reached ? 0.45 : 0.2), lineWidth: 1))
                        Image(systemName: items[i].icon)
                            .font(.system(size: 13))
                            .foregroundStyle(mark.opacity(reached ? 1 : 0.55))
                    }
                    .frame(width: 32, height: 32)
                    Text(items[i].label)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.22), lineWidth: 1))
    }
}

// MARK: - 报名规则卡（仅表单态显示）

private struct SignupRulesCard: View {
    let theme: ActivityTheme
    let rules: String?

    var body: some View {
        if let rules, !rules.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                    Text("报名规则")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
                Spacer().frame(height: 10)
                ForEach(Array(rules.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.enumerated()), id: \.offset) { _, line in
                    Text(line.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 9.5))
                        .lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.25), lineWidth: 1))
            .padding(.top, 16)
        }
    }
}

// MARK: - 上传表单

private struct SignupFormArea: View {
    let theme: ActivityTheme
    @ObservedObject var form: ActivitySignupFormModel
    let submitText: String
    let onSubmit: () -> Void

    @State private var pickedItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("上传穿搭照")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Text(form.photos.isEmpty ? "仅图片 · 最多 \(maxSignupPhotos) 张" : "已选 \(form.photos.count)/\(maxSignupPhotos)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer().frame(height: 8)
            if form.photos.isEmpty {
                pickerBox(height: 150) {
                    VStack(spacing: 0) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 26))
                            .foregroundStyle(theme.accent.opacity(0.7))
                        Spacer().frame(height: 8)
                        Text("点击选择穿搭照片")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer().frame(height: 3)
                        Text("仅限图片（不支持视频）· 越完整越容易通过")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            } else {
                photoStrip
                Spacer().frame(height: 6)
                Text("第一张将作为主图展示在穿搭墙与凭证卡")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(height: 12)
            lookInput
            Spacer().frame(height: 20)
            submitButton
            Spacer().frame(height: 10)
            Text("提交后进入人工审核 · 结果以消息通知 · 通过即生成入店凭证")
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            form.addPhotos(items)
            pickedItems = []
        }
    }

    private func pickerBox(height: CGFloat, @ViewBuilder content: @escaping () -> some View) -> some View {
        PhotosPicker(
            selection: $pickedItems,
            maxSelectionCount: maxSignupPhotos - form.photos.count,
            matching: .images
        ) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(theme.accent.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.accent.opacity(0.45), lineWidth: 1.5)
                )
        }
    }

    /// 已选照片：缩略图行（逐张删除 + 上传态/失败重试）+ 追加格
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(form.photos.enumerated()), id: \.element.id) { i, photo in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(i == 0 ? theme.accent : Color.white.opacity(0.1),
                                            lineWidth: i == 0 ? 1.5 : 1)
                            )
                        // 主图角标（左下，渐变底）
                        if i == 0 {
                            VStack {
                                Spacer()
                                HStack {
                                    Text("主图")
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(theme.buttonGradient)
                                        .clipShape(UnevenRoundedRectangle(
                                            topLeadingRadius: 0, bottomLeadingRadius: 12,
                                            bottomTrailingRadius: 0, topTrailingRadius: 8))
                                    Spacer()
                                }
                            }
                            .frame(width: 96, height: 96)
                        }
                        // 上传中 / 失败重试
                        if photo.uploading {
                            ZStack {
                                Color.black.opacity(0.45)
                                ProgressView().tint(.white).scaleEffect(0.8)
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if photo.failed {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                Text("上传失败 · 点重试")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .frame(width: 96, height: 96)
                            .background(Color.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                            .onTapGesture { form.retryUpload(photo.id) }
                        }
                        // 删除
                        Button {
                            form.removePhoto(photo.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
                if form.photos.count < maxSignupPhotos {
                    PhotosPicker(
                        selection: $pickedItems,
                        maxSelectionCount: maxSignupPhotos - form.photos.count,
                        matching: .images
                    ) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.accent.opacity(0.7))
                            .frame(width: 96, height: 96)
                            .background(theme.accent.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.accent.opacity(0.45), lineWidth: 1.5)
                            )
                    }
                }
            }
        }
    }

    private var lookInput: some View {
        HStack(spacing: 10) {
            Text("造型名")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            TextField("", text: Binding(
                get: { form.look },
                set: { form.setLook($0) }
            ), prompt: Text("选填 · 给穿搭起个名字").foregroundStyle(.white.opacity(0.2)))
                .font(.system(size: 11))
                .foregroundStyle(Noir.ivory)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent.opacity(0.18), lineWidth: 1))
    }

    private var submitButton: some View {
        Button(action: onSubmit) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                Text(form.submitting ? "提交中 …" : submitText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(theme.buttonGradient)
            .clipShape(Capsule())
            .opacity(form.submitting ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!form.canSubmit)
    }
}

// MARK: - 审核中

private struct PendingCard: View {
    let theme: ActivityTheme
    let my: SignupInfo
    let onWallClick: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.12))
                    .overlay(Circle().stroke(theme.accent.opacity(0.5), lineWidth: 1))
                Image(systemName: "clock")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.accent.opacity(pulse ? 1 : 0.45))
            }
            .frame(width: 64, height: 64)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            Spacer().frame(height: 12)
            Text("报名审核中")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Noir.ivory)
            Spacer().frame(height: 4)
            Text("审核通过后将生成入店凭证 · 请留意消息通知")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            Spacer().frame(height: 16)
            // 我的报名卡
            HStack(spacing: 12) {
                WebImage(url: webImageURL(my.img), contentMode: .fill) { Color.white.opacity(0.05) }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("我的报名")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Noir.ivory)
                    if let look = my.look, !look.isEmpty {
                        Text("「\(look)」")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer()
                Text("审核中")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.accent.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.5), lineWidth: 1))
            }
            .padding(10)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.2), lineWidth: 1))
            Spacer().frame(height: 12)
            Button(action: onWallClick) {
                Text("先去逛逛穿搭墙 →")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 已通过：入店凭证卡（flow-border 质感）

private struct PassCard: View {
    let theme: ActivityTheme
    let my: SignupInfo
    let nickname: String?
    let onWallClick: () -> Void
    let onResign: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 凭证框：外层 accent 边 + 内层暗色渐变（对齐 v71 flow-border 质感）
            VStack(spacing: 0) {
                HStack {
                    Text(theme.passLabel)
                        .font(.system(size: 9, design: .serif))
                        .italic()
                        .tracking(3)
                        .foregroundStyle(theme.accent)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 8))
                            .foregroundStyle(activityPassGreen)
                        Text("审核通过")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(activityPassGreen)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(activityPassGreen.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(activityPassGreen.opacity(0.5), lineWidth: 1))
                }
                Spacer().frame(height: 14)
                HStack(spacing: 14) {
                    WebImage(url: webImageURL(my.img), contentMode: .fill) { Color.white.opacity(0.05) }
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(theme.accent.opacity(0.55), lineWidth: 1.5)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nickname ?? "我的凭证")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Noir.ivory)
                        if let look = my.look, !look.isEmpty {
                            Text("「\(look)」")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.accent)
                        }
                        Text(my.ticketNo ?? "-")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                }
                Spacer().frame(height: 16)
                Rectangle().fill(Color.white.opacity(0.27)).frame(height: 0.5)
                Spacer().frame(height: 10)
                HStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                    Text("到店出示本凭证 · 着报名服饰入店")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(red: 0x17 / 255, green: 0x10 / 255, blue: 0x0A / 255),
                             Color(red: 0x12 / 255, green: 0x0A / 255, blue: 0x0D / 255)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .padding(1)
            .background(theme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent, lineWidth: 1.5))

            Spacer().frame(height: 16)
            HStack(spacing: 10) {
                Button(action: onWallClick) {
                    Text("去看穿搭墙")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(theme.buttonGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onResign) {
                    Text("重新报名")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 已拒绝：原因卡

private struct RejectedReasonCard: View {
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("报名未通过")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Noir.crimsonHot)
            if let reason, !reason.isEmpty {
                Spacer().frame(height: 3)
                Text("原因：\(reason)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer().frame(height: 2)
            Text("修改后可重新提交")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Noir.crimson.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.crimson.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 「我的报名」分隔标语（v74 原型）

struct ActivitySignupMineDivider: View {
    let theme: ActivityTheme

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, theme.accent.opacity(0.4)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            if !theme.deco.isEmpty {
                Text(theme.deco)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.accent.opacity(0.7))
                    .padding(.leading, 6)
            }
            Text("我 的 报 名")
                .font(.system(size: 9.5))
                .tracking(2.5)
                .foregroundStyle(theme.accent.opacity(0.7))
                .padding(.horizontal, 6)
            LinearGradient(colors: [theme.accent.opacity(0.4), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}
