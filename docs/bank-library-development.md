# 银行卡资料库与后续开发手册

更新：2026-10-27。开始前先读[权益优先架构](product-architecture.md)。CardPilot维护银行卡权益和轻量账本，不再追求银行奖励结算模拟。

## 当前范围与入口

银行卡 → 添加 → 银行 → 产品 → 官方卡面与权益预览 → 添加 → 个人尾号/账单日/额度。手动添加及自定义卡面继续保留。个人迎新在对应活动或迎新记录中编辑，不要求先选择“可计算方案”或确认银行资格。

当前展示 HSBC、BOCHK、BEA、CNCBI 信银国际、交通银行香港、Mox、工银亚洲和建行亚洲八家银行的二十四个产品，包含中银万事达扣账卡、CNCBI GBA 双币卡与 CNCBI 多币扣账卡：

| 银行 | 稳定产品ID | 产品 |
| --- | --- | --- |
| HSBC | hsbc.student.visa.gold | 学生汇财金卡 |
| HSBC | hsbc.mastercard.debit | 蓝狮子Mastercard扣账卡 |
| HSBC | hsbc.pulse.unionpay.diamond | Pulse银联双币钻石卡 |
| BOCHK | bochk.chill.platinum | Chill白金卡 |
| BOCHK | bochk.sogo.visa.platinum | SOGO 崇光 Visa 白金卡 |
| BOCHK | bochk.sogo.visa.signature | SOGO 崇光 Visa Signature |
| BOCHK | bochk.go.diamond | GO钻石卡 |
| BOCHK | bochk.go.platinum | GO白金卡 |
| BOCHK | bochk.gba.youth | 大湾区青年卡 |
| BOCHK | bochk.mastercard.debit | 中银万事达卡扣账卡 |
| BEA | bea.hku.student.visa | HKU学生Visa |
| BEA | bea.udc.diamond | UDC钻石普通版 |
| BEA | bea.udc.diamond.student | UDC钻石学生版 |
| CNCBI | cncbi.gba.dual | GBA双币卡 |
| CNCBI | cncbi.multi-currency.debit | 多币扣账卡（Mastercard） |
| BOCOM | bocom.go-goal.visa.platinum | Go-Goal Visa 白金信用卡 |
| BOCOM | bocom.gba.unionpay.diamond | 大湾区银联双币钻石信用卡 |
| Mox | mox.credit.mastercard | Mox Credit 信用卡 |
| ICBC Asia | icbcasia.horoscope.unionpay.diamond | 宇宙星座银联钻石 |
| ICBC Asia | icbcasia.horoscope.visa.signature | 宇宙星座 Visa Signature |
| ICBC Asia | icbcasia.gba.unionpay.diamond | 粤港澳湾区银联钻石 |
| CCB Asia | ccbasia.eye.visa.signature | eye Visa Signature（eye+） |
| CCB Asia | ccbasia.travo.world.mastercard | TRAVO World Mastercard |
| CCB Asia | ccbasia.unionpay.dual.currency | 银联双币卡 |

所有产品都由同一份 Catalog V2 快照定义；GO钻石/白金、UDC普通/学生、两张扣账卡均保持独立产品ID。活动改名不换ID；真正的新活动批次才创建新ID。

## 职责与数据分离

