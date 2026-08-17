import Foundation

// MARK: - 组局模型补充（列表模型 GroupEventInfo 在 HomeAPI.swift）

/// 组局详情（对齐安卓 GroupEventDetailInfo）
struct GroupEventDetailInfo: Decodable {
    let id: Int64
    let userId: Int64?
    let coverImage: String?
    let title: String?
    let eventType: Int?
    let eventTime: String?
    let location: String?
    let cityCode: Int?
    let storeId: Int64?
    let storeName: String?
    let participantLimit: Int?
    let currentCount: Int?
    let rabbitCoinPrice: Int?
    let status: Int?
    let organizerId: Int64?
    let organizerName: String?
    let organizerAvatar: String?
    let joined: Bool?
    let isOrganizer: Bool?
    let hasGroup: Bool?
    let allowQuit: Int?
    let description: String?
    let images: [String]?
    let remainCount: Int?
    let joinRecords: [JoinRecordItem]?
    let imGroupId: Int64?
    let isInGroup: Bool?
    let imGroupIdStr: String?
    let imGroupName: String?
    let imGroupAvatar: String?
}

struct JoinRecordItem: Decodable, Identifiable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let participantCount: Int?

    var id: Int64 { userId }
}

/// 可组局门店
struct StoreOption: Decodable, Identifiable {
    let id: Int64
    let name: String
    let cover: String?
    let detailAddress: String?
    let businessHours: String?
}

// MARK: - 请求模型

struct CreateGroupEventReq: Encodable {
    let title: String
    let eventType: Int
    let eventTime: String        // "yyyy-MM-dd HH:mm"
    var location: String? = nil
    var cityCode: Int? = nil
    var storeId: Int64? = nil
    let participantLimit: Int
    var rabbitCoinPrice: Int = 0
    var description: String? = nil
    var coverImage: String? = nil
    var images: [String]? = nil
    var allowQuit: Int = 1
    var draft: Bool? = nil
}

struct UpdateDraftReq: Encodable {
    let id: Int64
    var title: String? = nil
    var eventType: Int? = nil
    var eventTime: String? = nil
    var cityCode: Int? = nil
    var storeId: Int64? = nil
    var participantLimit: Int? = nil
    var rabbitCoinPrice: Int? = nil
    var description: String? = nil
    var coverImage: String? = nil
    var images: [String]? = nil
    var allowQuit: Int? = nil
}

struct PublishEventReq: Encodable { let id: Int64 }
struct JoinGroupEventReq: Encodable { let id: Int64; let participantCount: Int }
struct BindGroupReq: Encodable { let eventId: Int64; let imGroupId: Int64 }

// MARK: - 群组（组局沟通群用，完整群功能在密语阶段补齐）

struct GroupInfo: Decodable {
    let id: Int64
    let imGroupId: String?
    let name: String?
    let memberCount: Int64?
    let joined: Bool?
}

struct CreateGroupReq: Encodable {
    let name: String
    let memberUserIds: [Int64]
}

enum GroupAPI {
    static func create(name: String) async throws -> GroupInfo {
        try await APIClient.shared.post("app-api/im/group/create", body: CreateGroupReq(name: name, memberUserIds: []))
    }

    /// 返回 String（如需要审批的提示语）
    static func join(groupId: Int64) async throws -> String? {
        try await APIClient.shared.post("app-api/im/group/join", query: ["groupId": String(groupId)])
    }
}

// MARK: - 组局 API（对齐安卓 GroupEventApi）

enum GroupEventAPI {

    static func list(pageNo: Int = 1, pageSize: Int = 20, tab: String = "hot") async throws -> PageResult<GroupEventInfo> {
        try await APIClient.shared.get("app-api/social/group-event/list", query: [
            "pageNo": String(pageNo), "pageSize": String(pageSize), "tab": tab
        ])
    }

    static func detail(id: Int64) async throws -> GroupEventDetailInfo {
        try await APIClient.shared.get("app-api/social/group-event/detail", query: ["id": String(id)])
    }

    static func create(_ req: CreateGroupEventReq) async throws -> GroupEventInfo {
        try await APIClient.shared.post("app-api/social/group-event/create", body: req)
    }

    static func updateDraft(_ req: UpdateDraftReq) async throws -> GroupEventInfo {
        try await APIClient.shared.put("app-api/social/group-event/update-draft", body: req)
    }

    static func publish(id: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/group-event/publish", body: PublishEventReq(id: id))
    }

    static func join(id: Int64, participantCount: Int = 1) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/group-event/join", body: JoinGroupEventReq(id: id, participantCount: participantCount))
    }

    static func quit(id: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/group-event/quit", query: ["id": String(id)])
    }

    static func cancel(id: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/group-event/cancel", query: ["id": String(id)])
    }

    static func finish(id: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/group-event/finish", query: ["id": String(id)])
    }

    static func bindGroup(eventId: Int64, imGroupId: Int64) async throws -> Bool {
        try await APIClient.shared.post("app-api/social/group-event/bind-group", body: BindGroupReq(eventId: eventId, imGroupId: imGroupId))
    }

    /// 可组局门店（按城市）
    static func storesByCity(_ cityCode: Int) async throws -> [StoreOption] {
        try await APIClient.shared.get("app-api/social/store/list-by-city", query: ["cityCode": String(cityCode)])
    }
}
