import SwiftUI
import SwiftData

struct OfferPanel: View {
    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let info: BenefitInfo
    var onEdit: (() -> Void)?
    @State private var managingWelcome = false
    @State private var showingReader = false
    @State private var refreshToken = 0

    init(info: BenefitInfo, onEdit: (() -> Void)? = nil) {
        self.info = info; self.onEdit = onEdit
    }

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        let _ = refreshToken
        let tracking = info.isWelcome ? (try? OfferTrackingStore.load(for: info, context: context)) : nil
        Group {
            if phoneLayout {
                Button { showingReader = true } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        heading(tracking)
                        if info.headline != "查看适用权益与条件" {
                            Text(info.headline).font(.headline).foregroundStyle(PilotTheme.accent)
                        }
                        phoneSummary
                        phoneFooter
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pilotPanel()
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看适用条件和官方条款")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Button { showingReader = true } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            heading(tracking)
                            Text(info.headline).font(.title3.weight(.semibold)).foregroundStyle(PilotTheme.accent)
                            VStack(alignment: .leading, spacing: 12) {
                                BenefitConditionGrid(info: info, compact: true)
                                BenefitNotesView(info: info, compact: true, limit: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("阅读完整条款：\(info.title)")
                    Divider()
                    desktopFooter(tracking)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .pilotPanel()
            }
        }
        .sheet(isPresented: $managingWelcome) { WelcomeTrackingEditor(info: info) }
        .sheet(isPresented: $showingReader) {
            BenefitDetailView(info: info)
        }
        .onReceive(NotificationCenter.default.publisher(for: Persistence.didChange)) { _ in refreshToken &+= 1 }
    }

    private func heading(_ tracking: WelcomeTracking?) -> some View {
        let headingLayout = phoneLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 7))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return headingLayout {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.cardName).font(.caption).foregroundStyle(.secondary)
                Text(info.title).font(phoneLayout ? .subheadline.weight(.semibold) : .headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !phoneLayout { Spacer(minLength: 0) }
            HStack(spacing: 8) {
                if info.personal.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("已收藏")
                }
                if let tracking {
                    let status = tracking.effectiveStatus()
                    Label(status.label, systemImage: status.symbol)
                        .font(.caption).foregroundStyle(status == .received ? PilotTheme.accent : .secondary)
                } else if info.isNotStarted {
                    Text("尚未开始").font(.caption).foregroundStyle(.secondary)
                } else if info.isEnded {
                    Text("已结束").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var phoneSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(info.labeledTerms.prefix(info.capCents > 0 ? 1 : 2)) { term in
                Text((term.label.map { $0 + "：" } ?? "") + term.value)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if info.capCents > 0 {
                let period = info.catalogRule?.capPeriod ?? info.legacyRule?.capPeriod
                let label = period == "monthly" ? "每月回赠上限" : period == "campaign" ? "整期回赠上限" : "回赠上限"
                Text(label + " " + Money.text(info.capCents))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if info.labeledTerms.isEmpty, !info.noteTerms.isEmpty {
                Text("适用条件见详情")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var phoneFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Label(info.periodDescription, systemImage: info.periodStatus == .unknown ? "calendar.badge.questionmark" : "calendar")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func desktopFooter(_ tracking: WelcomeTracking?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(info.periodDescription, systemImage: info.periodStatus == .unknown ? "calendar.badge.questionmark" : "calendar")
                if let tracking, tracking.hasKnownDeadline {
                    Text("个人消费截止 " + tracking.deadline.formatted(.dateTime.year().month().day()))
                }
                if !info.verifiedOn.isEmpty { Text("资料核实于 " + info.verifiedOn) }
                if let url = URL(string: info.sourceURL), url.scheme == "https" {
                    Link("官方条款", destination: url)
                        .font(.caption.weight(.medium))
                        .tint(PilotTheme.accent)
                }
            }.font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Spacer(minLength: 4)
                if info.isWelcome {
                    Button("管理迎新", action: { managingWelcome = true }).frame(minHeight: 44)
                }
                Spacer(minLength: 4)
                if info.canEdit, let onEdit {
                    Button("编辑", systemImage: "pencil", action: onEdit)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .font(.subheadline)
        }
    }

}
