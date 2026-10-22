import SwiftUI

struct WelcomePlanSummary: View {
    let plan: WelcomePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plan.title).font(.headline)
            Text(plan.details).font(.subheadline).foregroundStyle(.secondary)
            if plan.isAddon {
                Label("可单独记录奖励状态", systemImage: "plus.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !plan.verified {
                Label("待核实", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
            }
            if let url = URL(string: plan.sourceURL), !plan.sourceURL.isEmpty {
                Link("官方条款", destination: url).font(.subheadline).frame(minHeight: 44)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pilotPanel()
    }
}
