#if os(iOS)
import SwiftUI
import Testing
@testable import CardPilot

/// Numeric offscreen layout checks; no sheet presentation, UI actions or screenshots.
@Suite(.serialized) @MainActor
struct GuidePresentationSizingTests {
    private func environment(size: DynamicTypeSize = .large) -> EnvironmentValues {
        var values = EnvironmentValues()
        values.locale = Locale(identifier: "zh_Hans_HK")
        values.dynamicTypeSize = size
        values.displayScale = 3
        return values
    }

    private func measure(width: CGFloat = 393, height: CGFloat = 2000,
                         typeSize: DynamicTypeSize = .large) throws -> CardUsageGuidePresentation {
        let product = try #require(BankLibrary.load().product(id: "hsbc.mastercard.debit"))
        let guide = try #require(product.usageGuide)
        return try #require(CardUsageGuidePresentation.measure(guide: guide, productName: product.catalog.name,
                            available: CGSize(width: width, height: height), environment: environment(size: typeSize)))
    }

    @Test func shortGuideHasItsHeightBeforePresentation() throws {
        let result = try measure(height: 760)
        #expect(result.height > 150)
        #expect(result.height < 640)
        #expect(result.productName.contains("Mastercard"))
    }

    @Test func widthAndTextSizeChangeMeasuredLayout() throws {
        let wide = try measure(width: 430)
        let narrow = try measure(width: 320)
        let accessible = try measure(typeSize: .accessibility3)
        #expect(narrow.height > wide.height)
        #expect(accessible.height > narrow.height)
    }

    @Test func smallWindowsCapLongContent() throws {
        let natural = try measure()
        let capped = try measure(height: 300)
        #expect(natural.height > capped.height)
        #expect(capped.height == 300)
    }
}
#endif
