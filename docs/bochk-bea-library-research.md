# BOCHK / BEA 卡片库资料核对

核对日期：2026-10-22。仅使用银行官方产品页、产品资料概要及条款PDF。这里的资料用于用户明确选择后建立卡片，不会自动新增持卡或覆盖手动设置。`verified`表示官方已核实，`calculable`表示目前引擎能够表达，两者分开。

## 产品与迎新

| 产品ID | 日常回赠 | 本轮迎新资料 | 采用的官方依据 |
|---|---|---|---|
| `bochk.chill.platinum` | 基础0.4%积分等值；网上或海外外币4%；月实体消费HK$1,000后指定商户8%，额外回赠共用月HK$150上限 | 新客消费HK$3,000得HK$300；个人期为发卡当月及后2个历月；申请截止2026-12-31 | [白金/World对照产品页](https://www.bochk.com/dam/boccreditcard/chillcard/chi/index617.html)、[回赠条款](https://www.bochk.com/dam/boccreditcard/chillcard/chill_offer_tnc_tc.pdf)、[迎新条款](https://www.bochk.com/dam/boccreditcard/chillcard/chill_wg_tc.pdf) |
| `bochk.go.diamond` | 基础0.4%；手机3倍积分等值1.2%，包括基础共月HK$100上限，2026-07-01～12-31 | 手机10%整期封顶HK$800；同批中银多卡只能一项迎新 | [产品页](https://www.bochk.com/dam/boccreditcard/gocard/chi/index.html)、[日常条款33–38](https://www.bochk.com/dam/boccreditcard/gocard/gocardoffer_TC.pdf)、[迎新第2页](https://www.bochk.com/dam/boccreditcard/gocard/Go_WG_TC.pdf) |
| `bochk.go.platinum` | 基础0.4%；手机2倍积分等值0.8%，包括基础共月HK$100上限；不套用钻石倍率 | 上述迎新明确同时适用于白金；独立方案/规则ID，资格仍须确认 | [同一日常条款的白金分栏](https://www.bochk.com/dam/boccreditcard/gocard/gocardoffer_TC.pdf)、[迎新22条](https://www.bochk.com/dam/boccreditcard/gocard/Go_WG_TC.pdf) |
| `bochk.gba.youth` | 基础0.4%；港澳内地实体零售额外5%，月HK$100，网上除外 | 手机10%整期HK$300，用满目标HK$3,000；发卡当月及后2个历月；申请截止2026-12-31 | [产品页](https://www.bochk.com/tc/creditcard/details/cobrand/cobrand/gbayouth.html)、[活动条款](https://www.bochk.com/dam/boccreditcard/cbc_pdf/gba_product_tnc_tc.pdf)、[迎新条款](https://www.bochk.com/dam/boccreditcard/cbc_pdf/gba_welcome_tnc.pdf) |
| `bochk.mastercard.debit` | 扣账卡；基础0.5%无上限，私人财富客户额外0.5%最高1%；12种主要货币外币交易费豁免 | 不适用（扣账卡无迎新） | [中银扣账卡产品页](https://www.bochk.com/dam/more/bocdebitcard/card/tc.html)；细则及私人财富资格以银行最新条款为准 |
| `bea.hku.student.visa` | 已核对学生Visa卡种与永久免年费；未找到足以确定其基础现金等值的专属条款，`baseRewardVerified:false` | 网上/指定手机链接申请，新客发卡日起2个月HK$2,000得HK$200；申请期2026-07-01～2027-01-13 | [HKU学生产品页](https://www.hkbea.com/html/en/bea-hku-student-credit-card.html)内WelcomeGift图像map直接链接[现行学生迎新PDF](https://www.hkbea.com/pdf/en/credit-card/Student_card/bea-student-card-tnc.pdf)，未套用GOAL或i-Titanium回赠 |
| `bea.udc.diamond` | 与学生版共用钻石签账规则：基础0.4%，本地餐饮1.2%、其他本地0.8%、CNY4.8%、非CNY外币4%；额外奖赏月100,000积分（约HK$400） | 新客：发卡3个月HK$4,000得HK$400，另CNY4,000得CNY400；双分项已核实但暂不自动计算。指定现有客：发卡2个月HK$2,000得HK$300，单独方案 | [综合奖赏条款第9页](https://www.hkbea.com/pdf/en/credit-card/master-reward-tnc_en.pdf)、[新客迎新](https://www.hkbea.com/pdf/en/credit-card/upd_tnc_en.pdf)、[2026-09指定现有客条款](https://www.hkbea.com/pdf/en/credit-card/2ndcard300.pdf) |
| `bea.udc.diamond.student` | 复用普通版日常签账规则，独立产品与独立迎新；官方学生页列永久免年费 | 新客：发卡3个月HK$1,000得HK$100，另CNY1,000得CNY100；不能套用普通版金额 | [学生版产品页](https://www.hkbea.com/html/en/bea-credit-card-welcome-offer-diamond-student-card.html)、[学生版迎新PDF](https://www.hkbea.com/pdf/en/credit-card/updst_tnc_en.pdf) |

## 日期、客群及不能自动计算的条件

- 中银新客通常须确认过去12个月指定主卡持有/取消情况，BEA方案须按各自6个月资格条款确认；不能仅以“新添加卡片”视为银行新客。金额目标不能代替激活、申请渠道、身份及其他资格确认。
- GO加码为把同一10%迎新上限由HK$300提升至HK$800，不能再叠加固定HK$500。GBA/GO的消费目标用于用满百分比回赠，并非必须先花到目标才开始有回赠。
- GO迎新条款限制同批申请多张中银信用卡只获一项迎新；BEA UDC迎新条款的 Welcome Offer 第3条限制每名合资格客户领取一次，并排除未注明可同享的其他推广。当前主方案分别使用 `bochk.primary-welcome.2026`、`bea.primary-welcome.2026` 资格组，避免同一期跨产品重复估算；新一期必须按实际条款重新设组，不将银行 ID 当永久排他锁。过去持卡及销卡资格仍须由用户核对，App 不连接银行查询。
- Chill及GBA日常活动只写“即日起”，并未找到官方具体起日；沿用旧资料2026-10-21作为保守启用日期，不能宣称这是银行公布起日。迎新申请期与个人消费期分别存储；中银个人期按历月，BEA按发卡日起月份，不硬套90天。
- UDC普通/学生两项新客迎新分别奖励HKD及CNY，现有固定奖金模型只有HKD，故标`verified:true, calculable:false`，保留完整两个门槛，不虚构HK$800或HK$200合并奖励。
- BEA学生UDC产品页仍写旧2个月及2025年活动，而其链接的现行迎新PDF明确2026-04-01～2027-01-13及3个月；采用带日期PDF。普通UDC旧客产品页写3个月，2026-09更新的专属PDF为2个月；同样采用专属PDF并提醒申领前确认。
- 已重新读取[Chill当前官方商户名单图](https://www.bochk.com/dam/boccreditcard/chillcard/chilll_merchant_banner_tc.jpg)，其标注2026-05-01起，现有关键词名单仍对应；名单图头部10%及HK$1,500为World宣传，白金仍按专属8%及HK$1,000条款。全港戏院需MCC，未凭类别一律当作指定商户。
- GO登记后高达20倍/10倍积分、Go商户5%、外币交易费回赠等推广本轮未完整表达登记/名单/互斥条件，不自动启用。[登记推广页](https://www.bochk.com/tc/creditcard/promotions/offers/gompq126.html)
- MCC、分期、钱包、充值、保费、循环交易、英国/欧洲经济区实体交易等排除不能完全由简化类别识别，仍需用户按银行规定设置交易资格；外币迎新门槛可能包含银行手续费，估算不保证等同入账。

## 手续费与年费

[中银2026-08-17产品资料概要](https://www.bochk.com/creditcard/bocci/agt/key_facts_statement_chi.pdf)列Visa/Mastercard外币费1.95%、银联双币非港币费1%但中国内地人民币交易除外；银联双币境外港币结算不另加1%，故修正Go及GBA旧资料的`overseasHKDFeePercent`为0。Go/GBA配置`cnyFeeBps:0, cnyFeeRegions:["CN"]`，只有明确内地人民币交易享豁免；其他或未知地区按普通外币费率估算，不能仅凭CNY推定免收。

[BEA最新产品资料概要](https://www.hkbea.com/pdf/en/supp_card_key_facts_statement_en.pdf)列Visa等外币费1.95%、银联外币费1%、境外港币费1%。普通UDC主卡首年免年费（标准HK$1,800）；学生UDC及HKU学生主卡网页列永久免年费。双币人民币子账户按相应产品条款使用。

## 图像来源与资源名

| 本地资源（BankLibrary内） | 官方资源URL | 说明 |
|---|---|---|
| `Catalog/images/cards/bochk-chill-platinum.png` | https://www.bochk.com/dam/boccreditcard/chillcard/images/cardface_platinum.png | 复用此前官方白金卡面，未替换为World |
| `bochk-go-diamond.png` | https://www.bochk.com/creditcard/images/cardface/301_DD_0955_00012.png | 官方独立钻石数字卡面，1536×969，保留完整原图 |
| `bochk-go-platinum.png` | https://www.bochk.com/creditcard/images/cardface/301_DG_0955_00012.png | 官方独立白金数字卡面，1536×969，保留完整原图 |
| `bochk-go.png` | https://www.bochk.com/dam/boccreditcard/cardproductlisting/images/layout/credit-card/cardType_195.png | 旧组合图，仅用于识别并修复老版本已保存图片；新产品不再使用 |
| `bochk-go-cf.png` | https://www.bochk.com/dam/boccreditcard/cardproductlisting/images/layout/credit-card/GOCard_CF.png | 旧组合备选，同样只用于旧图识别 |
| `bochk-gba-youth.png` | https://www.bochk.com/dam/boccreditcard/cardproductlisting/images/layout/credit-card/cardType_219.png | 青年卡独立卡面，示例头像及号码为银行发布的产品样图 |
| `bochk-mastercard-debit.png` | https://www.bochk.com/dam/more/bocdebitcard/card/images/card-4.png | 中银万事达扣账卡灰色Platinum版卡面，151×240 |
| `Catalog/images/cards/bea-hku-student-visa.png` | https://www.hkbea.com/images/eform/app/bea/eFrom/card/c34.png | 官方HKU学生申请表c34的独立Visa卡面 |
| `bea-udc-diamond.png` | https://www.hkbea.com/images/eform/app/bea/eFrom/card/c05D.png | 官方UDC申请表实际card-face=c05D；普通及学生共用此卡面，产品ID仍分开 |
| `bochk-logo.png` | https://www.bochk.com/etc/designs/bochk_web/images/logo.png | 银行官网页首logo |
| `bea-logo.png` | https://www.hkbea.com/images-solar/logo.png | 银行官网页首logo |

这些图像及品牌标识的权利归相应银行/品牌所有，未发现其以开源图片许可证发布；它们用于卡种识别，不纳入本项目代码许可证。未改变官方卡面内容或伪造银行商标。

GO 独立卡面来自[银行奖励说明](https://www.bochk.com/creditcard/BOCPAY/LDP/rewards/faq/eng/)引用的[公开卡片映射](https://www.bochk.com/creditcard/BOCPAY/LDP/rewards/faq/js/getJson.js)，两款分别标明 DIAMOND / PLATINUM。网页映射保留旧“大湾区一卡通”显示名称，实际公开图片为GO标识；与GO产品页卡种核对后采用。没有重绘、裁切或把第三方营销数据作为权益依据。

## 文件边界

Catalog V2 的 `products` 保留原有所有卡片和规则ID，包含 `bea.udc.diamond.student`、`bochk.go.platinum`、`bochk.mastercard.debit`；原 `bochk.go.diamond` 及其既有规则ID不变。CNCBI GBA 与多币扣账卡也直接定义在同一份 Catalog 中；不再维护银行 manifest 或独立 catalog 文件。公开快照当前为五家银行十五款产品（另含交银香港两款），卡面与 Logo 存放在 `Resources/Catalog/images/` 并由 SHA-256 引用。

本子任务只做资料/资源更新及JSON引用核对，没有修改Swift代码，没有构建或进行UI验收。

## 双重迎新及用户控制修正（2026-10-22）

官方现行《新客户限时双重迎新奖赏优惠条款及细则》：https://www.bochk.com/dam/creditcard/banner/GoCard/DoubleWG_TC.pdf 。核实时该 PDF 为2026-10-01至12-31申请推广期，要求同一历日提交至少两张合资格卡申请，其中一张GO卡，并于2027-01-31前获批；GO与另一合资格卡可分别取得迎新资格，仍须满足各卡签账要求。Chill属于合资格卡。此前将全部中银迎新无条件锁成一项，遗漏了限时例外。

按用户要求，App不再强制执行跨卡互斥；银行条件保留供参考，不替用户决定能否同时开启。未更改各卡已保存奖励金额、消费条件或个人到账记录。产品主方案仍是同一张卡的一项选择，不用另造“双重奖励”叠加同一张卡的迎新金额。
