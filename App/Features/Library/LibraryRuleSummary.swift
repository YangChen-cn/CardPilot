import SwiftUI

struct LibraryRuleSummary: View {
    let rule: CatalogRule
    var verifiedOn = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rule.name).font(.headline)
            if let rate = rule.ratePercent {
                Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "% 回赠")
                    .font(.title3).bold().foregroundStyle(PilotTheme.accent)
            }
            if let cap = rule.capHKD, cap > 0 {
                Text((rule.capPeriod == "monthly" ? "每月上限 " : "整期上限 ") + Money.text(Money.cents(cap)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text([rule.startsOn ?? "开始日期未核实", rule.endsOn ?? "结束日期未核实"].joined(separator: " 至 "))
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                if let notes = rule.notes, !notes.isEmpty { Text(notes).font(.subheadline).foregroundStyle(.secondary) }
                if let category = rule.category, !category.isEmpty { LabeledContent("消费类别", value: category) }
                if let currency = rule.currency, !currency.isEmpty { LabeledContent("币种", value: currency) }
                if let method = rule.paymentMethod, !method.isEmpty { LabeledContent("支付方式", value: PaymentMethod.canonical(method)) }
                if let minimum = rule.minimumHKD, minimum > 0 { LabeledContent("单笔最低消费", value: Money.text(Money.cents(minimum))) }
                if let monthly = rule.monthlyPhysicalThresholdHKD, monthly > 0 { LabeledContent("每月实体消费门槛", value: Money.text(Money.cents(monthly))) }
                if let url = URL(string: rule.sourceURL) { Link("官方条款", destination: url).frame(minHeight: 44) }
                if !verifiedOn.isEmpty { Text("资料核实于 " + verifiedOn).font(.caption).foregroundStyle(.secondary) }
            }.font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading).pilotPanel()
    }
}
