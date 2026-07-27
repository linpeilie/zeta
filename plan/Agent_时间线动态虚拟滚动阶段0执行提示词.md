# Agent 时间线动态虚拟滚动：阶段 0 执行提示词

> 对应详设：`plan/Agent_时间线动态高度虚拟滚动与滚动条详细设计.md`  
> 阶段目标：建立可重复的现状基线和诊断证据，不开始滚动方案改造  
> 使用方式：将下方完整提示词交给一个新的编码 Agent 执行

## 可直接使用的提示词

````text
你现在在 `D:\Development\Workspace\zeta` 仓库中工作。

本次任务是执行“Agent 时间线动态高度虚拟滚动与滚动条”方案的阶段 0：基线与诊断。

这不是修复阶段。你的目标是把当前滚动问题变成可重复、可量化、可回归的证据，并据此判断是否可以进入阶段 1。

## 一、开始前必须完成

1. 完整阅读：
   - `AGENTS.md`
   - `plan/Agent_时间线动态高度虚拟滚动与滚动条详细设计.md`
   - 本文件：`plan/Agent_时间线动态虚拟滚动阶段0执行提示词.md`
2. 重点阅读详设以下章节：
   - 第 3 章“当前实现与根因”
   - 第 18 章“性能预算与可观测性”
   - 第 19 章“测试详设”
   - 第 20 章“验收标准”
   - 第 21 章“实施阶段”中的阶段 0、阶段 1
3. 先执行只读检查：
   - `git status --short`
   - `git branch --show-current`
   - `git rev-parse HEAD`
   - `flutter --version`
4. 仓库存在 `.codegraph/` 时，必须先使用 CodeGraph 理解相关代码，至少覆盖：
   - `_AgentConversationTimeline`
   - `_AgentPaneState` 中现有滚动逻辑
   - `AgentTimelineViewportItem`
   - `AgentTimelineProjectionCache`
   - `autoScrollTickListenable`
   - 当前 virtualization、streaming 和 expand/collapse 测试
5. 保留所有已有用户改动：
   - 不执行 `git reset --hard`
   - 不执行 `git checkout -- .`
   - 不删除或覆盖不属于本任务的文件
   - 不擅自 stage、commit 或清理工作区

## 二、阶段 0 唯一目标

完成以下四项工作：

1. 固化当前动态高度虚拟列表的确定性测试 fixture；
2. 采集当前 `pixels`、`maxScrollExtent`、viewport、可见锚点和构建数量等基线；
3. 通过自动化测试或稳定 profile 场景，证明当前“thumb 不动或突然跳变”的根因可以重复观察；
4. 输出阶段 0 基线报告和是否允许进入阶段 1 的明确门禁结论。

阶段 0 不评价新算法效果，因为新算法尚未实现。

## 三、严格范围

### 允许

- 新增或扩充测试 fixture；
- 新增 `test/` 下的测试辅助类；
- 在确实无法从测试树读取指标时，新增最小、只读、仅测试可见的诊断接口；
- 新增阶段 0 基线报告：
  - `plan/Agent_时间线动态虚拟滚动阶段0基线报告.md`
- 为了让测试稳定而做不改变生产滚动语义的测试性重构；
- 使用 `dart:developer` 记录显式开启的诊断信息；
- 创建临时 profile/trace 文件，但必须放在仓库外或 Git 忽略目录，且不得提交。

### 禁止

- 不实现 `IdeExtentIndex`；
- 不实现 Fenwick Tree；
- 不实现 `IdeAnchoredDynamicSliverList` 或任何自定义 RenderSliver；
- 不实现锚点补偿；
- 不实现 `followEnd/free` 新状态机；
- 不替换现有 `SliverList`；
- 不替换或重绘生产滚动条；
- 不修改现有 `_stickToBottom/_scrollToEnd` 行为；
- 不改变 Provider、domain、timeline store、projection identity 或持久化协议；
- 不引入第三方依赖；
- 不为了让基线“更好看”顺手修复当前问题；
- 不提交永久失败或默认 skip 的测试；
- 不使用 `print` 或无条件输出高频日志；
- 不把真实用户消息、凭证、绝对用户项目路径、DevTools 原始 trace 或敏感截图提交到仓库。

如果发现必须修改生产滚动行为才能完成阶段 0，立即停止该方向，将其记录为阻塞项；不得越界进入后续阶段。

## 四、先确认当前实现事实

至少核对并在报告中引用实际文件和符号：

- `lib/src/features/agent/presentation/widgets/agent_pane_sections.dart`
  - 当前 `CustomScrollView + SliverPadding + SliverList`
  - `SliverChildBuilderDelegate`
  - stable key 和 `findChildIndexCallback`
