import SwiftUI

struct RecommendationWorkbench: View {
    let cards: [BankCard]
    var compact = false
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var draft = RecommendationDraft()
    @State private var addingCard = false

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        let _ = catalog.revision
        Group {
            if !compact && !cards.contains(where: { !$0.isArchived }) {
                ContentUnavailableView {
                    Label("先添加一张银行卡", systemImage: "creditcard")
                } description: {
                    Text("根据你持有的卡片，比较可能适用的权益。")
                } actions: {
                    Button("从资料库添加", systemImage: "plus", action: { addingCard = true })
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            } else if compact { content }
            else {
                ScrollView {
                    content.padding(phoneLayout ? PilotTheme.phonePagePadding : PilotTheme.pagePadding)
                        .frame(maxWidth: 900).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .sheet(isPresented: $addingCard) { AddCardFlowView() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 28) {
            if !compact {
                if !phoneLayout { Text("这一笔，考虑哪张卡？").font(.title2.bold()) }
                Text(phoneLayout ? "选好类别与地区，看看哪些权益可能适用。" : "按公开权益筛选，帮你找到值得查看的优惠。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("排序先看公开权益力度，再参考已确认条件；未填写的支付方式、商户等会标为待确认。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RecommendationFields(draft: draft, compact: compact)
            if let issue = draft.validationError {
                Text(issue).font(.subheadline).foregroundStyle(.secondary)
            } else {
                let suggestions = RecommendationEngine.suggest(cards: cards, query: draft)
                if suggestions.isEmpty {
                    ContentUnavailableView("暂无匹配的公开权益", systemImage: "creditcard", description: Text("可调整条件，或到卡片详情查看完整优惠。"))
                } else {
                    ForEach(compact ? Array(suggestions.prefix(2)) : suggestions) { result in
                        RecommendationRow(result: result)
                    }
                    if compact, suggestions.count > 2 {
                        NavigationLink("查看全部 \(suggestions.count) 张候选") { RecommendView() }
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                }
            }
            if !compact { Text("优惠及合资格消费以官方条款为准。")
                    .font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
