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
                    Text("1. 在快捷指令 → 自动化中新建「交易」自动化，每张 Wallet 付款卡片单独设置。")
                    Text("2. 添加 CardPilot「记录 Apple Pay 交易」动作，选择对应的 CardPilot 银行卡。")
                    Text("3. 「钱包金额原文」绑定「交易 → 数量」，「商户」绑定「交易 → 商家」，选择立即运行。")
                    Text("Wallet 的「数量」可能是带币种符号的文本，不能直接转换成普通数字。新动作会识别明确的 HKD/CNY/USD 标记并保留原币；仅有数字、$ 或 ¥ 时无法可靠判定币种，不会猜成 HKD。可为单币种自动化指定备用币种；GO 等双币卡建议保持自动并用真机消费验证。¥ 也可能代表 JPY，自动模式不会直接当成人民币；负数或退款请手动核对。此自动化只针对受支持的感应付款。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).navigationTitle("快捷记账")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: { dismiss() }) } }
        }
        .editorSize()
    }
}
