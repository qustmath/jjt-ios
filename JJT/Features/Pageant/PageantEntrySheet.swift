import SwiftUI
import PhotosUI

/// 参选/编辑作品半屏弹层（对齐安卓 PageantEntrySheet）：
/// 照片 1~9 张（不限比例） + 视频选填（≤15 秒，转码 720p + 抽封面） + 简述 ≤20 字。
/// 已参赛打开即编辑模式（预填，编辑保留票数）；作者可删除作品（票数清零下榜）。
struct PageantEntrySheet: View {

    @StateObject private var vm = PageantEntrySheetModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.textDim)
                Spacer()
                Text(vm.isEditing ? "编辑参赛作品" : "我要参选")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                Spacer()
                Button { vm.submit() } label: {
                    Text(vm.submitting ? "提交中…" : (vm.isEditing ? "保存" : "提交"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(vm.canSubmit ? Noir.crimsonHot : .white.opacity(0.3))
                }
                .disabled(!vm.canSubmit || vm.submitting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Rectangle().fill(Noir.goldLine).frame(height: 1).opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 审核拒绝原因（编辑模式，机审拒绝可改重交）
                    if let remark = vm.auditRemark, !remark.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Noir.crimsonHot)
                            Text("审核未通过：\(remark)（修改后可重新提交）")
                                .font(.system(size: 11))
                                .foregroundStyle(Noir.crimsonHot.opacity(0.9))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Noir.crimson.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    photoSection
                    videoSection
                    lineSection

                    // 删除作品（仅编辑模式；删除后票数清零下榜）
                    if vm.isEditing {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Text("删除我的参赛作品")
                                .font(.system(size: 13))
                                .foregroundStyle(Noir.crimsonHot)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.crimsonHot.opacity(0.4), lineWidth: 1))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(Noir.noir.ignoresSafeArea())
        .onAppear { vm.loadExisting() }
        .onChange(of: pickedItems) { _, items in
            vm.addImages(items)
            pickedItems = []
        }
        .onChange(of: pickedVideo) { _, item in
            if let item { vm.addVideo(item) }
            pickedVideo = nil
        }
        .onChange(of: vm.submitted) { _, ok in if ok { dismiss() } }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("知道了") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .confirmationDialog("删除后票数清零并下榜，确定删除参赛作品？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { vm.deleteEntry() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 照片区（1~9 张）

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("参赛照片")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Text("1~9 张 · 第一张为封面")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.textFaint)
            }
            let cellW = (JJTMetrics.screenWidth - 40 - 20) / 3
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: 10), count: 3), spacing: 10) {
                ForEach(vm.images) { item in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let remote = item.remoteURL {
                                AsyncImage(url: webImageURL(remote)) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir3 }
                                }
                            } else {
                                Image(uiImage: item.image).resizable().scaledToFill()
                            }
                        }
                        .frame(width: cellW, height: cellW)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.hairlineGold, lineWidth: 1))

                        if item.url == nil && !item.failed {
                            ZStack {
                                Color.black.opacity(0.45)
                                ProgressView().tint(.white)
                            }
                            .frame(width: cellW, height: cellW)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else if item.failed {
                            ZStack {
                                Color.black.opacity(0.55)
                                Text("上传失败")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(width: cellW, height: cellW)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button { vm.removeImage(item.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(radius: 2)
                        }
                        .padding(5)
                    }
                }
                if vm.images.count < 9 {
                    PhotosPicker(selection: $pickedItems, maxSelectionCount: 9 - vm.images.count, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 22))
                                .foregroundStyle(Noir.gold.opacity(0.7))
                            Text("\(vm.images.count)/9")
                                .font(.system(size: 10))
                                .foregroundStyle(Noir.textFaint)
                        }
                        .frame(width: cellW, height: cellW)
                        .background(Noir.noir2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.hairlineGold, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                }
            }
        }
    }

    // MARK: - 视频区（选填 ≤15 秒）

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("参赛视频")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Text("选填 · 15 秒内")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.textFaint)
            }
            if vm.videoUrl != nil || vm.videoStage != nil {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let cover = vm.videoCoverLocal {
                            Image(uiImage: cover).resizable().scaledToFill()
                        } else if let remote = vm.videoCoverUrl {
                            AsyncImage(url: webImageURL(remote)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Noir.noir3 }
                            }
                        } else {
                            Noir.noir3
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        Group {
                            if vm.videoStage == "compressing" {
                                overlayLabel("视频压缩中…", spinner: true)
                            } else if vm.videoStage == "uploading" {
                                overlayLabel("视频上传中…", spinner: true)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    )
                    Button { vm.removeVideo() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 2)
                    }
                    .padding(8)
                }
                .frame(height: 150)
            } else {
                PhotosPicker(selection: $pickedVideo, matching: .videos) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.badge.plus")
                            .foregroundStyle(Noir.gold.opacity(0.7))
                        Text("添加参赛视频")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Noir.noir2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
            }
        }
    }

    // MARK: - 简述（≤20 字）

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("参赛宣言")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Text("≤20 字")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.textFaint)
                Spacer()
                Text("\(vm.line.count)/20")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.textFaint)
            }
            TextField("一句话介绍你的暗夜之姿", text: $vm.line)
                .font(.system(size: 13))
                .noirField()
                .onChange(of: vm.line) { _, v in if v.count > 20 { vm.line = String(v.prefix(20)) } }
        }
    }

    private func overlayLabel(_ text: String, spinner: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.5)
            HStack(spacing: 8) {
                if spinner { ProgressView().tint(.white).scaleEffect(0.9) }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class PageantEntrySheetModel: ObservableObject {

    struct EntryImage: Identifiable {
        let id = UUID()
        let image: UIImage
        /// 编辑模式回填的远端图
        var remoteURL: String?
        var url: String?
        var failed = false
    }

    @Published var images: [EntryImage] = []
    @Published var videoUrl: String?
    @Published var videoCoverUrl: String?
    @Published var videoCoverLocal: UIImage?
    @Published var videoStage: String? // compressing / uploading
    @Published var line = ""
    @Published var isEditing = false
    @Published var auditRemark: String?
    @Published var submitting = false
    @Published var submitted = false
    @Published var error: String?

    var canSubmit: Bool {
        !line.trimmingCharacters(in: .whitespaces).isEmpty
            && !images.isEmpty
            && images.allSatisfy { $0.url != nil }
            && videoStage == nil
    }

    /// 编辑模式：拉我的作品预填（对齐安卓 loadExisting；编辑保留票数）
    func loadExisting() {
        Task {
            guard let entry = try? await PageantAPI.myEntry() else { return }
            isEditing = true
            auditRemark = entry.auditStatus == 2 ? entry.auditRemark : nil
            line = entry.line ?? ""
            images = (entry.images ?? []).map { url in
                EntryImage(image: placeholderImage(), remoteURL: url, url: url)
            }
            videoUrl = entry.video
            videoCoverUrl = entry.videoCover
        }
    }

    func addImages(_ items: [PhotosPickerItem]) {
        for item in items {
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                let entry = EntryImage(image: img)
                images.append(entry)
                await upload(id: entry.id)
            }
        }
    }

    func removeImage(_ id: UUID) { images.removeAll { $0.id == id } }

    private func upload(id: UUID) async {
        guard let i = images.firstIndex(where: { $0.id == id }) else { return }
        guard let data = images[i].image.jpegData(compressionQuality: 0.82) else {
            images[i].failed = true
            return
        }
        do {
            let url = try await APIClient.shared.uploadFile(data: data, filename: "pageant_\(id.uuidString.prefix(8)).jpg", mime: "image/jpeg")
            if let j = images.firstIndex(where: { $0.id == id }) { images[j].url = url }
        } catch {
            if let j = images.firstIndex(where: { $0.id == id }) { images[j].failed = true }
        }
    }

    /// 选视频 → 15 秒校验 → 转码 720p → 抽封面 → 分别上传（对齐安卓 addVideo）
    func addVideo(_ item: PhotosPickerItem) {
        Task {
            guard let picked = try? await item.loadTransferable(type: PickedVideo.self) else { return }
            let duration = await VideoTranscoder.durationSeconds(picked.url)
            // 上限 15 秒（0.5s 容差，对齐安卓 VIDEO_MAX_MS + 500）
            if duration > 15 {
                error = "参赛视频需 15 秒内"
                return
            }
            videoUrl = nil
            videoCoverUrl = nil
            videoCoverLocal = nil
            videoStage = "compressing"
            let coverData = await VideoTranscoder.captureCover(picked.url)
            if let coverData { videoCoverLocal = UIImage(data: coverData) }
            guard let out = await VideoTranscoder.transcode720p(picked.url) else {
                videoStage = nil
                error = "视频处理失败，请重试"
                return
            }
            videoStage = "uploading"
            do {
                let videoData = try Data(contentsOf: out)
                let vurl = try await APIClient.shared.uploadFile(data: videoData, filename: "pageant_video_\(UUID().uuidString.prefix(8)).mp4", mime: "video/mp4")
                var curl: String?
                if let coverData {
                    curl = try? await APIClient.shared.uploadFile(data: coverData, filename: "pageant_cover_\(UUID().uuidString.prefix(8)).jpg", mime: "image/jpeg")
                }
                videoUrl = vurl
                videoCoverUrl = curl
                videoStage = nil
            } catch {
                videoStage = nil
                self.error = "视频上传失败，请重试"
            }
            try? FileManager.default.removeItem(at: out)
        }
    }

    func removeVideo() {
        videoUrl = nil
        videoCoverUrl = nil
        videoCoverLocal = nil
        videoStage = nil
    }

    func submit() {
        let l = line.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { error = "请填写参赛宣言"; return }
        guard !images.isEmpty, images.allSatisfy({ $0.url != nil }) else { error = "照片还在上传中…"; return }
        submitting = true
        Task {
            do {
                let req = PageantEntrySaveReq(
                    images: images.compactMap(\.url),
                    video: videoUrl,
                    videoCover: videoCoverUrl,
                    line: l
                )
                _ = isEditing ? try await PageantAPI.updateEntry(req) : try await PageantAPI.join(req)
                submitting = false
                submitted = true
                jjtShowToast(isEditing ? "作品已保存" : "参选成功，审核通过后公开展示")
            } catch let e as APIError {
                submitting = false
                if case .business(_, let msg) = e { error = msg } else { error = "提交失败，请重试" }
            } catch {
                submitting = false
                self.error = "提交失败，请重试"
            }
        }
    }

    func deleteEntry() {
        Task {
            if (try? await PageantAPI.deleteEntry()) == true {
                jjtShowToast("作品已删除")
                submitted = true
            } else {
                error = "删除失败，请重试"
            }
        }
    }

    private func placeholderImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
