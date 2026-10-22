import SwiftUI

struct LibraryBankRow: View {
    let bank: LibraryBank
    let productCount: Int

    var body: some View {
        HStack(spacing: 16) {
            LibraryBankLogo(resource: bank.logoResource)
                .frame(width: 54, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(bank.name).font(.headline)
                if !bank.name.localizedStandardContains(bank.shortName) {
                    Text(bank.shortName).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(productCount) 款").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 10)
    }
}
