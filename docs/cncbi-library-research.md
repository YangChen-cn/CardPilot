# CNCBI 信银国际资料核对

核对日期：2026-10-23。仅用于 CardPilot 的资料展示；不连接银行账户，不自动判定用户资格。金额、上限和日期均以银行最新条款为准。

## 产品

| 产品ID | 产品信息 | 采用的官方依据 |
|---|---|---|
| `cncbi.gba.dual` | 信银国际 GBA 双币卡（银联 Diamond）；基础 0.4%，人民币签账额外 3.6%（连基础共 4%，月上限 HK$150），单笔满 CNY4,000 额外 6%（月上限 HK$250），另有固定 HK$600 迎新描述 | [信用卡推广页](https://www.cncbinternational.com/personal/promotions/credit-card/tc/index.html?SOURCE=ATJ15)、[基础奖赏条款](https://www.cncbinternational.com/_promotion/201111/rewards-programs/tc/tnc_cash_rebate_dcc.pdf) |
| `cncbi.multi-currency.debit` | 多币扣账卡（Mastercard）；支持港元、人民币、美元、澳元、加元、欧元、英镑、日圆、纽元、新加坡元共 10 种货币直接扣账；基础现金回赠 0.2% 不设上限；经 Mastercard 网络涉及外币兑换收取 1.95% 外币交易费；须持有有效的单名综合货币结算储蓄存款户口 | [多币扣账卡产品页](https://www.cncbinternational.com/personal/multi-currency-debit-card/tc/index.html)、[2025-10-13 新闻稿](https://www.cncbinternational.com/_document/about-us/media-center/2025-10-13/tc/p251013.pdf) |

## 展示边界

- GBA 的 4%/6% 与固定迎新属于限时推广，目录保留显式 `group` 和来源，但不据此自动计算用户实际回赠。人民币、钱包、缴费和单笔门槛等条件以官方条款为准。
- 多币扣账卡是扣账卡，不设信用额度；1.95% 仅在交易涉及外币兑换时适用。动态货币兑换（DCC）和商户结算币种可能影响最终费用，App 不推断具体汇率。
- 两张卡的基础数字为官方页面已核实资料；迎新资格、开户条件、私人财富等级及推广名额仍须用户自行向银行确认。

## 图像来源与资源名

| 本地资源（BankLibrary内） | 来源 | 说明 |
|---|---|---|
| `cncbi-gba-dual.png` | 官方产品页核对卡种；卡面由公开产品宣传图裁切 | 官方页面未提供可直接下载的独立 GBA 卡面文件；未重绘卡面或伪造标志。若后续取得官方独立卡面，应替换并记录下载 URL |
| `cncbi-multi-currency-debit.png` | https://www.cncbinternational.com/_document/about-us/media-center/2025-10-13/tc/p251013.pdf（第3页内嵌图） | 官方新闻稿内嵌卡面，403×657，保留完整比例 |
| `cncbi-logo.png` | https://www.cncbinternational.com/personal/e-banking/inmotion/images/cncbi-logo.png | 银行官网页首 logo，230×62 |

这些图像及品牌标识的权利归中信银行（国际）所有，仅用于卡种识别，不纳入项目代码许可证。
