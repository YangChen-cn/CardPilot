import SwiftUI

struct DashboardBalance: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本月已记录消费").font(.headline)
                Spacer()
                Text("\(snapshot.monthCount) 笔").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(Money.text(snapshot.monthSpend))
                .font(.largeTitle.weight(.semibold)).monospacedDigit()
            if snapshot.unvaluedCount > 0 {
                Text(snapshot.originalTotals).font(.subheadline).monospacedDigit()
                Text("港币合计仅包含有可信汇率的记录；\(snapshot.unvaluedCount) 笔按原币保留。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
