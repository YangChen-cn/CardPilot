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
        VStack(alignment: .leading, spacing: 14) {
            // The whole terms block is the reader target. A small button is easy
            // to miss, especially in a long card, so keep the affordance visible
            // without making the hit area tiny.
            Button {
                showingReader = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    let headingLayout = phoneLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    headingLayout {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(info.cardName).font(.caption).foregroundStyle(.secondary)
                            Text(info.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        }
                        if !phoneLayout { Spacer(minLength: 0) }
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
                    Text(info.headline).font(.title3.weight(.semibold)).foregroundStyle(PilotTheme.accent)
                    VStack(alignment: .leading, spacing: 12) {
                        if phoneLayout {
                            // Keep the phone summary scan-friendly; every condition
                            // remains available in the full-card reader target.
                            ForEach(info.labeledTerms.prefix(2)) { term in
                                Text((term.label.map { $0 + "：" } ?? "") + term.value)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            BenefitConditionGrid(info: info, compact: true)
                        }
                        BenefitNotesView(info: info, compact: true, limit: 1)
                    }
                    HStack(spacing: 4) {
                        Text("查看完整条款")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PilotTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("阅读完整条款：\(info.title)")
            Divider()
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
                        .frame(minHeight: phoneLayout ? 44 : nil)
                }
            }.font(.caption).foregroundStyle(.secondary)
            if !phoneLayout || info.isWelcome || (info.canEdit && onEdit != nil) {
                HStack(spacing: 10) {
                    if !phoneLayout { Spacer(minLength: 4) }
                    if info.isWelcome {
                        Button("管理迎新", action: { managingWelcome = true }).frame(minHeight: 44)
                    }
                    if phoneLayout { Spacer(minLength: 4) }
                    if info.canEdit, let onEdit { Button("编辑", systemImage: "pencil", action: onEdit).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // LazyVGrid can propose the row height from a shorter sibling. Keep the
        // card at its intrinsic height so a long terms block can never be clipped
        // by the next row.
        .fixedSize(horizontal: false, vertical: true)
        .pilotPanel()
        .sheet(isPresented: $managingWelcome) { WelcomeTrackingEditor(info: info) }
        .sheet(isPresented: $showingReader) { BenefitDetailView(info: info) }
        .onReceive(NotificationCenter.default.publisher(for: Persistence.didChange)) { _ in refreshToken &+= 1 }
    }
}
