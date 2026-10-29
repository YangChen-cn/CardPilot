import SwiftUI
import SwiftData

struct CardProductPreviewView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [BankCard]
    let product: CardProduct
    let onFinish: () -> Void
    @State private var savedCard: BankCard?
    @State private var showingSetup = false
    @State private var adding = false
    @State private var error: String?

    private var existingCard: BankCard? { cards.first { $0.catalogID == product.id } }
    private var generalRules: [CatalogRule] { product.catalog.rules.filter { $0.kind != "welcome" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LibraryProductArtwork(product: product)
                    .aspectRatio(PilotTheme.cardAspectRatio, contentMode: .fit)
                    .frame(maxWidth: 440).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Text(product.catalog.name).font(.title2).bold()
                    Text(product.catalog.bank + " · " + CardKind.normalized(product.catalog.kind ?? "").label + " · " + product.catalog.network).font(.subheadline).foregroundStyle(.secondary)
                    if let existingCard {
                        Label(existingCard.isArchived ? "已在卡包中归档" : "已在你的卡包中", systemImage: existingCard.isArchived ? "archivebox" : "checkmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                GroupBox("卡片信息") {
                    VStack(spacing: 14) {
                        if product.baseRewardVerified, let rate = product.catalog.baseRatePercent {
                            LabeledContent("基础回赠", value: rate.formatted(.number.precision(.fractionLength(0...2))) + "%")
                        } else {
                            LabeledContent("基础回赠", value: "待核实")
                        }
                        if let fee = product.catalog.foreignFeePercent {
                            LabeledContent("外币手续费", value: fee.formatted(.number.precision(.fractionLength(0...2))) + "%")
                        }
                        if let fee = product.catalog.annualFeeNote, !fee.isEmpty {
                            LabeledContent("年费", value: fee)
                        }
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
                if let guide = product.usageGuide {
                    CardUsageGuideSection(guide: guide, productName: product.catalog.name)
                }
                if !generalRules.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("日常优惠").font(.title3).bold()
                        ForEach(generalRules) { rule in LibraryRuleSummary(rule: rule, verifiedOn: product.catalog.verifiedOn) }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("迎新奖励").font(.title3).bold()
                    if product.welcomePlans.isEmpty {
                        Text("暂无可用迎新资料，可稍后自行添加。").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(product.welcomePlans) { plan in WelcomePlanSummary(plan: plan) }
                        Text("添加后可自行记录迎新状态与截止日期。").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let caveats = product.catalog.caveats, !caveats.isEmpty {
                    PilotDisclosureGroup("产品说明") {
                        Text(caveats).font(.subheadline).foregroundStyle(.secondary).padding(.top, 12)
                    }.pilotPanel()
                }
                if let url = URL(string: product.catalog.sourceURL) {
                    Link("银行官方资料", destination: url).font(.subheadline).frame(minHeight: 44)
                    Text("资料核实于 " + product.catalog.verifiedOn).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(PilotTheme.pagePadding).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(PilotTheme.canvas)
        .navigationTitle("卡片资料")
        .inlineNavigationTitle()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: add) {
                Label(adding ? "正在添加…" : (existingCard == nil ? "添加到卡包" : "设置我的卡片"), systemImage: existingCard == nil ? "plus" : "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).controlSize(.large).disabled(adding)
            .padding(PilotTheme.pagePadding).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationDestination(isPresented: $showingSetup) {
            if let savedCard { PersonalCardSetupView(card: savedCard, product: product, onFinish: onFinish) }
        }
        .alert("未能添加卡片", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "请重试。") }
    }

    private func add() {
        adding = true
        defer { adding = false }
        do {
            savedCard = try existingCard ?? LibraryOnboarding.add(product: product, in: context)
            showingSetup = true
        } catch { self.error = PilotError.message(error, fallback: "未能保存银行卡，请重试。") }
    }
}
