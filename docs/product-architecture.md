# 权益优先架构

更新：2026-10-23。以本文件为当前开发约束，旧研究中的精确返现路线已停止。

CardPilot 是原生银行卡权益管理与轻量消费统计工具。权益展示优先，其次是优惠查询与提醒、消费统计、简单选卡建议。银行最终资格、MCC、推广登记、共享名额和结算金额不在本产品的自动判断范围。

## 当前数据与职责

| 数据 | 保存位置与用途 |
| --- | --- |
| 官方银行/产品 | Catalog Schema V2 的 `banks`/`products`，由公开 GitHub Pages 快照定义；稳定银行ID和产品ID，不再在 App 中硬编码银行白名单 |
| 官方卡面/Logo | `CatalogAsset { path, sha256, contentType }`；路径相对 Catalog 根，按 SHA-256 下载、校验和缓存；个人自定义卡面与官方资源分开存储 |
| 官方活动 | 公开 GitHub Pages 上的版本化 CatalogRule 快照；启动/回前台每6小时检查（失败后5分钟重试），校验后原子缓存为只读资料，不写入SwiftData |
| 当前活动解释 | OfferStore从只读资料投影活动，BenefitInfo合并个人overlay并解释活动文字、费率参考、限制、来源与日期；无需任何消费数据；旧RewardRule只作个人自建或历史迁移 |
| 用户持卡资料 | BankCard尾号、账单日、还款日、自定义名称/图片和归档；有`imageData`即个人/旧版图片，无图且有`catalogID`时使用当前官方卡面；官方更新不覆盖个人图片。该所有权由现有字段推导，不新增SwiftData字段；额度及手动账单、还款沿用现有领域文档 |
| 卡片类型与显示 | `BankCard.kind` 保留“信用卡/借记卡”存储值，界面将借记卡称“扣账卡”；卡片页偏好 `@AppStorage("cards.displayMode")` 选择一起显示或按类型分组，一起显示时可筛选；不新增SwiftData字段 |
| 个人迎新 | 新官方迎新使用welcomeTrackingOffer文档，key为welcomeTracking:offer:<cardKey>:<offerID>（官方卡cardKey为同步稳定的BankCard.overlayKey）；状态、申请/发卡日期、个人截止日、门槛参考、奖励内容、备注、到账日期；旧welcomeTracking:rule.syncKey只读迁移 |
| 个人活动状态 | offerState文档，key为offerState:<cardKey>:<offerID>；隐藏、收藏、登记、备注；官方卡cardKey跨设备稳定，旧UUID key只读迁移；当前每个官方产品单实例，未来多实例需加入同步实例标识 |
| 消费事实 | SpendTransaction及邮件/快捷指令/CSV来源证据；记录原币，不推断银行资格 |
| 消费统计 | DashboardSnapshot仅汇总卡片、类别、月度趋势与最近记录；无回赠、手续费或奖励回放 |
| 选卡建议 | RecommendationEngine按用户提供的条件排除明确不符项，先按公开权益力度、再按明确满足条件与待确认限制排序；未填写支付方式、商户、登记状态或有效期时标记“需补充信息”，不读取账本、不预测结算或精确收益 |

活动按资料显式给出的日常、限时、商户、迎新分组，不再由`capPeriod`推断。`isEnabled`旧值不再决定是否有权浏览权益；用户隐藏的官方活动写入个人overlay，个人活动仍可归档，历史迎新仍可查。不能精确计算的已有文字迎新也作为当前资料中的稳定描述条目展示，不制造数值门槛。来源不完整与活动日期未知会明确提示，不把资料核实日当作真实活动起点。

个人迎新状态为未确认、进行中、用户确认已达标、奖励已到账、已结束。状态可由用户更新；不读交易累计、不互斥、不根据模型猜测银行资格。到期提醒仅针对用户追踪且已确认截止日的进行中迎新。未知日期不排提醒，也不自动显示过期。

## 保留的轻量路径

```
内置资料 + 公开只读快照(缓存，单文件原子提交) → OfferStore投影 → BenefitInfo → 权益界面/简单选卡建议
                                               ↘ 个人offerState叠加（按卡片实例）
旧RewardRule（个人/历史） ─────────────────────┘
用户迎新记录 → 手动状态与个人日期 → 展示/本机到期提醒
邮件/短信/Shortcuts/手动/CSV → 身份去重与冲突核对 → 原币交易 → 消费统计
SwiftData + DomainRecord → 既有用户授权文件夹同步
```

邮件和手动记录缺少支付方式、渠道、地区或汇率时仍可保存，不出现返现资格核对。仅卡片无法唯一匹配、金额/币种错误、疑似重复、财务事实冲突要求处理。稳定来源ID是重试依据；同日同商户同金额仅作为疑似重复。原有邮件与Wallet核对投影继续保留用户分类、备注和明确填写的信息。

HKD合计仅统计可换算的记录；原币按币种分别显示。CSV缺少汇率不会默认1；Shortcuts汇率0表示未知。币种不证明消费地区。旧版本已经保存的汇率保留，不擅自猜测哪些旧汇率是用户输入；用户可编辑。

## 删除与兼容边界

已删除RewardEngine、RewardReplay、RewardCardSnapshot、RewardDocumentSnapshot、ActivityWorker/Request/Snapshot/Store、RuleTimeline、ResolvedRule及相关奖励/资格快照、逐笔条件确认页面、跨卡迎新选择授权、复杂推荐工作线程与多层包装。

RulePolicyStore仅保留当前活动手改保护、待采用官方更新、归档。它不再生成历史计算区间。PricingStore仅保留当前卡片覆盖资料读取，不再写定价历史。RulePolicyState/RuleRevision、PricingRevision、PersonalCardProfile/WelcomeAddonRecord和WelcomeReceipt是旧数据的被动解码/同步边界，没有旧引擎调用路径；不会因新配置删除用户旧档案或到账。

SwiftData schema仍为V3，卡片/交易/活动稳定同步key及文件格式2保持。新的welcomeTracking领域文档参与既有同步验证。旧客户端不认识新kind时会拒绝整份同步，手机和Mac必须一起升级；这不等于旧客户端兼容。不要删除旧schema或重建账本。

旧迎新记录首次读取时恢复申请/发卡/个人截止日期和到账；有新手动状态时优先使用新文档。没有旧个人截止日的文字迎新保持未知，用户可主动记录。

## 开发与验证

- 权益/资料维护不增加计算规则，不引入新后端或依赖；维护目前五家银行、十五个产品。
- 相关测试覆盖权益零交易展示、手动状态保存/旧到账恢复/双端同步、未知日期、原币导入和合计、去重与冲突、适用性建议。
- 本轮是广泛公共路径删除，执行完整剩余测试套件；后续小修仅跑直接受影响项。
- macOS单卡账本沿用独立CardLedgerSheet，避免此前导航目标/工具栏布局循环；iOS保留推入导航。不要因界面整理重建那条macOS调用链。
- UI 需在真实设备上人工检查；macOS 构建应使用稳定的签名身份，邮件钥匙串组件需要与 App 相同的证书。不要用测试数据覆盖真实账本和同步目录。