- `lib/src/features/agent/presentation/agent_pane.dart`
  - `_scrollController`
  - `_stickToBottom`
  - `_shouldStickToBottom`
  - `_scrollToEnd`
- `lib/src/features/agent/presentation/agent_timeline_projection.dart`
  - `AgentTimelineViewportItem.id`
  - block/activity/footer 的稳定 ID
- `lib/src/features/agent/application/agent_conversation_ui_signals.dart`
  - live/autoScroll 信号及刷新合并
- 现有测试：
  - `test/src/features/agent/presentation/agent_timeline_virtualization_test.dart`
  - `test/src/features/agent/presentation/agent_conversation_widget_test.dart`
  - 其他实际覆盖 Agent pane 状态保留的测试

如果文件名或结构已经变化，以 CodeGraph 和当前源码为准，并在报告中说明差异。

## 五、建立统一的测试指标

优先在 `test/` 下新增测试辅助模型，例如：

```text
ScrollMetricsSample
  label
  frame/step
  pixels
  maxScrollExtent
  viewportDimension
  extentBefore
  extentAfter
  normalizedOffset
  firstVisibleItemId
  firstVisibleItemTop
  builtChildCount
```

其中：

```text
normalizedOffset =
  maxScrollExtent <= 0 ? 0 : pixels / maxScrollExtent
```

要求：

- 指标模型不可依赖业务 Provider；
- 指标采集不改变滚动位置；
- 优先从 `ScrollableState.position`、stable key 和测试树读取；
- 不要仅为取指标暴露可写的生产 controller；
- 数值比较使用明确容差；
- 测试失败信息必须能指出具体 step 和前后指标；
- 如需输出完整 trace，只在显式诊断开关打开时使用 `dart:developer`；
- 正常 `flutter test` 不应产生大量日志。

如果无需新增生产诊断接口，应明确记录“生产代码零修改”。

## 六、必须固化的四类场景

### 场景 A：混合高度虚拟列表

建立确定性 fixture，至少包含 2,000 项和稳定 `ValueKey`。

高度集合至少覆盖：

```text
24, 80, 2,000, 32, 600, 48
```

为了稳定暴露 Flutter 默认 `SliverList` 的估算变化，可以同时使用：

- 交替高度序列；
- 按高度分段的序列，例如先大量短项，再出现大块项。

至少采集：

- 首帧 built child 数；
- 初始 `maxScrollExtent`；
- 多个滚动 step 的 `pixels/maxScrollExtent/normalizedOffset`；
- 首次进入极高 item 前后的 `maxScrollExtent`；
- 到达列表末尾后的最终 metrics；
- 当前视口附近可见 child 数。

必须验证：

- 首帧没有构建全部 2,000 项；
- 当前实现仍然是虚拟化；
- 能否稳定观察 `maxScrollExtent` 随新高度样本发生明显修正；
- 修正是否远大于单个普通短 item 的高度；
- 同一滚动动作下 normalized offset/thumb proxy 是否出现停滞或突变。

阶段 0 的 characterization test 可以断言“当前问题确实存在”，但测试名称必须明确包含 `baseline` 或 `characterization`，并注明该断言将在阶段 2 接入新 sliver 后反转或替换。不得留下失败测试。

### 场景 B：流式更新

基于现有 Agent fixture，至少覆盖：

1. 用户位于底部时，live Markdown 持续增长；
2. 用户主动上滚并离开底部时，live Markdown 持续增长。

采集更新前后：

- `pixels`
- `maxScrollExtent`
- end distance
- 首个可见 item ID 和 top
- autoScroll tick 数或等价可观测事件

报告必须回答：

- 当前底部跟随能否稳定到达最新末尾；
- 手动离开底部后，视口是否被抢回；
- metrics 变化与当前 48px threshold 的关系；
- 是否存在连续 `animateTo/jumpTo` 目标变化。

不要在阶段 0 修改这些行为。

### 场景 C：展开与折叠

至少覆盖：

- command group；
- file edit group；
- 如现有 fixture 难以构造其中一类，必须说明阻塞原因并补一个等价的动态高度卡片场景。

将被展开/折叠的 item 放在：

1. 当前锚点之前；
2. 当前锚点之后。

采集：

- 展开/折叠前后的 `pixels/maxScrollExtent`；
- 原锚点 item 的 viewport top；
- 动画 settle 前后的偏移；
- 当前 built child 数。

报告必须明确：

