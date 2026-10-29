#if os(iOS)
import SwiftUI

struct CardUsageGuideSheetContent: View {
    let guide: CardUsageGuide
    let productName: String
    var scrolling = true
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("推荐用法").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button("完成", action: onClose)
                    .buttonStyle(.glass).controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, PilotTheme.pagePadding)
            .padding(.top, 12).padding(.bottom, 8)

            if scrolling {
                ScrollView { CardUsageGuideBody(guide: guide, productName: productName) }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                CardUsageGuideBody(guide: guide, productName: productName)
            }
        }
    }
}
#endif
