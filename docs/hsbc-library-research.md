# HSBC 卡片库核实记录

核实日期：2026-10-22。产品、费率和迎新依据官方页面及条款；卡面备份来源与规则证据分开记录。

## 产品及条款

- `hsbc.student.visa.gold`：[汇财金卡学生卡](https://www.hsbc.com.hk/zh-hk/credit-cards/products/student-visa-gold/)，Visa。[学生专属条款](https://www.hsbc.com.hk/content/dam/hsbc/hk/tc/docs/credit-cards/student/terms-and-conditions.pdf)列学生身份、指定院校、永久免年费，以及 2026-04-01～2027-02-28 申请的迎新：发卡首 60 个历日合资格签账 HKD2,000，新客 $300 奖赏钱、现有客户 $200，方案互斥。处理申请时持卡状态及过去 12 个月销卡条件须由用户确认，不能因为新添加卡片就自动视为新客。
- `hsbc.pulse.unionpay.diamond`：[Pulse 银联双币钻石信用卡](https://www.hsbc.com.hk/zh-hk/credit-cards/products/unionpay-dual-currency-diamond/)。[一般迎新条款](https://www.hsbc.com.hk/content/dam/hsbc/hk/tc/docs/credit-cards/offers/welcome-terms-and-conditions.pdf)列 2026-03-01～2027-02-28 申请，首 60 个历日合资格 HKD/CNY8,000，按 1:1 累计门槛：新客网上指定渠道 $800、其他认可渠道 $600、现有客户 $200 奖赏钱；只选择符合资格的一项。
- [现行奖赏钱条款](https://www.hsbc.com.hk/content/dam/hsbc/hk/vam/pdf/rewardcash-programme-terms-and-conditions.pdf)为 2026-10-12 生效版：每 250 元合资格消费基本 $1 奖赏钱，按抵账价值估算 0.4%；Pulse 人民币子账户按面值累计，消费费用仍按交易汇率。银行会累计零头，App 逐笔到分只是估算。网上缴费、现金、税款、钱包充值等资格排除仍需正确记录，未默认加最红自主奖赏。
- [学生学费推广条款](https://www.hsbc.com.hk/content/dam/hsbc/hk/docs/credit-cards/tc/tuition-fee-payment-tcs1.pdf)：2026-10-01～2027-03-31，指定网银/App 网上缴费渠道、指定院校，额外 2.4%，整期 $200 上限。引擎不能证明付款使用银行专用缴费渠道，规则默认关闭，不能将所有教育或网购自动当作学费。
- [Pulse 特别奖赏条款](https://www.hsbc.com.hk/content/dam/hsbc/hk/docs/credit-cards/unionpay-dual-currency/diamond-card-terms-and-conditions.pdf)：2026-07-01～12-31，指定内地/澳门手机付款额外 5X 基本奖赏钱。真实条款有 HKD80,000 合资格消费范围、多币种及主附卡合并；本模板只表达 CNY、CN/MO、Apple Pay/云闪付子集，不能完整还原共用消费上限，故默认关闭。推导的 $1,600 不应视为银行直接公布的固定奖励上限。

学生卡自动增值附加奖励、Pulse `HSBCPULSE` 二维码次数奖励及现金套现分期奖励仅作已核实方案说明，不参与计算。次数奖励不是任意单笔百分比，分期贷款不是日常零售签账。银行卡本身新增不会自动安装任何个人迎新；用户须选择方案、申请日期/渠道、发卡日和资格确认。

一般迎新条款第 12、14 条及学生条款第 11、12 条分别限制本推广领取次数及与其他迎新推广同享（另有明文规定的奖励除外）。因此当前主方案使用 `hsbc.primary-welcome.2026` 资格组，在学生卡与 Pulse 间核对同一期主迎新；不是永久限制用户以后参加汇丰迎新。自动增值、二维码及分期附加奖励单独标为 `kind:addon`，可与主方案同时登记个人资格、渠道及到账记录；它们仍不参与自动收益估算。叠加资格需按对应条款确认。

## 卡面和 Logo

本机直接请求 HSBC 官方图片域及公司官网发生 TLS 超时。采用公开、无个人资料的同款资源备份，保留原始图像和宽高比；未通过生成图片改造银行卡面。

| 本地资源 | 官方原图/标识出处 | 实际下载备份 |
| --- | --- | --- |
| `hsbc-student.jpg` | [官方学生金卡 1600×900 图](https://www.hsbc.com.hk/content/dam/hsbc/hk/images/mass/credit-cards/tile-16-9/9358-hsbc-visa-gold-card-grey-1600x900.jpg) | [SmartDollar 同款学生金卡图](https://smartdollar.hk/api/media/file/hsbc-visa-gold-card-for-students.jpg) |
| `Catalog/images/cards/hsbc-pulse-unionpay-diamond.png` | [官方 Pulse 图](https://www.hsbc.com.hk/content/dam/hsbc/hk/images/mass/credit-cards/tile-16-9/9358-hsbc-pulse-unionpay-grey-1600x900.jpg) | [Maxr 产品页](https://www.maxr.ws/credit-cards/hsbc-pulse)所用[同款银联钻石卡 PNG](https://static.wixstatic.com/media/bec40d_50daf9136ed34ca1b659a180ca5dde55~mv2.png/v1/fill/w_1536%2Ch_969%2Cal_c/HSBC%20Dual%20Currency%20Diamond%20Credit%20Card.png) |
| `hsbc-logo.png` | [HSBC 公司官网标准标识](https://www.hsbc.com/-/files/hsbc/header/hsbc-logo-200x25.svg)；Commons 说明追溯至 HSBC 官方发布 | [Wikimedia 原图备份](https://upload.wikimedia.org/wikipedia/commons/b/ba/HSBC_Logo_2018.png) |

学生卡对照官方八达通学生推广图中的香港金狮 Visa 款式，Pulse 对照官方产品图中的香港红狮银联双币钻石款式，未使用其他国家同名卡。银行图片和商标权利归相应持有人，未发现开源图片授权；不适用本项目代码许可证。备份站内容不作为优惠事实来源。

学生卡原始资源是带大面积灰色外边距的 1600×900 宣传画布。展示层 `CardImageContentLayout` 仅在旧版或当前资料库版的来源字节 SHA-256 完全匹配时使用其中 `(440,224,720,453)` 的完整卡片区域，移除卡外背景；按解码缩放比例应用。资料库、预览与已保存个人卡面共用该展示规则。原文件及 SwiftData 中的图像数据不修改，不重绘卡面、不按颜色自动裁剪用户自定义图片。

## 扩展提示

新增 HSBC 产品遵循 [资料库维护手册](bank-library-development.md)。产品、权益、迎新方案、核实与可计算标记统一写入 `App/Resources/Catalog/catalog.json` 的 Catalog V2 `products`，官方卡面写入 `App/Resources/Catalog/images/` 并通过 SHA-256 引用；不再维护独立 manifest 或 JSON v1 文件。同一银行新客、现有客及渠道方案使用独立方案 ID，互斥消费奖励不可全部启用。

## Mastercard 蓝狮子扣账卡（2026-10-22）

- 稳定产品 ID：`hsbc.mastercard.debit`；种类：借记卡，卡组织 Mastercard，与学生汇财金 Visa 信用卡独立。银行产品页核实12种货币（含HKD/CNY/USD）从对应账户直接扣款，合资格签账0.4%现金回赠，免外币交易费及年费；余额不足时可能有兑换，原币记账不代表自行推定港币换汇。
- 官方产品及基础权益：https://www.hsbc.com.hk/zh-hk/debit-cards/products/mastercard-debit-card/
- 当前使用条款（页面标示2026-09-20起生效）：https://www.hsbc.com.hk/content/dam/hsbc/hk/tc/docs/debit-cards/mastercard-debit-card/terms-and-conditions.pdf
- 官方卡面原始及实际下载来源：https://www.hsbc.com.hk/content/dam/hsbc/hk/images/mass/debit-card/card-face/17578-hsbc-world-debit-mastercard-640x1024.jpg 。原图640×1024，本地缓存 `BankLibrary/Catalog/images/cards/hsbc-mastercard-debit.jpg`，保持完整卡面。
- 支付宝推广包含首次绑卡优惠券、即时折扣及Mastercard额外奖赏；2026-06-15至12-31期间AlipayHK不合资格。未将最高CNY300写成固定迎新或通用返现规则；本次不导入不可准确表达的加码活动。

2026-10-25：当前资料库重新编码的同尺寸原图 SHA-256 为 `49448f56b8136d8fef39656e5c0f5e8a4cba60f0c884bde249bca9b0c3c6c3b0`；与旧版 `0a5d027b…` 共用上述裁边视口。新安装、离线资料库、云端缓存及原有持卡图片均通过共享解码器显示。未知指纹保持原图，不猜测裁边。
