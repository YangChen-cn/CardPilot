# 银行交易邮件云端采集

使用自己的 Google Apps Script 每天读取 Gmail 中的受支持银行交易提醒，将最小交易证据保存在自己的私人 Google Drive 文件中。CardPilot 通过带设备密钥的 HTTPS POST 拉取并在本地解析、核对和保存；银行卡、账本和已有同步方式保持不变。不需要 Gmail API key、服务器或 GitHub 邮箱令牌。

Gmail 的普通 API key 不能代替访问私人邮箱所需的用户授权。本项目使用 `gmail.readonly`：授权后脚本能够读取邮箱，但代码只查询三家银行的指定发件人；不发送、删除、标已读或修改标签。Google 允许使用安装型时间触发器在云端执行，受个人账户配额约束，无需另租服务器。[Google 授权说明](https://developers.google.com/apps-script/guides/services/authorization)、[Gmail 消息读取接口](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get)、[Apps Script 配额](https://developers.google.com/apps-script/guides/services/quotas)。

## 第一次部署

需要你在自己的 Google 账户中完成一次授权。不要把密码、应用专用密码、OAuth refresh token 或这里生成的连接密钥发到聊天里。

1. 打开 [Google Apps Script](https://script.google.com/home/start)，新建独立项目，命名为 `CardPilot 银行邮件`。将仓库 `cloud/apps-script/Code.gs` 的完整内容替换默认 `Code.gs`。
2. 在「项目设置」打开「在编辑器中显示 appsscript.json 清单文件」，将仓库同目录的 `appsscript.json` 复制进去。清单启用 Advanced Gmail v1、Drive v3，时区为 `Asia/Hong_Kong`。如编辑器要求补加服务，在左侧「服务」中加入 Gmail API 与 Drive API；使用自己的标准 Cloud 项目时，还需在该项目启用这两个 API。[高级服务启用说明](https://developers.google.com/apps-script/guides/services/advanced)、[Advanced Gmail](https://developers.google.com/apps-script/advanced/gmail)、[Advanced Drive](https://developers.google.com/apps-script/advanced/drive)。
3. 在函数下拉列表选择 `setupCardPilot`，点击「运行」，确认 Google 授权。它首先采集过去 30 天，成功后安装每天香港时间约 03:00 的触发器。Google 会在该小时内选择运行时间，不保证精确到分钟。[时间触发器说明](https://developers.google.com/apps-script/guides/triggers/installable#time-driven_triggers)。
4. 在「项目设置 → 脚本属性」找到自动生成的 `CARDPILOT_TOKEN`。它是独立的高熵连接密钥，不是你的 Gmail 密码。只复制到 CardPilot 的安全输入框；不要写入源码、URL、截图、公开日志或 Git 仓库。
5. 点击「部署 → 新部署 → 网络应用」。执行身份选「我」，访问权限选「任何人」，部署后复制以 `/exec` 结尾的部署 URL。脚本以你自己的身份读取私人缓存；知道 URL 仍无法获取资料，必须同时持有连接密钥。不要选择只允许登录 Google 的访问方式，否则原生 App 无法直接拉取。[Web App 执行身份](https://developers.google.com/apps-script/guides/web)。
6. 在 CardPilot 的邮件同步设置填入部署 URL 与连接密钥，保存并同步一次。手机与 Mac 分别安全配置连接；不要将密钥放入账本文件夹同步。App 连接设置由当前版本界面引导。

完成后，可在 Apps Script「触发器」看到唯一的 `collectBankMail` 每日任务。在「执行记录」检查是否成功；脚本属性 `CARDPILOT_LAST_RESULT` 只包含时间、数量及完成状态，不包含邮件正文或密钥。重新运行 `setupCardPilot` 会保留原有邮箱身份、密钥和私人归档，只重建本脚本的每日任务，不会安装重复任务。

### macOS 钥匙串授权

自签名证书固定，并不代表每次重新编译后的主程序都拥有相同钥匙串分区身份。Apple 的 legacy keychain 实现对未归类为 Apple 开发者签名的程序使用 `cdhash`，主程序更新后可能再次提示，即使上一版选择了始终允许。[Apple 的 partition 身份实现](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp#L176-L274)。

macOS 现由独立、无界面依赖的 `CardPilotMailKeychain` 组件读写原有连接记录，主 App 不再直接查询。组件随 App 打包并使用同一 `CardPilot` 证书签名，仅接受指定 App 标识且证书相同的直接父进程；App 发送连接资料前也会验证组件身份。资料仅经匿名进程管道返回，日志不含密钥。原有服务名及钥匙串记录保留，不删除 ACL、不允许所有应用、不复制到明文文件。一个进程内复用已读取的连接，减少重复访问。

第一次切换旧记录时，系统可能要求对该组件选择一次「始终允许」。之后普通 App／UI 更新复用不变的组件，避免每次重编译主程序都重新授权；组件自身源码、协议或工具链确实更新时，仍可能需要重新授权。iOS 继续使用原生 SecItem，不使用这个 macOS 组件。不要向 agent 提供 Mac 登录密码，也不要通过清空或开放钥匙串规避授权。

首次运行失败时，先运行 `checkCardPilotServices`。它只检查授权状态与 Gmail／Drive 的只读列表能力，不创建或更改邮件、归档、触发器及密钥。执行日志仅输出固定状态：`GRANTED`／`REQUIRED`、`GMAIL_LIST`／`DRIVE_LIST` 的 `OK` 或安全错误类别。`ADVANCED_SERVICE_MISSING` 检查清单及高级服务；`API_NOT_ENABLED` 检查 Cloud 项目的 Gmail／Drive API；`OAUTH_SCOPE_MISSING` 检查授权时是否勾选清单要求的权限；`QUOTA_LIMIT` 等待配额恢复。采集失败的 `CARDPILOT_LAST_RESULT` 还会记录 `stage` 和 `failureClass`，用于区分读取、解析或写归档的失败，不记录底层异常正文和资源 ID。

若要更新脚本，复制新代码后，在「部署 → 管理部署 → 编辑」选择新版本更新现有部署。保留脚本属性及 Drive 文件，设备 URL 和连接密钥可继续使用。不要通过新建脚本项目来更新，这会生成新的邮箱身份。

## 支持的真实模板

| 银行 | 当前支持 | 自动处理的边界 |
|---|---|---|
| BOCHK | `istatement@bochk.com` 的「交易通知 (Transaction Notification)」 | 保留尾号、商户、原币金额和交易日；通知只有日/月时不能伪造具体时分 |
| BEA | `lcccaut@hkbea.com` 的「Contactless Payment Transaction Notification」 | 保留尾号、非接触式消费金额、商户和交易日期；同一邮件线程中多封提醒分别保留 |
| HSBC | `onlineservicesnotification@hsbc.com.hk` 的「Online Transaction has been made on your Debit Card」 | 已核对的是扣账卡网上交易模板，含日期及时间；未找到真实信用卡消费提醒样本，本轮不宣称支持该模板 |

采集端必须同时通过精确发件人、受支持主题以及 Gmail 添加的 `mx.google.com` Authentication-Results 中对齐银行域名的 `dmarc=pass`。展示名称、邮件正文中的银行 Logo 和转发说明都不能代替验证。失败的认证只保留被检查邮件的 ID，不保存其正文。

还款、转账、投资执行、OTP、额度变更、结单备妥、广告及未支持的退款／拒付／撤销模板都不进入消费 feed。授权或交易提醒不等同最终清算；银行后续撤销与账单核对仍需单独支持。不能用 CNY 推断交易地区为 CN，也不能用收件时间冒充银行交易时分。

## 卡片匹配与重新核对

资料库只包含官方产品、卡面和通用优惠，不知道你的个人卡片尾号。邮件使用银行及后 4 位匹配已添加的个人卡片，不需要完整卡号、安全码或账单账号。请在卡片个人设置填写尾号；同一家银行多张卡不能仅凭银行名称猜选。现有 HSBC 适配器明确解析扣账卡网上消费，不会将其计入汇财金等信用卡；已同步的旧 HSBC 提醒同样按扣账卡处理。

补上卡片或尾号后，在「交易核对」点「重新匹配」，可直接重试本地已保存的待核对邮件，无需重新授权 Gmail 或重抓邮件。邮件设置中的「立即更新」也会先重试旧项。成功入账的项退出待核对，缺卡片、疑似重复或财务事实冲突的项保留并更新原因，已忽略的邮件不恢复。缺少汇率、支付方式、地区或渠道不阻止原币入账，也不要求逐笔资格确认。

首页「交易待核对」和邮件设置现在进入同一「交易核对」页面，直接展示银行邮件及其他来源的待核对记录，不再隔一层邮件列表入口。

## 每日运行与离线行为

- 首次检查过去 30 天，以后从最后完整成功时间向前重叠 7 天查询，防止迟到邮件遗漏。按 Gmail **message ID** 去重，不能按 thread ID；同一天同商户同金额的两封真实消费提醒可以属于同一个线程。
- 每次最多读取 500 封尚未处理邮件，Gmail 查询逐页读取。未完成时已采集部分先安全保存，成功扫描游标不前移，下次继续核对未处理 ID；读取或保存失败不推进游标。若积压较多，可手动再次运行 `collectBankMail`，不必重新安装。
- 认证通过且主题受支持的邮件若没有可读正文、日期无效或正文超出适配限制，会使本次采集失败并保留原游标，等待修复适配；不会将它当作已成功处理并静默丢弃。
- 私人 Drive 归档只追加，保留原始消息身份及最小交易证据，不保存附件、完整卡号、收件人、邮件 HTML 链接或推广页脚。单个文件上限为 45 MB；达到容量或一次查询超过 20,000 个候选 ID 时会停止并报固定错误，保留旧归档和游标，需维护扩容，不会静默删除历史。
- App 分页拉取，每页最多 500 条、5 MB。使用追加位置游标，迟到但交易日期较早的邮件仍出现在游标后面。每页导入成功后才保存设备游标；重试相同页由本地邮件身份幂等处理。若其中一封受支持主题的邮件字段或币种无法解析，整页暂停并保留游标；需更新适配后重试，当前版本不跳过坏项继续导入后续页。
- 云端每日任务可在 Mac 关机时采集，但不会直接写关闭的 iOS/macOS SwiftData。App 打开或回到前台并具备网络时再导入，随后沿用现有设备同步。首次导入、待核对项和银行邮件优先策略由原生 App 处理。

## 设备接口

```http
POST https://script.google.com/macros/s/DEPLOYMENT_ID/exec
Content-Type: application/json

{"token":"设备安全保存的密钥","after":"上次成功页的可选不透明游标"}
```

返回：

```json
{
  "schemaVersion": 1,
  "messages": [{
    "id": "稳定邮箱身份:不可变邮件ID",
    "sender": "istatement@bochk.com",
    "subject": "交易通知 (Transaction Notification)",
    "receivedAt": "2026-10-22T00:00:00.000Z",
    "body": "最小交易字段文本",
    "authenticationResults": "mx.google.com; dmarc=pass header.from=bochk.com"
  }],
  "nextCursor": "下一追加位置"
}
```

任何非空页都返回推进后的 `nextCursor`，最后一页也如此；继续读取会得到空消息数组和 `nextCursor:null`。设备应在成功处理该页后保存非空游标，再发下一次请求。空页表示目前没有更多消息；以后新增消息仍从保存的追加位置拉取。

GET 不返回账户资料。Apps Script ContentService 不提供自定义 HTTP 状态码，错误也可能是 HTTP 200，客户端必须先检查 JSON `error`，不能仅依赖状态码。错误包括 `UNAUTHORIZED`、`SETUP_REQUIRED`、`INVALID_CURSOR`、`COLLECTOR_UNAVAILABLE`，不回显正文、令牌或底层服务异常。Google 会将 ContentService 的输出重定向到 `script.googleusercontent.com`，客户端需按 Google 的方式跟随响应重定向。[ContentService 重定向说明](https://developers.google.com/apps-script/guides/content#redirects)。

## 暂停、轮换与维护

在 Apps Script「触发器」移除 `collectBankMail` 即可停止每日采集。在设备关闭自动拉取只停止该设备获取，不删除云端资料。运行 `rotateCardPilotToken` 可使旧密钥立即失效，再将脚本属性中的新值直接填入各设备；该函数不打印或返回密钥。若私人 Drive 文件被删除，先在 Drive 垃圾箱恢复同一文件，避免另建空归档掩盖丢失。

不要在 GitHub Actions 中使用 Gmail 插件的令牌：该授权不能转移给独立 runner。若未来改用 Actions，需独立 Google OAuth、加密输出、持久游标及单独部署方案；不能把私人交易数据提交到代码仓库。本方案把 Gmail 与归档留在同一 Google 账户，设备凭据只访问受支持的交易 feed。

无凭据的本地检查：`node --test script/test-bank-mail-cloud.cjs`。它模拟 Google 服务，覆盖发件人验证、分页、同线程多笔、幂等、失败游标保护及追加游标；不会连接私人邮箱。模拟通过不能代替用户在 Google 账户中的首次授权和真实云端触发器运行验收。
