import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PilotTheme {
    static let accent = Color("PilotAccent")
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 20
    static let pagePadding: CGFloat = 20
    // Compact iPhone layout; desktop and regular-width views retain their existing metrics.
    static let phonePagePadding: CGFloat = 16
    static let phoneSectionSpacing: CGFloat = 24
    static let minimumTouchTarget: CGFloat = 44
    static let cardAspectRatio: CGFloat = 1.586
    static let cardCornerRadius: CGFloat = 14

    /// System surfaces keep system materials, list backgrounds, and iOS 26 scroll
    /// edge effects intact. Branding belongs in content and controls, not every page.
    static var canvas: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    static var groupedCanvas: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color.clear
        #endif
    }

    static var surface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.clear
        #endif
    }

    static var cardBackdrop: Color {
        Color.primary.opacity(0.045)
    }
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": .purple
        case "red": .red
        case "blue": .blue
        case "orange": .orange
        default: accent
        }
    }
}

extension View {
    func phonePrimaryAction() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
            .labelStyle(.titleAndIcon)
    }

    func pilotPanel() -> some View {
        padding(PilotTheme.spacing)
            .background(PilotTheme.surface, in: .rect(cornerRadius: PilotTheme.radius))
            .overlay { RoundedRectangle(cornerRadius: PilotTheme.radius).strokeBorder(.primary.opacity(0.045)) }
    }

    @ViewBuilder func editorSize() -> some View {
        #if os(macOS)
        frame(minWidth: 560, idealWidth: 600, minHeight: 620, idealHeight: 720)
        #else
        self
        #endif
    }

    /// Inline titles are an iOS navigation-bar affordance. Keeping this tiny
    /// platform wrapper avoids leaking an iOS-only modifier into shared views.
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder func minimizedSearchToolbar() -> some View {
        #if os(iOS)
        searchToolbarBehavior(.minimize)
        #else
        self
        #endif
    }
}
