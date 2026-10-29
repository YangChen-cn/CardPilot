import SwiftUI

struct AddCardFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogRepository.self) private var catalog
    @State private var library: BankLibrary?
    @State private var search = ""
    @State private var error: String?
    @State private var showingManual = false
    @State private var manualSaved = false
    @State private var showingBankList = false

    private var banks: [LibraryBank] {
        library?.banks.filter {
            search.isEmpty || $0.name.localizedStandardContains(search) || $0.shortName.localizedStandardContains(search)
        } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                #if os(iOS)
                Section {
                    PilotSearchField(text: $search, prompt: "搜索银行")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                #endif
                if let library {
                    Section("选择银行") {
                        ForEach(banks) { bank in
                            NavigationLink {
                                BankProductsView(bank: bank, products: library.products(for: bank.id), onFinish: finish)
                            } label: {
                                LibraryBankRow(bank: bank, productCount: library.products(for: bank.id).count)
                            }
                        }
                        if banks.isEmpty { ContentUnavailableView.search }
                    }
                    Section {
                        Button("手动添加银行卡", systemImage: "square.and.pencil", action: showManual)
                            .frame(minHeight: 44)
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("暂时无法打开资料库", systemImage: "creditcard.trianglebadge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试", action: load).buttonStyle(.bordered)
                        Button("手动添加", action: showManual)
                    }
                } else {
                    ProgressView("正在打开资料库").frame(maxWidth: .infinity).padding()
                }
            }
            .onAppear { showingBankList = true; load() }
            .onDisappear { showingBankList = false }
            .onChange(of: catalog.revision) { _, _ in
                if showingBankList { load() }
            }
            .groupedListStyle()
            .background(PilotTheme.groupedCanvas)
            .pilotSearchChrome(text: $search, prompt: "搜索银行")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("添加银行卡")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", action: finish) }
            }
        }
        .editorSize()
        .sheet(isPresented: $showingManual, onDismiss: manualDismissed) {
            CardEditor(onSaved: { manualSaved = true })
        }
    }

    private func load() {
        do { library = try BankLibrary.load(); error = nil }
        catch { self.error = "请稍后重试，也可以先手动添加银行卡。" }
    }
    private func showManual() { manualSaved = false; showingManual = true }
    private func manualDismissed() { if manualSaved { finish() } }
    private func finish() { dismiss() }
}
