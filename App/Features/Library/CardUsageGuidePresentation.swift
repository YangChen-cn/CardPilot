#if os(iOS)
import SwiftUI
import UIKit
import OSLog

/// A sheet exists only after its immutable content and initial height are ready.
@MainActor struct CardUsageGuidePresentation: Identifiable {
    let id = UUID()
    let guide: CardUsageGuide
    let productName: String
    let height: CGFloat

    static func prepare(guide: CardUsageGuide, productName: String, anchor: UIView,
                        environment: EnvironmentValues) -> Self? {
        guard let window = anchor.window else { return nil }
        let available = window.bounds.inset(by: window.safeAreaInsets).size
        return measure(guide: guide, productName: productName, available: available, environment: environment)
    }

    static func measure(guide: CardUsageGuide, productName: String, available: CGSize,
                        environment: EnvironmentValues) -> Self? {
        guard available.width.isFinite, available.height.isFinite,
              available.width > 0, available.height > 0 else { return nil }

        let content = CardUsageGuideSheetContent(guide: guide, productName: productName,
                                                scrolling: false, onClose: { })
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.locale, environment.locale)
            .environment(\.timeZone, environment.timeZone)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.displayScale, environment.displayScale)
            .tint(PilotTheme.accent)
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let measured = host.sizeThatFits(in: CGSize(width: available.width, height: .greatestFiniteMagnitude))
        guard measured.height.isFinite, measured.height > 0 else { return nil }
        let height = min(ceil(measured.height), available.height)
        Logger(subsystem: "com.cardpilot.app", category: "guide-sizing")
            .notice("Prepared guide width=\(Double(available.width), privacy: .public) content=\(Double(measured.height), privacy: .public) detent=\(Double(height), privacy: .public)")
        return Self(guide: guide, productName: productName, height: height)
    }
}
#endif
