import SwiftUI

/// Hidden entirely when a catalog product has no editorial guide.
struct CardUsageGuideSection: View {
    let guide: CardUsageGuide
    let productName: String
    @State private var showingGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("推荐用法").font(.title3.weight(.semibold))
            Text(guide.summary).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("查看使用场景与上限说明", systemImage: "lightbulb", action: { showingGuide = true })
                .frame(minHeight: PilotTheme.minimumTouchTarget)
            Text("AI 整理的用卡参考，以银行条款为准。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingGuide) {
            CardUsageGuideView(guide: guide, productName: productName)
        }
    }
}
