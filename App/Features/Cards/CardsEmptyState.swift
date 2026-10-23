import SwiftUI

/// Uses the system empty-state presentation so actions, Dynamic Type, and
/// VoiceOver follow the same rules as the rest of the app.
struct CardsEmptyState: View {
    let onCatalog: () -> Void
    let onManual: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("你的第一张卡", systemImage: "creditcard")
        } description: {
            Text("添加银行卡，集中查看权益、优惠与消费。")
        } actions: {
            Button("从资料库添加", systemImage: "plus", action: onCatalog)
                .buttonStyle(.borderedProminent)
            Button("手动添加", action: onManual)
                .buttonStyle(.bordered)
        }
    }
}
