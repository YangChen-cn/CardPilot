# 参与贡献

感谢你愿意改进 CardPilot。这个项目以本地优先、资料可核实和尊重个人数据为边界。

## 开始之前

1. 先搜索已有 issue，避免重复。
2. 较大的功能或数据结构改动，请先开 issue 说明目标、取舍和兼容方案。
3. 不要为了演示或测试重置、覆盖真实账本、同步目录和钥匙串。

## 开发环境

```sh
git clone https://github.com/YangChen-cn/CardPilot.git
cd CardPilot
xcodegen generate
open CardPilot.xcodeproj
```

当前开发使用 Xcode 27、Swift 6；App 最低 macOS / iOS 26.0。修改 `project.yml` 或增删源文件后需要重新运行 `xcodegen generate`。

仓库默认使用维护者的本机签名证书 `CardPilot`，因为可选的 macOS 邮件钥匙串组件依赖稳定签名。普通贡献者不需要该证书：在 Xcode 中选择自己的 Team，或在命令行覆盖 `CODE_SIGN_IDENTITY`。完整说明见 README 的“开始使用”。

## 提交规范

- 一个提交只做一件事，提交信息用祈使句说明结果。
- 不提交 `build/`、DerivedData、日志、密钥、证书、真实卡号/尾号、真实交易、邮件正文、连接密钥或个人信息。
- 不提交 `*.store`、`*.store-wal`、`*.store-shm` 等本地数据库文件。
- 资料库改动必须保留稳定 ID，不因为整理文案随意改 ID。
- 卡面、图标和条款截图请确认来源允许使用，并在对应研究文档中记录来源。

## 测试

```sh
./script/test.sh -quiet
```

测试使用独立的 `build/TestDerivedData`，不会覆盖正在运行的 App。若本机没有测试脚本要求的证书：

- 在 Xcode 中运行 `CardPilotTests`；或
- 通过项目的构建设置使用自己的签名身份。

资料库改动至少运行 `BankLibraryTests`、`RemoteCatalogTests` 和直接相关的资料/定价测试。涉及同步、迁移或数据格式的改动，请运行完整测试套件并在 PR 中说明结果。

## 新增或修改银行资料

- 优先使用银行官方产品页、条款 PDF 或官方新闻稿。
- 明确区分官方产品、活动模板和个人持卡资料。
- 未核实的价格、日期、资格和上限保持未知，不用其他产品资料补齐。
- 卡面必须来自可核实来源；不要使用带个人信息的截图。
- 在独立 `CardPilot-Catalog` 仓库维护公开资料，按其文档校验后用 `script/import_catalog_snapshot.py` 同步 App 内置快照；复用银行、产品和活动稳定 ID，图片使用 `path` / `sha256` / `contentType` 描述。
- 用卡指南每卡只写一份整体策略，保留来源和关键限制；填写前阅读 Catalog 的 `docs/usage-guide.md`。
- 同步更新公开 schema 和 validator，并递增 `contentVersion`。

## Pull Request

请包含：

- 改动目的和用户可见变化；
- 测试命令与结果；
- UI 改动的说明，若已有手工验收截图或录屏可附上；文档修改不要求启动 App，小修不反复启动模拟器；
- 资料改动的官方来源和核实日期；
- 兼容性、迁移或个人数据影响说明。

## 行为准则

请保持专业、具体和善意。讨论技术问题，不攻击个人；不要公开他人的卡片、交易、邮箱或其他私人信息。

## 许可证

提交贡献即表示你同意以本项目的 [MIT License](LICENSE) 授权该贡献。
