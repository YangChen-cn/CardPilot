import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class CardDraft {
    var bank = "BOCHK 中银香港"
    var name = ""
    var network = "Mastercard"
    var kind = "信用卡"
    var lastFour = ""
    var statementDay = 0
    var paymentDay = 0
    var basePercent = Decimal(0)
    var feePercent = Decimal(0)
    var overseasHKDPercent = Decimal(0)
    var theme = "teal"
    var isArchived = false
    var artworkSource: CardArtworkSource = .catalog
    var imageData: Data?
    var sourceURL = ""
    var error: String?
    var terms: CardTerms?
    let existing: BankCard?

    init(card: BankCard?) {
        existing = card
        guard let card else { return }
        bank = card.bank; name = card.name; network = card.network; kind = card.kind
        lastFour = card.lastFour; statementDay = card.statementDay; paymentDay = card.paymentDay
        let pricing = PricingStore.current(card)
        basePercent = Decimal(pricing.baseRateBps) / 100; feePercent = Decimal(pricing.foreignFeeBps) / 100
        overseasHKDPercent = Decimal(pricing.overseasHKDFeeBps) / 100
        theme = card.theme; isArchived = card.isArchived
        artworkSource = card.artworkSource
        imageData = artworkSource == .custom ? card.imageData : nil; sourceURL = card.sourceURL
        terms = pricing.terms
    }

    func importArtwork(_ data: Data) throws {
        try CatalogImporter.validateImage(data)
        imageData = data
        artworkSource = .custom
    }

    func restoreCatalogArtwork() {
        imageData = nil
        artworkSource = .catalog
    }

    func save(in context: ModelContext) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !bank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请填写银行和卡片名称。"; return false }
        guard lastFour.isEmpty || (lastFour.count == 4 && lastFour.allSatisfy(\.isNumber)) else { error = "尾号须为4位数字，或留空。"; return false }
        guard [basePercent, feePercent, overseasHKDPercent].allSatisfy({ $0 >= 0 && $0 <= 100 }) else { error = "比例须在0–100%之间。"; return false }
        do {
            if artworkSource == .custom {
                guard let imageData, !imageData.isEmpty else { throw PilotError.invalid("请重新导入自定义卡面。") }
                try CatalogImporter.validateImage(imageData)
            }
            let official = existing.map { PricingStore.current($0, applyingOverride: false) }
            if !sourceURL.isEmpty { try CatalogImporter.validateHTTPS(sourceURL) }
            try Persistence.save(context) {
                let card = existing ?? BankCard(bank: bank, name: name)
                if existing == nil { context.insert(card) }
                card.bank = bank.trimmingCharacters(in: .whitespacesAndNewlines)
                card.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                card.network = network; card.kind = kind; card.lastFour = lastFour
                card.statementDay = statementDay; card.paymentDay = paymentDay
                card.baseRateBps = Int(Money.cents(basePercent)); card.foreignFeeBps = Int(Money.cents(feePercent))
                card.overseasHKDFeeBps = Int(Money.cents(overseasHKDPercent))
                card.theme = theme; card.isArchived = isArchived
                card.sourceURL = sourceURL
                card.imageData = artworkSource == .custom ? imageData : nil
                try card.setArtworkSource(artworkSource, in: context)
                card.modifiedAt = .now
                try Persistence.setProfileRevision(cardKey: card.syncKey, date: card.modifiedAt,
                                                   context: context, advancing: true)
                if let terms { try DocumentStore.put(terms, key: "cardTerms:" + card.syncKey, kind: "cardTerms", in: context) }
                if existing != nil, !card.catalogID.isEmpty, let official {
                    var requested = CardPricing(card)
                    requested.terms = terms
                    let fields = requested.overrideFields(comparedTo: official)
                    if fields.isEmpty {
                        try DocumentStore.remove("cardOverride:" + card.syncKey, in: context)
                    } else {
                        requested.overriddenFields = fields
                        try DocumentStore.put(requested, key: "cardOverride:" + card.syncKey, kind: "cardOverride", in: context)
                    }
                }
            }
            return true
        } catch { self.error = PilotError.message(error); return false }
    }
}
