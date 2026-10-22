import SwiftUI

/// A plain scrollable empty state keeps actions out of system unavailable-view sizing.
struct CardsEmptyState: View {
    let onCatalog: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "creditcard")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("你的第一张卡").font(.title2.bold())
                Text("添加银行卡，集中查看权益、优惠与消费。")
                    .font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                Button(action: onCatalog) {
                    Label("从资料库添加", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .phonePrimaryAction()
                .buttonBorderShape(.roundedRectangle(radius: 14))
                Button(action: onManual) {
                    Text("手动添加").frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PilotTheme.accent)
            }
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
    }
}
