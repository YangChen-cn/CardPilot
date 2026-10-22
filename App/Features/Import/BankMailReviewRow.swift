import SwiftUI

struct BankMailReviewRow: View {
    let review: MailReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.mail.merchant).font(.headline)
                Spacer()
                Text(Money.text(review.mail.amountCents, currency: review.mail.currency)).monospacedDigit()
            }
            Text(review.reason).font(.subheadline).foregroundStyle(.secondary)
            Text("\(review.mail.bankID.uppercased()) · 尾号 \(review.mail.lastFour)\(review.mail.requiredCardKind == "借记卡" ? " · 扣账卡" : "") · \(review.mail.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6).contentShape(.rect)
    }
}
