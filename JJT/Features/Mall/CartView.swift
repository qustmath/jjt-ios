import SwiftUI

/// 购物车 — 对齐安卓 CartScreen（勾选/步进/删除/全选）
/// 结算链路（settlement/下单/支付）下一轮迁移，本期按钮占位
struct CartView: View {

    @StateObject private var vm = CartViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?
    @State private var checkoutItems: [CheckoutView.Item]?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if vm.isLoading && vm.items.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else if vm.items.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "cart")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("购物车是空的")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                } else {
                    // 用 List 才有 swipeActions（ScrollView+LazyVStack 不支持滑动删除）
                    List {
                        ForEach(vm.items) { item in
                            CartItemRow(item: item,
                                        onToggle: { vm.toggleSelected(item) },
                                        onCount: { vm.updateCount(item, count: $0) })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { vm.delete(item) } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { vm.load() }

                    bottomBar
                }
            }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.ivory)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Noir.noir3.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 100)
                        .transition(.opacity)
                }
            }
        }
        .onAppear { vm.load() }
        .fullScreenCover(isPresented: Binding(
            get: { checkoutItems != nil },
            set: { if !$0 { checkoutItems = nil } }
        )) {
            if let items = checkoutItems {
                CheckoutView(items: items)
            }
        }
        // 下单/支付完成 → 刷新购物车
        .onReceive(NotificationCenter.default.publisher(for: .jjtOrderChanged)) { _ in
            vm.load()
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
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
            Text("购物车")
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

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { vm.toggleSelectAll() } label: {
                HStack(spacing: 6) {
                    NoirCheck(checked: vm.allSelected)
                    Text("全选")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Text("合计：")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Text("¥\(fenToYuan(vm.totalPriceFen))")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Noir.crimsonHot)
            Button {
                // 勾选商品按 cartId 走结算（对齐安卓）
                checkoutItems = vm.items.filter { $0.selected == true }
                    .map { CheckoutView.Item(skuId: nil, count: nil, cartId: $0.id) }
            } label: {
                Text("结算(\(vm.selectedCount))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)))
            }
            .disabled(vm.selectedCount == 0)
            .opacity(vm.selectedCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.95))
    }
}

// MARK: - 勾选圆钮

private func NoirCheck(checked: Bool) -> some View {
    ZStack {
        Circle()
            .fill(checked ? Noir.crimson : Color.clear)
            .overlay(Circle().stroke(checked ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
        if checked {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }
    .frame(width: 18, height: 18)
}

// MARK: - 购物车行

private struct CartItemRow: View {
    let item: MallCartItem
    let onToggle: () -> Void
    let onCount: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                NoirCheck(checked: item.selected ?? false)
            }
            // List 行内按钮必须 borderless，否则行内点击会误路由到首个按钮
            // （症状：点加减时勾选框状态被切换）
            .buttonStyle(.borderless)

            // sku.picUrl 可能是空串，须回退 spu 图（实测后端行为）
            AsyncImage(url: webImageURL(item.sku?.picUrl.flatMap { $0.isEmpty ? nil : $0 } ?? item.spu?.picUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Noir.noir3
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.spu?.name ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(1)
                if let props = item.sku?.properties, !props.isEmpty {
                    Text(props.compactMap(\.valueName).joined(separator: " / "))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                HStack {
                    Text("¥\(fenToYuan(item.sku?.price))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Noir.crimsonHot)
                    Spacer()
                    HStack(spacing: 0) {
                        Button { onCount(item.count - 1) } label: {
                            Image(systemName: "minus").font(.system(size: 11)).frame(width: 26, height: 26)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Noir.ivory)
                        Text("\(item.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Noir.ivory)
                            .frame(minWidth: 26)
                        Button { onCount(item.count + 1) } label: {
                            Image(systemName: "plus").font(.system(size: 11)).frame(width: 26, height: 26)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Noir.ivory)
                    }
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - 模型（对齐安卓 CartItem 等）

struct MallCartItem: Decodable, Identifiable {
    let id: Int64
    var count: Int
    var selected: Bool?
    let spu: CartSpu?
    let sku: CartSku?

    struct CartSpu: Decodable {
        let id: Int64
        let name: String?
        let picUrl: String?
        let stock: Int?
    }

    struct CartSku: Decodable {
        let id: Int64
        let picUrl: String?
        let price: Int?
        let stock: Int?
        let properties: [SkuProperty]?
    }
}

private struct CartListResp: Decodable {
    let validList: [MallCartItem]?
    let invalidList: [MallCartItem]?
}

private struct UpdateCountReq: Encodable { let id: Int64; let count: Int }
private struct UpdateSelectedReq: Encodable { let ids: [Int64]; let selected: Bool }

// MARK: - ViewModel（乐观更新，不整页重拉——修屏闪）

@MainActor
final class CartViewModel: ObservableObject {
    @Published var items: [MallCartItem] = []
    @Published var isLoading = false

    var allSelected: Bool { !items.isEmpty && items.allSatisfy { $0.selected == true } }
    var selectedCount: Int { items.filter { $0.selected == true }.reduce(0) { $0 + $1.count } }
    var totalPriceFen: Int { items.filter { $0.selected == true }.reduce(0) { $0 + ($1.sku?.price ?? 0) * $1.count } }

    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            if let resp: CartListResp = try? await APIClient.shared.get("app-api/trade/cart/list") {
                items = resp.validList ?? []
            }
        }
    }

    func toggleSelected(_ item: MallCartItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].selected = !(item.selected ?? false)
        Task {
            _ = try? await APIClient.shared.put("app-api/trade/cart/update-selected",
                                                body: UpdateSelectedReq(ids: [item.id], selected: items[i].selected ?? true)) as Bool
        }
    }

    func toggleSelectAll() {
        let newVal = !allSelected
        for i in items.indices { items[i].selected = newVal }
        Task {
            _ = try? await APIClient.shared.put("app-api/trade/cart/update-selected",
                                                body: UpdateSelectedReq(ids: items.map(\.id), selected: newVal)) as Bool
        }
    }

    func updateCount(_ item: MallCartItem, count: Int) {
        guard count >= 1, let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].count = count
        Task {
            _ = try? await APIClient.shared.put("app-api/trade/cart/update-count",
                                                body: UpdateCountReq(id: item.id, count: count)) as Bool
        }
    }

    func delete(_ item: MallCartItem) {
        let backup = items
        items.removeAll { $0.id == item.id }
        Task {
            let ok = try? await APIClient.shared.delete("app-api/trade/cart/delete", query: ["ids": "\(item.id)"]) as Bool
            if ok == nil { items = backup }
        }
    }
}
