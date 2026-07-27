# Agent 时间线动态虚拟滚动阶段 5 性能验证报告

## 1. 元数据

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-07-27 |
| Git branch | `flutter` |
| Flutter | 3.44.4 / Dart 3.12.2 |
| 验证模式 | `flutter test` headless widget 测试（确定性 logical px，DPR=1） |
| 对照基线 | `plan/Agent_时间线动态虚拟滚动阶段0基线报告.md` 场景 A～D |

## 2. 阶段 5 交付物

| 交付 | 说明 |
| --- | --- |
| `test/src/ui/core/virtualization/ide_virtual_scroll_perf_test.dart` | 详设 19.6 可复现 2,000 项混合高度 + 锚点前增高 fixture |
| `IdeVirtualListController` debug 指标 | correction 次数/峰值、measurement 次数、laidOut child、measured/fresh 计数 |
| 旧路径保留注释 | `_stickToBottom` / `_scrollToEndLegacy` 与 flag 去留说明 |
| 本报告 | 相对阶段 0 的对照结论 |

## 3. 性能与稳定性对照（场景 A 同源）

### 3.1 Fixture

- 2,000 项；冷启动统一 estimate = 50 logical px。
- 真实高度：阶段 0 同源 `_mixedExtent`（前 60 项 24/80 交替；其后 2000/32/600/48/24/80 循环）。
- viewport 400×600，DPR=1。
- 实现：`IdeAnchoredDynamicSliverList` + `IdeExtentIndex`。

### 3.2 阶段 0（普通 SliverList）关键数字

| 指标 | 阶段 0 |
| --- | ---: |
| 首帧 built | 17 / 2000 |
| before extreme maxScrollExtent | 105,771 |
| after extreme maxScrollExtent | 344,815 |
| **max 跳变（滚入极高项）** | **+239,043** |
| normalized 变化 | 0.017018 → **0.007540（反降）** |
| 根因 | 新样本均值 × 大量未显示项 |

### 3.3 阶段 5 新路径验收（自动化断言）

| 指标 | 阶段 5 断言 / 观察 |
| --- | --- |
| 首帧 built | `< 100`（虚拟化保留） |
| extent records | 恒等于 2,000 |
| geometry.scrollExtent | `== extentIndex.totalExtent` |
| 滚入极高项 max 跳变 | **`< 25,000`**（远小于阶段 0 的 239k） |
| normalized 反降 | 不允许伴随巨大 max 增长的大幅反降（`< 0.05`） |
| 存活 child | laidOut / end built `< 100` |
| 锚点前增高 | viewport 偏差 **`≤ 1` logical px** |
| measuredCount | `> 0` 且 **`< 2000`**（未全量测量） |

结论：

1. **已消除“新均值 × 剩余项”式 maxScrollExtent 放大**；单项实测只按 `m - e` 修正 total。
2. **首帧仍保持虚拟化**，符合 18.2 / 20.4。
3. **锚点前增高**由 `scrollOffsetCorrection` 消化，视觉偏差 ≤ 1px（阶段 0 场景 C 曾漂 50px）。
4. 未测项仍为 estimate，滚到末尾需多跳几次跟随 max 收敛——这是“未全量测量”的预期行为，不再表现为全局均值重估。

### 3.4 复杂度复核

| 操作 | 目标 | 实现 |
| --- | --- | --- |
| point measurement | O(log n) | Fenwick `add` |
| prefix / indexAtOffset | O(log n) | Fenwick |
| totalExtent | O(1) | 维护总和 |
| synchronize | O(n) | 可接受（snapshot 级） |

## 4. 旧路径与 feature flag 评估

| 项 | 建议 |
| --- | --- |
| `kUseAnchoredDynamicTimelineSliver` | **保留默认 true 至少一个发布周期** |
| 关闭方式 | `--dart-define=ZETA_USE_ANCHORED_DYNAMIC_TIMELINE=false` |
| `_stickToBottom` / `_scrollToEndLegacy` | **保留**，仅 flag=false 使用；已加“勿删”注释 |
| 立即删除 flag / 旧路径 | **否**（违反 17.2 与阶段 5 要求） |
| 下一发布周期 | 若生产无回归，再评估删除旧路径 |

## 5. 清理项清单

| 项 | 状态 |
| --- | --- |
| 临时 patch 文件（`.tmp_*`） | 确认不在工作区 |
| debug 指标挂到 controller | 已完成（无 `print`） |
| 旧滚动 API 保留说明 | 已写入 `agent_pane` / flag 文件 |
| 不删除 flag 回退 | 遵守 |
| 不改 Provider/domain/持久化 | 遵守 |

## 6. 验证命令

| 命令 | 结果 |
| --- | --- |
| `dart format .` | 通过 |
| `flutter analyze` | 通过（见会话终验） |
| `flutter test`（含 19.6） | 通过（见会话终验） |
| `git diff --check` | 通过 |

## 7. 阶段 5 结论

**阶段 5 完成。**

- 可复现 2,000 项混合高度 fixture 已固化为自动化测试。
- 相对阶段 0，max extent 跳变与锚点漂移问题在新路径下已收敛到验收门槛内。
- feature flag 与旧 stick-to-bottom 路径明确保留一个发布周期。
- 全量静态分析与测试门禁通过后，方案可进入发布观察，而非继续大改架构。
