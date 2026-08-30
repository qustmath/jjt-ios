import SwiftUI

/// 商城首页 — 对齐安卓 MallTab：搜索+购物车 → 优惠券横幅 → 排序栏 → 双列商品流
struct MallHomeView: View {

    @StateObject private var vm = MallHomeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var detailSpuId: Int64?
    @State private var showCart = false
    @State private var showCouponCenter = false
    @State private var keyword = ""

    var body: some View {
        ZStack {
            Noir.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                couponBanner
                sortBar
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                // 排序 tab 分页容器：左右滑切换（对齐安卓与广场 tab 一致的体验）
                TabView(selection: $vm.sort) {
                    ForEach(MallHomeViewModel.Sort.allCases, id: \.self) { s in
                        gridSection.tag(s)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .jjtKeyboardDismiss()
        .onAppear {
            vm.load()
            vm.refreshCartCount()
        }
        .onChange(of: vm.sort) { _, s in vm.load(sort: s) }
        // 加购成功 → 刷新购物车角标
        .onReceive(NotificationCenter.default.publisher(for: .jjtCartChanged)) { _ in
            vm.refreshCartCount()
        }
        .fullScreenCover(isPresented: Binding(
            get: { detailSpuId != nil },
            set: { if !$0 { detailSpuId = nil } }
        )) {
            if let id = detailSpuId {
                SpuDetailView(spuId: id)
            }
        }
    }

    // MARK: - 顶栏：返回 + 搜索 + 标题 + 购物车

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("搜索暗夜好物", text: $keyword)
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.ivory)
                    .submitLabel(.search)
                    .onSubmit { vm.load(keyword: keyword) }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        vm.load(keyword: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))

            Button { showCart = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "cart")
                        .font(.system(size: 19))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 38, height: 38)
                    if vm.cartCount > 0 {
                        Text("\(min(vm.cartCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(Noir.crimson))
                            .offset(x: 4, y: -2)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .fullScreenCover(isPresented: $showCart) { CartView() }
    }

    // MARK: - 优惠券横幅

    private var couponBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "ticket")
                .font(.system(size: 14))
                .foregroundStyle(Noir.crimsonHot)
            Text("领券中心 · 好礼券限量发放中")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("领取")
                .font(.system(size: 10))
                .foregroundStyle(Noir.crimsonHot)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(LinearGradient(colors: [Noir.crimson.opacity(0.18), Noir.gold.opacity(0.12)], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.crimson.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { showCouponCenter = true }
        .fullScreenCover(isPresented: $showCouponCenter) { CouponCenterView() }
    }

    // MARK: - 排序栏

    private var sortBar: some View {
        HStack(spacing: 24) {
            ForEach(MallHomeViewModel.Sort.allCases, id: \.self) { s in
                let selected = vm.sort == s
                VStack(spacing: 3) {
                    Text(s.label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Noir.crimsonHot : Color.white.opacity(0.4))
                    Capsule()
                        .fill(selected
                              ? LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)
                              : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 20, height: 2.5)
                }
                .onTapGesture { vm.sort = s }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 商品双列流

    private var gridSection: some View {
        ScrollView {
            if vm.isLoading {
                ProgressView().tint(Noir.crimson)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
            } else if vm.items.isEmpty {
                Text("暂无商品")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
            } else {
                let colW = (JJTMetrics.screenWidth - 20 - 10) / 2
                LazyVGrid(columns: [GridItem(.fixed(colW), spacing: 10), GridItem(.fixed(colW))], spacing: 10) {
                    ForEach(vm.items) { item in
                        SpuCard(item: item, width: colW) { detailSpuId = item.id }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)

                if vm.isLoadingMore {
                    ProgressView().tint(Noir.crimson).frame(maxWidth: .infinity).padding(16)
                } else if !vm.isEnd {
                    Color.clear.frame(height: 1).onAppear { vm.loadMore() }
                }

                Text("荆棘兔官方出品 · 暗夜好物持续上新")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .refreshable { vm.load() }
    }
}

// MARK: - 商品卡片（对齐安卓 SpuCard）

struct SpuCard: View {
    let item: SpuListItem
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 封面
            ZStack {
                if let pic = item.picUrl, !pic.isEmpty {
                    AsyncImage(url: webImageURL(pic)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Noir.noir3
                        }
                    }
                    .frame(width: width, height: width)
                    .clipped()
                } else {
                    LinearGradient(colors: [Color(red: 0x2E/255, green: 0x0A/255, blue: 0x14/255), Color(red: 0x10/255, green: 0x06/255, blue: 0x0A/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: width, height: width)
                        .overlay(Image(systemName: "bag").font(.system(size: 32)).foregroundStyle(.white.opacity(0.15)))
                }
                // 底部暗渐变
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                        .frame(height: width * 0.4)
                }
                .allowsHitTesting(false)
            }
            .frame(width: width, height: width)

            // 信息
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name ?? "")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(Noir.ivory)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .bottom, spacing: 6) {
                    Text("¥\(fenToYuan(item.price))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0xFF/255, green: 0x5F/255, blue: 0x7E/255), Noir.crimson, Color(red: 0x7A/255, green: 0x0A/255, blue: 0x1C/255)], startPoint: .leading, endPoint: .trailing))
                    if (item.marketPrice ?? 0) > (item.price ?? 0) {
                        Text("¥\(fenToYuan(item.marketPrice))")
                            .font(.system(size: 10))
                            .strikethrough()
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }

                HStack {
                    Text("已售\(item.salesCount ?? 0)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "cart")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - ViewModel

@MainActor
final class MallHomeViewModel: ObservableObject {

    enum Sort: CaseIterable {
        case def, priceAsc, salesDesc
        var label: String { switch self { case .def: "综合"; case .priceAsc: "价格"; case .salesDesc: "销量" } }
        var field: String? { switch self { case .def: nil; case .priceAsc: "price"; case .salesDesc: "salesCount" } }
        var asc: Bool? { switch self { case .def: nil; case .priceAsc: true; case .salesDesc: false } }
    }

    @Published var items: [SpuListItem] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var isEnd = false
    @Published var sort: Sort = .def
    @Published var keyword: String?
    @Published var cartCount = 0

    private var pageNo = 1

    func load(sort: Sort? = nil, keyword: String? = nil) {
        if let sort { self.sort = sort }
        self.keyword = keyword
        pageNo = 1
        isLoading = true
        Task {
            defer { isLoading = false }
            if let resp = try? await MallAPI.spuPage(pageNo: 1, keyword: self.keyword, sortField: self.sort.field, sortAsc: self.sort.asc) {
                items = resp.list ?? []
                isEnd = (resp.list?.count ?? 0) < 10
            }
        }
        Task { cartCount = (try? await MallAPI.cartCount()) ?? 0 }
    }

    func loadMore() {
        guard !isLoading, !isLoadingMore, !isEnd else { return }
        isLoadingMore = true
        let next = pageNo + 1
        Task {
            defer { isLoadingMore = false }
            guard let resp = try? await MallAPI.spuPage(pageNo: next, keyword: keyword, sortField: sort.field, sortAsc: sort.asc) else { return }
            let list = resp.list ?? []
            let existing = Set(items.map(\.id))
            items += list.filter { !existing.contains($0.id) }
            pageNo = next
            isEnd = list.count < 10
        }
    }

    /// 加购成功后刷新角标
    func refreshCartCount() {
        Task { cartCount = (try? await MallAPI.cartCount()) ?? 0 }
    }
}
