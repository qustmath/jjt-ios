import SwiftUI

/// 结算下单 — 对齐安卓 CheckoutScreen：
/// 配送方式（实物快递/自提可选，虚拟商品强制自提）+ 地址/自提门店+联系人 +
/// 优惠券 + 兔币/萝贝抵扣 + 结算错误 1011003005 自动回退另一配送方式重试
struct CheckoutView: View {

    /// 结算项：skuId+count（立即购买）或 cartId（购物车结算）二选一
    struct Item: Identifiable {
        let id = UUID()
        let skuId: Int64?
        let count: Int?
        let cartId: Int64?
    }

    let items: [Item]
    /// 初始配送方式（1 快递 / 2 自提；虚拟商品强制 2，由调用方按 SPU 判定）
    let initialDeliveryType: Int
    /// 商品支持的自提门店 id（空 = 不过滤）
    let pickUpStoreIds: [Int64]
    /// 萝贝抵扣比例（0 = 不支持，不显示萝贝行）
    let radishCoinRate: Int

    init(items: [Item], deliveryType: Int = 1, pickUpStoreIds: [Int64] = [], radishCoinRate: Int = 0) {
        self.items = items
        self.initialDeliveryType = deliveryType
        self.pickUpStoreIds = pickUpStoreIds
        self.radishCoinRate = radishCoinRate
    }

