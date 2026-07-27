# Agent 时间线动态虚拟滚动阶段 0 基线报告

## 1. 基线元数据

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-07-27 |
| Git branch | `flutter` |
| Git commit | `08b647fd079bc6537fa1c2e9e1bfd6237d5d0ded` |
| 开始前 dirty files | `?? plan/Agent_时间线动态虚拟滚动阶段0执行提示词.md`；`?? plan/Agent_时间线动态高度虚拟滚动与滚动条详细设计.md` |
| Flutter | 3.44.4 stable，revision `ad70ec4617` |
| Dart | 3.12.2 |
| DevTools | 2.57.0 |
| 平台 | Windows，PowerShell |
| 测试模式 | `flutter test` headless widget test；确定性逻辑尺寸与 DPR=1 |

开始前两份未跟踪方案文档属于已有用户改动，本阶段未覆盖、删除、stage 或
commit 它们。

## 2. 当前实现确认

### 2.1 虚拟化与稳定 identity

- `lib/src/features/agent/presentation/widgets/agent_pane_sections.dart`
  - `_AgentConversationTimeline`：第 186 行；
  - `CustomScrollView`：第 229 行；
  - `SliverPadding`：第 235 行；
  - `SliverList`：第 237 行；
  - `SliverChildBuilderDelegate`：第 238 行；
  - `agentTimelineViewportItemKey`：第 243 行；
  - `findChildIndexCallback`：第 249 行。
- `lib/src/features/agent/presentation/agent_timeline_projection.dart`
  - `AgentTimelineViewportItem.id` 是 stable ID；
  - block ID 为 `turn scope + turn id + block id`；
  - activity ID 为 `live-activity-<turn id>`；
  - footer ID 为 `turn scope + footer + turn id`。
- `lib/src/features/agent/presentation/agent_timeline_projection_cache.dart`
  - `AgentTimelineProjectionCache.resolve` 按 turn render revision 复用 projection；
  - `retainOnly` 仅清除不可见 turn 的 projection；
  - 该缓存不保存 child 高度、prefix offset 或 layout epoch。

当前列表确实是 render-block 粒度的虚拟列表，但未布局 child 的高度仍由默认
`SliverList` 估算。

### 2.2 滚动与 auto-scroll 链路

- `lib/src/features/agent/presentation/agent_pane.dart`
  - `_autoScrollBottomThreshold = 48`：第 86 行；
  - `_scrollController`：第 94 行；
  - `_stickToBottom`：第 99 行；
  - `_shouldStickToBottom`：第 577 行；
  - `_distanceToBottom = maxScrollExtent - pixels`：第 584～586 行；
  - `_scrollToEnd`：第 589 行；
  - reduce motion 时 `jumpTo(maxScrollExtent)`：第 596 行；
  - 其余情况用 180ms `animateTo(maxScrollExtent)`：第 599～603 行。
- `lib/src/features/agent/application/agent_conversation_ui_signals.dart`
  - `autoScrollTickListenable`：第 64 行；
  - `scheduleStreamFlush`：第 107 行；
  - 16ms 合并 timer：第 121～124 行；
  - 合并后的 `scheduledAutoScroll` 在第 147、164 行发布。

因此当前链路是：

```text
stream delta
  -> 16ms UI signal 合并
  -> autoScroll tick
  -> _shouldStickToBottom（48px）
  -> post-frame animateTo/jumpTo(current maxScrollExtent)
```

### 2.3 现有测试覆盖

- `agent_timeline_virtualization_test.dart` 已验证首帧不构建全部 child，以及
  prepend 后 stable key 保留 State。
- `agent_conversation_widget_test.dart` 已验证 command group 展开后的 scroll
  pixels、file edit 展开渲染，以及手动上滚后 streaming 不抢回。
- `agent_pane_pr3_test.dart` 和 `ide_shell_widget_test.dart` 覆盖 resize、页面切换、
  Agent Canvas/controller/草稿与面板状态保留。
- 阶段 0 前的测试没有统一采集 `maxScrollExtent`、normalized offset、stable
  anchor 的 viewport top 与 built child count；展开测试主要断言 scroll pixels，
  未同时断言原稳定 item 的视觉坐标。

## 3. Fixture 与指标定义

### 3.1 统一指标

`test/support/scroll_metrics_trace.dart` 新增只依赖 Flutter 测试树的
`ScrollMetricsSample`：

```text
label / step
pixels / maxScrollExtent / viewportDimension
extentBefore / extentAfter / endDistance
normalizedOffset = maxScrollExtent <= 0 ? 0 : pixels / maxScrollExtent
firstVisibleItemId / firstVisibleItemTop
trackedAnchorId / trackedAnchorTop
builtChildCount / visibleChildCount
```

