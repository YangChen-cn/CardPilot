import SwiftUI
import Charts

struct SpendingChart: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每月消费").font(.headline)
            Text("近六个月 · 仅含可换算为港币的记录")
                .font(.caption).foregroundStyle(.secondary)
            Chart(snapshot.monthly) { month in
                BarMark(x: .value("月份", month.date, unit: .month), y: .value("HKD", Double(month.cents) / 100))
                    .foregroundStyle(PilotTheme.accent).cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            .accessibilityLabel("近六个月已记录消费柱状图，按港币统计")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
