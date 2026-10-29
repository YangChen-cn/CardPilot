import SwiftUI

private struct PilotSearch: ViewModifier {
    @Binding var text: String
    let prompt: LocalizedStringKey
    @State private var presented = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            // Keep native page search. The minimized toolbar presentation can
            // reactivate itself during dismissal (FB24779236), even with a binding.
            .searchable(text: $text, isPresented: $presented,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
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
