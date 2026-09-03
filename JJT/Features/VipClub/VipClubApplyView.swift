import SwiftUI
import PhotosUI

/// 申请入会（对齐安卓 VipClubApplyScreen）
/// 动态问卷（questionsJson）+ 想遇到的人 + 交友目的 + 写真上传（最多 6 张）→ 提交审核
struct VipClubApplyView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var info: VipClubInfo?
    @State private var isLoading = true
    @State private var questions: [VipClubQuestion] = []
    @State private var answers: [Int: String] = [:]
    @State private var wantToMeet = ""
    @State private var purpose = ""
    @State private var photos: [String] = []
    @State private var uploading = false
    @State private var submitting = false
    @State private var submitted = false
    @State private var error: String?
    @State private var photoItem: PhotosPickerItem?

    private var canSubmit: Bool {
        let missing = questions.first { $0.required && (answers[$0.index]?.trimmingCharacters(in: .whitespaces).isEmpty != false) }
        return missing == nil && !photos.isEmpty && !uploading && !submitting
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if submitted {
                    submittedState
                } else {
                    formState
                }
            }
        }
        .jjtPageGestures()
        .onAppear { load() }
        .onChange(of: photoItem) { _, item in uploadPhoto(item) }
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
                Text("申请入会")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                Text("APPLICATION")
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 提交成功

    private var submittedState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Color(red: 0x12/255, green: 0x0C/255, blue: 0x04/255)],
                                         center: .center, startRadius: 0, endRadius: 60))
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(Noir.goldLight.opacity(0.6), lineWidth: 1.5))
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Noir.goldLight)
            }
            Text("申请已提交")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Noir.goldText)
            Text("创始团队将尽快审核你的入会资格\n审核结果将通过官方号通知")
                .font(.system(size: 12))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Text("返回")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 11)
                    .background(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - 表单

    private var formState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 问卷
                ForEach(questions, id: \.index) { q in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(q.question)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Noir.ivory)
                            if q.required {
                                Text("*")
                                    .foregroundStyle(Noir.crimsonHot)
                            }
                        }
                        TextField("请输入", text: Binding(
                            get: { answers[q.index] ?? "" },
                            set: { answers[q.index] = $0 }
                        ))
                        .noirField()
                    }
                }

                fieldLabel("想遇到的人")
                TextField("如：成熟稳重的同行者", text: $wantToMeet)
                    .noirField()

                fieldLabel("交友目的")
                TextField("如：长期伴侣 / 朋友 / 玩伴", text: $purpose)
                    .noirField()

                // 写真上传
                HStack(spacing: 4) {
                    fieldLabel("写真照片")
                    Text("*")
                        .foregroundStyle(Noir.crimsonHot)
                    Spacer()
                    Text("\(photos.count)/6")
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
                    if photos.count < 6 {
                        PhotosPicker(selection: $photoItem, matching: .images) {
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

                Text("照片将用于会员资料展示，请上传真实清晰的照片")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))

                Button { submit() } label: {
                    Text(submitting ? "提交中…" : (uploading ? "图片上传中…" : "提交审核"))
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            canSubmit
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Noir.ivory)
    }

    // MARK: - 数据

    private func load() {
        Task {
            info = try? await VipClubAPI.info()
            questions = VipClubQuestion.parse(info?.questionsJson)
            isLoading = false
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) {
        guard let item, !uploading else { return }
        uploading = true
        Task {
            defer { uploading = false; photoItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                let url = try await APIClient.shared.uploadFile(data: data, filename: "photo_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")
                photos.append(url)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard canSubmit else {
            if photos.isEmpty { error = "请至少上传一张写真照片" }
            else { error = "请完整填写必填项" }
            return
        }
        submitting = true
        Task {
            do {
                // answersJson：{"0":"答案","1":"答案"}（对齐安卓 JSONArray 对象形式）
                var obj: [String: String] = [:]
                for q in questions {
                    if let a = answers[q.index], !a.isEmpty { obj[String(q.index)] = a }
                }
                let answersData = try JSONSerialization.data(withJSONObject: obj)
                let photoData = try JSONSerialization.data(withJSONObject: photos)
                var req = VipClubApplyReq()
                req.answersJson = String(data: answersData, encoding: .utf8)
                req.wantToMeet = wantToMeet.isEmpty ? nil : wantToMeet
                req.purpose = purpose.isEmpty ? nil : purpose
                req.photoUrls = String(data: photoData, encoding: .utf8)
                _ = try await VipClubAPI.apply(req)
                submitting = false
                submitted = true
            } catch {
                submitting = false
                self.error = error.localizedDescription
            }
        }
    }
}