- 锚点前高度变化会造成多少视觉位移；
- 锚点后高度变化是否影响当前视口；
- 现有测试只验证 scroll pixels，还是同时验证稳定 item 的视觉坐标。

### 场景 D：宽度变化

使用确定性 viewport 尺寸，至少执行：

```text
1400 -> 700 -> 1400
```

fixture 中必须包含会因换行改变高度的 Markdown/长文本。

采集每次 settle 后：

- `pixels`
- `maxScrollExtent`
- viewportDimension
- 首个可见 item ID 和 top
- built child 数

报告必须回答：

- 宽度变化是否造成全局 scroll extent 大幅变化；
- 原可见 anchor 是否漂移；
- 恢复原宽度后 metrics 是否回到接近原值；
- 当前实现是否有可复用的高度缓存。

## 七、测试稳定性要求

测试必须：

- 使用固定 viewport、固定数据和固定 key；
- 不依赖真实 Provider、网络或本机用户历史；
- 不依赖 wall clock；
- 动画通过 `pump`/`pumpAndSettle` 或受控 fake async 推进；
- 对 Flutter 浮点布局使用合理容差；
- 避免断言 RawScrollbar 私有绘制常量；
- 通过 metrics 和 anchor 坐标证明问题；
- 连续运行至少 3 次，确认不是偶发；
- 不因为生成报告而写入运行时用户目录。

如果某个问题只能通过人工 profile 稳定复现：

1. 自动化测试仍需覆盖可测的结构事实；
2. 把固定操作步骤、窗口尺寸、数据 fixture、运行模式和观察指标写入报告；
3. 使用 Windows Profile：
   - `flutter run -d windows --profile`
4. 原始 trace 放在仓库外；
5. 仓库中只记录脱敏汇总数字和结论。

## 八、建议改动位置

优先级从高到低：

1. 扩充：
   - `test/src/features/agent/presentation/agent_timeline_virtualization_test.dart`
   - `test/src/features/agent/presentation/agent_conversation_widget_test.dart`
2. 如场景较多，可新增：
   - `test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart`
3. 通用测试辅助类放到现有 test support 结构中；若没有合适位置，可新增：
   - `test/support/scroll_metrics_trace.dart`
4. 仅在测试树无法取得必要指标时，才对 `lib/` 添加最小只读诊断接口。
5. 新增：
   - `plan/Agent_时间线动态虚拟滚动阶段0基线报告.md`

不要为了符合建议路径而破坏仓库现有测试组织；以当前结构为准。

## 九、基线报告必须包含

`plan/Agent_时间线动态虚拟滚动阶段0基线报告.md` 至少包含：

1. 基线元数据
   - 日期
   - Git branch/commit
   - 开始前 dirty files
   - Flutter/Dart 版本
   - 平台和测试模式
2. 当前实现确认
   - 实际文件/符号
   - 当前虚拟化、滚动和 auto-scroll 链路
3. Fixture 定义
   - 数据量
   - 高度分布
   - viewport
   - 动作步骤
4. 场景 A～D 的指标表
5. 根因证据
   - 哪一段数据证明 maxScrollExtent 在重估
   - 哪一段数据证明 anchor 漂移
   - 哪一段数据证明 bottom lock 的现状
6. 测试与验证命令
   - 完整命令
   - 退出码
   - 通过/失败数量
   - 失败原因
7. 阶段 0 改动清单
8. 已知限制和未覆盖项
9. 阶段门禁结论
10. 阶段 1 建议输入

报告中的数字必须来自本次实际执行，不得编造。

## 十、验证命令

根据实际文件补充精准命令，但至少运行：

```powershell
dart format .
flutter analyze
flutter test test/src/features/agent/presentation/agent_timeline_virtualization_test.dart
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart
flutter test
git diff --check
git status --short
```

如果新增独立 baseline test，必须单独运行该文件至少 3 次，例如：

```powershell
flutter test test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart
flutter test test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart
flutter test test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart
```

要求：

- 如命令受环境限制无法运行，说明具体限制和已经完成的替代验证；
- 不得把“没有运行”写成“通过”；
- analyze 或测试失败时，先判断是否由本阶段引入；
- 可以确认的既有、无关失败要附证据；
- 不能确认时按失败处理。

## 十一、阶段 0 门禁

最终只允许输出：

```text
下一阶段是否可以开始：是
```

或：

```text
下一阶段是否可以开始：否
```

### 输出“是”必须同时满足

1. 场景 A 的动态高度估算变化可重复；
2. 场景 B、C、D 均有自动化证据，或有明确且可重复的 profile 证据；
3. 至少记录：
   - pixels
   - maxScrollExtent
   - viewportDimension
   - anchor ID/top
   - built child count
