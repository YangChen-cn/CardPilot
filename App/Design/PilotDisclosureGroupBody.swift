import SwiftUI

struct PilotDisclosureGroupBody: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .subheadline) private var indicatorWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: indicatorWidth)
                        .rotationEffect(.degrees(configuration.isExpanded ? (layoutDirection == .rightToLeft ? -90 : 90) : 0))
                        .accessibilityHidden(true)
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? Text("已展开") : Text("已收起"))

            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    configuration.content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
    }

    private func toggle() {
        if reduceMotion { configuration.isExpanded.toggle() }
        else { withAnimation(.easeInOut(duration: 0.18)) { configuration.isExpanded.toggle() } }
    }
}