采样从 `ScrollableState.position`、stable `ValueKey` 和 render box 坐标读取，
不写 controller、不改变滚动位置。完整 trace 只在
`ZETA_SCROLL_BASELINE_DIAGNOSTICS=true` 时通过 `dart:developer` 开启；如同时提供
`ZETA_SCROLL_BASELINE_TRACE_PATH`，可写入 Git 忽略的临时路径。普通
`flutter test` 不输出高频诊断。

### 3.2 场景 A：混合高度虚拟列表

- 2,000 项，stable key 为 `baseline-item-<index>`。
- index 0～59 交替使用 24、80。
- index 60 起重复使用 2,000、32、600、48、24、80。
- viewport：400×600，DPR=1。
- 动作：首帧 → jump 1,800 → jump 2,600（首次布局极高项）→ 重复跟随当前
  max extent 到列表末尾。

### 3.3 场景 B：真实 Agent streaming

- 使用现有 `MainApp + FakeAgentProvider + AgentPane` fixture。
- 24 条固定 ID 历史消息，live Markdown 初始 180 行。
- viewport：1,400×700；timeline viewportDimension 实测 495.880。
- 底部连续追加 3 次，每次固定增长 60px；然后手动 jump 到顶部，再追加一次。
- 记录 4 次 auto-scroll tick 等价通知。

### 3.4 场景 C：真实 command/file edit group

- 使用现有 Agent history mapper、grouping、production card 和 `AgentPane`。
- command group 位于稳定 anchor 之前；file edit group 位于 anchor 之后。
- viewport：1,000×450；timeline viewportDimension 实测 257.880。
- command 与 file edit 都采集 collapsed、动画中、expanded、再次 collapsed。
- stable tracked anchor：
  `history-block-turn-baseline-message-history-anchor`。

### 3.5 场景 D：宽度变化

- 300 条可换行的确定性长文本，stable key 为 `width-item-<index>`。
- 每项包含 12 次固定长句，足以在窄宽度发生换行。
- viewport 高度 600，滚动到 pixels=2,400。
- 动作：宽 1,400 → 700 → 1,400，每次等待 settle。

## 4. 场景 A～D 指标

### 4.1 场景 A

| step | pixels | maxScrollExtent | viewport | normalized | first anchor / top | built / visible |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| initial | 0.000 | 100,105.882 | 600.000 | 0.000000 | `0` / 0.000 | 17 / 12 |
| before extreme | 1,800.000 | 105,771.478 | 600.000 | 0.017018 | `35` / -8.000 | 23 / 12 |
| after extreme | 2,600.000 | 344,814.500 | 600.000 | 0.007540 | `50` / 0.000 | 16 / 11 |
| transient end estimate | 344,814.500 | 1,167,749.714 | 600.000 | 0.295281 | `794` / -14.500 | 7 / 2 |
| settled end | 903,784.000 | 903,784.000 | 600.000 | 1.000000 | `1998` / -1,432.000 | 2 / 2 |

首次进入极高 item 的滚动动作只增加 800px，但 `maxScrollExtent` 增加
239,043.022px，远大于普通 24/80px 短项。与此同时 normalized offset 从
0.017018 反向降到 0.007540。它直接复现了内容继续向下移动、thumb proxy
停滞或反向跳变的根因。

首帧只存活 17/2,000 child，当前实现仍保持虚拟化。末尾定位过程中估算曾从
1,167,749.714 回落到最终 903,784.000，也证明 max extent 会随新高度样本继续
重估，而不是稳定的内容高度模型。

### 4.2 场景 B

| step | pixels | maxScrollExtent | end distance | first anchor / top | built / visible |
| --- | ---: | ---: | ---: | --- | ---: |
| bottom before | 3,748.120 | 3,748.120 | 0.000 | live message / -3,207.120 | 3 / 3 |
| bottom growth 0 | 3,808.120 | 3,808.120 | 0.000 | live message / -3,267.120 | 3 / 3 |
| bottom growth 1 | 3,868.120 | 3,868.120 | 0.000 | live message / -3,327.120 | 3 / 3 |
| bottom growth 2 | 3,928.120 | 3,928.120 | 0.000 | live message / -3,387.120 | 3 / 3 |
| free before | 0.000 | 4,224.453 | 4,224.453 | fixed history 0 / 16.000 | 27 / 24 |
| free after | 0.000 | 4,353.342 | 4,353.342 | fixed history 0 / 16.000 | 27 / 24 |

结论：

- 底部时 3 次增长均 settle 到 end distance 0，当前 fixture 下 bottom follow
  稳定到达最新末尾。
- 手动离开底部后，pixels 保持 0，stable anchor ID/top 保持不变，没有被抢回。
- free 场景更新前 end distance 4,224.453，远大于 48px threshold，因此
  `_shouldStickToBottom` 为 false。
