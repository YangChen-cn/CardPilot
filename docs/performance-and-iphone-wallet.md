# 性能与 iPhone 卡包

更新：2026-10-23。沿用 SwiftUI／SwiftData 与现有权益优先架构；不迁移、清空或替换个人账本。

## 阶段一：查询与更新

- `DashboardSpendingData` 仅读取当前月及前五个月的交易，最近消费另用 `fetchLimit = 3` 查询。首页 `body` 读取已保存快照，不随布局、展开或卡面选择重新聚合全部历史。
- SwiftData 模型留在主 Actor；转换为不可变 `SpendInput` 后后台单次遍历统计。保存、同步直接保存、重新出现、回前台和香港日期边界刷新；过期任务结果不覆盖新快照。读取失败保留旧统计并提供重试。
- `OfferProjectionDocuments` 每次投影批量读取所需的个人状态和旧 policy，用稳定键索引；保留稳定键 → UUID 旧键 → 历史 policy 的读取顺序。该索引仅在本次投影内使用，下次投影直接观察最新保存状态，不引入永久缓存或同步版本。
- `CatalogAssetImage` 在资料检查／失败重试信号变化时保留已加载且 SHA-256 相同的图片，仅缺失图片重试；资源哈希改变才重新加载。已取消的旧请求不回写新资源。

验证：macOS 构建及 17 项针对性测试通过，范围为 `DashboardSpendingTests`、`OfferSyncStabilityTests`、`CatalogAssetStoreTests`、`CardOrderTests`。新增用例覆盖查询窗口、保存修改／删除、月份切换、同步后刷新、个人状态优先级与历史回退。iOS Simulator 目标编译通过。没有进行 UI 自动化或运行速度倍数测量；这些结果不能替代用户的实际界面验收。

阶段一提交：`Reduce dashboard queries and batch offer state reads`。

## 阶段二：iPhone 卡包

- 卡片菜单增加“精选卡片／紧凑列表”，偏好存为 `cards.phonePresentation`，不修改桌面 `cards.displayMode`。默认精选只展示一张可横向分页的卡面，下面集中显示当前卡名称、权益、账本及预选卡记账。
- 下方紧凑行支持点选当前卡并回到卡面；紧凑模式则直接打开详情。继续复用稳定卡片身份、搜索、分类、归档、加卡及拖动排序／辅助功能移序，不复制业务逻辑或伪造余额。
- 官方横竖图片均完整 fit，缩略图仅整体缩放；卡面不随文字字号改变比例，元数据继续支持 Dynamic Type。VoiceOver 可调节精选卡，Reduce Motion 下关闭切卡和移序动画。
- macOS 继续原网格和工具栏，常规宽度布局不增加手机卡包；未更改共享 `WalletCardTile`、资料库或存储模型。

验证：iOS Simulator 增量编译通过；macOS 已在阶段一针对性测试时完成编译，17 项相关回归通过，不因纯布局重复执行全量。通过 `script/run_ios.sh 'iPhone 17'` 构建、安装并启动最新版，保留模拟器既有数据，不导入真实 Mac 账本。实际卡片分页、紧凑列表、深浅色和大字体效果由用户验收；未运行 UI 自动化或截图巡检。

阶段二提交：`Refine the iPhone wallet with featured cards and a compact list`。
