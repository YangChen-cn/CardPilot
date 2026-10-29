import SwiftUI

struct CardUsageScenarioView: View {
    let scenario: CardUsageScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scenario.title).font(.headline)
            Text(scenario.periodDescription()).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("适用场景").font(.subheadline.weight(.semibold))
                Text(scenario.whenToUse)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("怎么刷").font(.subheadline.weight(.semibold))
                Text(scenario.howToUse)
            }
            if let cap = scenario.capNote {
                VStack(alignment: .leading, spacing: 6) {
                    Text("回赠上限").font(.subheadline.weight(.semibold))
                    Text(cap)
                }
            }
            if let stop = scenario.stopAfter {
                VStack(alignment: .leading, spacing: 6) {
                    Text("何时考虑换卡").font(.subheadline.weight(.semibold))
                    Text(stop)
                }
            }
            ForEach(Array((scenario.warnings ?? []).enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(scenario.sourceURLs.enumerated()), id: \.offset) { index, source in
                    if let url = URL(string: source) {
                        Link(destination: url) {
                            Text(scenario.sourceURLs.count == 1 ? "官方资料与条款" : "官方资料与条款 \(index + 1)")
                                .frame(minHeight: PilotTheme.minimumTouchTarget, alignment: .leading)
                        }
                    }
                }
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
