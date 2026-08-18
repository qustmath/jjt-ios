import SwiftUI

// MARK: - 收藏 / 优惠券 API（对齐安卓 FavoriteApi / CouponApi）

private struct FavoriteReq: Encodable { let spuId: Int64 }
private struct CouponTakeReq: Encodable { let templateId: Int64 }

enum FavoriteAPI {
    /// 收藏状态
    static func exists(spuId: Int64) async throws -> Bool {
        try await APIClient.shared.get("app-api/product/favorite/exits", query: ["spuId": "\(spuId)"])
    }

    static func add(spuId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/product/favorite/create", body: FavoriteReq(spuId: spuId))
    }

    static func remove(spuId: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/product/favorite/delete", body: FavoriteReq(spuId: spuId))
    }

    static func page(pageNo: Int) async throws -> PageResult<FavoriteItem> {
        try await APIClient.shared.get("app-api/product/favorite/page", query: ["pageNo": "\(pageNo)", "pageSize": "20"])
    }
}

struct FavoriteItem: Decodable, Identifiable {
    let id: Int64
    let spuId: Int64
    let spuName: String?
    let picUrl: String?
    let price: Int?
}

enum CouponAPI {
    /// 领券中心分页
    static func templatePage(pageNo: Int) async throws -> PageResult<CouponTemplate> {
        try await APIClient.shared.get("app-api/promotion/coupon-template/page", query: ["pageNo": "\(pageNo)", "pageSize": "10"])
    }

    /// 商品可领券
    static func templateList(spuId: Int64) async throws -> [CouponTemplate] {
        try await APIClient.shared.get("app-api/promotion/coupon-template/list", query: ["spuId": "\(spuId)", "count": "10"])
    }

    /// 领取
    static func take(templateId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/promotion/coupon/take", body: CouponTakeReq(templateId: templateId))
    }
}

struct CouponTemplate: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let description: String?
    let totalCount: Int?
    let usePrice: Int?
    let validStartTime: String?
    let validEndTime: String?
    let discountType: Int?
    let discountPercent: Int?
    let discountPrice: Int?
    let takeCount: Int?
    let canTake: Bool?
}

// MARK: - 我的收藏页（对齐安卓 FavoriteScreen）

struct FavoriteView: View {

    @StateObject private var vm = FavoriteViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var detailSpuId: Int64?

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
                    Text("我的收藏")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if vm.isLoading && vm.items.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else if vm.items.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "heart")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("还没有收藏商品")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                } else {
                    let colW = (JJTMetrics.screenWidth - 32 - 10) / 2
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.fixed(colW), spacing: 10), GridItem(.fixed(colW))], spacing: 10) {
                            ForEach(vm.items) { item in
                                VStack(spacing: 0) {
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: webImageURL(item.picUrl.flatMap { $0.isEmpty ? nil : $0 })) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Noir.noir3
                                            }
                                        }
                                        .frame(width: colW, height: colW)
                                        .clipped()
                                        Button { vm.remove(item) } label: {
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Noir.crimsonHot)
                                                .padding(8)
                                                .background(Color.black.opacity(0.4))
                                                .clipShape(Circle())
                                        }
                                        .padding(8)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.spuName ?? "")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Noir.ivory)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("¥\(fenToYuan(item.price))")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Noir.crimsonHot)
                                    }
                                    .padding(10)
                                }
                                .background(Color(red: 0x14/255, green: 0x14/255, blue: 0x19/255))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
                                .contentShape(Rectangle())
                                .onTapGesture { detailSpuId = item.spuId }
                            }
                        }
                        .padding(16)

                        if !vm.isEnd {
                            Color.clear.frame(height: 1).onAppear { vm.loadMore() }
                        }
                    }
                    .refreshable { vm.load() }
                }
            }
        }
        .onAppear { vm.load() }
        .fullScreenCover(isPresented: Binding(
            get: { detailSpuId != nil },
            set: { if !$0 { detailSpuId = nil } }
        )) {
            if let id = detailSpuId {
                SpuDetailView(spuId: id)
            }
        }
    }
}

@MainActor
final class FavoriteViewModel: ObservableObject {
    @Published var items: [FavoriteItem] = []
    @Published var isLoading = false
    @Published var isEnd = false
    private var pageNo = 1

    func load() {
        pageNo = 1
        isLoading = true
        Task {
            defer { isLoading = false }
            if let resp = try? await FavoriteAPI.page(pageNo: 1) {
                items = resp.list ?? []
                isEnd = (resp.list?.count ?? 0) < 20
            }
        }
    }

