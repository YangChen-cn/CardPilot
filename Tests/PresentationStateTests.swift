import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct PresentationStateTests {
    @Test func existingAutomationDoesNotSilentlyAssumeHongKongRegion() throws {
        let intent = RecordTransactionIntent()
        intent.merchant = "Shop"; intent.amount = 100; intent.overseas = true
        let request = try intent.transactionRequest(cardID: "card")
        #expect(request.region.isEmpty)
        #expect(request.isOverseas)
    }

}
