import SwiftUI

/// Shared by desktop, iPhone display and pre-presentation size measurement.
struct CardUsageGuideBody: View {
    let guide: CardUsageGuide
    let productName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(productName).font(.title2.weight(.semibold))
                Text(guide.summary).font(.body)
                Text("整理于 " + guide.reviewedOn).font(.caption).foregroundStyle(.secondary)
            }
            if let strategy = guide.scenarios.first {
                Divider()
                CardUsageScenarioView(scenario: strategy)
            }
            Text("用卡参考，具体优惠见官方条款。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(PilotTheme.pagePadding)
        .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        .textSelection(.enabled)
    }
}
