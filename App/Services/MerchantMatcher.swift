import Foundation

enum MerchantMatcher {
    static func matches(_ merchant: String, keyword: String) -> Bool {
        // Latin merchant tokens need boundaries: GU must not match "GUCCI".
        let tokenOnly = keyword.unicodeScalars.allSatisfy { $0.isASCII }
        if tokenOnly {
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            let pattern = "(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])"
            return merchant.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return merchant.localizedStandardContains(keyword)
    }
}