- 4 次受控 delta 产生 4 次等价 auto-scroll 通知。底部连续目标依次为
  3,808.120、3,868.120、3,928.120；结合生产代码，每个符合 threshold 的 tick
  都会创建新的 post-frame `animateTo/jumpTo` 目标。测试按受控帧 settle，不声称
  已直接统计重叠动画实例。

### 4.3 场景 C

| step | pixels | maxScrollExtent | tracked anchor top | built / visible |
| --- | ---: | ---: | ---: | ---: |
| command collapsed | 282.000 | 486.120 | 0.000 | 35 / 13 |
| command mid-animation | 282.000 | 531.933 | 45.813 | 35 / 12 |
| command expanded | 282.000 | 536.120 | 50.000 | 35 / 11 |
| command collapsed again | 282.000 | 486.120 | 0.000 | 35 / 13 |
| file collapsed | 282.000 | 486.120 | 0.000 | 35 / 13 |
| file mid-animation | 282.000 | 515.440 | 0.000 | 35 / 11 |
| file expanded | 282.000 | 518.120 | 0.000 | 35 / 11 |
| file collapsed again | 282.000 | 486.120 | 0.000 | 35 / 13 |

锚点前 command group 增高 50px 时 pixels 完全不变，原 stable anchor 的
viewport top 从 0 漂到 50px；动画中已经漂到 45.813px。当前没有锚点补偿。

锚点后的 file edit group 增高 32px 时 pixels 与原 anchor top 均保持不变。
新增 characterization test 同时验证 pixels 和 stable item 视觉坐标，补足了现有
测试只关注 pixels/渲染结果的缺口。

### 4.4 场景 D

| width | pixels | maxScrollExtent | viewport | first anchor / top | built / visible |
| ---: | ---: | ---: | ---: | --- | ---: |
| 1,400 | 2,400.000 | 58,200.000 | 600.000 | `12` / -48.000 | 7 / 4 |
| 700 | 2,400.000 | 110,400.000 | 600.000 | `11` / -64.000 | 4 / 2 |
| 1,400 restored | 2,400.000 | 58,200.000 | 600.000 | `12` / -48.000 | 7 / 4 |

宽度减半时全局 `maxScrollExtent` 增加 52,200px（+89.69%），pixels 不变但
首个可见 ID 从 12 漂到 11，top 从 -48 漂到 -64。恢复原宽度后本 fixture 的
metrics 精确回到原值。当前唯一的 projection cache 不缓存 child 高度，因此没有
可供阶段 2 直接复用的高度缓存；恢复来自相同宽度下重新布局与相同估算样本。

## 5. 根因证据

1. **max extent 全局重估**：场景 A 在 800px 滚动内将 max extent 从
   105,771.478 修正到 344,814.500；滚到末尾又从 1,167,749.714 收敛到
   903,784.000。
2. **thumb proxy 停滞/突变**：场景 A 的 pixels 增加 800px，normalized offset
   却从 0.017018 降到 0.007540。
3. **anchor 漂移**：场景 C 的 command group 在 anchor 前增高 50px，pixels
   不变，anchor top 同量漂移 50px；场景 D 的 resize 还导致首个可见 ID 改变。
4. **bottom lock 现状**：场景 B 位于底部时每次增长均保持 end distance 0；
   离底 4,224.453px 后更新保持 pixels=0 和 anchor top=16，不被抢回。
5. **根因定位**：默认 `SliverList` 缺少逐 item 的 offscreen extent 模型；
   projection cache 只缓存 render block；bottom lock 又把每个 tick 的目标绑定到
   正在变化的 `maxScrollExtent`。数据与详设第 3 章假设一致。

## 6. 测试与验证命令

| 命令 | 退出码 | 结果 |
| --- | ---: | --- |
| `dart format .` | 0 | 304 files，0 changed |
| `flutter analyze` | 0 | No issues found |
| `flutter test test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart`（第 1 次） | 0 | 4/4 passed |
| 同上（第 2 次） | 0 | 4/4 passed |
| 同上（第 3 次） | 0 | 4/4 passed |
| `flutter test test/src/features/agent/presentation/agent_timeline_virtualization_test.dart` | 0 | 2/2 passed |
| `flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart` | 0 | 34/34 passed |
| `flutter test` | 0 | 819/819 passed |
| diagnostic baseline（显式 diagnostics + ignored trace path） | 0 | 4/4 passed，生成本报告数值 |
| `git diff --check` | 0 | 无 whitespace error |
| `git status --short` | 0 | 仅方案文档、基线报告和新增测试文件；见第 7 节 |

实施中有两类已修复的阶段内失败：

