import Foundation

// MARK: - 属性测试 API（对齐安卓 QuizApi）

struct QuizInfo: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let subtitle: String?
    let iconUrl: String?
    let partCount: Int?
    let totalQuestions: Int?
    let optionStyle: String?
}

struct DimensionInfo: Decodable {
    let key: String?
    let label: String?
    let group: String?
    let groupLabel: String?
}

struct QuizDetail: Decodable {
    let id: Int64
    let name: String?
    let subtitle: String?
    let description: String?
    let iconUrl: String?
    let partCount: Int?
    let totalQuestions: Int?
    let optionStyle: String?
    let resultRule: String?
    let dimensions: [DimensionInfo]?
}

struct OptionInfo: Decodable {
    let label: String?
    let dimension: String?
    let score: Int?
}

struct QuestionInfo: Decodable, Identifiable {
    let id: Int64
    let quizId: Int64?
    let partIndex: Int?
    let sort: Int?
    let content: String?
    let options: [OptionInfo]?
}

struct AnswerItem: Encodable {
    let questionId: Int64
    let optionIndex: Int
}

struct SubmitResult: Decodable {
    let resultKey: String?
    let resultTitle: String?
    let subtitle: String?
    let description: String?
    let compatible: String?
    let playStyles: [String]?
    let iconUrl: String?
    let dimScores: [String: Int]?
    let dimensions: [DimensionInfo]?
}

struct MyResultInfo: Decodable {
    let quizId: Int64?
    let quizName: String?
    let quizIconUrl: String?
    let resultKey: String?
    let resultTitle: String?
    let dimScoresJson: String?
    let createTime: String?
}

struct ResultDetailInfo: Decodable {
    let quizId: Int64?
    let resultKey: String?
    let title: String?
    let subtitle: String?
    let description: String?
    let compatible: String?
    let playStyles: [String]?
    let iconUrl: String?
}

enum QuizAPI {
    static func list() async throws -> [QuizInfo] {
        try await APIClient.shared.get("app-api/social/quiz/list")
    }

    static func detail(quizId: Int64) async throws -> QuizDetail {
        try await APIClient.shared.get("app-api/social/quiz/detail", query: ["quizId": String(quizId)])
    }

    static func questions(quizId: Int64) async throws -> [QuestionInfo] {
        try await APIClient.shared.get("app-api/social/quiz/questions", query: ["quizId": String(quizId)])
    }

    static func submit(quizId: Int64, answers: [AnswerItem]) async throws -> SubmitResult {
        struct Req: Encodable { let quizId: Int64; let answers: [AnswerItem] }
        return try await APIClient.shared.post("app-api/social/quiz/submit", body: Req(quizId: quizId, answers: answers))
    }

    static func myResults() async throws -> [MyResultInfo] {
        try await APIClient.shared.get("app-api/social/quiz/my-results")
    }

    static func myAnswers(quizId: Int64) async throws -> [AnswerItem] {
        struct Item: Decodable { let questionId: Int64; let optionIndex: Int }
        let items: [Item] = try await APIClient.shared.get("app-api/social/quiz/my-answers", query: ["quizId": String(quizId)])
        return items.map { AnswerItem(questionId: $0.questionId, optionIndex: $0.optionIndex) }
    }

    static func resultDetail(quizId: Int64, resultKey: String) async throws -> ResultDetailInfo {
        try await APIClient.shared.get("app-api/social/quiz/result-detail", query: ["quizId": String(quizId), "resultKey": resultKey])
    }
}
