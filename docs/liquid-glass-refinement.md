# 第二阶段：Liquid Glass 与原生转场

更新：2026-10-30。基于第一阶段 `87c253d`，实现提交 `c7dc4fd`，搜索验收跟进 `ab18153`。

## 材质与交互

- 导航继续使用系统 TabView、NavigationSplitView、Toolbar、Sheet。卡包和账本用 `ToolbarSpacer` 区分低频菜单与新增操作，不重建导航栏。
- macOS 卡包的显示/添加菜单采用 `.glass` / `.glassProminent`，放在同一个 `GlassEffectContainer`；资料库预览的添加按钮采用悬浮 `.glassProminent`，移除底部整条材质栏和分隔线，保留安全区与系统滚动边缘效果。
- 叠放翻卡控件采用一个玻璃胶囊，保留两侧 44pt 点击区；成功/错误反馈使用轻量玻璃提示，不接收触摸，也不覆盖正文为新的工具栏。
- 自定义胶囊和提示在“降低透明度”下使用不透明表面；“减弱动态效果”关闭自定义缩放与玻璃交互效果。系统按钮本身遵循系统辅助功能设置。
- 权益卡片、长正文、统计和银行卡面不加玻璃。银行卡面只绘制一次，删除重复卡面、模糊、渐变与额外阴影叠层；继续保持原比例和完整图案。未做帧率采样，不将代码简化当作性能测量结果。

## 转场连续性

| 入口 | 处理 |
| --- | --- |
| 卡面展示 / 紧凑列表 → 卡片详情 | 缩放来源改为实际卡面，不再把文字和整行一起放大；使用稳定卡片 ID 与圆角来源配置 |
| 叠放卡面 / 下方卡名 → 卡片详情 | 两个入口交给同一个打开操作，使用当前卡面来源，保留现有快速切卡队列与手势取消逻辑 |
| 银行产品列表 → 产品预览 | 使用产品 ID 对应原生缩放转场，移除固定高度造成的额外卡面留白 |
| 权益卡 / 整卡指南 → 阅读面板 | 从所点内容展开 iOS 原生面板；由系统处理交互式关闭，不添加手动计时或自定义返回手势 |
| 大字号 / 减弱动态效果 | 紧凑列表隐藏图片时保留普通导航；减弱动态效果不使用缩放转场，macOS 继续使用原生桌面导航与 Sheet |

卡片按压采用轻微缩放及透明度反馈，减少整块变暗的闪烁；展开指示符使用同一箭头旋转，保留整行点击与子控件独立操作。重复消费确认锚定保存按钮，交易删除确认锚定对应交易行；删除仍须用户确认，取消不修改账本。

## 搜索取消验收跟进

用户反馈卡包搜索点右侧取消后重新展开。第一次修补 `ab18153` 只增加 `isPresented` 绑定和退出清空查询，**用户复验确认仍会回弹，不能视为修复通过**。

进一步查到 [Apple Developer Forums 845737](https://developer.apple.com/forums/thread/845737)：相同的 minimized toolbar search 组合会难以关闭，DTS 工程师复现了相似异常。它与本项目现象一致，但不是 CardPilot 已完成独立最小复现的证明。

中间版本 `f31e83f` 改用 `.navigationBarDrawer(displayMode: .always)` 避开折叠模式，但用户继续反馈：搜索栏固定在顶部，滚动时与卡面、正文叠在一起，影响可读性。此方案已被替代。

**当前实现**：iOS 使用 `PilotSearchField`（SwiftUI TextField、清除和取消按钮），作为卡包、账本、添加银行的普通内容行，随 ScrollView/List 滚走；不使用 overlay、置顶分区头或系统搜索呈现控制器。取消清空查询并释放焦点，小叉只清空文字；不通过定时或再次激活焦点来干预系统。

顶部导航采用系统清晰滚动边缘和可见页面背景，避免银行卡图案透入标题与按钮区域；搜索行本身不加玻璃。辅助功能大字号时取消按钮改为纵向排列，点击区域保留44pt。macOS 继续原有工具栏搜索。

参考 Apple 的 [Managing search interface activation](https://developer.apple.com/documentation/swiftui/managing-search-interface-activation) 和 [ScrollEdgeEffectStyle](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle)。各次局部呈现修补只编译受影响目标，不重复单元/全量测试；实际取消与滚动可读性仍由用户复验。

## 官方依据

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)：优先系统导航与控件，玻璃用于功能层，避免遮盖内容和过量使用。
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)：相邻自定义玻璃元素共享容器；正文不需要玻璃形变。
- [Build a SwiftUI app with the new design — WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)：工具栏分组、原生玻璃按钮和缩放呈现。
- [MatchedTransitionSourceConfiguration](https://developer.apple.com/documentation/swiftui/matchedtransitionsourceconfiguration)、[ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer)：来源形状与原生工具栏分组 API。
- [accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)：降低透明度时，自定义背景使用不透明表面。

## 验证与手动验收

- `git diff --check` 通过；XcodeGen 生成工程已同步新源文件。
- macOS 独立测试目录执行 `CardDeckInteractionTests`、`CrossSourceTransactionTests`、`LedgerQueryTests`、`EditorDraftTests`：29 项通过，含参数化共 34 次执行，0 失败、0 跳过。未新增复述布局实现的测试，未重复全量测试。
- iOS Simulator 目标编译通过。最后补齐常规宽度权益来源后，由现有启动脚本再次增量编译交付。
- 第一轮搜索绑定补丁的 iOS 与 macOS 编译均通过；用户复验未解决回弹后，停用折叠工具栏模式，仅编译和交付受影响的 iOS 目标。没有增加新搜索引擎、焦点抢夺或延时重试。
- 用户再次反馈固定搜索栏遮挡内容后，改为滚动内容行，双端编译通过；随后只调整iOS按钮命中区，由现有启动脚本再次编译、安装并打开iPhone17。没有重启macOS App，未改变筛选/账本/资料库数据逻辑。
- macOS 使用原脚本、固定 `CardPilot` 证书构建，deep/strict 签名验证、启动和进程检查通过；打开正常数据版本。
- 本轮卡片/面板转场安排 iPhone 专项验收：现有 iPhone 17 模拟器使用 `--demo --preview-library-cards`，资料在内存，不导入或替换 Mac 账本。当前机器可用运行时为 iOS 27.0；iOS 26 实机未验收。
- 启动供用户验收不等于 UI 验收通过；没有截图、点击巡检或 UI 自动化。

建议依次查看：

1. 叠放卡面和下方卡名是否使用同一展开/返回路径；快速连续切卡后打开再返回是否自然。
2. 切换紧凑列表、卡面展示，检查卡面来源；资料库选择产品、进入预览、继续个人配置是否顺畅。
3. 打开并关闭权益详情、推荐用法；检查拖动关闭或中途取消关闭，来源是否仍可见可点。
4. 检查工具栏菜单分组、悬浮添加按钮、保存反馈和错误反馈；删除确认取消后应保留记录。
5. 检查深色模式、大字号、减弱动态效果和降低透明度。实际文字对比、触摸手感、返回手势与 VoiceOver 由设备上的人工验收确认。
6. 点内容中的搜索行 → 输入 `1` → 取消 → 返回完整卡包并收起键盘；等待片刻，不应重新进入编辑。再点空搜索行应可正常输入。向上滚动时搜索整行应离开屏幕，不应贴在卡面/正文上。另测框内小叉、账本与添加银行页。

存储、同步格式、钥匙串组件、公开 Catalog 和已发布 IPA 均未变更；第一阶段的草稿保护继续保留。
