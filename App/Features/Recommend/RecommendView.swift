import SwiftUI
import SwiftData

struct RecommendView: View {
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]

    var body: some View {
        RecommendationWorkbench(cards: cards)
            .background(PilotTheme.canvas)
            .navigationTitle("选卡建议")
    }
}
