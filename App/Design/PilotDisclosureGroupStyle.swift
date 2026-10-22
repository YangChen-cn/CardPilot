import SwiftUI

/// Keeps DisclosureGroup state native while making the full heading a button.
struct PilotDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        PilotDisclosureGroupBody(configuration: configuration)
    }
}
