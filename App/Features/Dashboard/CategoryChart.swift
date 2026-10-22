import SwiftUI
import Charts

struct CategoryChart: View {
    let totals: [CategoryTotal]
    private let colors: [Color] = [PilotTheme.accent, .purple, .orange, .blue, .pink, .indigo, .mint, .gray]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("本月消费类别").font(.headline)
            Text("仅含可换算为港币的记录").font(.caption).foregroundStyle(.secondary)
            if totals.isEmpty {
                ContentUnavailableView("暂无分类统计", systemImage: "chart.pie", description: Text("每笔消费都可选择分类。"))
            } else {
                Chart(totals) { total in
                    SectorMark(angle: .value("消费", total.cents), innerRadius: .ratio(0.68), angularInset: 2)
                        .foregroundStyle(by: .value("分类", total.name)).cornerRadius(4)
                }
                .chartForegroundStyleScale(domain: totals.map(\.name), range: colors)
                .chartLegend(position: .bottom, spacing: 12)
                .frame(height: 210)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 256, alignment: .topLeading)
    }
}
