import SwiftUI
import WebKit

/// 商品详情 — 对齐安卓 SpuDetailScreen
/// 结构：媒体轮播 → 价格标题 → 规格行（SKU 弹层）→ 富文本详情 → 底部操作栏
/// v1 未含：评价区、领券、收藏（后续补）
struct SpuDetailView: View {

    let spuId: Int64

    @StateObject private var vm = SpuDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showSkuSheet = false
    @State private var toast: String?
    @State private var checkoutItem: CheckoutView.Item?

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()

            if let spu = vm.spu {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            mediaPager(spu)
                            priceSection(spu)
                            specRow(spu)
                            if let desc = spu.description, !desc.isEmpty {
                                detailHtml(desc)
                            }
                            serviceTags
                        }
                    }
                    bottomBar(spu)
                }
            } else {
                ProgressView().tint(Noir.crimson)
            }

            // 悬浮返回
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.45))
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 56)
                    Spacer()
                }
                Spacer()
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
                        .padding(.bottom, 120)
                        .transition(.opacity)
                }
            }
        }
        .onAppear { vm.load(id: spuId) }
        .sheet(isPresented: $showSkuSheet) {
            if let spu = vm.spu {
                SkuSheet(spu: spu,
                         onDone: { msg in
                             showSkuSheet = false
                             if let msg { showToast(msg) }
                             vm.refreshCartCount()
                         },
                         onBuyNow: { skuId, count in
                             showSkuSheet = false
                             checkoutItem = CheckoutView.Item(skuId: skuId, count: count, cartId: nil)
                         })
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { checkoutItem != nil },
            set: { if !$0 { checkoutItem = nil } }
        )) {
            if let item = checkoutItem, let spu = vm.spu {
                // 对齐安卓：虚拟商品强制自提；实物不支持快递则默认自提（#123/#124）
                let isVirtual = (spu.productType ?? 0) == 1
                let types = spu.deliveryTypes ?? []
                let defaultDelivery = isVirtual ? 2 : (!types.isEmpty && !types.contains(1) ? 2 : 1)
                CheckoutView(
                    items: [item],
                    deliveryType: defaultDelivery,
                    pickUpStoreIds: spu.pickUpStoreIds ?? [],
                    radishCoinRate: spu.radishCoinDeductMaxRate ?? 0
                )
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: - 媒体轮播

    private func mediaPager(_ spu: SpuDetail) -> some View {
        let images = spu.sliderPicUrls ?? (spu.picUrl.map { [$0] } ?? [])
        return ZStack(alignment: .bottom) {
            if !images.isEmpty {
                TabView {
                    ForEach(images.indices, id: \.self) { i in
                        AsyncImage(url: webImageURL(images[i])) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Noir.noir3
                            }
                        }
                        .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenWidth)
                        .clipped()
                        .tag(i)
                    }
                }
                .tabViewStyle(.page)
                .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenWidth)
                .clipped()
            } else {
                Noir.noir3
                    .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenWidth)
            }
            // 底部融入底色
            LinearGradient(colors: [.clear, Noir.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
                .allowsHitTesting(false)
        }
        .frame(width: JJTMetrics.screenWidth, height: JJTMetrics.screenWidth)
    }

    // MARK: - 价格与标题

    private func priceSection(_ spu: SpuDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("¥\(fenToYuan(spu.price))")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0xFF/255, green: 0x5F/255, blue: 0x7E/255), Noir.crimson, Color(red: 0x7A/255, green: 0x0A/255, blue: 0x1C/255)], startPoint: .leading, endPoint: .trailing))
                if (spu.marketPrice ?? 0) > (spu.price ?? 0) {
                    Text("¥\(fenToYuan(spu.marketPrice))")
                        .font(.system(size: 13))
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.bottom, 3)
                    let discount = (spu.price ?? 0) * 10 / max(spu.marketPrice ?? 1, 1)
                    Text("限时 \(discount)折")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.crimsonHot)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Noir.crimson.opacity(0.2))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Noir.crimson.opacity(0.4), lineWidth: 1))
                        .padding(.bottom, 3)
                }
            }
            Text(spu.name ?? "")
                .font(.system(size: 19, weight: .bold, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(Noir.ivory)
            HStack(spacing: 12) {
                Text("已售\(spu.salesCount ?? 0)")
                HStack(spacing: 4) {
                    Image(systemName: "cart").font(.system(size: 10))
                    Text("顺丰包邮")
                }
                if (spu.productType ?? 0) == 1 {
                    Text("虚拟商品 · 到店核销")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Noir.goldLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Noir.gold.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Noir.gold.opacity(0.4), lineWidth: 1))
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 规格行

    private func specRow(_ spu: SpuDetail) -> some View {
        let specText = (spu.skus ?? []).count <= 1 ? "默认" : "请选择规格"
        return HStack {
            Text("规格")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(specText)
                .font(.system(size: 13))
                .foregroundStyle(Noir.ivory)
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(LinearGradient(colors: [Color(red: 0x1A/255, green: 0x1A/255, blue: 0x20/255).opacity(0.92), Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .contentShape(Rectangle())
        .onTapGesture { showSkuSheet = true }
    }

    // MARK: - 富文本详情

    private func detailHtml(_ html: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("商品详情")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Noir.ivory)
            HtmlView(html: html)
                .frame(minHeight: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - 服务保障

    private var serviceTags: some View {
        HStack(spacing: 16) {
            ForEach(["正品保障", "顺丰包邮", "7天无理由"], id: \.self) { tag in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.gold.opacity(0.7))
                    Text(tag)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // MARK: - 底部操作栏

    private func bottomBar(_ spu: SpuDetail) -> some View {
        HStack(spacing: 12) {
            Button { showSkuSheet = true } label: {
                Text("加入购物车")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Noir.goldPale)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule()
                            .stroke(Noir.gold.opacity(0.5), lineWidth: 1)
                            .background(Capsule().fill(Color.clear))
                    )
            }
            Button { showSkuSheet = true } label: {
                Text("立即购买")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(red: 0x0C/255, green: 0x0C/255, blue: 0x10/255).opacity(0.95))
    }
}

// MARK: - SKU 选择弹层（对齐安卓 SkuSelectorSheet）

struct SkuSheet: View {
    let spu: SpuDetail
    /// 完成回调（message 非空为提示文案）
    let onDone: (String?) -> Void
    /// 立即购买：不走加购，直接带 skuId+count 去结算
    let onBuyNow: (Int64, Int) -> Void

    @State private var selected: [String: String] = [:] // propertyName → valueName
    @State private var count = 1
    @State private var isSubmitting = false

    /// 按属性名分组的可选值
    private var groups: [(name: String, values: [String])] {
        var order: [String] = []
        var map: [String: [String]] = [:]
        for sku in spu.skus ?? [] {
            for p in sku.properties ?? [] {
                guard let pn = p.propertyName, let vn = p.valueName else { continue }
                if map[pn] == nil { order.append(pn); map[pn] = [] }
                if map[pn]?.contains(vn) == false { map[pn]?.append(vn) }
            }
        }
        return order.map { (name: $0, values: map[$0] ?? []) }
    }

    /// 当前选中的 SKU（所有组都选了且能匹配到）
    private var matchedSku: SpuDetailSku? {
        let gs = groups
        guard !gs.isEmpty, gs.allSatisfy({ selected[$0.name] != nil }) else {
            // 单规格商品直接返回唯一 SKU
            return (spu.skus?.count == 1) ? spu.skus?.first : nil
        }
        return (spu.skus ?? []).first { sku in
            gs.allSatisfy { g in
                sku.properties?.contains(where: { $0.propertyName == g.name && $0.valueName == selected[g.name] }) == true
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Noir.noir.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // 头部：图 + 价格 + 库存（sku.picUrl 可能为空串，须回退 SPU 图）
                            HStack(spacing: 14) {
                                AsyncImage(url: webImageURL(matchedSku?.picUrl.flatMap { $0.isEmpty ? nil : $0 } ?? spu.picUrl)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Noir.noir3
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("¥\(fenToYuan(matchedSku?.price ?? spu.price))")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(LinearGradient(colors: [Color(red: 0xFF/255, green: 0x5F/255, blue: 0x7E/255), Noir.crimson], startPoint: .leading, endPoint: .trailing))
                                    Text("库存 \(matchedSku?.stock ?? spu.stock ?? 0) 件")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.4))
                                    if let sku = matchedSku, let props = sku.properties, !props.isEmpty {
                                        Text("已选：" + props.compactMap(\.valueName).joined(separator: " / "))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Noir.textDim)
                                    }
                                }
                                Spacer()
                            }

                            // 属性组
                            ForEach(groups, id: \.name) { g in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(g.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Noir.ivory)
                                    FlowLayout(spacing: 10) {
                                        ForEach(g.values, id: \.self) { v in
                                            let sel = selected[g.name] == v
                                            Text(v)
                                                .font(.system(size: 12))
                                                .foregroundStyle(sel ? Noir.goldPale : .white.opacity(0.7))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(sel ? Noir.crimson.opacity(0.25) : Color.white.opacity(0.05))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(sel ? Noir.crimson : Color.white.opacity(0.1), lineWidth: 1))
                                                .onTapGesture { selected[g.name] = v }
                                        }
                                    }
                                }
                            }

                            // 数量
                            HStack {
                                Text("数量")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Noir.ivory)
                                Spacer()
                                StepperView(count: $count, max: max(matchedSku?.stock ?? 99, 1))
                            }
                        }
                        .padding(20)
                    }

                    // 确定
                    HStack(spacing: 12) {
                        Button { submit(buyNow: false) } label: {
                            Text("加入购物车")
                        }
                        .buttonStyle(NoirPrimaryButtonStyle(enabled: canSubmit && !isSubmitting))
                        .disabled(!canSubmit || isSubmitting)
                        Button { submit(buyNow: true) } label: {
                            Text("立即购买")
                        }
                        .buttonStyle(NoirPrimaryButtonStyle(enabled: canSubmit && !isSubmitting))
                        .disabled(!canSubmit || isSubmitting)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("选择规格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onDone(nil) }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var canSubmit: Bool {
        guard let sku = matchedSku else { return groups.isEmpty && (spu.skus?.isEmpty ?? true) }
        return (sku.stock ?? 0) > 0
    }

    private func submit(buyNow: Bool) {
        guard let sku = matchedSku ?? spu.skus?.first else {
            onDone("该商品暂不可购买")
            return
        }
        // 立即购买：直接结算，不进购物车（对齐安卓）
        if buyNow {
            onBuyNow(sku.id, count)
            return
        }
        isSubmitting = true
        Task {
            do {
                _ = try await MallAPI.cartAdd(skuId: sku.id, count: count)
                isSubmitting = false
                onDone("已加入购物车")
            } catch {
                isSubmitting = false
                onDone(error.localizedDescription)
            }
        }
    }
}

// MARK: - 数量步进器

private struct StepperView: View {
    @Binding var count: Int
    var max: Int = 99

    var body: some View {
        HStack(spacing: 0) {
            Button { if count > 1 { count -= 1 } } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
            }
            .foregroundStyle(count > 1 ? Noir.ivory : Noir.textFaint)
            Text("\(count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Noir.ivory)
                .frame(minWidth: 32)
            Button { if count < max { count += 1 } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
            }
            .foregroundStyle(count < max ? Noir.ivory : Noir.textFaint)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - 流式布局（属性标签换行）

private struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - HTML 渲染（WKWebView 包裹）

struct HtmlView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        let styled = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        body { background: transparent; color: rgba(255,255,255,0.7);
               font: 14px/1.7 -apple-system; margin: 0; }
        img { max-width: 100% !important; height: auto !important; border-radius: 8px; }
        a { color: #E8304F; }
        </style></head><body>\(html)</body></html>
        """
        wv.loadHTMLString(styled, baseURL: nil)
    }
}

// MARK: - ViewModel

@MainActor
final class SpuDetailViewModel: ObservableObject {
    @Published var spu: SpuDetail?
    @Published var isLoading = false

    func load(id: Int64) {
        isLoading = true
        Task {
            defer { isLoading = false }
            spu = try? await MallAPI.spuDetail(id: id)
        }
    }

    func refreshCartCount() {
        NotificationCenter.default.post(name: .jjtCartChanged, object: nil)
    }
}

/// 购物车变动通知（首页角标等监听）
extension Notification.Name {
    static let jjtCartChanged = Notification.Name("jjtCartChanged")
}
