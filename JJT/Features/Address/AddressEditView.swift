import SwiftUI

/// 新增/编辑地址 — 对齐安卓 AddressEditScreen（含省市区三级级联选择）
struct AddressEditView: View {

    let addressId: Int64?
    /// 保存成功回调（外层负责关页 + 刷新列表）
    let onSaved: () -> Void

    @StateObject private var vm = AddressEditViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 14) {
                        field("收货人", text: $vm.name)
                        field("手机号", text: $vm.mobile, keyboard: .phonePad)

                        // 地区选择 — 点击整行弹出
                        Button { vm.showPicker = true } label: {
                            HStack {
                                Text(vm.areaName.isEmpty ? "所在地区" : vm.areaName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(vm.areaName.isEmpty ? Noir.textFaint : Noir.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .noirField()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        field("详细地址（街道、楼栋、门牌号）", text: $vm.detailAddress)

                        // 默认地址
                        Button { vm.isDefault.toggle() } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(vm.isDefault ? Noir.crimson : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(vm.isDefault ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
                                    if vm.isDefault {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 18, height: 18)
                                Text("设为默认地址")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        Button { vm.save() } label: {
                            Text(vm.isSaving ? "保存中…" : "保存")
                        }
                        .buttonStyle(NoirPrimaryButtonStyle(enabled: vm.canSave && !vm.isSaving))
                        .disabled(!vm.canSave || vm.isSaving)
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear { vm.load(id: addressId) }
        .onChange(of: vm.success) { _, ok in if ok { onSaved() } }
        .sheet(isPresented: $vm.showPicker) { areaPicker }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("确定", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text(addressId == nil ? "新增地址" : "编辑地址")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14))
            .keyboardType(keyboard)
            .noirField()
    }

    // MARK: - 省市区三级选择器

    private var areaPicker: some View {
        NavigationStack {
            ZStack {
                Noir.noir.ignoresSafeArea()
                List {
                    let nodes: [AreaNode] = switch vm.pickerStep {
                    case 0: vm.areaTree
                    case 1: vm.selectedProvince?.children ?? []
                    default: vm.selectedCity?.children ?? []
                    }
                    ForEach(nodes) { node in
                        Button {
                            switch vm.pickerStep {
                            case 0: vm.selectProvince(node)
                            case 1: vm.selectCity(node)
                            default: vm.selectDistrict(node)
                            }
                        } label: {
                            Text(node.name ?? "")
                                .font(.system(size: 14))
                                .foregroundStyle(Noir.ivory)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.pickerStep == 0 ? "选择省" : vm.pickerStep == 1 ? "选择市" : "选择区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { vm.showPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - ViewModel

@MainActor
final class AddressEditViewModel: ObservableObject {
    @Published var id: Int64?
    @Published var name = ""
    @Published var mobile = ""
    @Published var areaId: Int?
    @Published var areaName = ""
    @Published var detailAddress = ""
    @Published var isDefault = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var success = false

    // 地区选择
    @Published var areaTree: [AreaNode] = []
    @Published var selectedProvince: AreaNode?
    @Published var selectedCity: AreaNode?
    @Published var selectedDistrict: AreaNode?
    @Published var showPicker = false
    @Published var pickerStep = 0 // 0=省 1=市 2=区

    var canSave: Bool {
        !name.isEmpty && !detailAddress.isEmpty && areaId != nil
            && mobile.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    /// 手机号校验提示（canSave 为 false 时的具体原因）
    var mobileValid: Bool {
        mobile.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    /// 并发加载地区树 + （编辑时）地址详情，编辑按 areaId 反查三级回填
    func load(id: Int64?) {
        Task {
            async let treeResult = (try? await AddressAPI.areaTree()) ?? []
            var addr: AddressInfo?
            if let id { addr = try? await AddressAPI.get(id: id) }
            let tree = await treeResult
            areaTree = tree
            guard let addr else { return }
            self.id = addr.id
            name = addr.name ?? ""
            mobile = addr.mobile ?? ""
            areaId = addr.areaId
            areaName = addr.areaName ?? ""
            detailAddress = addr.detailAddress ?? ""
            isDefault = addr.defaultStatus == true
            // 反查三级
            if let aid = addr.areaId {
                for prov in tree {
                    for city in prov.children ?? [] {
                        if let dist = city.children?.first(where: { $0.id == aid }) {
                            selectedProvince = prov
                            selectedCity = city
                            selectedDistrict = dist
                        }
                    }
                }
            }
        }
    }

    func selectProvince(_ node: AreaNode) {
        selectedProvince = node
        selectedCity = nil
        selectedDistrict = nil
        pickerStep = 1
    }

    func selectCity(_ node: AreaNode) {
        selectedCity = node
        selectedDistrict = nil
        pickerStep = 2
    }

    func selectDistrict(_ node: AreaNode) {
        selectedDistrict = node
        areaId = node.id
        areaName = [selectedProvince?.name, selectedCity?.name, node.name]
            .compactMap { $0 }.joined(separator: " ")
        showPicker = false
        pickerStep = 0
    }

    func save() {
        guard canSave else {
            if !mobileValid { error = "请填写正确的手机号" }
            else if areaId == nil { error = "请选择所在地区" }
            else { error = "请填写完整信息" }
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            let req = AddressReq(
                id: id, name: name, mobile: mobile,
                areaId: areaId.map { Int64($0) },
                detailAddress: detailAddress, defaultStatus: isDefault
            )
            do {
                if id != nil {
                    _ = try await AddressAPI.update(req)
                } else {
                    _ = try await AddressAPI.create(req)
                }
                success = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
