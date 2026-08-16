import SwiftUI
import PhotosUI

/// 发布帖子 — 对齐安卓 CreatePostScreen（v1：图片帖；视频发布需转码/截帧，后续迁移）
struct CreatePostView: View {

    @StateObject private var vm = CreatePostViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶栏
                HStack {
                    Button("取消") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundStyle(Noir.textDim)
                    Spacer()
                    Text("发布")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Button { vm.publish() } label: {
                        Text(vm.isPublishing ? "发布中…" : "发布")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(vm.canPublish && !vm.isPublishing
                                ? LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing)))
                    }
                    .disabled(!vm.canPublish || vm.isPublishing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Rectangle().fill(Noir.goldLine).frame(height: 1).opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        imageSection
                        textSection
                        metaSection
                        paidSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }

            if let err = vm.errorMessage {
                VStack {
                    Spacer()
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Noir.noir3.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 60)
                        .transition(.opacity)
                        .onAppear {
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await MainActor.run { withAnimation { vm.errorMessage = nil } }
                            }
                        }
                }
            }
        }
        .onChange(of: pickedItems) { _, items in
            vm.addImages(items)
            pickedItems = []
        }
        .onChange(of: vm.created) { _, created in
            if created {
                NotificationCenter.default.post(name: .jjtPostCreated, object: nil)
                dismiss()
            }
        }
    }

    // MARK: - 图片区

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("图片")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Noir.textDim)

            let cellW = (JJTMetrics.screenWidth - 40 - 20) / 3
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: 10), count: 3), spacing: 10) {
                ForEach(vm.images) { item in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cellW, height: cellW)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.hairlineGold, lineWidth: 1))

                        // 上传状态
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
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(Noir.crimsonHot)
                                    Text("点击重试")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .frame(width: cellW, height: cellW)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { vm.retry(item.id) }
                        }

                        // 删除
                        Button { vm.remove(item.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(radius: 2)
                        }
                        .padding(5)
                    }
                }

                // 添加按钮（最多 9 张）
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

    // MARK: - 文案区

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题（首行即标题）", text: $vm.title)
                .font(.system(size: 15, weight: .semibold))
                .noirField()
                .onChange(of: vm.title) { _, v in if v.count > 100 { vm.title = String(v.prefix(100)) } }

            ZStack(alignment: .topLeading) {
                if vm.content.isEmpty {
                    Text("分享今晚的暗夜穿搭 / 派对见闻…")
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.textFaint)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 21)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $vm.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .onChange(of: vm.content) { _, v in if v.count > 3000 { vm.content = String(v.prefix(3000)) } }
            }
            .background(Noir.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairline))
        }
    }

    // MARK: - 话题 / 地点

    private var metaSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("#")
                    .foregroundStyle(Noir.crimsonHot)
                    .font(.system(size: 14, weight: .semibold))
                TextField("话题（空格分隔，如 哥特 茶会）", text: $vm.topics)
                    .font(.system(size: 13))
            }
            .noirField()

            HStack(spacing: 8) {
                Image(systemName: "mappin")
                    .foregroundStyle(Noir.crimsonHot)
                    .font(.system(size: 13))
                TextField("地点（选填）", text: $vm.location)
                    .font(.system(size: 13))
            }
            .noirField()
        }
    }

    // MARK: - 付费设置

    private var paidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Noir.gold)
                    .font(.system(size: 13))
                Text("付费密语")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Toggle("", isOn: $vm.paidEnabled)
                    .tint(Noir.crimson)
                    .labelsHidden()
            }
            if vm.paidEnabled {
                HStack(spacing: 8) {
                    TextField("价格（兔币）", text: $vm.paidPrice)
                        .font(.system(size: 13))
                        .keyboardType(.numberPad)
                        .noirField()
                    Text("兔币")
                        .font(.system(size: 12))
                        .foregroundStyle(Noir.textDim)
                }
                Text("未解锁的用户将看到虚化遮罩，支付后可见全文")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.textFaint)
            }
        }
        .padding(14)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
    }
}

// MARK: - ViewModel

@MainActor
final class CreatePostViewModel: ObservableObject {

    struct ImageItem: Identifiable {
        let id = UUID()
        let image: UIImage
        /// 上传完成的远端 URL；nil = 上传中
        var url: String?
        var failed = false
    }

    @Published var images: [ImageItem] = []
    @Published var title = ""
    @Published var content = ""
    @Published var topics = ""
    @Published var location = ""
    @Published var paidEnabled = false
    @Published var paidPrice = ""
    @Published var isPublishing = false
    @Published var errorMessage: String?
    @Published var created = false

    var canPublish: Bool {
        let full = (title + content).trimmingCharacters(in: .whitespacesAndNewlines)
        return !full.isEmpty && !images.isEmpty && images.allSatisfy { $0.url != nil }
    }

    /// 相册选图：先上屏占位，再后台压缩上传（对齐安卓 addImages）
    func addImages(_ items: [PhotosPickerItem]) {
        for item in items {
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { continue }
                let entry = ImageItem(image: img)
                images.append(entry)
                await upload(id: entry.id)
            }
        }
    }

    func retry(_ id: UUID) {
        guard let i = images.firstIndex(where: { $0.id == id }) else { return }
        images[i].failed = false
        Task { await upload(id: id) }
    }

    func remove(_ id: UUID) {
        images.removeAll { $0.id == id }
    }

    private func upload(id: UUID) async {
        guard let i = images.firstIndex(where: { $0.id == id }) else { return }
        guard let data = images[i].image.jpegData(compressionQuality: 0.82) else {
            images[i].failed = true
            return
        }
        do {
            let url = try await APIClient.shared.uploadFile(data: data, filename: "post_\(id.uuidString.prefix(8)).jpg", mime: "image/jpeg")
            if let j = images.firstIndex(where: { $0.id == id }) {
                images[j].url = url
            }
        } catch {
            if let j = images.firstIndex(where: { $0.id == id }) {
                images[j].failed = true
            }
        }
    }

    func publish() {
        // 标题 + 正文合并为 content（首行即标题，与详情页解析一致）
        let full = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? content.trimmingCharacters(in: .whitespacesAndNewlines)
            : title.trimmingCharacters(in: .whitespaces) + "\n" + content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { errorMessage = "请输入内容"; return }
        guard !images.isEmpty else { errorMessage = "请至少选择一张图片"; return }
        guard images.allSatisfy({ $0.url != nil }) else { errorMessage = "图片还在上传中…"; return }

        let topicList = topics
            .split(whereSeparator: { " ，,".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }

        isPublishing = true
        Task {
            do {
                _ = try await SocialAPI.createPost(CreatePostReq(
                    mediaType: "image",
                    images: images.compactMap(\.url),
                    video: nil,
                    videoCover: nil,
                    content: full,
                    topics: topicList.isEmpty ? nil : topicList,
                    location: location.isEmpty ? nil : location,
                    latitude: nil,
                    longitude: nil,
                    cityCode: nil,
                    cityName: nil,
                    paidPrice: paidEnabled ? Int(paidPrice) : nil,
                    previewSeconds: nil
                ))
                isPublishing = false
                created = true
            } catch {
                isPublishing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