| 位置 | 职责 |
| --- | --- |
| Resources/Catalog/catalog.json、Resources/Catalog/images/ | 内置 Catalog V2 离线回退：8家银行、24个产品、Logo与卡面（Mox及建行三款为参考官方素材的AI横版示意，已明确标注）；所有图片有SHA-256；只读，不含个人字段 |
| 公开快照 | 公开仓库 YangChen-cn/CardPilot-Catalog 的 docs/catalog.json 与 docs/images/；banks/products/artwork 全部云端定义，不含个人数据或凭据 |
| CatalogRepository、RemoteCatalogCache | 获取、校验、ETag/Last-Modified、6小时检查、单文件原子快照和更新状态；304仅用有效快照，同版本正文变化拒绝；只读，不持有SwiftData上下文，不写个人账本 |
| CatalogAssetStore、CatalogAssetImage | 按SHA-256独立下载/校验/磁盘缓存卡面与Logo；3个并发上限、按sha去重、原子写入、内存解码有上限；离线用缓存或内置回退，单图失败只显示占位并可在下次检查重试 |
| BankLibrary、CardProduct | 解码 Catalog V2；银行与产品不再硬编码白名单，验证bankID引用、产品/活动/迎新和asset描述；生产环境优先最后有效缓存，测试跳过用户缓存；displayCatalog补充无ruleIDs的文字迎新 |
| LibraryOnboarding | 只为选中的产品创建个人BankCard实例；官方卡不复制imageData，只保存catalogID；个人状态使用卡片overlayKey隔离。来源通过catalog/custom个人投影显式保存，不新增SwiftData字段 |
| CardArtwork、LibraryArtworkUpdates | 以明确的 catalog/custom 来源选择卡面；官方卡按catalogID读取当前CatalogAsset，个人导入才写入custom；启动只保留持卡资源缓存引用，不再识别或迁移旧图片。来源与图片随卡片个人资料共同同步，不改 SwiftData Schema |
| OfferStore、BenefitInfo | 从当前只读资料投影官方活动并合并个人overlay；展示自然语言限制、来源、日期；旧RewardRule只作为个人自建或历史迁移来源 |
| OfferPanel、BenefitReaderView | 直接展示当前活动和自然语言限制、来源、日期；不读取交易历史 |
| OfferStateStore、OfferTrackingStore | 官方活动的隐藏/收藏/登记/备注与迎新状态；key使用跨设备稳定的卡片overlayKey+活动稳定ID；旧UUID与WelcomeTrackingStore只读迁移 |
| PersonalCardDraft | 仅个人持卡资料与额度；不再选择互斥主方案/附加奖励或改写旧迎新档案 |
| WelcomeTrackingStore | 旧迎新记录与个人自建活动兼容；新官方迎新使用OfferTrackingStore，不重写旧档案 |
| RulePolicyStore | 个人自建规则的手改保护与归档；旧官方规则只读历史，不再写回或作为当前活动来源 |
| DocumentValidator、SyncStore | 新旧领域文档验证及用户文件夹同步；已知kind含offerState和welcomeTrackingOffer |

官方产品、活动模板、用户持卡、个人迎新和消费必须分别维护。RewardRule旧模型名和旧字段保留以兼容SwiftData V3，不代表恢复计算职责。旧PersonalCardProfile/WelcomeAddonRecord/WelcomeReceipt、RuleRevision和PricingRevision仅保存可读历史；新界面不生成奖励历史或跨卡互斥逻辑。

## 云端只读资料与个人状态

