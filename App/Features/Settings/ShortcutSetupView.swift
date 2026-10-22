import SwiftUI
import AppIntents

struct ShortcutSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("快速开始") {
                    Text("CardPilot已提供记账动作，可直接在快捷指令中使用。")
                    Link("打开快捷指令", destination: URL(string: "shortcuts://")!)
                }
                Section("添加现成快捷指令") {
                    if let url = Bundle.main.url(forResource: "CardPilot 记一笔", withExtension: "shortcut") {
                        ShareLink("获取「记一笔」", item: url)
                    }
                    Text("在分享菜单中保存文件，再打开文件并选择「添加快捷指令」。首次添加由系统确认。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Apple Pay 自动记账") {
                    Text("1. 在手机的快捷指令中，添加「交易」自动化并选择付款卡片。")
                    Text("2. 添加「记录银行卡消费」动作，选择银行卡，将金额、商户和交易时间设为本次交易提供的内容。")
                    Text("3. 先完成一次付款测试，确认记录正确后开启自动运行。")
                    Text("Apple Pay 自动化可选择对应支付方式；有交易标识时一并传入，以防重复记账。外币可直接按原币保存，汇率选填。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).navigationTitle("快捷记账")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: { dismiss() }) } }
        }
        .editorSize()
    }
}
