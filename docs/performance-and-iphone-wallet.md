# 性能与 iPhone 卡包

更新：2026-10-23。沿用 SwiftUI／SwiftData 与现有权益优先架构；不迁移、清空或替换个人账本。

## 阶段一：查询与更新

- `DashboardSpendingData` 仅读取当前月及前五个月的交易，最近消费另用 `fetchLimit = 3` 查询。首页 `body` 读取已保存快照，不随布局、展开或卡面选择重新聚合全部历史。
- SwiftData 模型留在主 Actor；转换为不可变 `SpendInput` 后后台单次遍历统计。保存、同步直接保存、重新出现、回前台和香港日期边界刷新；过期任务结果不覆盖新快照。读取失败保留旧统计并提供重试。
- `OfferProjectionDocuments` 每次投影批量读取所需的个人状态和旧 policy，用稳定键索引；保留稳定键 → UUID 旧键 → 历史 policy 的读取顺序。该索引仅在本次投影内使用，下次投影直接观察最新保存状态，不引入永久缓存或同步版本。
- `CatalogAssetImage` 在资料检查／失败重试信号变化时保留已加载且 SHA-256 相同的图片，仅缺失图片重试；资源哈希改变才重新加载。已取消的旧请求不回写新资源。

验证：macOS 构建及 17 项针对性测试通过，范围为 `DashboardSpendingTests`、`OfferSyncStabilityTests`、`CatalogAssetStoreTests`、`CardOrderTests`。新增用例覆盖查询窗口、保存修改／删除、月份切换、同步后刷新、个人状态优先级与历史回退。iOS Simulator 目标编译通过。没有进行 UI 自动化或运行速度倍数测量；这些结果不能替代用户的实际界面验收。

阶段一提交：`Reduce dashboard queries and batch offer state reads`。

## iPhone 卡片样式

2026-10-23：在回退后的卡片页仅补回“紧凑列表”选项。右上角“…” → “卡片样式”可选择卡面展示或紧凑列表，独立偏好 `cards.phoneCompactList` 默认关闭；一起显示与按类型分组均可使用。紧凑行完整显示缩略卡面、名称、银行／卡组织／尾号，继续复用原有详情导航、拖动排序、账本菜单和辅助功能移序。macOS 维持现有网格。

此局部布局修改已通过 iOS Simulator、macOS 增量构建；已用现有脚本打开 iPhone 17 模拟器最新版，保留既有卡片与交易数据。未重复跑业务测试或自行进行 UI 验收。提交：`Add an optional compact list to the iPhone card page`。
