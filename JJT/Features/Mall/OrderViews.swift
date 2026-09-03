import SwiftUI

// MARK: - 订单模型与 API（对齐安卓 OrderApi；价格为分）

/// 兼容字段：后端时间字段有时返回字符串、有时返回 epoch 毫秒数字（Gson 会自动转，Swift 需手动）
private func decodeFlexString<K: CodingKey>(_ container: KeyedDecodingContainer<K>, for key: K) -> String? {
    if let s = try? container.decodeIfPresent(String.self, forKey: key) { return s }
    if let n = try? container.decodeIfPresent(Int64.self, forKey: key) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(n) / 1000))
    }
    return nil
}

struct OrderItemInfo: Decodable, Identifiable {
    let id: Int64
    let spuId: Int64?
    let spuName: String?
    let skuId: Int64?
    let properties: [SkuProperty]?
    let picUrl: String?
    let count: Int?
    let price: Int?
    let payPrice: Int?
}

struct OrderListItem: Decodable, Identifiable {
    let id: Int64
    let no: String?
    let status: Int?
    let productCount: Int?
    let createTime: String?
    let payOrderId: Int64?
    let payPrice: Int?
    let items: [OrderItemInfo]?

    private enum CodingKeys: String, CodingKey {
        case id, no, status, productCount, createTime, payOrderId, payPrice, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        no = try c.decodeIfPresent(String.self, forKey: .no)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        productCount = try c.decodeIfPresent(Int.self, forKey: .productCount)
        createTime = decodeFlexString(c, for: .createTime)
        payOrderId = try c.decodeIfPresent(Int64.self, forKey: .payOrderId)
        payPrice = try c.decodeIfPresent(Int.self, forKey: .payPrice)
        items = try c.decodeIfPresent([OrderItemInfo].self, forKey: .items)
    }
}

struct OrderDetail: Decodable {
    let id: Int64
    let no: String?
    let status: Int?
    let createTime: String?
    let userRemark: String?
    let payStatus: Bool?
    let payOrderId: Int64?
    let payTime: String?
    let payExpireTime: String?
    let totalPrice: Int?
    let discountPrice: Int?
    let deliveryPrice: Int?
    let payPrice: Int?
    let logisticsName: String?
    let logisticsNo: String?
    let deliveryTime: String?
    let receiverName: String?
    let receiverMobile: String?
    let receiverAreaName: String?
    let receiverDetailAddress: String?
    let rabbitCoinPrice: Int?
    let radishCoinPrice: Int?
    let items: [OrderItemInfo]?

    private enum CodingKeys: String, CodingKey {
        case id, no, status, createTime, userRemark, payStatus, payOrderId, payTime, payExpireTime
        case totalPrice, discountPrice, deliveryPrice, payPrice
        case logisticsName, logisticsNo, deliveryTime
        case receiverName, receiverMobile, receiverAreaName, receiverDetailAddress
        case rabbitCoinPrice, radishCoinPrice, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        no = try c.decodeIfPresent(String.self, forKey: .no)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        createTime = decodeFlexString(c, for: .createTime)
        userRemark = try c.decodeIfPresent(String.self, forKey: .userRemark)
        payStatus = try c.decodeIfPresent(Bool.self, forKey: .payStatus)
        payOrderId = try c.decodeIfPresent(Int64.self, forKey: .payOrderId)
        payTime = decodeFlexString(c, for: .payTime)
        payExpireTime = decodeFlexString(c, for: .payExpireTime)
        totalPrice = try c.decodeIfPresent(Int.self, forKey: .totalPrice)
        discountPrice = try c.decodeIfPresent(Int.self, forKey: .discountPrice)
        deliveryPrice = try c.decodeIfPresent(Int.self, forKey: .deliveryPrice)
        payPrice = try c.decodeIfPresent(Int.self, forKey: .payPrice)
        logisticsName = try c.decodeIfPresent(String.self, forKey: .logisticsName)
        logisticsNo = try c.decodeIfPresent(String.self, forKey: .logisticsNo)
        deliveryTime = decodeFlexString(c, for: .deliveryTime)
        receiverName = try c.decodeIfPresent(String.self, forKey: .receiverName)
        receiverMobile = try c.decodeIfPresent(String.self, forKey: .receiverMobile)
        receiverAreaName = try c.decodeIfPresent(String.self, forKey: .receiverAreaName)
        receiverDetailAddress = try c.decodeIfPresent(String.self, forKey: .receiverDetailAddress)
        rabbitCoinPrice = try c.decodeIfPresent(Int.self, forKey: .rabbitCoinPrice)
        radishCoinPrice = try c.decodeIfPresent(Int.self, forKey: .radishCoinPrice)
        items = try c.decodeIfPresent([OrderItemInfo].self, forKey: .items)
    }
}