- 官方资料的主数据源是公开GitHub Pages上的 Catalog Schema V2 JSON；银行、产品、Logo和卡面都由快照定义，不再通过“导入卡片与优惠”或启动刷新写入SwiftData。`CatalogRepository`只做文档下载、校验、缓存、版本比较和状态发布；`BankLibrary`把最后有效缓存或内置Catalog解码成当前只读产品目录。新增银行或产品不需要更新App。
- 更新检查发生在启动、回到前台且距上次检查超过6小时（失败后5分钟重试）、以及设置页“立即检查更新”。请求携带ETag/Last-Modified；304只记录检查时间。文档先校验schema、数量、银行/产品引用、asset路径/hash、来源、日期、分组、迎新计划和私有字段，全部通过后才原子替换缓存；失败保留最后有效缓存，首次使用内置Catalog。
- 发布契约：活动支付方式只使用canonical标签（`UnionPay`、`Apple Pay`、`支付宝`等）。客户端把`UnionPay App`、`云闪付`、`雲閃付`等输入统一映射为`UnionPay`；公开快照必须写`UnionPay`。`scripts/validate_catalog.py`会校验单个活动和`calculation.paymentMethods`/`excludedPaymentMethods`，CI在合并前拒绝未知或旧标签。活动本身遇到未知支付方式时保留为文本，不再因一项活动让整份 Catalog 失效；结构、日期、URL或图片错误仍会使本次更新保留上一份有效缓存。
- 文档与图片下载解耦。`CatalogAssetStore`按artifact的SHA-256查找磁盘缓存、内置回退和网络；下载采用有上限的流式读取，拒绝超大响应、非图片内容和跳出Catalog路径的同源重定向。图片校验失败不会让Catalog更新失败，也不会让产品消失。加载期间或失败时UI显示占位图；手动检查或下次联网会重试。缓存按当前/下架Catalog和持卡引用保留资源，超出容量预算时按最近访问时间回收无引用文件，不删除当前Catalog或持卡卡面仍引用的资源。
- `logo` / `artwork` 可省略或为 `null`，分别使用银行图标或程序卡面占位，不妨碍添加与查看权益；非空对象仍须完整通过路径、类型和哈希验证。远程缺图不会删除个人自定义卡面；官方来源产品在当前快照缺图时显示占位，不伪造旧图片引用。
- 官方活动使用显式`group`（daily/limited/merchant/welcome），日期可为空；`verifiedOn`只是资料核实日期，`updatedAt`是内容更新时间，不能拿来补活动开始、结束或个人截止日。迎新申请期和个人消费期分开。
- 个人状态不以产品ID或活动名称模糊匹配。`BenefitInfo.cardKey` 对官方卡使用同步稳定的 `BankCard.overlayKey`（即由catalogID派生的`card.syncKey`），官方offer key是`offer:<cardKey>:<offerID>`；隐藏/收藏/登记/备注文档key是`offerState:<cardKey>:<offerID>`，迎新新key是`welcomeTracking:offer:<cardKey>:<offerID>`。旧`BankCard.id` UUID键在启动时只读复制到新key并保留旧记录。当前每个官方产品只保留一个持卡实例；未来支持同产品多实例时，需在overlayKey中加入同步实例标识，避免不同实例共享状态。
- 旧官方RewardRule不删除、不改写：新安装不再复制官方规则；既有卡上的旧规则作为历史活动显示，旧迎新档案只读迁移到新key。旧个人自建规则（externalID为空）继续保留为个人活动。
- 活动延期使用同一ID；下架只让当前资料不再投影该活动，不删除个人历史；新批次必须使用新ID；不得按名称模糊匹配或把不同等级/用户版本合并。
- 远程快照只更新只读内容。个人持卡、尾号、账单/还款日、隐藏/收藏、登记、个人日期、门槛/奖励备注、到账、交易、手改名称/卡面和归档永不被远程覆盖，也不上传。

## 后续新增或更新资料

提交前先读 [Catalog PR 提交注意事项](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/pr-submission.md)。字段以实际客户端类型为准；`merchantKeywords` 是逗号分隔字符串，不能写数组。目录校验不能替代客户端解码验证。本轮素材出处与生图提示词见 [2026-10-27 素材记录](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/artwork-2026-10-27.md)。

