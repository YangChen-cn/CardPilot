import SwiftUI

struct CardUsageGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let guide: CardUsageGuide
    let productName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(productName).font(.title2.weight(.semibold))
                        Text(guide.summary).font(.body)
                        Text("整理于 " + guide.reviewedOn).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(guide.scenarios) { scenario in
                        Divider()
                        CardUsageScenarioView(scenario: scenario)
                    }
                    Text("用卡参考，具体优惠见官方条款。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(PilotTheme.pagePadding)
                .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .background(PilotTheme.canvas)
            .navigationTitle("推荐用法")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: { dismiss() })
                }
            }
        }
        .editorSize()
    }
}
