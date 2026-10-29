import Foundation

/// Agent-authored reading material based on public terms, never a calculation policy.
struct CardUsageGuide: Codable, Sendable {
    let summary: String
    let reviewedOn: String
    let scenarios: [CardUsageScenario]

    func validate(offerIDs: Set<String>) throws {
        try Self.validateText(summary, maximum: 480)
        _ = try CatalogImporter.date(reviewedOn)
        guard (1...12).contains(scenarios.count),
              Set(scenarios.map(\.id)).count == scenarios.count else {
            throw PilotError.invalid("推荐用法需要 1–12 个场景，且场景 ID 不得重复。")
        }
        for scenario in scenarios { try scenario.validate(offerIDs: offerIDs) }
    }

    static func validateText(_ value: String, maximum: Int) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.unicodeScalars.count <= maximum else {
            throw PilotError.invalid("推荐用法文字为空或超过长度限制。")
        }
    }
}
