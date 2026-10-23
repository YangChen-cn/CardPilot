import Foundation
import Testing
@testable import CardPilot

@Suite struct BankMailParserTests {
    private func time(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func message(_ bank: String, body: String, subject: String? = nil,
                         received: String = "2026-10-22T02:30:00Z") throws -> BankMailMessage {
        let addresses = ["bochk": "istatement@bochk.com", "bea": "lcccaut@hkbea.com", "hsbc": "onlineservicesnotification@hsbc.com.hk"]
        let domains = ["bochk": "bochk.com", "bea": "hkbea.com", "hsbc": "hsbc.com.hk"]
        let subjects = ["bochk": "交易通知 (Transaction Notification)", "bea": "Contactless Payment Transaction Notification",
                        "hsbc": "Online Transaction has been made on your Debit Card 您的扣賬卡網上交易已完成"]
        return BankMailMessage(id: "fixture-example-1", sender: addresses[bank] ?? "", subject: subject ?? subjects[bank] ?? "",
            receivedAt: try time(received), body: body,
            authenticationResults: "mx.google.com; dkim=pass header.i=@\(domains[bank] ?? ""); dmarc=pass (p=REJECT) header.from=\(domains[bank] ?? "")")
    }

    private let bocBody = """
    Card Account Number Ending with:1234
    Transaction Date:21/10
    Merchant Name:EXAMPLE SHOP
    Transaction Amount:CNY49.00
    卡號尾號：1234 交易日期：21/10 商戶名稱：示例商店 交易金額：CNY49.00
    """
    private let beaBody = """
    Your BEA Credit Card (last 4 digits 4567) has made a contactless payment transaction with HKD2.30 at EXAMPLE TRANSIT*on 2026/10/22.
    """
    private let hsbcBody = """
    HSBC Mastercard Debit Card number ending 7890.
    Merchant: EXAMPLE STORE Hong Kong HK
    Transaction currency and amount: HKD12.5
    Transaction date and time: 2026-10-11 20:11
    """

    @Test func bochkBilingualNotificationProducesOneDateOnlyPurchaseWithoutInventedConditions() throws {
        let value = try #require(try BankMailParser.parse(message("bochk", body: bocBody)))
        #expect(value.bankID == "bochk"); #expect(value.lastFour == "1234")
        #expect(value.merchant == "EXAMPLE SHOP"); #expect(value.amountCents == 4900); #expect(value.currency == "CNY")
        #expect(value.date == (try time("2026-10-20T16:00:00Z"))); #expect(!value.hasExactTime)
        #expect(value.paymentMethod == nil); #expect(value.channel == nil); #expect(value.region == nil)
        #expect(value.bankReference == nil)
    }

    @Test func beaContactlessDateDoesNotClaimApplePayOrAnExactTransactionTime() throws {
        let value = try #require(try BankMailParser.parse(message("bea", body: beaBody)))
        #expect(value.bankID == "bea"); #expect(value.lastFour == "4567")
        #expect(value.amountCents == 230); #expect(value.merchant == "EXAMPLE TRANSIT")
        #expect(value.date == (try time("2026-10-21T16:00:00Z"))); #expect(!value.hasExactTime)
        #expect(value.channel == "physical"); #expect(value.paymentMethod == nil); #expect(value.region == nil)
    }

    @Test func hsbcDebitOnlineTemplateHasExplicitTimeAndOnlyExplicitMerchantCountry() throws {
        var envelope = try message("hsbc", body: hsbcBody)
        envelope.sender = "HSBC Notifications <onlineservicesnotification@hsbc.com.hk>"
        let value = try #require(try BankMailParser.parse(envelope))
        #expect(value.bankID == "hsbc"); #expect(value.lastFour == "7890")
        #expect(value.cardKind == "借记卡")
        #expect(value.amountCents == 1250); #expect(value.date == (try time("2026-10-11T12:11:00Z")))
        #expect(value.hasExactTime); #expect(value.channel == "online"); #expect(value.paymentMethod == "网上支付"); #expect(value.region == "HK")
        envelope.body = hsbcBody.replacingOccurrences(of: " Hong Kong HK", with: "").replacingOccurrences(of: "HKD12.5", with: "CNY12.5")
        #expect(try BankMailParser.parse(envelope)?.region == nil)
        envelope.subject = "Online Transaction has been made on your Credit Card"
        #expect(try BankMailParser.parse(envelope) == nil)
    }

    private func creditMessage(date: String = "22 Oct", money: String = "HKD23.45") throws -> BankMailMessage {
        var value = try message("hsbc", body: """
        <table><tr><td>Credit card number</td><td>Ending with 1234</td></tr>
        <tr><td>Merchant</td><td>EXAMPLE CAFE</td></tr>
        <tr><td>Date</td><td>\(date)</td></tr>
        <tr><td>Amount</td><td>\(money)</td></tr></table>
        <table><tr><td>信用卡號碼</td><td>結尾數字 1234</td></tr></table>
        """)
        value.sender = "HSBC <HSBC_CNP@notification.hsbc.com.hk>"
        value.subject = "HSBC Credit Card Transaction Notification / 滙豐信用卡交易通知"
        return value
    }

    @Test func hsbcCreditBilingualHTMLPreservesDatePrecisionAndUnknownConditions() throws {
        let value = try #require(try BankMailParser.parse(creditMessage()))
        #expect(value.bankID == "hsbc"); #expect(value.cardKind == "信用卡")
        #expect(value.lastFour == "1234"); #expect(value.merchant == "EXAMPLE CAFE")
        #expect(value.amountCents == 2345); #expect(value.currency == "HKD")
        #expect(value.date == (try time("2026-10-21T16:00:00Z"))); #expect(!value.hasExactTime)
        #expect(value.paymentMethod == nil); #expect(value.channel == nil); #expect(value.region == nil)
    }

    @Test func hsbcCloudCellBreaksProduceTheSamePurchase() throws {
        var envelope = try creditMessage()
        let original = try #require(try BankMailParser.parse(envelope))
        envelope.body = "Credit card number\n\nEnding with 1234\n\nMerchant\n\nEXAMPLE CAFE\n\nDate\n\n22 Oct\n\nAmount\n\nHKD23.45"
        #expect(try BankMailParser.parse(envelope) == original)
    }

    @Test(arguments: ["31 Feb", "23 Oct", "01 Oct", "22 Foo"])
    func hsbcCreditRejectsInvalidFutureAndStaleDates(_ raw: String) throws {
        #expect(throws: (any Error).self) { try BankMailParser.parse(creditMessage(date: raw)) }
    }

    @Test func hsbcCreditSenderSubjectAuthenticationAndCurrencyStayStrict() throws {
        var value = try creditMessage(money: "USD1,234.56")
        #expect(try BankMailParser.parse(value)?.amountCents == 123456)
        value.authenticationResults = "mx.google.com; dmarc=fail header.from=hsbc.com.hk"
        #expect(throws: (any Error).self) { try BankMailParser.parse(value) }
        value = try creditMessage(); value.subject = "Welcome to HSBC credit cards"
        #expect(try BankMailParser.parse(value) == nil)
        value = try creditMessage(); value.sender = "HSBC@notification.hsbc.com.hk"
        #expect(try BankMailParser.parse(value) == nil)
        value = try creditMessage(money: "HKD1.234")
        #expect(throws: (any Error).self) { try BankMailParser.parse(value) }
        value = try creditMessage(); value.body = value.body.replacingOccurrences(of: "EXAMPLE CAFE", with: "")
        #expect(throws: (any Error).self) { try BankMailParser.parse(value) }
        value = try creditMessage(date: "31 Dec"); value.receivedAt = try time("2027-01-01T02:00:00Z")
        #expect(try BankMailParser.parse(value)?.date == (try time("2026-12-30T16:00:00Z")))
    }

    @Test func htmlTableFormattingAndEntitiesAreDecodedWithoutExecutingMarkup() throws {
        let html = """
        <html><style>ignored</style><table>
        <tr><td>Card Account Number Ending with:</td><td>1234</td></tr>
        <tr><td>Transaction Date:</td><td>21/10</td></tr>
        <tr><td>Merchant Name:</td><td>EXAMPLE&nbsp;SHOP &amp; CO</td></tr>
        <tr><td>Transaction Amount:</td><td>USD1,234.50</td></tr>
        </table><script>Transaction Amount:HKD900</script></html>
        """
        let value = try #require(try BankMailParser.parse(message("bochk", body: html)))
        #expect(value.merchant == "EXAMPLE SHOP & CO"); #expect(value.amountCents == 123450); #expect(value.currency == "USD")
    }

    @Test(arguments: ["2027-01-01T03:00:00Z", "2027-01-13T03:00:00Z"])
    func bochkYearlessDateUsesThePreviousYearWithinFourteenDays(_ receipt: String) throws {
        let body = bocBody.replacingOccurrences(of: "21/10", with: "31/12")
        let value = try #require(try BankMailParser.parse(message("bochk", body: body, received: receipt)))
        #expect(value.date == (try time("2026-12-30T16:00:00Z"))); #expect(!value.hasExactTime)
    }

    @Test(arguments: ["31/02", "23/10", "01/10"])
    func invalidFutureOrStaleBocDatesFailInsteadOfUsingReceiptTime(_ raw: String) throws {
        let envelope = try message("bochk", body: bocBody.replacingOccurrences(of: "21/10", with: raw))
        #expect(throws: (any Error).self) { try BankMailParser.parse(envelope) }
    }

    @Test(arguments: ["HKD0", "HKD-3.50", "HKD1.234", "HKD1,23.00", "HKD100000001", "EUR4.50"])
    func invalidMoneyNeverBecomesAPartialPurchase(_ amount: String) throws {
        let envelope = try message("bochk", body: bocBody.replacingOccurrences(of: "CNY49.00", with: amount))
        #expect(throws: (any Error).self) { try BankMailParser.parse(envelope) }
    }

    @Test(arguments: ["mx.google.com; dmarc=fail header.from=bochk.com",
                      "attacker.invalid; dmarc=pass header.from=bochk.com",
                      "mx.google.com; dmarc=pass header.from=bochk.com.attacker.invalid",
                      "mx.google.com; dmarc=pass header.from=hsbc.com.hk",
                      "mx.google.com; dmarc=fail header.from=bochk.com; dmarc=pass header.from=bochk.com"])
    func authenticationCannotBeTakenFromTheBodyDisplayNameOrLaterPassingResult(_ authentication: String) throws {
        var envelope = try message("bochk", body: bocBody + "\nmx.google.com; dmarc=pass header.from=bochk.com")
        envelope.authenticationResults = authentication
        #expect(throws: (any Error).self) { try BankMailParser.parse(envelope) }
    }

    @Test func spoofedSenderAndUnrelatedNoticesAreNotPurchases() throws {
        var envelope = try message("bochk", body: bocBody)
        envelope.sender = "istatement@bochk.com <attacker@example.invalid>"
        #expect(try BankMailParser.parse(envelope) == nil)
        envelope.sender = "istatement@bochk.com"
        for subject in ["Credit Card Statement", "Transaction Notification Refund", "交易通知 還款通知", "Transaction Notification OTP"] {
            envelope.subject = subject
            #expect(try BankMailParser.parse(envelope) == nil)
        }
        envelope.subject = "Transaction Notification"
        envelope.body = bocBody + "\nYour transaction has been declined."
        #expect(try BankMailParser.parse(envelope) == nil)
    }

    @Test func malformedKnownTemplateFailsButUnobservedFormatDoesNotPretendToBeSupported() throws {
        var envelope = try message("hsbc", body: hsbcBody.replacingOccurrences(of: "2026-10-11 20:11", with: "2026-02-31 20:11"))
        #expect(throws: (any Error).self) { try BankMailParser.parse(envelope) }
        envelope.body = hsbcBody.replacingOccurrences(of: "number ending 7890", with: "number ending 78901")
        #expect(throws: (any Error).self) { try BankMailParser.parse(envelope) }
        envelope.body = hsbcBody.replacingOccurrences(of: "Transaction currency and amount: HKD12.5", with: "")
        #expect(throws: (any Error).self) { try BankMailParser.parse(envelope) }
        envelope.subject = "Credit Card Repayment Confirmation"
        #expect(try BankMailParser.parse(envelope) == nil)
    }

    @Test func packageSupportsISO8601AndFractionsAndRejectsTheWholeMalformedBatch() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let first = try message("bochk", body: bocBody), second = try message("bea", body: beaBody)
        var uniqueSecond = second; uniqueSecond.id = "fixture-example-2"
        let data = try encoder.encode(BankMailPackage(schemaVersion: 1, messages: [first, uniqueSecond]))
        #expect(try BankMailParser.decodePackage(data).count == 2)
        let fractional = try #require(String(data: data, encoding: .utf8)).replacingOccurrences(of: "2026-10-22T02:30:00Z", with: "2026-10-22T02:30:00.123Z")
        #expect(try BankMailParser.decodePackage(Data(fractional.utf8)).count == 2)
        var invalid = uniqueSecond; invalid.body = "Format changed"
        #expect(throws: (any Error).self) { try BankMailParser.decodePackage(encoder.encode(BankMailPackage(schemaVersion: 1, messages: [first, invalid]))) }
        #expect(throws: (any Error).self) { try BankMailParser.decodePackage(encoder.encode(BankMailPackage(schemaVersion: 2, messages: [first]))) }
        #expect(throws: (any Error).self) { try BankMailParser.decodePackage(encoder.encode(BankMailPackage(schemaVersion: 1, messages: [first, first]))) }
        #expect(throws: (any Error).self) { try BankMailParser.decodePackage(Data(repeating: 0x20, count: 5_000_001)) }
        let tooMany = (0...500).map { index in
            var item = first; item.id = "fixture-\(index)"; return item
        }
        #expect(throws: (any Error).self) { try BankMailParser.decodePackage(encoder.encode(BankMailPackage(schemaVersion: 1, messages: tooMany))) }
    }
}