    func loadMore() {
        guard !isLoading, !isEnd else { return }
        let next = pageNo + 1
        Task {
            guard let resp = try? await FavoriteAPI.page(pageNo: next) else { return }
            let list = resp.list ?? []
            let existing = Set(items.map(\.id))
            items += list.filter { !existing.contains($0.id) }
            pageNo = next
            isEnd = list.count < 20
        }
    }

    func remove(_ item: FavoriteItem) {
        let backup = items
        items.removeAll { $0.id == item.id }
        Task {
            let ok = try? await FavoriteAPI.remove(spuId: item.spuId)
            if ok == nil { items = backup }
        }
    }
}

// MARK: - 领券中心（对齐安卓 CouponScreens）

struct CouponCenterView: View {

    @StateObject private var vm = CouponCenterViewModel()
    @Environment(\.dismiss) private var dismiss
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
                    Text("领券中心")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if vm.isLoading && vm.coupons.isEmpty {
                    Spacer()
                    ProgressView().tint(Noir.crimson)
                    Spacer()
                } else if vm.coupons.isEmpty {
                    Spacer()
                    Text("暂无可领优惠券")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.coupons) { c in
                                couponCard(c)
                            }
                        }
                        .padding(16)

                        if !vm.isEnd {
                            Color.clear.frame(height: 1).onAppear { vm.loadMore() }
                        }
                    }
                    .refreshable { vm.load() }
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
                        .padding(.bottom, 60)
                }
            }
        }
        .onAppear { vm.load() }
        .onChange(of: vm.message) { _, msg in
            if let msg { showToast(msg); vm.message = nil }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    private func couponCard(_ c: CouponTemplate) -> some View {
        let wineBg = Color(red: 0.36, green: 0.04, blue: 0.09).opacity(0.5)
        let darkBg = Color(red: 0.08, green: 0.03, blue: 0.04).opacity(0.7)
        return HStack(spacing: 0) {
            // 左侧票面
            VStack(alignment: .leading, spacing: 4) {
                Text(discountText(c))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Noir.ivory)
                if let usePrice = c.usePrice, usePrice > 0 {
                    Text("满¥\(fenToYuan(usePrice))可用")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("无门槛")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if let name = c.name {
                    Text(name)
                        .font(.system(size: 10))
                        .foregroundStyle(Noir.textDim)
                        .lineLimit(1)
                }
                if let end = c.validEndTime {
                    Text("有效期至 \(String(end.prefix(10)))")
                        .font(.system(size: 9))
                        .foregroundStyle(Noir.textFaint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Spacer()

            // 领取按钮（背景分支用 Group 包，避免三元异构类型触发编译器推断崩溃）
            Button { vm.take(c) } label: {
                Text(c.canTake == true ? "领取" : "已领取")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.canTake == true ? .white : .white.opacity(0.35))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if c.canTake == true {
                                Capsule().fill(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine], startPoint: .leading, endPoint: .trailing))
                            } else {
                                Capsule().fill(Color.white.opacity(0.08))
                            }
                        }
                    )
            }
            .disabled(c.canTake != true)
            .padding(.trailing, 14)
        }
        .background(LinearGradient(colors: [wineBg, darkBg], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.crimson.opacity(0.3), lineWidth: 1))
    }

    private func discountText(_ c: CouponTemplate) -> String {
        let type = c.discountType ?? 0
        if type == 1 {
            return "¥\(fenToYuan(c.discountPrice))"
        }
        if type == 2 {
            let p = Double(c.discountPercent ?? 100) / 10.0
            let rounded = p.rounded()
            if p == rounded {
                return "\(Int(rounded))折"
            }
            return String(format: "%.1f折", p)
        }
        return c.name ?? "优惠券"
    }
}

@MainActor
final class CouponCenterViewModel: ObservableObject {
    @Published var coupons: [CouponTemplate] = []
    @Published var isLoading = false
    @Published var isEnd = false
    @Published var message: String?
    private var pageNo = 1

    func load() {
        pageNo = 1
        isLoading = true
        Task {
            defer { isLoading = false }
            if let resp = try? await CouponAPI.templatePage(pageNo: 1) {
                coupons = resp.list ?? []
                isEnd = (resp.list?.count ?? 0) < 10
            }
        }
    }

    func loadMore() {
        guard !isLoading, !isEnd else { return }
        let next = pageNo + 1
        Task {
            guard let resp = try? await CouponAPI.templatePage(pageNo: next) else { return }
            let list = resp.list ?? []
            let existing = Set(coupons.map(\.id))
            coupons += list.filter { !existing.contains($0.id) }
            pageNo = next
            isEnd = list.count < 10
        }
    }

    func take(_ c: CouponTemplate) {
        Task {
            do {
                _ = try await CouponAPI.take(templateId: c.id)
                message = "领取成功"
                load()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
