import SwiftUI

enum PilotTheme {
    static let accent = Color("PilotAccent")
    static let canvas = Color("PilotCanvas")
    static let surface = Color("PilotSurface")
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 20
    static let pagePadding: CGFloat = 20
    // Compact iPhone layout; desktop and regular-width views retain their existing metrics.
    static let phonePagePadding: CGFloat = 16
    static let phoneSectionSpacing: CGFloat = 24
    static let minimumTouchTarget: CGFloat = 44
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
}