1. 用户授权扩大范围后再加银行/卡片。本轮只维护上表。先搜索ID和名称，防止重复或把不同等级/用户版本合并。
2. 从官方产品页及条款核实名称、卡组织、权益、门槛、限制、登记、上限和日期。不能确认的条件直接标待核实；无须为了展示一项权益建立可执行交易匹配模型。保留来源和真实核实日期。
3. 复杂权益优先写清自然语言notes/details。不能准确表达的奖励保留描述，不随意合并不同币种目标、虚构现金等值或复制宣传“最高”比例作为普遍回赠。不要写“引擎未建模”“关闭资格开关”等工程说明。
4. 新公开快照使用Catalog V2：顶层`schemaVersion: 2`、`contentVersion`、`publishedAt`、`banks`、`products`；活动写显式`group`，`startsOn`/`endsOn`可缺省并以null表示未知。`contentVersion`必须大于线上版本；`verifiedOn`、`updatedAt`不能补活动日期。活动官方期与个人消费截止日不可互相代替。
5. 官方公开卡面优先。图片先用`script/catalog_asset.py`去除EXIF/重编码，限制2400px、4MB，并把输出的`path`/`sha256`/`contentType`写入对应asset；公开仓库`CardPilot-Catalog`是唯一维护源：在其`docs/catalog.json`中更新资料，用`scripts/catalog_asset.py`处理图片并校验hash；App侧用`script/import_catalog_snapshot.py`把已验证快照复制到`App/Resources/Catalog/`，而不是反向生成云端资料。图片下载与规则出处写进对应银行研究文档；无法下载时不得用生成图冒充官方卡面。
6. 新卡安装只创建个人BankCard；官方权益由OfferStore从当前只读资料实时投影，不再复制为RewardRule。无ruleIDs的welcomePlans由displayCatalog生成externalID=plan.id的描述条目。新迎新仅未确认，不因旧calculable/isEnabled字段推断用户申请或达标；老已开启状态与到账读取保留。
7. 远程官方更新只替换只读缓存，不覆盖尾号、账单/还款日、个人状态/截止日、隐藏/收藏、归档、手工名称/卡面、交易。旧官方规则不删除；活动从新快照消失时只停止当前投影。个人自建活动永不被官方资料覆盖。
8. 新增/修改银行时只改Catalog，不改BankLibrary白名单；产品数量上限为1000、银行200。新增图片后运行公开仓库`python3 scripts/validate_catalog.py docs/catalog.json --base <上一版>`，再提交公开仓库并等待GitHub Pages。App不随资料更新发版。
9. 增删源文件后xcodegen generate。产品资料改动跑资料库及直接受影响测试；公共存储/同步大改才全量。UI由用户验收，交付前主动构建并打开macOS。

welcomePlans.kind、exclusionGroup、calculable及旧主/附方案字段仅为旧资料描述/兼容。不要再据此限制用户或要求建立多币种奖励引擎。普通/学生UDC现可展示原有完整迎新说明、让用户记录状态，无须自动计算资格。

## 个人状态与同步

- 新官方迎新使用`welcomeTracking:offer:<cardKey>:<offerID>`保存状态、申请/发卡日期、个人截止日、奖励文字、备注及到账；旧`welcomeTracking:offer:<BankCard.id>:<offerID>`和`welcomeTracking:+rule.syncKey`仅作历史或个人自建活动，首次读取时只读迁移。日期可以不录；`deadlineConfirmed=false`时不倒计时、不排到期提醒。
- 旧主方案/附加奖励的个人日期和到账首次读取会恢复，新手动记录优先。修改持卡资料不改旧profile或receipt。
- 稳定同步key沿用card:catalog:<产品ID>及原活动key。文件夹选择保持外层创建CardPilot文件夹、内层直接复用，不重复嵌套。
- schema仍V3、同步格式2。`offerState`、`welcomeTrackingOffer`是新增kind，DocumentValidator按kind校验；手机和Mac均须更新，旧客户端可能拒绝不认识的文档。
- macOS 的稳定签名与独立钥匙串组件见[银行邮件记账](bank-email-cloud.md)。开源构建使用自己的签名身份；默认的 CardPilot 证书仅用于维护者本机。个人额度填 0 仍只清除当前卡配置，保留共享组其他成员、账单和还款。

来源研究：[BOCHK/BEA](bochk-bea-library-research.md)、[HSBC](hsbc-library-research.md)、[CNCBI 信银国际](cncbi-library-research.md)。这些是事实来源记录，不构成银行实时服务。公开快照可按上述流程发布，但更新只替换只读缓存，不替代银行官方核实。

SOGO 两等级权益、迎新及AI横版示意及官方参考来源：[核实记录](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/bochk-sogo-research.md)。