struct ExpressTrack: Decodable, Identifiable {
    let time: String?
    let content: String?
    var id: String { (time ?? "") + (content ?? "") }
}

/// 订单状态文案（对齐 yudao TradeOrderStatusEnum）
func orderStatusText(_ status: Int?) -> String {
    switch status {
    case 0: return "待付款"
    case 10: return "待发货"
    case 20: return "已发货"
    case 30: return "已完成"
    case 40, 60, 61, 62, 63: return "已取消"
    default: return "售后/其他"
    }
}

enum OrderAPI {
    static func page(pageNo: Int, status: Int? = nil) async throws -> PageResult<OrderListItem> {
        var query = ["pageNo": "\(pageNo)", "pageSize": "10"]
        if let status { query["status"] = "\(status)" }
        return try await APIClient.shared.get("app-api/trade/order/page", query: query)
    }

    static func detail(id: Int64) async throws -> OrderDetail {
        try await APIClient.shared.get("app-api/trade/order/get-detail", query: ["id": "\(id)"])
    }

    static func receive(id: Int64) async throws -> Bool {
        try await APIClient.shared.put("app-api/trade/order/receive", query: ["id": "\(id)"])
    }

    static func cancel(id: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/trade/order/cancel", query: ["id": "\(id)"])
    }

    static func expressTracks(id: Int64) async throws -> [ExpressTrack] {
        try await APIClient.shared.get("app-api/trade/order/get-express-track-list", query: ["id": "\(id)"])
    }
}

// MARK: - 订单列表

struct OrderListView: View {

    @StateObject private var vm = OrderListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var detailId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
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
                    Text("我的订单")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if vm.isLoading && vm.orders.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else if vm.orders.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bag")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("暂无订单")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(vm.orders) { order in
                            OrderRow(order: order) { detailId = order.id }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        if !vm.isEnd {
                            Color.clear
                                .frame(height: 1)
                                .listRowBackground(Color.clear)
                                .onAppear { vm.loadMore() }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { vm.load() }
                }
            }
        }
        .onAppear { vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .jjtOrderChanged)) { _ in vm.load() }
        .fullScreenCover(isPresented: Binding(
            get: { detailId != nil },
            set: { if !$0 { detailId = nil } }
        )) {
            if let id = detailId {
                OrderDetailView(orderId: id)
            }
        }
        .jjtPageGestures()
    }
}

