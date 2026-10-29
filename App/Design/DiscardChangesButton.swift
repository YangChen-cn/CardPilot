import SwiftUI

/// Cancel and Escape share the same protection; a successful save dismisses directly.
struct DiscardChangesButton: View {
    let hasChanges: Bool
    let discard: () -> Void
    @State private var confirming = false

    var body: some View {
        Button("取消") {
            if hasChanges { confirming = true } else { discard() }
        }
        .keyboardShortcut(.cancelAction)
        .confirmationDialog("放弃未保存的更改？", isPresented: $confirming, titleVisibility: .visible) {
            Button("放弃更改", role: .destructive, action: discard)
            Button("继续编辑", role: .cancel) { }
        }
    }
}
