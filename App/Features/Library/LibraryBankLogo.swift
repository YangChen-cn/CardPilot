import SwiftUI

struct LibraryBankLogo: View {
    let resource: String
    @State private var data: Data?

    var body: some View {
        Group {
            if let data { LocalCardImage(data: data) }
            else { Image(systemName: "building.columns").font(.title2).foregroundStyle(.secondary) }
        }
        .task(id: resource) { data = BankLibrary.imageData(resource: resource) }
    }
}