- 首轮 fixture 校准时，free 场景用绝对 `<40px` 断言忽略了尚未 settle 的旧动画，
  command anchor key 也少了 `message-` 前缀；两者均改为等待稳定 metrics 和使用
  实际 stable key。最终连续 3 次均通过。
- 首次 `flutter analyze` 因新增测试使用 deprecated `binding.window` API 返回
  10 条 info、退出码 1；改用 `tester.view` 后重新运行，退出码 0、无问题。

这些失败均由阶段 0 测试开发过程引入并已消除，不是既有产品失败。

## 7. 阶段 0 改动清单

| 文件 | 修改类型 | 内容 | 影响生产行为 |
| --- | --- | --- | --- |
| `test/support/scroll_metrics_trace.dart` | 新增 | 统一 metrics/anchor/build 采样与显式诊断 trace | 否 |
| `test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart` | 新增 | A～D 确定性 characterization fixtures | 否 |
| `plan/Agent_时间线动态虚拟滚动阶段0基线报告.md` | 新增 | 基线数据、根因证据、门禁结论 | 否 |

生产代码零修改；未新增依赖；未修改 Provider、domain、timeline store、
projection identity、持久化、滚动条或 `_stickToBottom/_scrollToEnd`。

阶段结束时预期 dirty files：

```text
?? plan/Agent_时间线动态虚拟滚动阶段0基线报告.md
?? plan/Agent_时间线动态虚拟滚动阶段0执行提示词.md
?? plan/Agent_时间线动态高度虚拟滚动与滚动条详细设计.md
?? test/src/features/agent/presentation/agent_timeline_scroll_baseline_test.dart
?? test/support/scroll_metrics_trace.dart
```

其中执行提示词与总详设为开始前已有用户文件。

## 8. 已知限制与未覆盖项

- 自动化测试使用 normalized offset 作为 scrollbar thumb 位置代理，没有断言
  `RawScrollbar` 私有绘制常量；这符合阶段 0 的 metrics-first 要求。
- 问题已在 headless widget test 稳定复现，因此未额外运行 Windows profile，
  也未提交 DevTools trace 或截图。
- 场景 B 记录了 auto-scroll tick 数、每次变化后的目标和最终位置，但没有给
  `ScrollController.animateTo` 打补丁统计重叠动画对象；生产调用链和变化目标已
  足以作为阶段 0 证据。
- 场景 C 使用真实 production command/file edit cards，但 fixture 总量较小，
  built count 不是场景 C 的性能预算；2,000 项虚拟化预算由场景 A 单独覆盖。
- 阶段 0 不评价未来 extent index、RenderSliver、scrollbar 或 coordinator 的效果。

## 9. 阶段门禁结论

| # | 门禁 | 状态 | 证据 |
| ---: | --- | --- | --- |
| 1 | A 动态高度估算变化可重复 | 通过 | 连续 3 次测试通过；105,771.478 → 344,814.500 |
| 2 | B、C、D 有自动化证据 | 通过 | 三场景均为默认通过的 widget characterization |
| 3 | 记录 pixels/max/viewport/anchor/build | 通过 | `ScrollMetricsSample` 与第 4 节表格 |
| 4 | 未改变生产滚动行为 | 通过 | `lib/` 零修改 |
| 5 | characterization tests 默认通过 | 通过 | baseline 4/4 |
| 6 | 新增测试连续 3 次通过 | 通过 | 三次均退出码 0 |
| 7 | `flutter analyze` 通过 | 通过 | No issues found |
| 8 | 全量 `flutter test` 通过 | 通过 | 819/819 |
| 9 | 基线报告完整 | 通过 | 本报告 |
| 10 | 阶段 1 输入充分 | 通过 | stable ID、误差规模、边界与测试预算均已量化 |

```text
下一阶段是否可以开始：是
```

## 10. 阶段 1 建议输入

阶段 1 应保持纯 Dart，不接入 Agent UI。关键输入：

- 2,000 项初始只构建 17 个 child，必须保留虚拟化；
- 一次 2,000px 极端样本令默认 max extent 放大 239,043.022px，说明未知项不能
  被新的全局平均值批量重估；
- 单项 point update 的总高度变化必须严格等于 `measured - effective`；
- stable ID synchronize 必须跨不可变 projection snapshot 复用 record；
- width/layout epoch 变化应保留旧高度作 stale estimate，不能批量归零；
- prefix、lower-bound、0 高度、duplicate ID、NaN/Infinity、prepend/remove/
  reorder 和 10,000 次随机 update 必须按详设第 19.1 节覆盖；
- 阶段 1 不实现 anchor correction。场景 C 的 50px 漂移留给阶段 2 反转；
- 阶段 1 不改变场景 B 的 48px threshold 或逐 tick animate 行为。
