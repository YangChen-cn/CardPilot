import Foundation

/// Agent-authored reading material based on public terms, never a calculation policy.
struct CardUsageGuide: Codable, Sendable {
    let summary: String
    let reviewedOn: String
    let scenarios: [CardUsageScenario]

    func validate(offerIDs: Set<String>) throws {
        try Self.validateText(summary, maximum: 90)
        _ = try CatalogImporter.date(reviewedOn)
        guard scenarios.count == 1 else {
            throw PilotError.invalid("每张卡只能提供一份整体推荐用法。")
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
