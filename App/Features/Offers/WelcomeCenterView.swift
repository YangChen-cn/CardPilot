import SwiftUI
import SwiftData

struct WelcomeCenterView: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var documents: [DomainRecord]
    @AppStorage("welcome.reminders") private var remindersEnabled = false
    @State private var editing: BenefitInfo?
    @State private var message: String?
    @State private var filter = "进行中"
    @State private var reading: BenefitInfo?

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        let _ = documents.map(\.modifiedAt)
        let _ = catalog.revision
        // Keep archived/historical personal rewards accessible in the history filter.
        let welcome = OfferStore.offers(context: context).filter(\.isWelcome)
        let items = welcome.filter { info in
            guard let tracking = try? OfferTrackingStore.load(for: info, context: context) else { return true }
            let status = tracking.effectiveStatus()
            switch filter {
            case "待到账": return status == .achieved
            case "已结束": return status == .received || status == .ended
            case "全部": return true
            default: return status == .active || status == .unconfirmed
            }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if phoneLayout {
                    HStack {
                        Text(filter).font(.headline)
                        Spacer()
                        Menu("筛选迎新状态", systemImage: "line.3.horizontal.decrease.circle") {
                            Picker("迎新状态", selection: $filter) {
                                ForEach(["进行中", "待到账", "已结束", "全部"], id: \.self) { Text($0).tag($0) }
                            }
                        }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                } else {
                    Text("条件由银行公布，完成与到账状态由你确认。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("迎新状态", selection: $filter) {
                        ForEach(["进行中", "待到账", "已结束", "全部"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 480)
                }
                if items.isEmpty {
                    ContentUnavailableView("暂无\(filter == "全部" ? "" : filter)迎新记录", systemImage: "gift", description: Text("银行卡的迎新条件会显示在这里，可按实际情况更新个人状态。"))
                }
                LazyVGrid(columns: phoneLayout ? [GridItem(.flexible(), alignment: .top)] : [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(items) { info in goal(info).padding(.bottom, 8) }
                }
                Divider()
                let reminderLayout = phoneLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
                reminderLayout {
                    Label("截止前 7 天及 1 天提醒", systemImage: "bell")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !phoneLayout { Spacer() }
                    if remindersEnabled { Text("已开启").font(.subheadline).foregroundStyle(PilotTheme.accent) }
                    else { Button("开启提醒", action: enableReminders).buttonStyle(.bordered).frame(minHeight: 44) }
                }
                if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            }.padding(phoneLayout ? PilotTheme.phonePagePadding : PilotTheme.pagePadding).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }
        .background(PilotTheme.canvas).navigationTitle("迎新记录")
        .sheet(item: $editing) { WelcomeTrackingEditor(info: $0) }
        .sheet(item: $reading) { BenefitDetailView(info: $0) }
    }

    @ViewBuilder private func goal(_ info: BenefitInfo) -> some View {
        if let tracking = try? OfferTrackingStore.load(for: info, context: context) {
            let status = tracking.effectiveStatus()
            let days = HKCalendar.daysLeft(tracking.deadline)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.cardName).font(.caption).foregroundStyle(.secondary)
                    Text(info.title).font(.headline)
                }
                Label(status.label, systemImage: status.symbol).font(.subheadline.weight(.medium)).foregroundStyle(PilotTheme.accent)
                Text(tracking.rewardContent).font(.title3.weight(.semibold))
                if tracking.thresholdCents > 0 { Text("消费门槛 " + Money.text(tracking.thresholdCents)).font(.subheadline).foregroundStyle(.secondary) }
                let deadlineLayout = phoneLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                deadlineLayout {
                    if tracking.hasKnownDeadline {
                        Label(tracking.deadline.formatted(.dateTime.year().month().day()) + " 截止", systemImage: "calendar")
                    } else { Label("个人截止日期未记录", systemImage: "calendar.badge.questionmark") }
                    if !phoneLayout { Spacer() }
                    if tracking.hasKnownDeadline && (status == .active || status == .unconfirmed) {
                        Text(days == 0 ? "今天截止" : "还剩 \(days) 天").foregroundStyle(days <= 7 ? .orange : .secondary)
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if let date = tracking.receivedOn { Text("记录到账于 " + date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                if !tracking.notes.isEmpty { Text(tracking.notes).font(.subheadline).foregroundStyle(.secondary) }
                if !info.conditions.isEmpty {
                    if phoneLayout {
                        Button("查看官方条件与限制", systemImage: "book.pages", action: { reading = info })
                            .font(.subheadline).frame(minHeight: 44)
                    } else {
                        PilotDisclosureGroup("官方条件与限制") {
                            VStack(alignment: .leading, spacing: 12) {
                                BenefitConditionGrid(info: info)
                                BenefitNotesView(info: info)
                                Button("在阅读器中打开", systemImage: "book.pages", action: { reading = info })
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                if !info.verifiedOn.isEmpty {
                                    Text("资料核实于 " + info.verifiedOn).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }.font(.subheadline)
                    }
                }
                Divider()
                let actionLayout = phoneLayout && typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
                actionLayout {
                    if let url = URL(string: info.sourceURL), url.scheme == "https" {
                        Link("官方条款", destination: url).frame(minHeight: phoneLayout ? 44 : nil)
                    }
                    if !(phoneLayout && typeSize.isAccessibilitySize) { Spacer() }
                    Button("更新状态", action: { editing = info }).buttonStyle(.bordered).frame(minHeight: 44)
                }.font(.subheadline)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .pilotPanel()
        } else {
            Button("无法读取记录 · 重试", action: { editing = info }).frame(minHeight: 44)
        }
    }

    private func enableReminders() {
        Task {
            do { message = try await WelcomeReminderService.enable(context: context) ? "已开启到期提醒。" : "请在系统设置中允许 CardPilot 通知。" }
            catch { message = "暂时无法设置提醒，请稍后重试。" }
        }
    }
}
