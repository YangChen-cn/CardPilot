import SwiftUI

struct TransactionReviewItem: View {
    let request: TransactionRequest
    let cardName: String
    let duplicate: TransactionDuplicate?
    let approve: () -> Void
    let ignore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(request.merchant).font(.headline)
                Text(Money.text(request.amountCents, currency: request.currency)).font(.title2.weight(.semibold)).monospacedDigit()
                Text(cardName).font(.subheadline).foregroundStyle(.secondary)
                Text("\(sourceTitle(request.source)) · \(request.paymentMethod)").font(.caption).foregroundStyle(.secondary)
                Text(request.date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            if let duplicate {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label(duplicate.isExact ? "这笔交易已经记录" : "发现一笔相似消费", systemImage: "doc.on.doc").font(.subheadline.weight(.medium))
                    Text("\(duplicate.transaction.merchant) · \(Money.text(duplicate.transaction.amountCents, currency: duplicate.transaction.currency))")
                    Text("\(sourceTitle(duplicate.transaction.source)) · \(duplicate.transaction.paymentMethod)")
                    Text(duplicate.transaction.date, format: .dateTime.year().month().day().hour().minute())
                }.font(.caption).foregroundStyle(.secondary)
            }
            if duplicate?.isExact != true {
                Button("保存为另一笔消费", systemImage: "plus", action: approve)
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
            Button(duplicate?.isExact == true ? "使用已记录交易" : "忽略这条重复记录", action: ignore)
                .frame(minHeight: 44)
        }
        .padding(.vertical, 8)
    }

    private func sourceTitle(_ source: String) -> String {
        switch source {
        case "manual": "手动记账"
        case "shortcuts": "快捷指令"
        case "sms": "银行短信"
        case "email": "银行邮件"
        case "csv": "文件导入"
        default: "导入记录"
        }
    }
}