4. 当前生产滚动行为没有改变；
5. 新增 characterization tests 默认通过；
6. 新增测试连续运行 3 次均通过；
7. `flutter analyze` 通过；
8. 全量 `flutter test` 通过，或者失败已被确证为既有且与本阶段无关；
9. 基线报告完整；
10. 阶段 1 已获得足够输入，可以只实现纯 Dart extent index，而无需猜测阶段 0 数据。

任一条件没有满足，都必须输出“否”，不得给出模糊的“基本可以”“有条件可以”。

## 十二、最终回复的强制格式

最终回复必须完整、自包含，严格按以下结构输出：

### 1. 阶段 0 结论

- 一句话结论；
- 根因是否稳定复现；
- 基线报告路径。

### 2. 阶段 0 修改内容

使用表格逐项列出：

| 文件 | 修改类型 | 修改内容 | 是否影响生产行为 |
| --- | --- | --- | --- |

随后补充：

- 新增的 fixture；
- 新增的诊断指标；
- 没有修改但经过核验的关键生产文件；
- 明确声明是否新增依赖。

### 3. 基线证据摘要

按场景 A～D 分别给出：

- 测试动作；
- 关键前后数值；
- 观察结论；
- 是否稳定复现。

不得只写“测试通过”，必须给关键 metrics。

### 4. 测试结果

使用表格逐项列出：

| 命令 | 结果 | 退出码 | 说明 |
| --- | --- | --- | --- |

必须包含：

- format
- analyze
- 所有 targeted tests
- baseline test 的 3 次结果
- full test
- diff check

若有失败，列出失败测试名、是否由本阶段引入及证据。

### 5. 阶段门禁

逐项列出第十一节 10 条门禁的通过/失败状态，然后单独输出以下精确句式之一：

```text
下一阶段是否可以开始：是
```

或：

```text
下一阶段是否可以开始：否
```

### 6. 下一步提示词

必须输出一个完整、可复制、可在新会话独立执行的提示词。

如果门禁为“是”，标题为：

```text
阶段 1：Extent Index 执行提示词
```

该提示词必须：

- 要求完整阅读 `AGENTS.md`、总详设和阶段 0 基线报告；
- 引用本次实际报告路径和最关键基线数据；
- 只实现：
  - `IdeVirtualItemDescriptor`
  - `IdeExtentRecord`
  - `IdeLayoutEpoch`
  - Fenwick Tree
  - `IdeExtentIndex`
  - stable ID synchronize
  - 纯 Dart 单元测试
- 明确禁止接入 Agent UI、替换 SliverList、实现 RenderSliver、滚动条、锚点或 bottom lock；
- 要求覆盖详设第 19.1 节全部测试；
- 要求 10,000 次随机 update 与朴素数组对照；
- 要求 `dart format .`、`flutter analyze`、targeted test、`flutter test`；
- 要求输出阶段 1 修改内容、测试结果、是否可以进入阶段 2，以及阶段 2 提示词。

如果门禁为“否”，不要生成阶段 1 实施提示词。标题改为：

```text
阶段 0：缺口补齐与复测提示词
```

该提示词必须：

- 精确列出未通过的门禁；
- 引用失败命令和缺失证据；
- 只允许补齐阶段 0；
- 明确禁止开始阶段 1；
- 规定补齐后的复测命令；
- 再次要求输出“是否可以进入阶段 1”和后续提示词。

下一步提示词不得只写概要或占位符。

### 7. Git 提交信息

按 `AGENTS.md` 输出一个可复制的 Conventional Commits 提交信息，但不要自动提交。

## 十三、工作原则

- 先证据，后结论；
- 先复现，后设计；
- 阶段 0 只描述当前事实，不把详设中的未来算法当成已实现结果；
- 不使用主观的“感觉更顺滑”作为证据；
- 不为通过门禁而删除、放宽或 skip 测试；
- 若数据与详设假设冲突，以当前源码和实际数据为准，并在报告中指出；
- 完成阶段 0 后停止，不得继续实施阶段 1。
````

## 预期产物

执行该提示词后，仓库内预期新增或更新：

```text
plan/Agent_时间线动态虚拟滚动阶段0基线报告.md
test/src/features/agent/presentation/agent_timeline_virtualization_test.dart
test/src/features/agent/presentation/agent_conversation_widget_test.dart
test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart（按需）
test/support/scroll_metrics_trace.dart（按需）
```

阶段 0 不应新增生产滚动算法文件，也不应改变当前生产滚动行为。
