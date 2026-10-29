import Foundation

struct CardUsageScenario: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let whenToUse: String
    let howToUse: String
    let capNote: String?
    let stopAfter: String?
    let warnings: [String]?
    let relatedOfferIDs: [String]
    let sourceURLs: [String]
    let startsOn: String?
    let endsOn: String?

    func validate(offerIDs: Set<String>) throws {
        guard id.count <= 128,
              id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil,
              relatedOfferIDs.count <= 20,
              Set(relatedOfferIDs).count == relatedOfferIDs.count,
              Set(relatedOfferIDs).isSubset(of: offerIDs),
              (1...6).contains(sourceURLs.count), Set(sourceURLs).count == sourceURLs.count,
              (warnings ?? []).count <= 8 else {
            throw PilotError.invalid("推荐用法的场景标识、活动引用或来源无效。")
        }
        try CardUsageGuide.validateText(title, maximum: 80)
        try CardUsageGuide.validateText(whenToUse, maximum: 300)
        try CardUsageGuide.validateText(howToUse, maximum: 1_200)
        for text in [capNote, stopAfter].compactMap({ $0 }) + (warnings ?? []) {
            try CardUsageGuide.validateText(text, maximum: 400)
        }
        for source in sourceURLs {
            try CardUsageGuide.validateText(source, maximum: 2_048)
            try CatalogImporter.validateHTTPS(source)
        }
        if let startsOn { _ = try CatalogImporter.date(startsOn) }
        if let endsOn { _ = try CatalogImporter.date(endsOn) }
        if let startsOn, let endsOn, startsOn > endsOn {
            throw PilotError.invalid("推荐用法的起止日期无效。")
        }
    }

    /// A dated recommendation remains readable after expiry, but must never look current.
    func periodDescription(on date: Date = .now) -> String {
        let today = HKCalendar.calendar.startOfDay(for: date)
        if let endsOn, let end = try? CatalogImporter.date(endsOn), today > end {
            return "已结束 · " + endsOn
        }
        if let startsOn, let start = try? CatalogImporter.date(startsOn), today < start {
            return "尚未开始 · " + startsOn
        }
        switch (startsOn, endsOn) {
        case let (.some(start), .some(end)): return start + " 至 " + end
        case let (_, .some(end)): return "截至 " + end
        case let (.some(start), _): return start + " 起 · 截止日待核实"
        default: return "有效期待核实，请查看官方条款"
        }
    }
}
