import SwiftUI

/// 结算下单 — 对齐安卓 CheckoutScreen（v1：快递配送 + 地址选择 + 备注；优惠券/自提/虚拟币抵扣后续）
struct CheckoutView: View {

    /// 结算项：skuId+count（立即购买）或 cartId（购物车结算）二选一
    struct Item: Identifiable {
        let id = UUID()
        let skuId: Int64?
        let count: Int?
        let cartId: Int64?
    }

    let items: [Item]

    @StateObject private var vm = CheckoutViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showAddressPicker = false
    @State private var remark = ""
    @State private var payOrder: (id: Int64, price: Int)?
    @State private var toast: String?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if vm.isLoading && vm.settlement == nil {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            addressCard
                            itemsCard
                            remarkCard
                            priceCard
                        }
                        .padding(16)
                    }

                    submitBar
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
                }
            }
        }
        .onAppear { vm.loadSettlement(items: items, addressId: nil) }
        .fullScreenCover(isPresented: $showAddressPicker) {
            AddressListView(onSelect: { addr in
                vm.loadSettlement(items: items, addressId: addr.id)
            })
        }
        .fullScreenCover(isPresented: Binding(
            get: { payOrder != nil },
            set: { if !$0 { payOrder = nil } }
        )) {
            if let p = payOrder {
                PayView(payOrderId: p.id, priceFen: p.price) {
                    // 支付完成：关闭结算页 + 通知订单变更
                    payOrder = nil
                    NotificationCenter.default.post(name: .jjtOrderChanged, object: nil)
                    dismiss()
                }
            }
        }
        .onChange(of: vm.errorMessage) { _, msg in if let msg { showToast(msg); vm.errorMessage = nil } }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
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
            Text("确认订单")
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

    // MARK: - 地址卡

    private var addressCard: some View {
        Button { showAddressPicker = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin")
                    .font(.system(size: 16))
                    .foregroundStyle(Noir.goldLight)
                if let addr = vm.settlement?.address, addr.id != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(addr.name ?? "")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Noir.ivory)
                            Text(addr.mobile ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text("\(addr.areaName ?? "") \(addr.detailAddress ?? "")")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                } else {
                    Text("请选择收货地址")
                        .font(.system(size: 14))
                        .foregroundStyle(Noir.crimsonHot)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.hairlineGold, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 商品卡

    private var itemsCard: some View {
        VStack(spacing: 12) {
            ForEach(vm.settlement?.items ?? [], id: \.skuId) { item in
                HStack(spacing: 10) {
                    AsyncImage(url: webImageURL(item.picUrl.flatMap { $0.isEmpty ? nil : $0 })) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Noir.noir3
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.spuName ?? "")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(1)
                        if let props = item.properties, !props.isEmpty {
                            Text(props.compactMap(\.valueName).joined(separator: " / "))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        HStack {
                            Text("¥\(fenToYuan(item.price))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Noir.crimsonHot)
                            Spacer()
                            Text("×\(item.count ?? 1)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    // MARK: - 备注

    private var remarkCard: some View {
        HStack(spacing: 10) {
            Text("备注")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            TextField("选填，给卖家留言", text: $remark)
                .font(.system(size: 13))
                .foregroundStyle(Noir.ivory)
        }
        .padding(14)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    // MARK: - 价格卡

    private var priceCard: some View {
        VStack(spacing: 8) {
            priceLine("商品金额", fen: vm.settlement?.price?.totalPrice)
            priceLine("运费", fen: vm.settlement?.price?.deliveryPrice)
            if (vm.settlement?.price?.discountPrice ?? 0) > 0 {
                priceLine("优惠", fen: -(vm.settlement?.price?.discountPrice ?? 0))
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            HStack {
                Spacer()
                Text("实付 ")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Text("¥\(fenToYuan(vm.settlement?.price?.payPrice))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Noir.crimsonHot)
            }
        }
        .padding(14)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func priceLine(_ label: String, fen: Int?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text("¥\(fenToYuan(fen))")
                .font(.system(size: 12))
                .foregroundStyle(Noir.ivory)
        }
    }

    // MARK: - 提交栏

    private var submitBar: some View {
        HStack {
            Spacer()
            Text("¥\(fenToYuan(vm.settlement?.price?.payPrice))")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Noir.crimsonHot)
            Button {
                vm.createOrder(items: items, remark: remark) { orderId, payOrderId, price in
                    if let payOrderId {
                        payOrder = (payOrderId, price)
                    } else {
                        showToast("下单成功")
                        NotificationCenter.default.post(name: .jjtOrderChanged, object: nil)
                        dismiss()
                    }
                }
            } label: {
                Text(vm.isSubmitting ? "提交中…" : "提交订单")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)))
            }
            .disabled(vm.isSubmitting || vm.settlement?.address?.id == nil)
            .opacity(vm.settlement?.address?.id == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.95))
    }
}

// MARK: - 结算/下单模型

struct SettlementItem: Decodable {
    let spuId: Int64?
    let spuName: String?
    let skuId: Int64?
    let price: Int?
    let picUrl: String?
    let properties: [SkuProperty]?
    let cartId: Int64?
    let count: Int?
}

struct SettlementPrice: Decodable {
    let totalPrice: Int?
    let discountPrice: Int?
    let deliveryPrice: Int?
    let couponPrice: Int?
    let payPrice: Int?
}

struct SettlementAddress: Decodable {
    let id: Int64?
    let name: String?
    let mobile: String?
    let areaName: String?
    let detailAddress: String?
    let defaultStatus: Bool?
}

struct SettlementResp: Decodable {
    let items: [SettlementItem]?
    let price: SettlementPrice?
    let address: SettlementAddress?
}

private struct OrderCreateReq: Encodable {
    struct Item: Encodable {
        let skuId: Int64?
        let count: Int?
        let cartId: Int64?
    }
    let items: [Item]
    let addressId: Int64?
    let deliveryType: Int
    let remark: String?
}

private struct OrderCreateResp: Decodable {
    let id: Int64
    let payOrderId: Int64?
}

/// 订单变更通知（订单列表刷新用）
extension Notification.Name {
    static let jjtOrderChanged = Notification.Name("jjtOrderChanged")
}

// MARK: - ViewModel

@MainActor
final class CheckoutViewModel: ObservableObject {
    @Published var settlement: SettlementResp?
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    /// 结算（对齐安卓：items[i].skuId/count/cartId 拍平成 query 参数）
    func loadSettlement(items: [CheckoutView.Item], addressId: Int64?) {
        isLoading = true
        var query: [String: String] = ["deliveryType": "1", "pointStatus": "false"]
        for (i, item) in items.enumerated() {
            if let skuId = item.skuId { query["items[\(i)].skuId"] = "\(skuId)" }
            if let count = item.count { query["items[\(i)].count"] = "\(count)" }
            if let cartId = item.cartId { query["items[\(i)].cartId"] = "\(cartId)" }
        }
        let aid = addressId ?? settlement?.address?.id
        if let aid { query["addressId"] = "\(aid)" }
        Task {
            defer { isLoading = false }
            do {
                settlement = try await APIClient.shared.get("app-api/trade/order/settlement", query: query)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createOrder(items: [CheckoutView.Item], remark: String,
                     onCreated: (Int64, Int64?, Int) -> Void) {
        guard let addressId = settlement?.address?.id else {
            errorMessage = "请选择收货地址"
            return
        }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let resp: OrderCreateResp = try await APIClient.shared.post(
                    "app-api/trade/order/create",
                    body: OrderCreateReq(
                        items: items.map { OrderCreateReq.Item(skuId: $0.skuId, count: $0.count, cartId: $0.cartId) },
                        addressId: addressId,
                        deliveryType: 1,
                        remark: remark.isEmpty ? nil : remark
                    ))
                onCreated(resp.id, resp.payOrderId, settlement?.price?.payPrice ?? 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
