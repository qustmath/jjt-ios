import SwiftUI
import PhotosUI

/// 话题规则（对齐安卓 TopicRules 与服务端清洗管线，ADR 0014）：
/// ≤5 个、单个 ≤20 字（码点）；合法字符 中英文/数字/emoji；归一化 = 全半角统一 + 小写；展示名保留输入写法
enum TopicRules {
    static let maxTopics = 5
    static let maxLength = 20

    /// 合法字符：字母/数字/emoji（含肤色修饰、ZWJ、VS16、键帽符）；与服务端正则一致
    private static let validRegex = try! NSRegularExpression(
        pattern: "^[\\p{L}\\p{N}\\p{So}\\u200D\\uFE0F\\u20E3\\U0001F3FB-\\U0001F3FF]+$")

    /// 全角 → 半角（全角 ASCII 变体平移；全角空格转半角）
    static func toHalfWidth(_ s: String) -> String {
        String(s.unicodeScalars.map { sc -> Character in
            switch sc.value {
            case 0x3000: return " "
            case 0xFF01...0xFF5E: return Character(UnicodeScalar(sc.value - 0xFEE0)!)
            default: return Character(sc)
            }
        })
    }

    /// 输入态预归一化（宽松，便于连续输入）：全半角统一、去 #、去空格、限长
    static func preNormalizeInput(_ s: String) -> String {
        let t = toHalfWidth(s).replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "")
        return String(t.prefix(maxLength))
    }

    /// 提交态校验（与服务端同规则）：合法返回展示名，非法返回空串
    static func finalize(_ raw: String) -> String {
        let name = toHalfWidth(raw).replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.unicodeScalars.count <= maxLength else { return "" }
        let range = NSRange(name.startIndex..., in: name)
        return validRegex.firstMatch(in: name, range: range) != nil ? name : ""
    }

    /// 归一化键（chips 去重用）
    static func normKey(_ name: String) -> String {
        toHalfWidth(name).trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// 发布帖子 — 对齐安卓 CreatePostScreen：图文/视频双形态、话题 chips（实时补全）、POI 地点选择、付费密语
/// editPostId 非空为编辑模式：回填原帖内容，保存走 update
struct CreatePostView: View {

    /// 编辑模式的帖子 id；nil = 新发布
    var editPostId: Int64? = nil
    /// 预填内容（测评分享等场景，对齐安卓 initialContent；首行拆为标题）
    var initialContent: String = ""

    @StateObject private var vm = CreatePostViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showPoiPicker = false
    @State private var showRealname = false
    @FocusState private var topicFocused: Bool

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
                    Text(editPostId == nil ? "发布" : "编辑作品")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Button { vm.publish(editPostId: editPostId) } label: {
                        Text(vm.isPublishing ? "保存中…" : (publishBusyHint ?? (editPostId == nil ? "发布" : "保存")))
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
                        mediaSection
                        textSection
                        // 纯文字帖（未选媒体）：文字卡片模板选择（对齐安卓 TextCardStyleRow）
                        if vm.mediaType == "image", vm.images.isEmpty {
                            textCardStyleRow
                        }
                        topicSection
                        poiSection
                        paidSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                // 发布中锁定整个表单，不可再编辑（对齐需求：发布时不可再编辑作品）
                .disabled(vm.isPublishing)
                .opacity(vm.isPublishing ? 0.5 : 1)
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
        .onAppear {
            if let editPostId { vm.loadForEdit(editPostId) }
            else if !initialContent.isEmpty { vm.initContent(initialContent) }
        }
        .onChange(of: pickedItems) { _, items in
            vm.addImages(items)
            pickedItems = []
        }
        .onChange(of: pickedVideo) { _, item in
            if let item { vm.loadPickedVideo(item) }
            pickedVideo = nil
        }
        .onChange(of: vm.created) { _, created in
            if created {
                NotificationCenter.default.post(name: .jjtPostCreated, object: nil)
                dismiss()
            }
        }
        .sheet(isPresented: $showPoiPicker) {
            PoiPickerView { poi in
                vm.selectedPoi = poi
                showPoiPicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Noir.noir)
        }
        // 发布前实名检查：未认证 → 引导去认证（对齐安卓 needRealname）
        .alert("需要实名认证", isPresented: Binding(
            get: { vm.needRealname },
            set: { if !$0 { vm.needRealname = false } }
        )) {
            Button("去认证") {
                vm.needRealname = false
                showRealname = true
            }
            Button("取消", role: .cancel) { vm.needRealname = false }
        } message: {
            Text("发布内容需要先完成实名认证")
        }
        .fullScreenCover(isPresented: $showRealname) {
            RealnameVerifyView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    /// 发布按钮忙碌提示（图片上传中/视频压缩中/视频上传中）
    private var publishBusyHint: String? {
        if vm.videoStage == "compressing" { return "视频压缩中…" }
        if vm.videoStage == "uploading" { return "视频上传中…" }
        if vm.isUploading { return "图片上传中…" }
        return nil
    }

    // MARK: - 媒体区（图文 / 视频）

    @ViewBuilder
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 形态切换（还没选内容时可切；对齐安卓 setMediaType）
            if vm.images.isEmpty, vm.videoUrl == nil, editPostId == nil {
                Picker("形态", selection: Binding(
                    get: { vm.mediaType },
                    set: { vm.setMediaType($0) }
                )) {
                    Text("图文").tag("image")
                    Text("视频").tag("video")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if vm.mediaType == "video" {
                videoSection
            } else {
                Text("图片")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Noir.textDim)
                imageGrid
            }
        }
    }

    // MARK: - 图片区

    private var imageGrid: some View {
        let cellW = (JJTMetrics.screenWidth - 40 - 20) / 3
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: 10), count: 3), spacing: 10) {
            ForEach(vm.images) { item in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let remote = item.remoteURL {
                            // 编辑模式回填的远端图
                            AsyncImage(url: webImageURL(remote)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Noir.noir3
                                }
                            }
                        } else {
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                        }
                    }
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

    // MARK: - 视频区（对齐安卓：选视频 → 720p 转码 → 抽封面 → 上传）

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("视频")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Noir.textDim)

            if vm.videoUrl != nil || vm.videoStage != nil || vm.videoError {
                ZStack(alignment: .topTrailing) {
                    ZStack {
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
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        Group {
                            if vm.videoStage == "compressing" {
                                statusOverlay("视频压缩中…", spinner: true)
                            } else if vm.videoStage == "uploading" {
                                statusOverlay("视频上传中…", spinner: true)
                            } else if vm.videoError {
                                statusOverlay("处理失败，点击重选", spinner: false)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button { vm.removeVideo() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 2)
                    }
                    .padding(8)
                }
                .frame(height: 200)
            } else {
                PhotosPicker(selection: $pickedVideo, matching: .videos) {
                    VStack(spacing: 8) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 26))
                            .foregroundStyle(Noir.gold.opacity(0.7))
                        Text("选择视频（将压缩为 720p）")
                            .font(.system(size: 11))
                            .foregroundStyle(Noir.textFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Noir.noir2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
            }
        }
    }

    private func statusOverlay(_ text: String, spinner: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 8) {
                if spinner { ProgressView().tint(.white) }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
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

    // MARK: - 文字卡片模板选择（纯文字帖，对齐安卓 TextCardStyleRow）

    private var textCardStyleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文字卡片封面")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 10) {
                ForEach(TextCardRenderer.styles.indices, id: \.self) { i in
                    let style = TextCardRenderer.styles[i]
                    let isSel = i == vm.textCardStyle
                    Button { vm.textCardStyle = i } label: {
                        Text(style.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(isSel ? 0.95 : 0.5))
                            .frame(width: 52, height: 68)
                            .background(LinearGradient(colors: [Color(style.startColor), Color(style.endColor)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                isSel ? Noir.gold : Color.white.opacity(0.12), lineWidth: isSel ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("不选图片时，将按所选模板把文字生成封面图")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    // MARK: - 话题 chips（ADR 0014：逐条添加/单独删除/实时补全）

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("#")
                    .foregroundStyle(Noir.crimsonHot)
                    .font(.system(size: 14, weight: .semibold))
                TextField("话题（空格/# 确认，最多 5 个）", text: Binding(
                    get: { vm.topicInput },
                    set: { vm.onTopicInputChange($0) }
                ))
                .font(.system(size: 13))
                .focused($topicFocused)
                .onSubmit {
                    vm.commitTopicInput()
                }
            }
            .noirField()

            // 已选 chips
            if !vm.topicList.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(vm.topicList, id: \.self) { t in
                        HStack(spacing: 4) {
                            Text("#\(t)")
                                .font(.system(size: 11))
                                .foregroundStyle(Noir.crimsonHot)
                            Button { vm.removeTopic(t) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Noir.wine.opacity(0.35))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Noir.hairlineRed, lineWidth: 1))
                    }
                }
            }

            // 实时补全建议
            if topicFocused, !vm.topicSuggestions.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(vm.topicSuggestions) { s in
                        Button {
                            vm.addTopic(s.name ?? "")
                        } label: {
                            HStack(spacing: 4) {
                                Text("#\(s.name ?? "")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Noir.ivory)
                                if let n = s.useCount {
                                    Text("\(n)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 地点（POI 选择）

    private var poiSection: some View {
        Button { showPoiPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin")
                    .foregroundStyle(Noir.crimsonHot)
                    .font(.system(size: 13))
                if let poi = vm.selectedPoi {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(poi.title ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(1)
                        if let addr = poi.address, !addr.isEmpty {
                            Text(addr)
                                .font(.system(size: 10))
                                .foregroundStyle(Noir.textFaint)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { vm.selectedPoi = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("添加地点（选填）")
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.textFaint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .noirField()
        }
        .buttonStyle(.plain)
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
                // 视频帖：试看时长设置（对齐安卓 previewSeconds）
                if vm.mediaType == "video" {
                    HStack(spacing: 8) {
                        TextField("试看秒数（0 = 不可试看）", text: $vm.previewSeconds)
                            .font(.system(size: 13))
                            .keyboardType(.numberPad)
                            .noirField()
                        Text("秒")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.textDim)
                    }
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

// MARK: - POI 选择器（周边 + 搜索；对齐安卓 CreatePostScreen POI 弹层）

private struct PoiPickerView: View {

    let onSelect: (PoiInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var nearby: [PoiInfo] = []
    @State private var results: [PoiInfo] = []
    @State private var locating = true
    @State private var denied = false
    @State private var searchTask: Task<Void, Never>?

    private var shown: [PoiInfo] { keyword.isEmpty ? nearby : results }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择地点")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
                Spacer()
                Button("取消") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.textDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.35))
                    .font(.system(size: 13))
                TextField("搜索地点", text: $keyword)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                    .onChange(of: keyword) { _, v in scheduleSearch(v) }
            }
            .noirField()
            .padding(.horizontal, 16)

            if locating, keyword.isEmpty {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else if denied, keyword.isEmpty {
                VStack(spacing: 8) {
                    Text("定位未授权，可使用上方搜索找地点")
                        .font(.system(size: 12))
                        .foregroundStyle(Noir.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(30)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { poi in
                        Button {
                            onSelect(poi)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(Noir.crimsonHot)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(poi.title ?? "")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Noir.ivory)
                                        .lineLimit(1)
                                    Text(poi.address ?? "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Noir.textFaint)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let d = poi.distance {
                                    Text(d >= 1000 ? String(format: "%.1fkm", Double(d) / 1000) : "\(d)m")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.leading, 42)
                    }
                    if !keyword.isEmpty, results.isEmpty {
                        Text("没有找到相关地点")
                            .font(.system(size: 12))
                            .foregroundStyle(Noir.textFaint)
                            .padding(30)
                    }
                }
            }
        }
        .background(Noir.noir.ignoresSafeArea())
        .task { await loadNearby() }
    }

    private func loadNearby() async {
        guard let c = await CityLocator.shared.currentCoordinate() else {
            denied = true
            locating = false
            return
        }
        nearby = (try? await GeoAPI.nearbyPois(latitude: c.latitude, longitude: c.longitude)) ?? []
        locating = false
    }

    private func scheduleSearch(_ kw: String) {
        searchTask?.cancel()
        guard !kw.isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let city = await CityLocator.shared.currentCity()
            let c = await CityLocator.shared.currentCoordinate()
            results = (try? await GeoAPI.searchPoi(keyword: kw, cityName: city, latitude: c?.latitude, longitude: c?.longitude)) ?? []
        }
    }
}

// MARK: - ViewModel

@MainActor
final class CreatePostViewModel: ObservableObject {

    struct ImageItem: Identifiable {
        let id = UUID()
        let image: UIImage
        /// 编辑模式下回填的远端图（无需上传）
        var remoteURL: String?
        /// 上传完成的远端 URL；nil = 上传中
        var url: String?
        var failed = false
    }

    @Published var mediaType = "image" // image / video
    @Published var images: [ImageItem] = []
    @Published var title = ""
    @Published var content = ""
    /// 纯文字帖：文字卡片模板下标（TextCardRenderer.styles），发布时本地生图上传为封面
    @Published var textCardStyle = 0
    /// 实名引导弹窗（发布前检查，对齐安卓 needRealname）
    @Published var needRealname = false
    // 话题 chips（ADR 0014）
    @Published var topicList: [String] = []
    @Published var topicInput = ""
    @Published var topicSuggestions: [TopicInfo] = []
    // 地点（POI）
    @Published var selectedPoi: PoiInfo?
    // 视频
    @Published var videoUrl: String?
    @Published var videoCoverUrl: String?
    @Published var videoCoverLocal: UIImage?
    @Published var videoStage: String? // compressing / uploading
    @Published var videoError = false
    @Published var videoDurationSec = 0

    @Published var paidEnabled = false
    @Published var paidPrice = ""
    @Published var previewSeconds = ""
    @Published var isPublishing = false
    @Published var errorMessage: String?
    @Published var created = false

    /// 已选视频（转码重试用）
    private var pickedVideoURL: URL?
    private var suggestTask: Task<Void, Never>?

    /// 有图片正在上传（占位未上传完且未失败）
    var isUploading: Bool {
        images.contains { $0.url == nil && !$0.failed }
    }

    var canPublish: Bool {
        let full = (title + content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return false }
        if mediaType == "video" {
            // 视频形态：选了视频就必须处理完；没选视频按纯文字帖（降级 text/文字卡片）
            return videoUrl != nil && videoStage == nil && !videoError
        }
        // 图文形态：图片和文字至少发一种；有图则需全部传完（含失败重试中）；无图按纯文字帖
        if !images.isEmpty { return images.allSatisfy { $0.url != nil } }
        return true
    }

    /// 切换媒体形态（清空另一侧内容，对齐安卓 setMediaType）
    func setMediaType(_ t: String) {
        guard t != mediaType else { return }
        mediaType = t
        images = []
        removeVideo()
    }

    // ---- 图片 ----

    /// 相册选图：先上屏占位，再后台压缩上传（对齐安卓 addImages）
    func addImages(_ items: [PhotosPickerItem]) {
        for item in items {
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
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

    // ---- 视频（对齐安卓 setVideo：读时长 → 抽封面 → 720p 转码 → 上传） ----

    func loadPickedVideo(_ item: PhotosPickerItem) {
        Task {
            guard let picked = try? await item.loadTransferable(type: PickedVideo.self) else { return }
            await setVideo(picked.url)
        }
    }

    func setVideo(_ url: URL) async {
        pickedVideoURL = url
        videoDurationSec = await VideoTranscoder.durationSeconds(url)
        mediaType = "video"
        images = []
        videoUrl = nil
        videoCoverUrl = nil
        videoCoverLocal = nil
        videoStage = "compressing"
        videoError = false

        let coverData = await VideoTranscoder.captureCover(url)
        if let coverData { videoCoverLocal = UIImage(data: coverData) }

        guard let out = await VideoTranscoder.transcode720p(url) else {
            videoStage = nil
            videoError = true
            return
        }
        videoStage = "uploading"
        do {
            let videoData = try Data(contentsOf: out)
            let vurl = try await APIClient.shared.uploadFile(data: videoData, filename: "postvideo_\(UUID().uuidString.prefix(8)).mp4", mime: "video/mp4")
            var curl: String?
            if let coverData {
                curl = try? await APIClient.shared.uploadFile(data: coverData, filename: "postcover_\(UUID().uuidString.prefix(8)).jpg", mime: "image/jpeg")
            }
            videoUrl = vurl
            videoCoverUrl = curl
            videoStage = nil
        } catch {
            videoStage = nil
            videoError = true
        }
        try? FileManager.default.removeItem(at: out)
    }

    func removeVideo() {
        videoUrl = nil
        videoCoverUrl = nil
        videoCoverLocal = nil
        videoStage = nil
        videoError = false
        videoDurationSec = 0
        pickedVideoURL = nil
    }

    // ---- 话题 chips ----

    /// 话题输入（对齐安卓 setTopicInput）：#/＃ 作为分隔符逐词提交（与服务端拆分语义一致），
    /// 空格/逗号不触发提交（预归一化时会去掉）；本地预归一化（去空格，≤20 字）并触发实时补全（200ms 防抖，失败静默）
    func onTopicInputChange(_ v: String) {
        var pending = v
        if pending.contains("#") || pending.contains("＃") {
            let parts = pending.split(whereSeparator: { $0 == "#" || $0 == "＃" }).map(String.init)
            for part in parts.dropLast() where !TopicRules.finalize(part).isEmpty { addTopic(part) }
            pending = parts.last ?? ""
        }
        let cleaned = TopicRules.preNormalizeInput(pending)
        topicInput = cleaned
        suggestTask?.cancel()
        if cleaned.isEmpty {
            topicSuggestions = []
            return
        }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            topicSuggestions = (try? await SocialAPI.suggestTopics(keyword: cleaned, limit: 10)) ?? []
        }
    }

    /// 输入确认（键盘提交）：把当前输入落为 chip
    func commitTopicInput() {
        addTopic(topicInput)
        topicInput = ""
        topicSuggestions = []
    }

    /// 添加话题 chip（输入确认或点选补全）：本地按服务端同规则校验，按归一化键去重，≤5 个
    func addTopic(_ raw: String) {
        let name = TopicRules.finalize(raw)
        guard !name.isEmpty else {
            if !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                errorMessage = "话题仅支持中英文/数字/emoji，且不超过 20 字"
            }
            return
        }
        if topicList.count >= TopicRules.maxTopics {
            errorMessage = "最多添加 \(TopicRules.maxTopics) 个话题"
            return
        }
        // 归一化后重复：静默忽略（大小写/全半角差异视为同一话题），清输入框（对齐安卓）
        if topicList.contains(where: { TopicRules.normKey($0) == TopicRules.normKey(name) }) {
            topicInput = ""
            topicSuggestions = []
            return
        }
        topicList.append(name)
        topicInput = ""
        topicSuggestions = []
    }

    func removeTopic(_ name: String) {
        topicList.removeAll { $0 == name }
    }

    // ---- 编辑 / 发布 ----

    /// 预填内容（测评分享等，对齐安卓 initContent：首行为标题，其余为正文）
    func initContent(_ raw: String) {
        guard title.isEmpty, content.isEmpty else { return }
        let lines = raw.components(separatedBy: "\n")
        title = lines.first ?? ""
        content = lines.dropFirst().joined(separator: "\n")
    }

    /// 编辑模式：加载原帖回填（对齐安卓 loadForEdit；首行为标题，其余为正文）
    func loadForEdit(_ postId: Int64) {
        Task {
            guard let post = try? await SocialAPI.postDetail(id: postId) else { return }
            let raw = post.content ?? ""
            let lines = raw.components(separatedBy: "\n")
            title = lines.first ?? ""
            content = lines.dropFirst().joined(separator: "\n")
            topicList = post.topics ?? []
            if let place = post.location, !place.isEmpty {
                selectedPoi = PoiInfo(title: place, address: post.cityName, latitude: nil, longitude: nil, cityCode: nil, cityName: post.cityName, distance: nil)
            }
            if let price = post.paidPrice, price > 0 {
                paidEnabled = true
                paidPrice = "\(price)"
                if let sec = post.previewSeconds, sec > 0 { previewSeconds = "\(sec)" }
            }
            if post.mediaType == "video" {
                mediaType = "video"
                videoUrl = post.video
                videoCoverUrl = post.videoCover
            } else {
                images = (post.images ?? []).map { url in
                    ImageItem(image: placeholderImage(), remoteURL: url, url: url)
                }
            }
        }
    }

    private func placeholderImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    func publish(editPostId: Int64? = nil) {
        // 标题 + 正文合并为 content（首行即标题，与详情页解析一致）
        let full = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? content.trimmingCharacters(in: .whitespacesAndNewlines)
            : title.trimmingCharacters(in: .whitespaces) + "\n" + content.trimmingCharacters(in: .whitespacesAndNewlines)
        let isImage = mediaType == "image"
        // 图片和文字至少发一种：无媒体时按纯文字帖发布（对齐安卓）
        let hasMedia = isImage ? !images.isEmpty : (videoUrl != nil)
        guard hasMedia || !full.isEmpty else { errorMessage = "图片和文字至少发一种"; return }
        if isImage, !images.isEmpty {
            guard images.allSatisfy({ $0.url != nil }) else { errorMessage = "图片还在上传中…"; return }
        }
        if !isImage, videoStage != nil { errorMessage = "视频还在处理中…"; return }

        isPublishing = true
        Task {
            // 未实名：弹窗引导去认证，不发起发布（编辑同样需要，对齐安卓 checkRealname）
            guard await checkRealname() else {
                isPublishing = false
                return
            }
            do {
                // 纯文字：本地渲染文字卡片上传作为封面图（上传失败降级为纯文字帖 text）
                var effectiveMediaType = hasMedia ? mediaType : "text"
                var cardImageUrl: String?
                if !hasMedia {
                    let card = TextCardRenderer.render(full, styleIndex: textCardStyle)
                    if let data = card.jpegData(compressionQuality: 0.9) {
                        cardImageUrl = try? await APIClient.shared.uploadFile(
                            data: data, filename: "textcard_\(UUID().uuidString.prefix(8)).jpg", mime: "image/jpeg")
                    }
                    if cardImageUrl != nil { effectiveMediaType = "image" }
                }

                // 话题已是 chips 列表（本地预归一化 + 去重）；服务端清洗管线为最终权威
                let topicsArg = topicList.isEmpty ? nil : topicList
                let previewSec = effectiveMediaType == "video" && paidEnabled
                    ? min(max(Int(previewSeconds) ?? 0, 0), 120) : nil

                if let editPostId {
                    _ = try await SocialAPI.updatePost(UpdatePostReq(
                        id: editPostId,
                        mediaType: effectiveMediaType,
                        images: effectiveMediaType == "image" ? (cardImageUrl.map { [$0] } ?? images.compactMap(\.url)) : nil,
                        video: effectiveMediaType == "video" ? videoUrl : nil,
                        videoCover: effectiveMediaType == "video" ? videoCoverUrl : nil,
                        content: full,
                        topics: topicsArg,
                        location: selectedPoi?.title,
                        latitude: selectedPoi?.latitude,
                        longitude: selectedPoi?.longitude,
                        cityCode: selectedPoi?.cityCode,
                        cityName: selectedPoi?.cityName,
                        paidPrice: paidEnabled ? Int(paidPrice) : nil,
                        previewSeconds: previewSec
                    ))
                } else {
                    _ = try await SocialAPI.createPost(CreatePostReq(
                        mediaType: effectiveMediaType,
                        images: effectiveMediaType == "image" ? (cardImageUrl.map { [$0] } ?? images.compactMap(\.url)) : nil,
                        video: effectiveMediaType == "video" ? videoUrl : nil,
                        videoCover: effectiveMediaType == "video" ? videoCoverUrl : nil,
                        content: full,
                        topics: topicsArg,
                        location: selectedPoi?.title,
                        latitude: selectedPoi?.latitude,
                        longitude: selectedPoi?.longitude,
                        cityCode: selectedPoi?.cityCode,
                        cityName: selectedPoi?.cityName,
                        paidPrice: paidEnabled ? Int(paidPrice) : nil,
                        previewSeconds: previewSec
                    ))
                }
                isPublishing = false
                created = true
                jjtShowToast(editPostId == nil ? "发布成功" : "保存成功")
            } catch {
                isPublishing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 发布前实名检查（对齐安卓 checkRealname：未认证 → 弹窗引导去认证）
    private func checkRealname() async -> Bool {
        do {
            let user = try await UserAPI.getUserInfo()
            if user.realnameStatus == 1 { return true }
            needRealname = true
            return false
        } catch {
            errorMessage = "无法验证实名状态，请重试"
            return false
        }
    }
}