private struct OrderRow: View {
    let order: OrderListItem
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(order.createTime ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Noir.textFaint)
                Spacer()
                Text(orderStatusText(order.status))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(order.status == 0 ? Noir.crimsonHot : Noir.gold)
            }
            ForEach(order.items ?? []) { item in
                HStack(spacing: 10) {
                    AsyncImage(url: webImageURL(item.picUrl.flatMap { $0.isEmpty ? nil : $0 })) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Noir.noir3
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.spuName ?? "")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Noir.ivory)
                            .lineLimit(1)
                        if let props = item.properties, !props.isEmpty {
                            Text(props.compactMap(\.valueName).joined(separator: " / "))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    Spacer()
                    Text("×\(item.count ?? 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            HStack {
                Spacer()
                Text("共\(order.productCount ?? 0)件 实付 ")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Text("¥\(fenToYuan(order.payPrice))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Noir.crimsonHot)
            }
        }
        .padding(14)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

@MainActor
final class OrderListViewModel: ObservableObject {
    @Published var orders: [OrderListItem] = []
    @Published var isLoading = false
    @Published var isEnd = false
    private var pageNo = 1

    func load() {
        pageNo = 1
        isLoading = true
        Task {
            defer { isLoading = false }
            if let resp = try? await OrderAPI.page(pageNo: 1) {
                orders = resp.list ?? []
                isEnd = (resp.list?.count ?? 0) < 10
            }
        }
    }

    func loadMore() {
        guard !isLoading, !isEnd else { return }
        let next = pageNo + 1
        Task {
            guard let resp = try? await OrderAPI.page(pageNo: next) else { return }
            let list = resp.list ?? []
            let existing = Set(orders.map(\.id))
            orders += list.filter { !existing.contains($0.id) }
            pageNo = next
            isEnd = list.count < 10
        }
    }
}

// MARK: - 订单详情

struct OrderDetailView: View {

    let orderId: Int64

    @StateObject private var vm = OrderDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var payOrder: (id: Int64, price: Int)?
    @State private var toast: String?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()

            VStack(spacing: 0) {
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
                    Text("订单详情")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if let o = vm.order {
                    ScrollView {
                        VStack(spacing: 14) {
                            // 状态
                            HStack {
                                Text(orderStatusText(o.status))
                                    .font(.system(size: 18, weight: .bold, design: .serif))
                                    .foregroundStyle(Noir.goldText)
                                Spacer()
                            }

                            // 收货信息
                            if o.receiverName != nil {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(o.receiverName ?? "")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Noir.ivory)
                                        Text(o.receiverMobile ?? "")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    Text("\(o.receiverAreaName ?? "") \(o.receiverDetailAddress ?? "")")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardStyle()
                            }

                            // 商品
                            VStack(spacing: 12) {
                                ForEach(o.items ?? []) { item in
                                    HStack(spacing: 10) {
                                        AsyncImage(url: webImageURL(item.picUrl.flatMap { $0.isEmpty ? nil : $0 })) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Noir.noir3
                                            }
                                        }
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.spuName ?? "")
                                                .font(.system(size: 12.5))
                                                .foregroundStyle(Noir.ivory)
                                                .lineLimit(1)
                                            if let props = item.properties, !props.isEmpty {
                                                Text(props.compactMap(\.valueName).joined(separator: " / "))
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.white.opacity(0.4))
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("¥\(fenToYuan(item.price))")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Noir.ivory)
                                            Text("×\(item.count ?? 1)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                }
                            }
                            .cardStyle()

                            // 物流
                            if let no = o.logisticsNo, !no.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "shippingbox")
                                            .foregroundStyle(Noir.gold)
                                        Text("\(o.logisticsName ?? "快递") \(no)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Noir.ivory)
                                    }
                                    ForEach(vm.tracks.prefix(3)) { t in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.content ?? "")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.6))
                                            Text(t.time ?? "")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Noir.textFaint)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardStyle()
                            }

                            // 金额
                            VStack(spacing: 8) {
                                line("商品金额", fen: o.totalPrice)
                                line("运费", fen: o.deliveryPrice)
                                if (o.discountPrice ?? 0) > 0 { line("优惠", fen: -(o.discountPrice ?? 0)) }
                                HStack {
                                    Spacer()
                                    Text("实付 ")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text("¥\(fenToYuan(o.payPrice))")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(Noir.crimsonHot)
                                }
                            }
                            .cardStyle()

                            // 订单信息
                            VStack(alignment: .leading, spacing: 6) {
                                info("订单编号", o.no ?? "-")
                                info("创建时间", o.createTime ?? "-")
                                if let payTime = o.payTime { info("支付时间", payTime) }
                                if let remark = o.userRemark, !remark.isEmpty { info("备注", remark) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                        }
                        .padding(16)
                    }

                    // 底部操作（待付款：去支付/取消；已发货：确认收货）
                    if o.status == 0 || o.status == 20 {
                        HStack(spacing: 12) {
                            if o.status == 0 {
                                Button { vm.cancel(id: o.id) } label: {
                                    Text("取消订单")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                                if let payId = o.payOrderId {
                                    Button { payOrder = (payId, o.payPrice ?? 0) } label: {
                                        Text("去支付")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 11)
                                            .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)))
                                    }
                                }
                            } else {
                                Button { vm.receive(id: o.id) } label: {
                                    Text("确认收货")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.95))
                    }
                } else {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
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
        .onAppear { vm.load(id: orderId) }
        .onChange(of: vm.message) { _, msg in
            if let msg { showToast(msg); vm.message = nil }
        }
        .fullScreenCover(isPresented: Binding(
            get: { payOrder != nil },
            set: { if !$0 { payOrder = nil } }
        )) {
            if let p = payOrder, let o = vm.order {
                PayView(payOrderId: p.id, priceFen: p.price,
                        totalFen: o.totalPrice,
                        rabbitCoinFen: o.rabbitCoinPrice,
                        radishCoinFen: o.radishCoinPrice) {
                    payOrder = nil
                    NotificationCenter.default.post(name: .jjtOrderChanged, object: nil)
                    vm.load(id: orderId)
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    private func line(_ label: String, fen: Int?) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text("¥\(fenToYuan(fen))").font(.system(size: 12)).foregroundStyle(Noir.ivory)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(Noir.textFaint)
            Spacer()
            Text(value).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(14)
            .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

@MainActor
final class OrderDetailViewModel: ObservableObject {
    @Published var order: OrderDetail?
    @Published var tracks: [ExpressTrack] = []
    @Published var message: String?

    func load(id: Int64) {
        Task {
            order = try? await OrderAPI.detail(id: id)
            if order?.logisticsNo != nil {
                tracks = (try? await OrderAPI.expressTracks(id: id)) ?? []
            }
        }
    }

    func cancel(id: Int64) {
        Task {
            do {
                _ = try await OrderAPI.cancel(id: id)
                message = "订单已取消"
                load(id: id)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func receive(id: Int64) {
        Task {
            do {
                _ = try await OrderAPI.receive(id: id)
                message = "已确认收货"
                load(id: id)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
