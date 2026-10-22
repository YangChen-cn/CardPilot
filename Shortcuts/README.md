# CardPilot 快捷指令

已签名文件位于 `App/Resources/Shortcuts/`，也随 iOS/macOS App 打包，在「设置 → 快捷记账」中分享。将文件传到手机后打开，按系统提示添加；项目不会替用户静默安装工作流。

| 文件 | 实际动作 |
|---|---|
| CardPilot 记一笔.shortcut | 打开 `cardpilot://record`，显示记账表单 |

它们是可导入的快捷入口，不包含已绑定付款卡片的 Apple Pay 自动化。只用系统 URL 动作，避免工作流依赖侧载时可能改变的签名团队。

## Apple Pay 自动记账

在手机的快捷指令 App 创建「交易」自动化，选择 Wallet 付款卡片，添加 CardPilot 的「记录银行卡消费」动作，在动作内选择银行卡。将商户、金额、原始交易时间绑定到系统提供的交易内容，支付方式选Apple Pay；有原始交易标识时一并绑定。银行卡实体使用稳定ID，改名仍能接收；旧版精确名称工作流继续兼容。选择HKD/CNY/USD，外币必须提供折算汇率。

付款卡片和自动运行权限必须在手机选择。CardPilot不读取Wallet全量历史。原生记账动作现在不强制打开界面；需用实际付款验证系统字段、锁屏及后台执行权限，不能以模拟器编译代替真机验收。签名快捷文件是手动记账入口；官方资料不再通过快捷指令导入。疑似重复交易可在「设置 → 交易核对」确认。

Apple 官方：[交易触发器](https://support.apple.com/guide/shortcuts/apd65c67538a/ios)、[创建个人自动化](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios)、[共享快捷指令文件](https://support.apple.com/guide/shortcuts-mac/apdf01f8c054/mac)。

## 重新生成签名文件

本目录 `.wflow` 是可审阅的 XML 源文件，分发 `.shortcut` 由 macOS 自带命令签名：

```sh
./script/prepare_shortcuts.sh
```

签名需要系统快捷指令服务可用。官方资料由 `CatalogRepository` 只读更新，不再提供 Agent 导入动作。
