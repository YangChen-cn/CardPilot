import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FolderSyncController.self) private var sync
    @Environment(CatalogRepository.self) private var catalog
    @State private var selection: AppSection? = .cards
    @State private var showingTransaction = false
    @State private var showingSettings = false
    @State private var tab: AppSection = .cards
    @State private var reminderRevision = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if sizeClass == .compact {
                TabView(selection: $tab) {
                    Tab("卡包", systemImage: "creditcard", value: .cards) { mobile(.cards) }
                    Tab("权益", systemImage: "gift", value: .offers) { mobile(.offers) }
                    Tab("账本", systemImage: "list.bullet.rectangle", value: .transactions) { mobile(.transactions) }
                }
                .tabBarMinimizeBehavior(.never)
            } else { desktop }
            #else
            desktop
            #endif
        }
        .tint(PilotTheme.accent)
        .sheet(isPresented: $showingTransaction) { TransactionEditor() }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成", action: { showingSettings = false }) }
                }
            }
        }
        .task {
            guard !RuntimeMode.isEphemeral else { return }
            while !Task.isCancelled {
                await MailCloudController.shared.sync(in: context)
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
        .task {
            await LibraryArtworkUpdates.retainHeldArtwork(in: context)
            await sync.attach(context)
            try? OfferMigration.migrateLegacy(in: context)
            await catalog.checkIfNeeded()
        }
        .task(id: reminderRevision) { try? await WelcomeReminderService.refresh(context: context) }
        .onReceive(NotificationCenter.default.publisher(for: Persistence.didChange)) { _ in
            reminderRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            reminderRevision &+= 1
        }
        .onOpenURL { url in
            guard url.scheme == "cardpilot" else { return }
            if url.host == "record" { showingTransaction = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sync.resume()
                reminderRevision &+= 1
                Task { await MailCloudController.shared.sync(in: context) }
                Task { await catalog.checkIfNeeded() }
            }
            else if phase == .background { sync.suspend() }
        }
    }

    private var desktop: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }
                Section {
                    Label(AppSection.settings.rawValue, systemImage: AppSection.settings.symbol).tag(AppSection.settings)
                }
            }
            .navigationTitle("CardPilot")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
            .safeAreaInset(edge: .bottom) {
                Label(sync.statusSummary, systemImage: sync.isEnabled ? "arrow.triangle.2.circlepath" : "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            NavigationStack {
                sectionView(selection ?? .cards)
                    .navigationTitle(title(selection ?? .cards))
                    .toolbar {
                        if selection == .transactions {
                            ToolbarItem(placement: .primaryAction) {
                                Button("记一笔", systemImage: "plus", action: { showingTransaction = true })
                                    .keyboardShortcut("n", modifiers: .command)
                            }
                        }
                    }
            }
        }
        #if os(macOS)
        .frame(minWidth: 860, minHeight: 640)
        #endif
    }

    #if os(iOS)
    private func mobile(_ section: AppSection) -> some View {
        NavigationStack {
            sectionView(section)
                .navigationTitle(title(section))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if section == .cards {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("设置", systemImage: "gearshape", action: { showingSettings = true })
                                .labelStyle(.iconOnly)
                        }
                    }
                }
        }
    }
    #endif

    private func title(_ section: AppSection) -> String { section.navigationTitle }

    @ViewBuilder private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .cards: CardsView()
        case .offers: OffersView()
        case .transactions: TransactionsView()
        case .recommend: RecommendView()
        case .settings: SettingsView()
        }
    }

}
