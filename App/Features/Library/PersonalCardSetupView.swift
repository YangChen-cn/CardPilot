import SwiftUI
import SwiftData

struct PersonalCardSetupView: View {
    @Environment(\.modelContext) private var context
    @State private var draft: PersonalCardDraft
    @State private var showingError = false
    let onFinish: () -> Void

    init(card: BankCard, product: CardProduct, onFinish: @escaping () -> Void) {
        _draft = State(initialValue: PersonalCardDraft(card: card, product: product))
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            Section {
                LibraryProductArtwork(product: draft.product)
                    .frame(maxWidth: 280).frame(maxWidth: .infinity)
                Text(draft.card.name).font(.headline)
            }
            Section("持卡资料") {
                TextField("卡片尾号（选填）", text: $draft.lastFour)
                Stepper("账单日：" + (draft.statementDay == 0 ? "未设置" : "每月\(draft.statementDay)日"), value: $draft.statementDay, in: 0...31)
                Stepper("还款日：" + (draft.paymentDay == 0 ? "未设置" : "每月\(draft.paymentDay)日"), value: $draft.paymentDay, in: 0...31)
                TextField("信用额度（HKD）", value: $draft.creditLimit, format: .number)
                if let name = draft.sharedCreditName {
                    Text("与「\(name)」共享额度，修改会影响组内卡片。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("卡片权益已保存。迎新日期、备注和完成状态可在对应迎新活动中随时记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("保存", action: save).buttonStyle(.borderedProminent)
                Button("稍后设置", action: onFinish)
            }
        }
        .formStyle(.grouped).editorSize().navigationTitle("持卡资料")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: save) } }
        .alert("未能保存", isPresented: $showingError) { } message: { Text(draft.error ?? "请重试。") }
    }

    private func save() {
        if draft.save(in: context) { onFinish() } else { showingError = true }
    }
}
