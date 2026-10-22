import SwiftUI

/// Full-row disclosure for content panels, without changing native List/Section behavior.
struct PilotDisclosureGroup<Content: View>: View {
    private let title: LocalizedStringKey
    private let expansion: Binding<Bool>?
    private let content: Content
    @State private var expanded = false

    init(_ title: LocalizedStringKey, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        expansion = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: expansion ?? $expanded) {
            // Children keep native controls, lists and navigation semantics.
            content.disclosureGroupStyle(.automatic)
        }
        .disclosureGroupStyle(PilotDisclosureGroupStyle())
    }
}
