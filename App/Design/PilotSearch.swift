import SwiftUI

private struct PilotSearch: ViewModifier {
    @Binding var text: String
    let prompt: LocalizedStringKey
    @State private var presented = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .searchable(text: $text, isPresented: $presented, prompt: Text(prompt))
            .searchToolbarBehavior(.minimize)
            .onChange(of: presented) { _, active in
                // End the query with the search session. Rebuilding filtered
                // content must not reactivate a cancelled search field.
                if !active { text = "" }
            }
        #else
        content.searchable(text: $text, prompt: Text(prompt))
        #endif
    }
}

extension View {
    func pilotSearch(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        modifier(PilotSearch(text: text, prompt: prompt))
    }
}
