import SwiftUI

/// 收货地址列表 — 对齐安卓 AddressScreen
struct AddressListView: View {

    @StateObject private var vm = AddressListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var editorTarget: EditorTarget?
    @State private var deleteConfirmId: Int64?

    /// 选择模式（商城结算选地址用）；nil = 管理模式（点卡片进编辑）
    var onSelect: ((AddressInfo) -> Void)? = nil

    private struct EditorTarget: Identifiable {
        /// -1 表示新增
        let id: Int64
        var addressId: Int64? { id < 0 ? nil : id }
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.addresses.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("暂无地址，点击右上角 + 新增")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.addresses) { addr in
                                AddressCard(addr: addr,
                                            onTap: {
                                                if let onSelect { onSelect(addr); dismiss() }
                                                else { editorTarget = EditorTarget(id: addr.id) }
                                            },
                                            onDelete: { deleteConfirmId = addr.id })
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { vm.load() }
                }
            }
        }
        .onAppear { vm.load() }
        .fullScreenCover(item: $editorTarget) { target in
            AddressEditView(addressId: target.addressId) {
                editorTarget = nil
                vm.load()
            }
        }
        .alert("确认删除", isPresented: Binding(
            get: { deleteConfirmId != nil },
            set: { if !$0 { deleteConfirmId = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let id = deleteConfirmId { vm.delete(id: id) }
                deleteConfirmId = nil
            }
            Button("取消", role: .cancel) { deleteConfirmId = nil }
        } message: {
            Text("确定要删除该地址吗？")
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
            Text("收货地址")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Button { editorTarget = EditorTarget(id: -1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - 地址卡片

private struct AddressCard: View {
    let addr: AddressInfo
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)], center: .center, startRadius: 0, endRadius: 24))
                    .overlay(Circle().stroke(Noir.gold.opacity(0.3), lineWidth: 1))
                Image(systemName: "mappin")
                    .font(.system(size: 15))
                    .foregroundStyle(Noir.goldLight)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(addr.name ?? "")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Noir.ivory)
                    if addr.defaultStatus == true {
                        Text("默认")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing)))
                    }
                    Text(addr.mobile ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text("\(addr.areaName ?? "") \(addr.detailAddress ?? "")")
                    .font(.system(size: 12.5))
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Noir.crimsonHot.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(16)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - ViewModel

@MainActor
final class AddressListViewModel: ObservableObject {
    @Published var addresses: [AddressInfo] = []
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            if let list = try? await AddressAPI.list() {
                addresses = list.sorted { ($0.defaultStatus == true) && ($1.defaultStatus != true) }
            }
        }
    }

    func delete(id: Int64) {
        Task {
            _ = try? await AddressAPI.delete(id: id)
            load()
        }
    }
}
