import SwiftUI

/// System navigation owns interruption, interactive dismissal and the return path.
private struct PilotZoomTransition<ID: Hashable>: ViewModifier {
    let sourceID: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(iOS)
        if reduceMotion { content }
        else { content.navigationTransition(.zoom(sourceID: sourceID, in: namespace)) }
        #else
        content
        #endif
    }
}

extension View {
    func pilotZoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        modifier(PilotZoomTransition(sourceID: sourceID, namespace: namespace))
    }

    /// Match the artwork itself, keeping labels and actions out of the snapshot.
    @ViewBuilder func cardTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID?) -> some View {
        #if os(iOS)
        if let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.background(.clear)
                    .clipShape(.rect(cornerRadius: PilotTheme.cardCornerRadius))
            }
        } else { self }
        #else
        self
        #endif
    }
}
