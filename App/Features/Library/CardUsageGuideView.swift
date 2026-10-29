import SwiftUI

struct CardUsageGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let guide: CardUsageGuide
    let productName: String

    var body: some View {
        #if os(iOS)
        CardUsageGuideSheetContent(guide: guide, productName: productName, onClose: { dismiss() })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PilotTheme.canvas)
            .presentationDragIndicator(.visible)
        #else
        NavigationStack {
            ScrollView { CardUsageGuideBody(guide: guide, productName: productName) }
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

}