    @StateObject private var vm = CheckoutViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showAddressPicker = false
    @State private var showCouponSheet = false
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
                            deliverySection
                            itemsCard
                            couponRow
                            coinSection
                            remarkCard
                            priceCard
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)

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
        .onAppear { vm.start(items: items, deliveryType: initialDeliveryType, storeIds: pickUpStoreIds, radishRate: radishCoinRate) }
        .fullScreenCover(isPresented: $showAddressPicker) {
            AddressListView(onSelect: { addr in
                vm.addressId = addr.id
                vm.loadSettlement()
            })
        }
        .sheet(isPresented: $showCouponSheet) { couponSheet }
        .fullScreenCover(isPresented: Binding(
            get: { payOrder != nil },
            set: { if !$0 { payOrder = nil } }
        )) {
            if let p = payOrder {
                PayView(payOrderId: p.id, priceFen: p.price,
                        totalFen: vm.settlement?.price?.totalPrice,
                        rabbitCoinFen: vm.settlement?.price?.rabbitCoinPrice,
                        radishCoinFen: vm.settlement?.price?.radishCoinPrice) {
                    payOrder = nil
                    NotificationCenter.default.post(name: .jjtOrderChanged, object: nil)
                    dismiss()
                }
            }
        }
        .onChange(of: vm.errorMessage) { _, msg in if let msg { showToast(msg); vm.errorMessage = nil } }
        .jjtPageGestures()
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

    // MARK: - 配送方式区

    @ViewBuilder
    private var deliverySection: some View {
        VStack(spacing: 12) {
            // 虚拟商品强制自提，不显示切换器（对齐安卓 #124）
            if !vm.isVirtual {
                HStack(spacing: 10) {
                    deliveryTab(1, "快递配送")
                    deliveryTab(2, "到店自提")
                }
            }

            if vm.deliveryType == 1 {
                addressCard
            } else {
                storeCard
                contactCard
            }
        }
    }

    private func deliveryTab(_ type: Int, _ label: String) -> some View {
        let sel = vm.deliveryType == type
        return Button { vm.switchDeliveryType(type) } label: {
            Text(label)
                .font(.system(size: 13, weight: sel ? .semibold : .regular))
                .foregroundStyle(sel ? Noir.goldPale : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(sel ? Noir.crimson.opacity(0.2) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? Noir.crimson.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

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
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    /// 自提门店（按商品支持门店过滤）
    private var storeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自提门店")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(vm.pickUpStores, id: \.id) { store in
                let sel = vm.pickUpStoreId == store.id
                HStack(spacing: 10) {
                    Image(systemName: "storefront")
                        .foregroundStyle(sel ? Noir.goldLight : .white.opacity(0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.name ?? "")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Noir.ivory)
                        Text("\(store.areaName ?? "") \(store.detailAddress ?? "") · \(store.openingTime ?? "")-\(store.closingTime ?? "")")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    NoirRadio(selected: sel)
                }
                .contentShape(Rectangle())
                .onTapGesture { vm.pickUpStoreId = store.id }
            }
            if vm.pickUpStores.isEmpty {
                Text(vm.isLoading ? "加载门店中…" : "暂无可用自提门店")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .cardStyle()
    }

    /// 自提联系人（手机号格式校验，对齐安卓 PickUpContactSection）
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自提联系人")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            TextField("联系人姓名", text: $vm.receiverName)
                .font(.system(size: 13))
                .noirField()
            VStack(alignment: .leading, spacing: 4) {
                TextField("联系电话", text: $vm.receiverMobile)
                    .font(.system(size: 13))
                    .keyboardType(.phonePad)
                    .noirField()
                if !vm.receiverMobile.isEmpty && !vm.receiverMobileValid {
                    Text("请输入正确的手机号")
                        .font(.system(size: 11))
                        .foregroundStyle(Noir.crimsonHot)
                }
            }
            Text("下单后到店凭核销码取货")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(14)
        .cardStyle()
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
        .cardStyle()
    }

    // MARK: - 优惠券

    private var couponRow: some View {
        Button { showCouponSheet = true } label: {
            HStack {
                Image(systemName: "ticket")
                    .foregroundStyle(Noir.crimsonHot)
                    .font(.system(size: 13))
                Text("优惠券")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Text(vm.selectedCouponDesc ?? "可用 \(vm.usableCouponCount) 张")
                    .font(.system(size: 12))
                    .foregroundStyle(vm.couponId != nil ? Noir.crimsonHot : .white.opacity(0.4))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private var couponSheet: some View {
        NavigationStack {
            ZStack {
                Noir.noir.ignoresSafeArea()
                List {
                    Button {
                        vm.selectCoupon(nil)
                        showCouponSheet = false
                    } label: {
                        Text("不使用优惠券")
                            .font(.system(size: 14))
                            .foregroundStyle(vm.couponId == nil ? Noir.crimsonHot : .white.opacity(0.7))
                    }
                    .listRowBackground(Color.clear)
                    ForEach(vm.settlement?.coupons ?? [], id: \.id) { c in
                        Button {
                            if c.match == true {
                                vm.selectCoupon(c.id)
                                showCouponSheet = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(couponText(c))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(c.match == true ? Noir.ivory : .white.opacity(0.3))
                                    if c.match != true, let reason = c.mismatchReason {
                                        Text(reason)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                }
                                Spacer()
                                if vm.couponId == c.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Noir.crimsonHot)
                                }
                            }
                        }
                        .disabled(c.match != true)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("选择优惠券")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showCouponSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func couponText(_ c: SettlementCoupon) -> String {
        switch c.discountType {
        case 1: return "满\(fenToYuan(c.usePrice))减\(fenToYuan(c.discountPrice))"
        case 2:
            let p = Double(c.discountPercent ?? 100) / 10.0
            return p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))折券" : "\(p)折券"
        default: return c.name ?? "优惠券"
        }
    }

    // MARK: - 虚拟币抵扣

    private var coinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("虚拟币抵扣")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            coinRow(name: "兔币抵扣", unit: "兔币",
                    balance: vm.settlement?.totalRabbitCoin ?? 0,
                    use: $vm.useRabbitCoin, input: $vm.rabbitCoinInput,
                    deductPrice: vm.settlement?.price?.rabbitCoinPrice)
            // 商品不支持萝贝（rate=0）时不显示（对齐安卓 #127）
            if radishCoinRate > 0 {
                coinRow(name: "萝贝抵扣", unit: "萝贝",
                        balance: vm.settlement?.totalRadishCoin ?? 0,
                        use: $vm.useRadishCoin, input: $vm.radishCoinInput,
                        deductPrice: vm.settlement?.price?.radishCoinPrice)
            }
        }
        .padding(14)
        .cardStyle()
    }

    private func coinRow(name: String, unit: String, balance: Int,
                         use: Binding<Bool>, input: Binding<String>, deductPrice: Int?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "gem")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.gold)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                Text("余额 \(balance)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Toggle("", isOn: use)
                    .tint(Noir.crimson)
                    .labelsHidden()
                    .onChange(of: use.wrappedValue) { _, _ in vm.loadSettlement() }
            }
            if use.wrappedValue {
                HStack {
                    TextField("输入\(unit)数量", text: input)
                        .font(.system(size: 13))
                        .keyboardType(.numberPad)
                        .noirField()
                        .onChange(of: input.wrappedValue) { _, _ in vm.loadSettlement() }
                    if let p = deductPrice, p > 0 {
                        Text("-¥\(fenToYuan(p))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Noir.crimsonHot)
                    }
                }
            }
        }
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
        .cardStyle()
    }

    // MARK: - 价格卡

    private var priceCard: some View {
        VStack(spacing: 8) {
            priceLine("商品金额", fen: vm.settlement?.price?.totalPrice)
            priceLine("运费", fen: vm.settlement?.price?.deliveryPrice)
            if (vm.settlement?.price?.discountPrice ?? 0) > 0 {
                priceLine("订单优惠", fen: vm.settlement?.price?.discountPrice, negative: true)
            }
            if (vm.settlement?.price?.couponPrice ?? 0) > 0 {
                priceLine("优惠券", fen: vm.settlement?.price?.couponPrice, negative: true)
            }
            if (vm.settlement?.price?.vipPrice ?? 0) > 0 {
                priceLine("VIP 减免", fen: vm.settlement?.price?.vipPrice, negative: true)
            }
            if (vm.settlement?.price?.rabbitCoinPrice ?? 0) > 0 {
                priceLine("兔币抵扣", fen: vm.settlement?.price?.rabbitCoinPrice, negative: true)
            }
            if (vm.settlement?.price?.radishCoinPrice ?? 0) > 0 {
                priceLine("萝贝抵扣", fen: vm.settlement?.price?.radishCoinPrice, negative: true)
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
        .cardStyle()
    }

    private func priceLine(_ label: String, fen: Int?, negative: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text("\(negative ? "-" : "")¥\(fenToYuan(fen))")
                .font(.system(size: 12))
                .foregroundStyle(negative ? Noir.crimsonHot : Noir.ivory)
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
                vm.createOrder(remark: remark) { orderId, payOrderId, price in
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
            .disabled(!vm.canSubmit || vm.isSubmitting)
            .opacity(vm.canSubmit ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.95))
    }
}

// MARK: - 结算/下单模型（对齐安卓 SettlementResp 等）

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

struct SettlementCoupon: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let usePrice: Int?
    let discountType: Int?
    let discountPercent: Int?
    let discountPrice: Int?
    let match: Bool?
    let mismatchReason: String?
}

struct SettlementPrice: Decodable {
    let totalPrice: Int?
    let discountPrice: Int?
    let deliveryPrice: Int?
    let couponPrice: Int?
    let pointPrice: Int?
    let vipPrice: Int?
    let rabbitCoinPrice: Int?
    let radishCoinPrice: Int?
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
    let coupons: [SettlementCoupon]?
    let price: SettlementPrice?
    let address: SettlementAddress?
    let totalRabbitCoin: Int?
    let useRabbitCoin: Int?
    let totalRadishCoin: Int?
    let useRadishCoin: Int?
}

struct PickUpStore: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let areaName: String?
    let detailAddress: String?
    let openingTime: String?
    let closingTime: String?
}

private struct OrderCreateReq: Encodable {
    struct Item: Encodable {
        let skuId: Int64?
        let count: Int?
        let cartId: Int64?
    }
    let items: [Item]
    let couponId: Int64?
    let pointStatus: Bool
    let addressId: Int64?
    let deliveryType: Int
    let remark: String?
    let receiverName: String?
    let receiverMobile: String?
    let pickUpStoreId: Int64?
    let rabbitCoinStatus: Bool
    let useRabbitCoin: Int?
    let radishCoinStatus: Bool
    let useRadishCoin: Int?
}

private struct OrderCreateResp: Decodable {
    let id: Int64
    let payOrderId: Int64?
}

private extension View {
    func cardStyle() -> some View {
        background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

private func NoirRadio(selected: Bool) -> some View {
    ZStack {
        Circle()
            .stroke(selected ? Noir.crimson : Color.white.opacity(0.3), lineWidth: 1.5)
        if selected {
            Circle().fill(Noir.crimson).padding(4)
        }
    }
    .frame(width: 18, height: 18)
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

    // 配送
    @Published var deliveryType = 1
    @Published var isVirtual = false
    @Published var addressId: Int64?
    @Published var pickUpStores: [PickUpStore] = []
    @Published var pickUpStoreId: Int64?
    @Published var receiverName = ""
    @Published var receiverMobile = ""
    // 券/币
    @Published var couponId: Int64?
    @Published var useRabbitCoin = false
    @Published var rabbitCoinInput = ""
    @Published var useRadishCoin = false
    @Published var radishCoinInput = ""

    private var items: [CheckoutView.Item] = []
    private var allowedStoreIds: Set<Int64> = []
    private var radishRate = 0
    private var fallbackTried = false

    var receiverMobileValid: Bool {
        receiverMobile.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    /// 提交校验（对齐安卓：快递要地址；自提要联系人+手机号+门店）
    var canSubmit: Bool {
        guard settlement != nil else { return false }
        if deliveryType == 1 {
            return settlement?.address?.id != nil
        }
        return !receiverName.isEmpty && receiverMobileValid && pickUpStoreId != nil
    }

    var usableCouponCount: Int { settlement?.coupons?.filter { $0.match == true }.count ?? 0 }

    var selectedCouponDesc: String? {
        guard let couponId, let c = settlement?.coupons?.first(where: { $0.id == couponId }) else { return nil }
        switch c.discountType {
        case 1: return "满\(fenToYuan(c.usePrice))减\(fenToYuan(c.discountPrice))"
        case 2:
            let p = Double(c.discountPercent ?? 100) / 10.0
            return p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))折" : "\(p)折"
        default: return c.name
        }
    }

    func start(items: [CheckoutView.Item], deliveryType: Int, storeIds: [Int64], radishRate: Int) {
        guard self.items.isEmpty else { return }
        self.items = items
        self.deliveryType = deliveryType
        self.isVirtual = deliveryType == 2 && !storeIds.isEmpty || itemsAreVirtual(deliveryType)
        self.allowedStoreIds = Set(storeIds)
        self.radishRate = radishRate
        if deliveryType == 2 { loadPickUpStores() }
        loadSettlement()
    }

    /// 简化判定：调用方传 2 即按自提初始化（虚拟商品由详情页强制传 2）
    private func itemsAreVirtual(_ t: Int) -> Bool { t == 2 }

    func switchDeliveryType(_ type: Int) {
        guard deliveryType != type else { return }
        fallbackTried = false
        deliveryType = type
        if type == 2 && pickUpStores.isEmpty { loadPickUpStores() }
        loadSettlement()
    }

    func selectCoupon(_ id: Int64?) {
        couponId = id
        loadSettlement()
    }

    func loadPickUpStores() {
        Task {
            let all: [PickUpStore] = (try? await APIClient.shared.get("app-api/trade/delivery/pick-up-store/list")) ?? []
            pickUpStores = allowedStoreIds.isEmpty ? all : all.filter { allowedStoreIds.contains($0.id) }
            if pickUpStoreId == nil { pickUpStoreId = pickUpStores.first?.id }
        }
    }

    /// 结算（对齐安卓：items[i] 拍平 + 配送/券/虚拟币全参数；1011003005 自动回退重试）
    func loadSettlement() {
        guard !items.isEmpty else { return }
        isLoading = true
        var query: [String: String] = [
            "deliveryType": "\(deliveryType)",
            "pointStatus": "false",
            "rabbitCoinStatus": "\(useRabbitCoin)",
            "radishCoinStatus": "\(useRadishCoin)",
        ]
        for (i, item) in items.enumerated() {
            if let skuId = item.skuId { query["items[\(i)].skuId"] = "\(skuId)" }
            if let count = item.count { query["items[\(i)].count"] = "\(count)" }
            if let cartId = item.cartId { query["items[\(i)].cartId"] = "\(cartId)" }
        }
        if deliveryType == 1 {
            let aid = addressId ?? settlement?.address?.id
            if let aid { query["addressId"] = "\(aid)" }
        } else {
            if !receiverName.isEmpty { query["receiverName"] = receiverName }
            if !receiverMobile.isEmpty { query["receiverMobile"] = receiverMobile }
            if let sid = pickUpStoreId { query["pickUpStoreId"] = "\(sid)" }
        }
        if let couponId { query["couponId"] = "\(couponId)" }
        if useRabbitCoin, !rabbitCoinInput.isEmpty { query["useRabbitCoin"] = rabbitCoinInput }
        if useRadishCoin, !radishCoinInput.isEmpty { query["useRadishCoin"] = radishCoinInput }

        Task {
            defer { isLoading = false }
            do {
                settlement = try await APIClient.shared.get("app-api/trade/order/settlement", query: query)
            } catch let e as APIError {
                // 配送方式不匹配（1011003005）：自动回退另一配送方式重试一次（对齐安卓）
                if case .business(let code, _) = e, code == 1011003005, !fallbackTried {
                    fallbackTried = true
                    deliveryType = deliveryType == 1 ? 2 : 1
                    if deliveryType == 2 { loadPickUpStores() }
                    loadSettlement()
                } else {
                    errorMessage = e.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createOrder(remark: String,
                     onCreated: @escaping (Int64, Int64?, Int) -> Void) {
        guard canSubmit else {
            errorMessage = deliveryType == 1 ? "请选择收货地址" : "请完善自提信息（门店/联系人/手机号）"
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
                        couponId: couponId,
                        pointStatus: false,
                        addressId: deliveryType == 1 ? settlement?.address?.id : nil,
                        deliveryType: deliveryType,
                        remark: remark.isEmpty ? nil : remark,
                        receiverName: deliveryType == 2 ? receiverName : nil,
                        receiverMobile: deliveryType == 2 ? receiverMobile : nil,
                        pickUpStoreId: deliveryType == 2 ? pickUpStoreId : nil,
                        rabbitCoinStatus: useRabbitCoin,
                        useRabbitCoin: useRabbitCoin ? Int(rabbitCoinInput) : nil,
                        radishCoinStatus: useRadishCoin,
                        useRadishCoin: useRadishCoin ? Int(radishCoinInput) : nil
                    ))
                onCreated(resp.id, resp.payOrderId, settlement?.price?.payPrice ?? 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
