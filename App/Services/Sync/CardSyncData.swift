import Foundation

/// Value snapshot; contains no ModelContext or live SwiftData relationship.
struct CardSyncData: Codable, Equatable, Sendable {
    var profileRevision: Date? = nil
    var bank: String
    var name: String
    var network: String
    var kind: String
    var lastFour: String
    var statementDay: Int
    var paymentDay: Int
    var baseRateBps: Int
    var foreignFeeBps: Int
    var theme: String
    var isArchived: Bool
    var createdAt: Date
    var catalogID: String
    var sourceURL: String
    var verifiedOn: String
    var imageURL: String
    var annualFeeNote: String
    var caveats: String
    var overseasHKDFeeBps: Int
    var excludesWallets: Bool
    var imageData: Data?
    var artworkSource: CardArtworkSource? = nil

    @MainActor init(_ model: BankCard) {
        bank = model.bank
        name = model.name
        network = model.network
        kind = model.kind
        lastFour = model.lastFour
        statementDay = model.statementDay
        paymentDay = model.paymentDay
        baseRateBps = model.baseRateBps
        foreignFeeBps = model.foreignFeeBps
        theme = model.theme
        isArchived = model.isArchived
        createdAt = model.createdAt
        catalogID = model.catalogID
        sourceURL = model.sourceURL
        verifiedOn = model.verifiedOn
        imageURL = model.imageURL
        annualFeeNote = model.annualFeeNote
        caveats = model.caveats
        overseasHKDFeeBps = model.overseasHKDFeeBps
        excludesWallets = model.excludesWallets
        artworkSource = model.artworkSource
        imageData = artworkSource == .custom ? model.imageData : nil
    }

    @MainActor func apply(to model: BankCard) throws {
        model.bank = bank
        model.name = name
        model.network = network
        model.kind = kind
        model.lastFour = lastFour
        model.statementDay = statementDay
        model.paymentDay = paymentDay
        model.baseRateBps = baseRateBps
        model.foreignFeeBps = foreignFeeBps
        model.theme = theme
        model.isArchived = isArchived
        model.createdAt = createdAt
        model.catalogID = catalogID
        model.sourceURL = sourceURL
        model.verifiedOn = verifiedOn
        model.imageURL = imageURL
        model.annualFeeNote = annualFeeNote
        model.caveats = caveats
        model.overseasHKDFeeBps = overseasHKDFeeBps
        model.excludesWallets = excludesWallets
        let source = artworkSource ?? .catalog
        model.imageData = source == .custom ? imageData : nil
        if let context = model.modelContext { try model.setArtworkSource(source, in: context) }
    }
}
