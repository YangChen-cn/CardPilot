<div align="center">

<img src="docs/assets/app-icon.png" width="104" alt="CardPilot app icon">

# CardPilot

**集中查看银行卡权益，轻松记录日常消费。**

面向香港银行卡用户的原生 Apple App，重点适配 iPhone 与 macOS。无需 CardPilot 账号，离线可用，个人资料与公开银行卡资料分开保存。

[![Platform](https://img.shields.io/badge/platform-iPhone%20%7C%20macOS-111827?style=flat-square)](#系统要求)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](#技术栈与架构)
[![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat-square)](#技术栈与架构)
[![Storage](https://img.shields.io/badge/Storage-SwiftData-34C759?style=flat-square)](#技术栈与架构)
[![License](https://img.shields.io/badge/license-MIT-2EA44F?style=flat-square)](LICENSE)

[下载](#下载安装) · [功能](#功能) · [资料库](#银行卡资料库) · [界面](#界面) · [开发](#从源码运行) · [参与贡献](CONTRIBUTING.md)

</div>

![CardPilot macOS 卡片页](docs/assets/screenshot-macos-cards.jpg)

## 下载安装

**当前 iOS 预发布：0.2.0 RC（2026-10-29，Build 1）**

[下载 IPA](https://github.com/YangChen-cn/CardPilot/releases/download/v0.2.0rc/CardPilot-0.2.0rc.ipa) · [发布说明与 SHA-256 校验文件](https://github.com/YangChen-cn/CardPilot/releases/tag/v0.2.0rc) · [全部版本](https://github.com/YangChen-cn/CardPilot/releases)

IPA 使用维护者的 `CardPilot` 自签名证书，并非 App Store 或 TestFlight 安装包。请通过 Sideloadly、AltStore 或 Xcode，使用自己的证书与描述文件重签安装。最低要求 iOS 26.0。

macOS 可[从源码运行](#从源码运行)；本次 0.2.0 RC 发布提供 iOS IPA，没有附带新版 macOS 安装包。

## 功能

CardPilot 以**银行卡权益管理与轻量消费统计**为核心，帮助你了解每张卡的用途和限制，不模拟银行后台结算。

| 功能 | 当前支持 |
| --- | --- |
| **卡包** | 从资料库选卡，或手动添加并使用自定义卡面。iPhone 提供叠放、卡面展示、紧凑列表三种样式；默认叠放，保留已有显示偏好。macOS 使用侧栏与多列布局。 |
| **权益查询** | 按日常、限时、指定商户和迎新浏览，查看条件、门槛、上限、登记要求、截止日期与官方条款；支持收藏常看权益。 |
| **整卡用法推荐** | 每张卡一份整体策略：主要用在哪里、怎么付款、关键回赠上限、何时考虑换卡。总览和叠放卡包可直接打开完整指南。 |
| **迎新记录** | 自行记录申请日、发卡日、个人截止日、奖励和备注，手动更新为未确认、进行中、已达标、已到账或已结束；为已追踪且截止日明确的迎新设置到期提醒。 |
| **轻量账本** | 手动记账、CSV 导入、短信粘贴识别、银行邮件导入，以及 Apple Pay / Shortcuts 记录。提供基础去重，疑似重复或卡片匹配失败时交由用户核对。 |
| **消费统计** | 账本默认查看本月，可切换月份、筛选卡片与类别、搜索历史；总览显示各卡消费、分类分布、近六个月趋势和最近交易。每张卡也有独立消费账本。 |
| **这一笔刷哪张** | 根据类别、地区、可选金额、支付方式和商户比较可能适用的公开权益，保留待确认条件，不提供精确到账预测。 |
| **个人资料与同步** | 记录尾号、账单日、还款日、额度及手动账单/还款；用自己选择的 iCloud Drive 或共享文件夹同步手机与 Mac，无需 CardPilot 服务器。 |

迎新达标和奖励到账由用户确认，不按逐笔交易自动判断银行资格。外币消费可以只保留原币；跨币种港币合计只包含有可信换算资料的记录。

### 邮件与快捷指令记账

- **银行邮件**：可自行部署 Google Apps Script，每日采集 Gmail 中受支持的 HSBC、BOCHK、BEA 交易提醒。App 打开或回到前台、联网后再获取并导入，不会在 App 关闭时直接写入本机账本。详见[部署与连接说明](docs/bank-email-cloud.md)。
- **Apple Pay / Shortcuts**：需要自行配置快捷指令或自动化，并传入交易资料；不是直接读取 Wallet 的全部历史记录。
- **短信**：复制交易提醒后粘贴识别，不要求 App 读取系统短信库。

这些方式保留已知交易事实；支付渠道、地区或汇率缺失时保持未知，不为推算回赠强迫用户逐笔补齐。

## 银行卡资料库

资料来自独立的 [CardPilot-Catalog](https://github.com/YangChen-cn/CardPilot-Catalog)，银行、产品、活动、卡面、Logo 和整卡用法均通过只读快照维护。

**0.2.0 RC 内置快照：`2026102904`，8 家银行、24 款产品、24 份整卡指南。**

| 银行 | 已收录产品 |
| --- | --- |
| **HSBC 汇丰** | 学生汇财金卡、Pulse 银联双币钻石卡、蓝狮子 Mastercard 扣账卡 |
| **BOCHK 中银香港** | Chill 白金卡、GO 银联钻石卡、GO 银联白金卡、大湾区青年卡、万事达扣账卡、SOGO 崇光 Visa 白金卡、SOGO 崇光 Visa Signature |
| **BEA 东亚** | HKU 学生 Visa、UDC 双币钻石卡、UDC 双币钻石学生卡 |
| **CNCBI 信银国际** | GBA 双币卡、多币扣账卡 |
| **BOCOM 交通银行（香港）** | Go-Goal Visa 白金卡、大湾区银联双币钻石卡 |
| **Mox** | Mox Credit |
| **ICBC Asia 工银亚洲** | 宇宙星座银联钻石卡、宇宙星座 Visa Signature、粤港澳湾区银联钻石卡 |
| **CCB Asia 建行亚洲** | eye Visa Signature（eye+）、TRAVO World Mastercard、银联双币卡 |

App 在启动、回到前台或手动检查时获取更新，正常检查间隔为 6 小时；失败后可重试。网络不可用时使用最后有效缓存或内置资料。卡面按 SHA-256 独立下载和缓存，单张图片失败不影响权益查询。

资料更新只替换公开内容，不覆盖个人尾号、名称、卡面、迎新状态、备注或账本。已有字段内的资料更新通常不需要重新发布 App；新增协议字段仍需客户端支持。

整卡指南是基于公开权益整理的使用建议，每卡仅一份，不按促销逐条生成，也不读取账本计算个人剩余额度。活动条件、期限和来源仍可在权益详情中查看。资料维护见[银行卡开发手册](docs/bank-library-development.md)、[指南填写说明](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/usage-guide.md)和[Catalog PR 注意事项](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/pr-submission.md)。

## 隐私与数据

- **没有 CardPilot 用户数据库**：个人卡片、消费和记录先保存在本机 SwiftData。
- **同步由你选择**：启用文件夹同步后，个人资料会写入你授权的私人云盘或共享文件夹，传输由对应云盘服务完成。
- **公开资料与个人数据分离**：Catalog 不接收个人尾号、交易、邮箱连接或备注。
- **邮件采集可选**：脚本在你自己的 Google 账户中运行，筛选后的提醒保存在自己的私人 Drive；连接密钥保存在各设备钥匙串，不随账本文件夹同步。
- **没有广告或分析 SDK**：不需要为本地权益查询和记账注册账号。

发现安全问题请按 [SECURITY.md](SECURITY.md) 报告，不要公开敏感资料。

## 界面

以下截图来自较早版本，部分入口和布局与 0.2.0 RC 不同。

### macOS

<p align="center">
  <img src="docs/assets/screenshot-macos-overview.jpg" alt="CardPilot macOS 总览" width="49%">
  <img src="docs/assets/screenshot-macos-cards.jpg" alt="CardPilot macOS 卡片页" width="49%">
</p>

### iPhone

<p align="center">
  <img src="docs/assets/screenshot-ios-cards.jpg" alt="CardPilot iPhone 卡包" width="30%">
  <img src="docs/assets/screenshot-ios-card-detail.jpg" alt="CardPilot iPhone 卡片详情" width="30%">
  <img src="docs/assets/screenshot-ios-benefit.jpg" alt="CardPilot iPhone 权益详情" width="30%">
</p>

## 系统要求

- iPhone：iOS 26.0 或更新版本。
- Mac：macOS 26.0 或更新版本。
- 源码开发：当前使用 Xcode 27、Swift 6 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

## 从源码运行

```sh
git clone https://github.com/YangChen-cn/CardPilot.git
cd CardPilot
xcodegen generate
open CardPilot.xcodeproj
```

选择 `CardPilotMac` 或 `CardPilotIOS` scheme。修改 `project.yml` 或增删源文件后，重新运行 `xcodegen generate`。

### 签名与 macOS 运行

仓库默认使用维护者本机的稳定代码签名证书 `CardPilot`。其他开发者应在 Xcode 项目中配置自己的签名身份；iOS 真机另选自己的 Team 与描述文件。macOS App 与独立邮件钥匙串组件需要使用同一稳定证书，避免反复更换签名造成授权问题，详见[钥匙串说明](docs/bank-email-cloud.md#macos-钥匙串授权)。

已具备本机 `CardPilot` 证书时：

```sh
./script/build_and_run.sh --verify
```

该命令停止旧开发版、增量构建并打开 macOS App。只构建、不打开界面时：

```sh
xcodebuild \
  -project CardPilot.xcodeproj \
  -scheme CardPilotMac \
  -destination 'platform=macOS' \
  -derivedDataPath build/PublicDerivedData \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=CardPilot \
  build
```

使用自己的证书时，替换构建设置中的 `CardPilot`；不要在正在运行的 App bundle 上覆盖构建或重签名。

### iOS 编译与模拟器

仅编译，不安装或启动模拟器：

```sh
xcodebuild \
  -project CardPilot.xcodeproj \
  -scheme CardPilotIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/iOSDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

需要手动查看界面时，再使用本机已有的模拟器名称或 UUID：

```sh
./script/run_ios.sh 'iPhone 17'
```

此脚本会构建、安装并打开指定模拟器版本；普通文档或小修不需要启动模拟器。

### 测试

按改动范围选择直接相关的测试，例如资料库与指南：

```sh
./script/test.sh -quiet \
  -only-testing:CardPilotTests/BankLibraryTests \
  -only-testing:CardPilotTests/CardUsageGuideTests
```

大范围公共服务、存储迁移或同步协议变更再运行完整套件：

```sh
./script/test.sh -quiet
```

脚本使用固定 `CardPilot` 证书和独立 `build/TestDerivedData`；其他开发者可在 Xcode 中配置自己的签名身份后运行 `CardPilotTests`。不要让测试覆盖用户正在使用的 App。编译和测试通过不等于实际界面或真机同步已经验收。

### 发布打包

使用独立的 Release DerivedData，不停止或覆盖正在运行的开发版：

```sh
./script/package_release.sh ios --version 0.2.0rc --build 1
```

iOS 默认生成未签名 IPA；使用维护者现有自签名证书的方式为：

```sh
IOS_SIGN_IDENTITY=CardPilot ./script/package_release.sh ios --version 0.2.0rc --build 1
```

输出位于 `build/releases/<version>/`，包含 IPA、`.sha256` 和 `INSTALL.txt`。参数 `mac` 生成签名 DMG，`all` 构建两个平台；也可省略版本参数，使用 `project.yml` 当前值。iOS 包仍需有效证书和描述文件重签后侧载，不是 App Store / TestFlight 分发。

## 技术栈与架构

- **SwiftUI + Observation**：共享数据与业务，分别适配 iPhone 和 macOS 布局。
- **SwiftData V3**：本地卡片、消费和个人记录，保留旧数据读取路径。
- **只读 Catalog V2**：银行、产品、活动和用卡指南独立于个人数据；快照原子缓存，卡面按哈希缓存。
- **文件夹同步格式 2**：通过 `NSFileCoordinator` 和每设备独立快照合并个人数据，支持用户授权的 iCloud Drive 或共享文件夹。
- **轻量业务边界**：活动展示不依赖完整交易历史；迎新手动记录；选卡建议按已知条件比较，不维护精确返现回放。

```text
App/
  Features/      卡包、总览、权益、账本、推荐、设置
  Models/        SwiftData 模型
  Services/      资料库、权益投影、同步、账户、邮件导入
  Resources/     内置 Catalog、图标、快捷指令
Support/         独立 macOS 邮件钥匙串组件
Tests/           Swift Testing 单元与回归测试
docs/            架构、资料库、同步、邮件及技术说明
cloud/           可选的 Google Apps Script 邮件采集端
script/          构建、测试、打包和资料维护脚本
```

## 文档

- [权益优先架构](docs/product-architecture.md)
- [银行卡资料库维护](docs/bank-library-development.md)
- [整卡指南填写规范](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/usage-guide.md)
- [Catalog 提交规范](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/pr-submission.md)
- [文件夹同步](docs/folder-sync.md)
- [银行邮件记账](docs/bank-email-cloud.md)
- [消费与账户](docs/transactions-and-accounts.md)
- [轻量体验改进记录](docs/experience-polish.md)

## 参与贡献

欢迎提交 issue、资料修正和 Pull Request。开始前请读 [CONTRIBUTING.md](CONTRIBUTING.md)。银行资料在独立的 [CardPilot-Catalog](https://github.com/YangChen-cn/CardPilot-Catalog) 维护，App 只同步经验证的内置快照。

- 不提交真实卡号、尾号、交易、邮件、连接密钥、证书或个人信息。
- 资料修正保留稳定 ID，并附官方条款、真实核实日期和素材来源；用卡指南每卡只写一份整体策略。
- UI 由用户验收；已有截图或录屏可随 PR 提供，不为文档修改或小修反复启动模拟器。
- 按变更范围报告实际检查结果，区分资料校验、单元测试、编译、启动和手工验收。

## 许可证

本项目以 [MIT License](LICENSE) 开源。CardPilot 与各银行无隶属关系；银行名称、商标、卡面和产品资料归各自权利人所有。

优惠、费用和合资格条件以银行最新条款为准。
