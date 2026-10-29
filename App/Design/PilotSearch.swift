import SwiftUI

#if os(iOS)
/// Place inside the scroll content, never in an overlay or a pinned section header.
struct PilotSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).submitLabel(.search)
                    .onSubmit { focused = false }
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Label("清除搜索", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                    }.foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: PilotTheme.minimumTouchTarget)
            .background(.quaternary, in: .rect(cornerRadius: 12))
            if focused || !text.isEmpty {
                Button { text = ""; focused = false } label: {
                    Text("取消").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
                    .accessibilityLabel("取消搜索")
                    .foregroundStyle(PilotTheme.accent)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .buttonStyle(.plain)
    }
}
#endif

extension View {
    /// iOS search fields live in each page's scrolling content; macOS keeps toolbar search.
    @ViewBuilder func pilotSearchChrome(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        #if os(iOS)
        scrollEdgeEffectStyle(.hard, for: .top)
            .toolbarBackground(PilotTheme.canvas, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        #else
        searchable(text: text, prompt: Text(prompt))
        #endif
    }
}
