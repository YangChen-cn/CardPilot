import SwiftUI

struct CardUsageGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let guide: CardUsageGuide
    let productName: String

    var body: some View {
        #if os(iOS)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("推荐用法").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button("完成", action: { dismiss() })
                    .buttonStyle(.glass).controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, PilotTheme.pagePadding)
            .padding(.top, 12).padding(.bottom, 8)

            // Give presentation sizing an intrinsic height before it animates.
            // If the content exceeds the available space, use a scroll viewport.
            ViewThatFits(in: .vertical) {
                guideContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { guideContent }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(PilotTheme.canvas)
        .presentationSizing(.page.fitted(horizontal: false, vertical: true))
        .presentationDragIndicator(.visible)
        #else
        NavigationStack {
            ScrollView { guideContent }
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
        #endif
    }

    private var guideContent: some View {
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
