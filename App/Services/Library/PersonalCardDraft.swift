import Foundation
import Observation
import SwiftData

/// Personal card settings do not select benefits or decide welcome eligibility.
@MainActor @Observable final class PersonalCardDraft {
    let card: BankCard
    let product: CardProduct
    var lastFour: String
    var statementDay: Int
    var paymentDay: Int
    var creditLimit: Decimal = 0
    var sharedCreditName: String?
    var error: String?

    init(card: BankCard, product: CardProduct) {
        self.card = card; self.product = product
        lastFour = card.lastFour; statementDay = card.statementDay; paymentDay = card.paymentDay
        guard let context = card.modelContext else { return }
        do {
            if let group = try FinanceStore.snapshot(context: context).groups.first(where: { $0.cardKeys.contains(card.syncKey) }) {
                creditLimit = Decimal(group.limitCents) / 100
                if group.cardKeys.count > 1 { sharedCreditName = group.name }
            }
        } catch { self.error = PilotError.message(error) }
    }

    func save(in context: ModelContext) -> Bool {
        error = nil
        do {
            guard lastFour.isEmpty || (lastFour.count == 4 && lastFour.allSatisfy({ $0.isASCII && $0.isNumber })),
                  (0...31).contains(statementDay), (0...31).contains(paymentDay),
                  creditLimit >= 0, creditLimit <= Money.maxAmount else {
                throw PilotError.invalid("请检查尾号、账单日及信用额度。")
            }
            try Persistence.save(context) {
                card.lastFour = lastFour; card.statementDay = statementDay; card.paymentDay = paymentDay; card.modifiedAt = .now
                try Persistence.setProfileRevision(cardKey: card.syncKey, date: .now, context: context, advancing: true)
                try FinanceStore.setPersonalCreditLimit(card: card, cents: Money.cents(creditLimit), context: context)
                // Existing application, welcome and reward documents are intentionally untouched.
            }
            return true
        } catch { self.error = PilotError.message(error); return false }
    }
}
