import SwiftUI
import PhotosUI

/// 发起组局 — 表单 + 城市/门店选择 + 图片上传 + 发布/存草稿（对齐安卓 CreateGroupEventScreen）
/// draftId 非空 = 编辑草稿模式（进入时加载详情回填，发布时先更新再发布）
struct CreateGroupEventView: View {

    var draftId: Int64? = nil
    var onBack: (() -> Unit)? = nil

    @StateObject private var vm = CreateGroupEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showRealname = false

    private struct EventTypeOption: Identifiable {
        let type: Int
        let label: String
        var id: Int { type }
    }

    private static let EVENT_TYPES: [EventTypeOption] = [
        .init(type: 0, label: "聚餐"), .init(type: 1, label: "饮酒"), .init(type: 2, label: "KTV"),
        .init(type: 3, label: "运动"), .init(type: 4, label: "桌游"), .init(type: 5, label: "其他")
    ]

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 14) {
                        coverPicker
                        field("活动名") {
                            TextField("给组局起个名字", text: $vm.title).noirField()
                        }
                        field("类型") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Self.EVENT_TYPES) { opt in
                                        let selected = vm.eventType == opt.type
                                        Text(opt.label)
                                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                            .foregroundStyle(selected ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : Color.white.opacity(0.6))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(selected
                                                        ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing))
                                                        : AnyShapeStyle(Noir.noir2))
                                            .clipShape(Capsule())
                                            .onTapGesture { vm.eventType = opt.type }
                                    }
                                }
                            }
                        }
                        field("时间") {
                            DatePicker("活动时间", selection: $vm.eventDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(Noir.gold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .colorScheme(.dark)
                        }
                        field("城市") {
                            pickerRow(vm.cityName.isEmpty ? "选择城市" : vm.cityName) { vm.showCityPicker = true }
                        }
                        if !vm.storeOptions.isEmpty || vm.cityCode != nil {
                            field("门店") {
                                pickerRow(vm.storeName.isEmpty ? "选择门店" : vm.storeName) {
                                    if !vm.storeOptions.isEmpty { vm.showStorePicker = true }
                                }
                            }
                        }
                        field("人数上限") {
                            TextField("至少 2 人", text: $vm.participantLimit)
                                .keyboardType(.numberPad)
                                .noirField()
                        }
                        field("费用（兔币/人，0 为免费）") {
                            TextField("0", text: $vm.rabbitCoinPrice)
                                .keyboardType(.numberPad)
                                .noirField()
                        }
                        HStack {
                            Text("允许退出")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Toggle("", isOn: $vm.allowQuit)
                                .labelsHidden()
                                .tint(Noir.gold)
                        }
                        .padding(.horizontal, 4)
                        field("详情描述（可选）") {
                            TextEditor(text: $vm.description)
                                .frame(minHeight: 90)
                                .scrollContentBackground(.hidden)
                                .noirField()
                        }
                        field("图集（可选，最多 9 张）") {
                            imagesGrid
                        }
                        actionButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { vm.setup(draftId: draftId) }
        .onChange(of: vm.created) { _, ok in
            if ok {
                jjtShowToast(vm.isDraftMode ? "已保存" : "发布成功")
                if let onBack { onBack() } else { dismiss() }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
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
            Text("发起组局需要先完成实名认证")
        }
        .fullScreenCover(isPresented: $showRealname) {
            RealnameVerifyView()
        }
        // 城市选择
        .sheet(isPresented: $vm.showCityPicker) {
            optionSheet(title: "选择城市", options: vm.cityOptions.map { PickerOption(code: $0.cityCode, name: $0.cityName) }) { code, name in
                vm.setCity(code: code, name: name)
            }
        }
        // 门店选择
        .sheet(isPresented: $vm.showStorePicker) {
            optionSheet(title: "选择门店", options: vm.storeOptions.map { PickerOption(code: Int($0.id), name: $0.name) }) { code, name in
                vm.setStore(id: Int64(code), name: name)
            }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
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
                Text(vm.isDraftMode ? "编辑组局" : "发起组局")
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
        }
    }

    // MARK: - 封面

    private var coverPicker: some View {
        PhotosPicker(selection: $vm.coverItem, matching: .images) {
            ZStack {
                if let url = vm.coverUrl, let u = URL(string: url) {
                    AsyncImage(url: u) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            coverPlaceholder
                        }
                    }
                } else {
                    coverPlaceholder
                }
                if vm.coverUploading {
                    Color.black.opacity(0.4)
                    ProgressView().tint(Noir.gold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onChange(of: vm.coverItem) { _, item in vm.uploadCover(item) }
    }

    private var coverPlaceholder: some View {
        ZStack {
            Noir.noir2
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(Noir.gold.opacity(0.6))
                Text("添加封面")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - 图集

    private var imagesGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(vm.images) { img in
                ZStack(alignment: .topTrailing) {
                    Noir.noir3
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let url = img.remoteUrl, let u = URL(string: url) {
                                AsyncImage(url: u) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    }
                                }
                            } else if let data = img.localData, let ui = UIImage(data: data) {
                                Image(uiImage: ui).resizable().scaledToFill()
                            }
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if img.uploading {
                                ZStack {
                                    Color.black.opacity(0.4)
                                    ProgressView().tint(Noir.gold).scaleEffect(0.8)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    Button { vm.removeImage(img.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(4)
                }
            }
            if vm.images.count < 9 {
                PhotosPicker(selection: $vm.imageItems, maxSelectionCount: 9 - vm.images.count, matching: .images) {
                    ZStack {
                        Noir.noir2
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundStyle(Noir.gold.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Noir.hairlineGold, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .onChange(of: vm.imageItems) { _, items in vm.addImages(items) }
            }
        }
    }

    // MARK: - 通用件

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }

    private func pickerRow(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Noir.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private struct PickerOption: Identifiable {
        let code: Int
        let name: String
        var id: Int { code }
    }

    private func optionSheet(title: String, options: [PickerOption],
                             onPick: @escaping (Int, String) -> Void) -> some View {
        VStack(spacing: 12) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
                .frame(maxWidth: .infinity, alignment: .leading)
            if options.isEmpty {
                Text("暂无可选项")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(30)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(options) { opt in
                            Button { onPick(opt.code, opt.name) } label: {
                                Text(opt.name)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Noir.ivory)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Noir.noir2)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .presentationDetents([.medium])
        .presentationBackground(Color(red: 0x14/255, green: 0x14/255, blue: 0x1A/255))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { vm.saveDraft() } label: {
                Text("存草稿")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Noir.gold.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { vm.publish() } label: {
                Text(vm.isPublishing ? "发布中…" : (vm.isDraftMode ? "发布" : "发布组局"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.isPublishing)
        }
        .padding(.top, 10)
    }
}

// MARK: - ViewModel（对齐安卓 CreateGroupEventViewModel）

@MainActor
final class CreateGroupEventViewModel: ObservableObject {

    struct ImageItem: Identifiable {
        let id = UUID()
        var localData: Data?
        var remoteUrl: String?
        var uploading = false
    }

    @Published var draftId: Int64?
    @Published var coverItem: PhotosPickerItem?
    @Published var coverUrl: String?
    @Published var coverUploading = false
    @Published var title = ""
    @Published var eventType = 0
    @Published var eventDate = Date().addingTimeInterval(86400)
    @Published var cityCode: Int?
    @Published var cityName = ""
    @Published var cityOptions: [EventCityInfo] = []
    @Published var showCityPicker = false
    @Published var storeId: Int64?
    @Published var storeName = ""
    @Published var storeOptions: [StoreOption] = []
    @Published var showStorePicker = false
    @Published var participantLimit = "10"
    @Published var rabbitCoinPrice = "0"
    @Published var allowQuit = true
    @Published var description = ""
    @Published var images: [ImageItem] = []
    @Published var imageItems: [PhotosPickerItem] = []
    @Published var isPublishing = false
    @Published var created = false
    @Published var needRealname = false
    @Published var error: String?

    var isDraftMode: Bool { draftId != nil }

    private var didSetup = false

    func setup(draftId: Int64?) {
        guard !didSetup else { return }
        didSetup = true
        self.draftId = draftId
        Task { cityOptions = (try? await SocialAPI.eventCities()) ?? [] }
        if let draftId {
            Task { await loadDraft(draftId) }
        }
    }

    /// 编辑草稿：加载详情回填
    private func loadDraft(_ id: Int64) async {
        do {
            let d = try await GroupEventAPI.detail(id: id)
            title = d.title ?? ""
            eventType = d.eventType ?? 0
            if let t = d.eventTime {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                f.locale = Locale(identifier: "en_US_POSIX")
                if let date = f.date(from: String(t.prefix(16))) { eventDate = date }
            }
            cityCode = d.cityCode
            storeId = d.storeId
            storeName = d.storeName ?? ""
            participantLimit = "\(d.participantLimit ?? 10)"
            rabbitCoinPrice = "\(d.rabbitCoinPrice ?? 0)"
            allowQuit = d.allowQuit != 0
            description = d.description ?? ""
            coverUrl = d.coverImage
            images = (d.images ?? []).map { ImageItem(localData: nil, remoteUrl: $0, uploading: false) }
            if let code = d.cityCode {
                storeOptions = (try? await GroupEventAPI.storesByCity(code)) ?? []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setCity(code: Int, name: String) {
        if code != cityCode {
            cityCode = code
            cityName = name
            storeId = nil
            storeName = ""
            storeOptions = []
            showCityPicker = false
            Task { storeOptions = (try? await GroupEventAPI.storesByCity(code)) ?? [] }
        } else {
            showCityPicker = false
        }
    }

    func setStore(id: Int64, name: String) {
        storeId = id
        storeName = name
        showStorePicker = false
    }

    // ---- 图片上传 ----

    func uploadCover(_ item: PhotosPickerItem?) {
        guard let item else { return }
        coverUploading = true
        Task {
            defer { coverUploading = false; coverItem = nil }
            do {
                coverUrl = try await Self.uploadPhoto(item, name: "event_cover")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func addImages(_ items: [PhotosPickerItem]) {
        let slots = 9 - images.count
        for item in items.prefix(slots) {
            let entry = ImageItem(localData: nil, remoteUrl: nil, uploading: true)
            images.append(entry)
            Task {
                do {
                    let url = try await Self.uploadPhoto(item, name: "event_img")
                    if let idx = images.firstIndex(where: { $0.id == entry.id }) {
                        images[idx].remoteUrl = url
                        images[idx].uploading = false
                    }
                } catch {
                    images.removeAll { $0.id == entry.id }
                    self.error = error.localizedDescription
                }
            }
        }
        imageItems = []
    }

    func removeImage(_ id: UUID) {
        images.removeAll { $0.id == id }
    }

    private static func uploadPhoto(_ item: PhotosPickerItem, name: String) async throws -> String {
        guard let data = try await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data),
              let jpeg = ui.jpegData(compressionQuality: 0.82) else {
            throw APIError.business(code: -1, message: "读取图片失败")
        }
        return try await APIClient.shared.uploadFile(
            data: jpeg, filename: "\(name)_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")
    }

    // ---- 发布 / 草稿 ----

    private var eventTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: eventDate)
    }

    /// 基础校验，返回错误文案（nil 通过）
    private func validate() -> String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "请输入活动名" }
        if storeId == nil { return "请选择活动门店" }
        let limit = Int(participantLimit)
        if limit == nil || limit! < 2 { return "人数上限至少2人" }
        if images.contains(where: { $0.uploading }) { return "图片还在上传中…" }
        if coverUploading { return "封面上传中…" }
        return nil
    }

    private func buildReq(draft: Bool?) -> CreateGroupEventReq {
        var req = CreateGroupEventReq(
            title: title.trimmingCharacters(in: .whitespaces),
            eventType: eventType,
            eventTime: eventTimeString,
            participantLimit: Int(participantLimit) ?? 10
        )
        req.cityCode = cityCode
        req.storeId = storeId
        req.rabbitCoinPrice = Int(rabbitCoinPrice) ?? 0
        req.description = description.isEmpty ? nil : description
        req.coverImage = coverUrl
        let urls = images.compactMap(\.remoteUrl)
        req.images = urls.isEmpty ? nil : urls
        req.allowQuit = allowQuit ? 1 : 0
        req.draft = draft
        return req
    }

    func publish() {
        if let msg = validate() { error = msg; return }
        Task {
            // 新建发布前验实名（对齐安卓 checkRealname）
            if draftId == nil {
                do {
                    let user = try await UserAPI.getUserInfo()
                    if user.realnameStatus != 1 { needRealname = true; return }
                } catch {
                    self.error = error.localizedDescription
                    return
                }
            }
            isPublishing = true
            defer { isPublishing = false }
            do {
                if let draftId {
                    var req = UpdateDraftReq(id: draftId)
                    let r = buildReq(draft: nil)
                    req.title = r.title
                    req.eventType = r.eventType
                    req.eventTime = r.eventTime
                    req.cityCode = r.cityCode
                    req.storeId = r.storeId
                    req.participantLimit = r.participantLimit
                    req.rabbitCoinPrice = r.rabbitCoinPrice
                    req.description = r.description
                    req.coverImage = r.coverImage
                    req.images = r.images
                    req.allowQuit = r.allowQuit
                    _ = try await GroupEventAPI.updateDraft(req)
                    _ = try await GroupEventAPI.publish(id: draftId)
                } else {
                    _ = try await GroupEventAPI.create(buildReq(draft: nil))
                }
                created = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func saveDraft() {
        // 草稿校验放宽：不要求门店
        if title.trimmingCharacters(in: .whitespaces).isEmpty { error = "请输入活动名"; return }
        let limit = Int(participantLimit)
        if limit == nil || limit! < 2 { error = "人数上限至少2人"; return }
        if images.contains(where: { $0.uploading }) { error = "图片还在上传中…"; return }
        Task {
            isPublishing = true
            defer { isPublishing = false }
            do {
                if let draftId {
                    var req = UpdateDraftReq(id: draftId)
                    let r = buildReq(draft: nil)
                    req.title = r.title
                    req.eventType = r.eventType
                    req.eventTime = r.eventTime
                    req.cityCode = r.cityCode
                    req.storeId = r.storeId
                    req.participantLimit = r.participantLimit
                    req.rabbitCoinPrice = r.rabbitCoinPrice
                    req.description = r.description
                    req.coverImage = r.coverImage
                    req.images = r.images
                    req.allowQuit = r.allowQuit
                    _ = try await GroupEventAPI.updateDraft(req)
                } else {
                    _ = try await GroupEventAPI.create(buildReq(draft: true))
                }
                created = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
