import Foundation

// MARK: - 商城模型（对齐安卓 MallApi.kt；价格统一是「分」）

struct SpuListItem: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let introduction: String?
    let categoryId: Int64?
    let picUrl: String?
    let sliderPicUrls: [String]?
    let specType: Bool?
    let price: Int?           // 分
    let marketPrice: Int?     // 分
    let stock: Int?
    let salesCount: Int?
    let deliveryTypes: [Int]?
    let productType: Int?     // 0实物 1虚拟
}

struct SkuProperty: Decodable {
    let propertyId: Int64?
    let propertyName: String?
    let valueId: Int64?
    let valueName: String?
}

struct SpuDetailSku: Decodable, Identifiable {
    let id: Int64
    let properties: [SkuProperty]?
    let price: Int?
    let marketPrice: Int?
    let vipPrice: Int?
    let picUrl: String?
    let stock: Int?
}

struct SpuDetail: Decodable {
    let id: Int64
    let name: String?
    let introduction: String?
    let description: String?  // HTML
    let categoryId: Int64?
    let picUrl: String?
    let sliderPicUrls: [String]?
    let specType: Bool?
    let price: Int?
    let marketPrice: Int?
    let stock: Int?
    let skus: [SpuDetailSku]?
    let salesCount: Int?
    let deliveryTypes: [Int]?
    let pickUpStoreIds: [Int64]?
    let productType: Int?
    let radishCoinDeductMaxRate: Int?
}

struct MallCategory: Decodable, Identifiable {
    let id: Int64
    let parentId: Int64?
    let name: String?
    let picUrl: String?
}

struct CartAddReq: Encodable {
    let skuId: Int64
    let count: Int
}

// MARK: - 商城 API

enum MallAPI {

    /// 商品分页（sortField: price/salesCount）
    static func spuPage(pageNo: Int, pageSize: Int = 10, categoryId: Int64? = nil, keyword: String? = nil, sortField: String? = nil, sortAsc: Bool? = nil) async throws -> PageResult<SpuListItem> {
        var query = ["pageNo": "\(pageNo)", "pageSize": "\(pageSize)"]
        if let categoryId { query["categoryId"] = "\(categoryId)" }
        if let keyword, !keyword.isEmpty { query["keyword"] = keyword }
        if let sortField { query["sortField"] = sortField }
        if let sortAsc { query["sortAsc"] = "\(sortAsc)" }
        return try await APIClient.shared.get("app-api/product/spu/page", query: query)
    }

    static func spuDetail(id: Int64) async throws -> SpuDetail {
        try await APIClient.shared.get("app-api/product/spu/get-detail", query: ["id": "\(id)"])
    }

    static func categoryList() async throws -> [MallCategory] {
        try await APIClient.shared.get("app-api/product/category/list")
    }

    /// 加购物车
    static func cartAdd(skuId: Int64, count: Int) async throws -> Bool {
        try await APIClient.shared.post("app-api/trade/cart/add", body: CartAddReq(skuId: skuId, count: count))
    }

    /// 购物车数量（角标）
    static func cartCount() async throws -> Int {
        try await APIClient.shared.get("app-api/trade/cart/get-count")
    }
}

// MARK: - 工具

/// 分 → 元字符串（对齐安卓 fenToYuan）
func fenToYuan(_ fen: Int?) -> String {
    let f = fen ?? 0
    if f % 100 == 0 { return "\(f / 100)" }
    return String(format: "%.2f", Double(f) / 100).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression).replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
}
