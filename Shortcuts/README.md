# CardPilot 快捷指令

已签名文件位于 `App/Resources/Shortcuts/`，也随 iOS/macOS App 打包，在「设置 → 快捷记账」中分享。将文件传到手机后打开，按系统提示添加；项目不会替用户静默安装工作流。

| 文件 | 实际动作 |
|---|---|
| CardPilot 记一笔.shortcut | 打开 `cardpilot://record`，显示记账表单 |

它们是可导入的快捷入口，不包含已绑定付款卡片的 Apple Pay 自动化。只用系统 URL 动作，避免工作流依赖侧载时可能改变的签名团队。

## Apple Pay 自动记账

**Wallet 的「交易 → 数量」可能是带符号、千分位的格式化文本，而非纯数字。** 旧版「记录银行卡消费」的 Double 金额字段不适合直接接这个变量；请使用新增的 **「记录 Apple Pay 交易」** 动作。

1. iPhone「快捷指令 → 自动化 → 交易」，选择一张具体的 Wallet 付款卡片，设为「立即运行」。
2. 添加 CardPilot 的「记录 Apple Pay 交易」动作。先选择 CardPilot 里**对应的银行卡**，不要把 Wallet「卡片或凭证」变量传给这个字段。
3. 将 **「钱包金额原文」绑定「交易 → 数量」**，**「商户」绑定「交易 → 商家」**；两者使用 Wallet 变量，不需要手动「转换为数字」、取货币属性或拼接 URL。
4. 其他银行卡分别创建对应自动化。实际感应付款后检查 CardPilot 的商户、金额和原币是否正确；这不是网上/应用内 Apple Pay 的全量监听。

币种识别策略：
- **明确标记**：\`HKD\` / \`HK$\` → HKD；\`CNY\` / \`RMB\` / \`CN¥\` / \`¥\` → CNY；\`USD\` / \`US$\` → USD。
- **不明确**：Wallet 只传 \`12.50\` 或 \`$12.50\` 时，无法判断 HKD/CNY/USD；自动模式会报错而非默认为 HKD，以免污染账本。只用于单币种的卡片自动化可以在动作的「币种不明确时」填写固定备用币种。
- **局限**：\`¥\` 也可以表示日元，不能将它理解成跨国家/地区的可靠 ISO 代码；本功能只支持 HKD/CNY/USD，使用其他币种或前往日本等场景要核对原始金额。
- 不知道汇率时保留原币和未知汇率，**不自动伪造港币折算金额或交易地区**。

此动作独立于原「记录银行卡消费」手动/自定义快捷指令，不破坏已有设置。签名的「CardPilot 记一笔.shortcut」仍只是打开手动记账表单，**Apple 不允许分发文件直接替用户安装私人交易触发器**，所以新动作需要各自在 iPhone「自动化」中绑定。此方案仅复用开源项目[GoodToNote](https://github.com/zhy65401/goodToNote)处理 Wallet 格式化金额的设计思路，并未复制其源码。

Apple 官方：[交易触发器](https://support.apple.com/guide/shortcuts/apd65c67538a/ios)、[创建个人自动化](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios)。

## 重新生成签名文件

本目录 `.wflow` 是可审阅的 XML 源文件，分发 `.shortcut` 由 macOS 自带命令签名：

```sh
./script/prepare_shortcuts.sh
```

签名需要系统快捷指令服务可用。官方资料由 `CatalogRepository` 只读更新，不再提供 Agent 导入动作。
