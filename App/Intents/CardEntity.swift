import AppIntents
import SwiftData

struct CardEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "银行卡")
    static var defaultQuery: CardEntityQuery { CardEntityQuery() }
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
