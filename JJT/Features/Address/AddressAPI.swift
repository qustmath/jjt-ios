import Foundation

// MARK: - 收货地址 API（对齐安卓 AddressApi / AreaApi）

struct AddressInfo: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let mobile: String?
    let areaId: Int?
    let areaName: String?
    let detailAddress: String?
    let defaultStatus: Bool?
}

struct AddressReq: Encodable {
    let id: Int64?
    let name: String
    let mobile: String
    let areaId: Int64?
    let detailAddress: String
    let defaultStatus: Bool
}

/// 地区树节点（id 可选即满足 Identifiable）
struct AreaNode: Decodable, Identifiable {
    let id: Int?
    let name: String?
    let children: [AreaNode]?
}

enum AddressAPI {

    static func list() async throws -> [AddressInfo] {
        try await APIClient.shared.get("app-api/member/address/list")
    }

    static func get(id: Int64) async throws -> AddressInfo {
        try await APIClient.shared.get("app-api/member/address/get", query: ["id": "\(id)"])
    }

    static func create(_ req: AddressReq) async throws -> Int64 {
        try await APIClient.shared.post("app-api/member/address/create", body: req)
    }

    static func update(_ req: AddressReq) async throws -> Bool {
        try await APIClient.shared.put("app-api/member/address/update", body: req)
    }

    static func delete(id: Int64) async throws -> Bool {
        try await APIClient.shared.delete("app-api/member/address/delete", query: ["id": "\(id)"])
    }

    static func areaTree() async throws -> [AreaNode] {
        try await APIClient.shared.get("app-api/system/area/tree")
    }
}
