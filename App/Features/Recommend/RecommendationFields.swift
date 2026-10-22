import SwiftUI

struct RecommendationFields: View {
    @Bindable var draft: RecommendationDraft
    var compact = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if phoneLayout { phoneFields }
            else { desktopFields }
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phoneFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("消费类别").font(.subheadline).foregroundStyle(.secondary)
                Picker("消费类别", selection: $draft.category) {
                    ForEach(SpendCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0.rawValue) }
                }
                .labelsHidden().pickerStyle(.menu).frame(minHeight: 44, alignment: .leading)
                .accessibilityLabel("消费类别")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("消费地区").font(.subheadline).foregroundStyle(.secondary)
                Picker("消费地区", selection: $draft.region) {
                    Text("请选择地区").tag("")
                    Text("香港").tag("HK"); Text("中国内地").tag("CN")
                    Text("澳门").tag("MO"); Text("其他地区").tag("other")
                }
                .labelsHidden().pickerStyle(.menu).frame(minHeight: 44, alignment: .leading)
                .accessibilityLabel("消费地区")
            }
            Divider()
            PilotDisclosureGroup("支付方式、金额与商户（选填）") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("支付方式", selection: $draft.paymentMethod) {
                        Text("暂未确定").tag("")
                        ForEach(PaymentMethod.allCases.filter { $0 != .unknown }) { Text($0.rawValue).tag($0.rawValue) }
                    }.pickerStyle(.menu).frame(minHeight: 44)
                    if !compact {
                        Picker("币种", selection: $draft.currency) {
                            ForEach(Currency.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                        TextField("预计金额（选填）", value: $draft.amount, format: .number.precision(.fractionLength(0...2)))
                            .frame(minHeight: 44)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("商户名称（选填）", text: $draft.merchant).frame(minHeight: 44)
                    }
                }.padding(.top, 8)
            }.font(.subheadline)
            Text(draft.paymentMethod.isEmpty ? "支付方式未确定：相关优惠仍需确认。" : "支付方式：" + PaymentMethod.canonical(draft.paymentMethod))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var desktopFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("消费类别", selection: $draft.category) {
                ForEach(SpendCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0.rawValue) }
            }
            Picker("消费地区", selection: $draft.region) {
                Text("请选择").tag("")
                Text("香港").tag("HK"); Text("中国内地").tag("CN")
                Text("澳门").tag("MO"); Text("其他地区").tag("other")
            }
            Picker("支付方式", selection: $draft.paymentMethod) {
                Text("暂未确定").tag("")
                ForEach(PaymentMethod.allCases.filter { $0 != .unknown }) { Text($0.rawValue).tag($0.rawValue) }
            }
            if !compact {
                HStack {
                    Picker("币种", selection: $draft.currency) { ForEach(Currency.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                        .fixedSize()
                    TextField("预计金额（选填）", value: $draft.amount, format: .number.precision(.fractionLength(0...2)))
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                TextField("商户名称（选填）", text: $draft.merchant)
            }
        }
    }
}
