import SwiftUI

/// Brief feedback floats above content; it never becomes another toolbar.
struct PilotFeedbackBanner: View {
    let message: String
    let systemImage: String
    var isError = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                label.background(PilotTheme.surface, in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.3)) }
            } else {
                label.glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
        .padding(.horizontal, PilotTheme.phonePagePadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    private var label: some View {
        Label {
            Text(message).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(isError ? Color.red : PilotTheme.accent)
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: 720, alignment: .leading)
    }
}
