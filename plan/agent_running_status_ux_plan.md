# Agent 执行中状态体验方案

最后更新: 2026-07-13

## 0. 文档目的

本文整合近期关于 **Codex thread 执行中 UI** 的问题排查、已落地改动与后续方案讨论，形成统一设计与分阶段落地计划。

本文回答：

1. 执行中为什么难以判断「还在动」还是「卡住 / 在等人」？
2. 标题栏、thread 列表、时间线、footer 应如何分层展示状态？
3. 「思考了多久 / 命令跑了多久 / 本轮跑了多久」如何在现有架构下实现？
4. 按什么优先级落地，避免误报、整页狂刷与协议泄漏？

**范围：**

- 主路径：`features/agent` 会话面板 + `project_threads` / 项目列表中的 thread 行。
- 不改 app-server 协议也可先做出可用体验；协议字段仅作终态校准。

**非目标（本阶段）：**

- 精确预测模型剩余时间。
- 硬判定「进程已死锁」（仅做软提示）。
- 为历史会话伪造不存在的时间戳。

---

## 1. 背景与用户问题

### 1.1 用户可感知问题

| 现象 | 影响 |
| --- | --- |
| 执行中只有 spinner，信息同质 | 无法区分思考、跑命令、等首 token、真静默 |
| 等待审批/输入与「模型工作中」观感接近 | 可行动状态不够醒目 |
| 看不到「已经跑了多久」 | 难判断是正常长任务还是异常拖住 |
| 上下文进度环曾不刷新 | 占用比与右上角 token 不同步（已修） |

用户真正想回答的三个问题：

1. **在等人吗？**（审批 / 输入）
2. **在干什么？**（思考 / 回复 / 命令 / 启动中）
3. **多久了 / 多久没动静？**（时长 + 存活感）

### 1.2 近期相关改动（已完成）

#### A. 上下文窗口进度环不刷新 —— ✅ 已修

- **根因：** UI 分区刷新中，`AgentTokenUsageEvent` 只调度 `header`，composer 不重建。
- **上下文环** 在 composer（`currentThreadLastTokenUsage`），监听 `composerVersion`。
- **会话总 token** 在 header，故会刷新。
- **修复：** `scheduleStreamFlush` 支持 `composer`；token 事件改为  
  `_scheduleStreamFlush(header: true, composer: true)`。

#### B. 执行中图标改为圆形进度 —— ✅ 已落地

- 标题栏与 thread 列表统一使用 `IdeBusySpinner`（不定进度 `CircularProgressIndicator`）。
- 替代静态 `Icons.autorenew_rounded`。
- 测试注意：无限动画不可 `pumpAndSettle`，改用 `pump` / 固定时长。

以上为基础设施；**相位、时长、存活提示** 仍属本文后续方案。

---

## 2. 现状盘点

### 2.1 状态展示（改动前 / 当前基线）

| 状态 | 标题栏 | Thread 列表 |
| --- | --- | --- |
| 等待审批 | 状态胶囊「等待审批」 | 橙色文案「等待审批」 |
| 等待输入 | 状态胶囊「等待输入」 | 橙色文案「等待输入」 |
| 系统错误 | 状态胶囊「系统错误」 | — |
| 其余 running | 仅 `IdeBusySpinner` | 仅 `IdeBusySpinner` |
| 空闲 | — | 相对时间（如 `5m`） |

关键逻辑：

- `showRunningIndicator = isTurnRunning && threadStatusCapsuleLabel == null`
- 列表 `isBusy = active || waitingOnApproval || waitingOnUserInput`
- 等待态已优先于普通 spinner；**工作中子相位未建模**

### 2.2 协议与本地已有信号（未充分用于 UI）

| 信号 | 来源 | 当前用途 |
| --- | --- | --- |
| `thread/status/changed` + waiting flags | 协议 | 胶囊 / 列表等待文案 |
| turn `startedAt` / 完成时 `duration` | timeline | footer 终态耗时；running 时多不涨秒 |
| message / reasoning / plan delta | 流式事件 | 时间线内容；不驱动头栏相位 |
| tool `pending/inProgress/completed` + title | 工具卡 | 卡内状态；无 `startedAt` |
| `thread/tokenUsage/updated` | 协议 | header 总 token + composer 上下文环 |
| turn footer「进行中 · Xs」 | UI 文案已预留 | running 时 `duration` 常为 null → 只显示「进行中」 |

### 2.3 UI 分区刷新架构（约束）

`AgentConversationUiSignals` 将刷新拆成：

- `history` / `header` / `composer` / `expansion` / `liveTurn` / `autoScroll`

流式路径以 **事件驱动 + 16ms 节流** 为主，**没有每秒时钟源**。

含义：

- 相位/对象变化 → 应走现有 header / live 信号。
- **仅秒数 +1** → 必须用局部 ticker，禁止整 VM `notifyListeners` 每秒狂刷。

### 2.4 时长相关代码锚点

| 能力 | 位置 | 说明 |
| --- | --- | --- |
| Turn `startedAt` / `duration` | `AgentConversationTurnState` | pending live turn 时写 `startedAt`；完成时冻结 |
| Footer 文案 | `_turnDurationLabel` | running 预留「进行中 · duration」 |
| 格式化 | `_formatDuration` | `12s` / `1m 5s` |
| Tool 模型 | `AgentToolCall` | **无** `startedAt` / `duration` |
| Reasoning | → `AgentToolKind.think` 卡 | 与工具卡同路径，可统一 item 计时 |

---

## 3. 目标体验

### 3.1 信息架构

```text
Turn 生命周期
├─ 等待人
│  ├─ 等待审批
│  └─ 等待输入
├─ 工作中
│  ├─ 启动中（turn 已起、尚无产出）
│  ├─ 思考中（reasoning）
│  ├─ 回复中（agent message 流）
│  └─ 工具执行中（带工具短标题，如命令）
└─ 工作中但静默
   ├─ 暂无新输出（软）
   └─ 可能较慢（更软 warning + 可取消）
```

### 3.2 三种时长（勿混为一个数字）

| 名称 | 含义 | 典型文案 | 起止 |
| --- | --- | --- | --- |
| **Turn elapsed** | 本轮从发出到现在/结束 | `运行 1m 12s`；footer `进行中 · 1m 12s` | turn.startedAt → now / completed |
| **Segment elapsed** | 当前主活动段 | `思考中 · 24s`；`执行 · git status · 8s` | 进入相位 → 离开相位 |
| **Item elapsed** | 单条思考/工具卡 | 卡旁 `12s` | item 首次出现或 inProgress → completed |

展示分工：

| 表面 | 优先展示 |
| --- | --- |
| 标题栏 | 主 segment 文案 + segment 或 turn 时长 |
| Thread 列表 | 短标签 + 可选短时长；详情放 tooltip |
| 时间线卡片 | Item elapsed |
| Turn footer | Turn elapsed（结束后冻结） |
| Composer 侧 | 可选：取消旁 `运行中 · 24s` |

### 3.3 展示优先级（同屏信息有限时）

1. 是否等人（最高，可行动）
2. 当前相位 + 对象（在干什么）
3. 已运行 / 本段时长
4. 静默 / 存活提示
5. 「可能较慢」软警告（最低频）

### 3.4 设计原则

1. **默认真值**：只展示事件能支撑的结论，不猜模型内心。
2. **静默 ≠ 失败**：长推理合法；用「暂无新输出」，不用「已卡死」。
3. **列表从简、详情从详**。
4. **可行动优先于装饰**：等待态要能到达审批/输入；可疑静默要能取消。
5. **分区刷新兼容**：秒级 tick 局部重建；相位变化才 bump header/live。
6. **中立模型**：计时与相位在 application/timeline；UI 不解析 Codex raw。
7. **本地时钟为主，协议 duration 为辅**：进行中用 `now - startedAt`；结束优先 provider duration。

---

## 4. 活动相位（Phase）模型

### 4.1 相位枚举（建议）

| 相位 | 含义 | 判定线索（现有事件） |
| --- | --- | --- |
| `waitingApproval` | 等人批 | `waitingOnApproval` |
| `waitingUserInput` | 等人答 | `waitingOnUserInput` |
| `starting` | turn 已起、无产出 | turn running 且无 delta/tool |
| `thinking` | 推理中 | reasoning delta / think 卡 inProgress |
| `responding` | 写回复 | agent message delta |
| `toolRunning` | 工具执行 | tool `inProgress`（execute/read/edit/…） |
| `silent` | 仍 running 但一段时间无事件 | 启发式 |
| `systemError` | 系统错误 | runtime status |
| `idle` | 非 running | — |

### 4.2 主 segment 优先级（标题栏只显示一个主态）

```text
waitingApproval / waitingUserInput
  > toolRunning
  > responding
  > thinking
  > starting
  > silent（覆盖在工作中之上的软态，或作为修饰）
```

同一时刻可能多工具/边想边写：标题栏只显示主 segment；各卡各自 item 计时。

### 4.3 文案示例（中文，可再定稿）

| 相位 | 标题栏 | 列表短标签 |
| --- | --- | --- |
| 等待审批 | 等待审批 | 等待 |
| 等待输入 | 等待输入 | 输入 |
| 启动中 | 启动中 · 3s | 启动 |
| 思考中 | 思考中 · 24s | 思考 |
| 回复中 | 回复中 · 12s | 回复 |
| 工具 | 执行中 · npm test · 8s | 命令 / 工具 |
| 静默 | 暂无新输出 · 45s | 静默 |
| 可能较慢 | 可能较慢，可取消 · 3m | 慢 |

无明确 segment 时回退：`运行中 · {turnElapsed}`。

### 4.4 颜色语义

| 语义 | 色 | 场景 |
| --- | --- | --- |
| 活跃工作 | `accent` | 思考/回复/工具进行中 |
| 等人 | `warning` | 审批/输入（已有） |
| 静默 | `muted` 或弱 warning | 暂无新输出 |
| 错误 | error / warning | systemError、失败 |

Spinner 可随语义变色，避免永远同色转圈。

---

## 5. 时长实现方案

### 5.1 数据原则

```text
进行中：
  elapsed = now - startedAt

结束后：
  finalDuration = providerDuration ?? (completedAt - startedAt)
```

与现有 turn complete 逻辑对齐。

### 5.2 Domain / Timeline 扩展（概念）

**Turn（已有，补齐用法）：**

- `startedAt`：pending/live 启动时写入（已有）
- running 展示：不依赖写入中的 `duration`，UI 现算 elapsed
- complete：冻结 `duration`（已有）

**Tool / Think item（需扩展）：**

```text
AgentToolCall（或并列元数据）
  startedAt    // 首次观测到开始；merge 不可覆盖
  completedAt  // 可选
  duration     // 终态冻结；running 时 UI 不算它
```

- 首次 `inProgress` / 首次 reasoning delta / `item/started` → stamp `startedAt`
- completed/failed/cancelled → 冻结 duration
- merge 规则对齐现有「空 content 不覆盖」：`startedAt` **只写一次**

**Segment 快照（application 暴露给 UI）：**

```text
TurnActivitySnapshot
  phase
  label          // 如工具短标题
  segmentStartedAt
  turnStartedAt
  lastActivityAt
  primaryToolId? // 可选，用于卡片联动
```

纯函数：

```text
elapsed(now, startedAt, {completedAt, frozenDuration})
```

### 5.3 相位状态机（事件驱动，不新开协议）

```text
turn started / pending live turn
  → starting（或直接 thinking，产品可选）

reasoning delta
  → thinking，segmentStartedAt = 首次 reasoning 时间
  → 同步 think item.startedAt

agent message delta
  → responding

tool inProgress
  → toolRunning，label = tool.title
  → item.startedAt

waitingOnApproval / waitingOnUserInput
  → waiting*（时长 = 进入等待起，或单独字段）

任意上述事件
  → 刷新 lastActivityAt

turn completed / failed / interrupted
  → 冻结全部 duration，停 ticker
```

**无 reasoning 的长静默：** 不要硬显示「思考中」；显示 `运行中 · turnElapsed` 或 `等待模型 · Xs`。

### 5.4 实时刷新：ElapsedTicker

```text
┌─────────────────────────────────────┐
│ Timeline / ViewModel                │
│  turn.startedAt                     │
│  currentActivity snapshot           │
│  tool.startedAt                     │
└──────────────┬──────────────────────┘
               │ isTurnRunning 时启动
               ▼
┌─────────────────────────────────────┐
│ ElapsedTicker（约 1s）               │
│  ValueNotifier<DateTime> now        │
│  或 ValueNotifier<int> tick         │
└──────────────┬──────────────────────┘
               │ ListenableBuilder 局部包
               ▼
  Header 文案 / Tool 卡角标 / Footer / 列表行
```

**生命周期：**

- `isTurnRunning == true` → start
- turn 结束 / 切 thread / dispose → stop
- 列表：共享 1s clock，或仅可见 running 行订阅

**与分区信号关系：**

| 变化类型 | 刷新方式 |
| --- | --- |
| 相位/工具名变化 | `header` / `liveTurn` 等现有信号 |
| 仅秒数 +1 | ticker 局部 rebuild，**不** headerVersion++ |
| Token | 已有 header + composer flush |

### 5.5 各表面落地细节

#### A. Turn footer（最小改动、语义顺）

现有：

```text
进行中            →  进行中 · 24s   （startedAt 现算 + ticker）
已完成 · 1m 5s    →  保持
```

只解决 **整轮多久**。

#### B. 标题栏（主战场）

```text
[spinner] 思考中 · 24s
[spinner] 执行中 · npm test · 8s
[spinner] 运行中 · 1m 12s
```

可选副行（P1+）：`上次输出 3s 前`。

等待胶囊保持优先，不与 spinner 同时抢主位。

#### C. 时间线卡片

| 卡片 | 进行中 | 结束后 |
| --- | --- | --- |
| Think | `思考中 · 12s` | `思考 · 12s` |
| Command | `运行中 · 8s` | `8s` |
| 其他 tool | 同理 | 同理 |

#### D. Thread 列表

```text
思考 24s | 命令 | 1m+
```

需将轻量 `phase + busySince` 同步到列表状态（今日多仅为 `runningThreadIds`）。  
列表默认 **一词 + 可选时长**；hover tooltip 给 turn/segment/最后活动。

#### E. Composer / 操作区

- 取消旁小字：`运行中 · 24s`
- 静默过久：取消更显眼，或「取消并重试」
- 等待审批/输入：引导 focus/scroll 到审批卡或输入区

#### F. 时间线 status strip（可选）

Live turn 底部固定：

```text
正在执行: rg "foo" · 8s
模型生成中… · 12s
仍在运行，暂无新输出（45s）
```

比只改 header 更能回答「卡在哪一步」。

---

## 6. 存活感与「卡住」软提示

### 6.1 存活信号（lastActivityAt）

任一刷新：

- message / reasoning / plan delta
- tool 进度 / 状态变化
- token usage 更新
- thread status 变化

### 6.2 分级（阈值建议可配置，初值示意）

| 级别 | 条件示例 | UI |
| --- | --- | --- |
| 正常 | 最近 N 秒有事件 | accent spinner + 相位 + 时长 |
| 沉默 | 约 30–60s 无事件 | 文案「暂无新输出 · 45s」；spinner 弱化/变色 |
| 可疑 | 约 2–3min 无事件且无 inProgress 工具输出 | 软 warning「可能较慢，可取消」 |
| 工具长跑 | 单工具 inProgress 很久且无 outputDelta | 「命令执行中 · 已 2m」 |

**禁止：** 直接写「已卡死」。  
**配套动作：** 取消、重试、复制诊断（比纯变色更有用）。

相位可影响阈值：`starting` 零事件更敏感；`thinking` 可更长。

---

## 7. 分层与依赖方向

```text
domain
  - 可选 TurnActivityPhase / 工具 startedAt 字段
  - 纯函数 elapsed / format（可从 _formatDuration 上提复用）

application（timeline store + 可选 activity tracker）
  - 事件 stamp startedAt
  - merge 保护 startedAt
  - 维护 TurnActivitySnapshot + lastActivityAt
  - turn 完成冻结 duration

presentation
  - ElapsedTicker
  - header / list / card / footer 只读 snapshot + now
  - 不解析 provider raw

project_threads
  - 从 provider 事件或会话 VM 同步 phase / busySince
  - 列表短展示 + tooltip
```

符合 Agents.md：协议细节留在 agent data 层；UI 消费中立模型。

---

## 8. 边界与风险

| 项 | 说明 |
| --- | --- |
| 切 thread / 后台 thread | 列表时长依赖 busySince 同步，不能只靠当前选中 VM |
| merge 冲掉 startedAt | 必须只写一次 |
| pending turn 重命名 | pending → 真实 turnId 时 metadata 迁移 |
| 系统休眠 / 时钟回拨 | `DateTime.now()` 可接受跳变；极端可用 Stopwatch（历史回放更难） |
| 历史会话 | 无 startedAt 不显示 live 秒；仅终态 duration |
| 多工具并行 | 标题栏主工具；各卡独立计时 |
| 无 reasoning 模型 | 避免伪「思考中」 |
| 测试 | 无限 spinner + 1s ticker 均避免 `pumpAndSettle` 死等 |
| 误报 | 静默阈值过短会烦；先软文案、后警告 |

---

## 9. 分阶段落地

### Phase 0 — 已完成

| 项 | 状态 |
| --- | --- |
| Token 事件同时刷新 header + composer | ✅ |
| 执行中 `IdeBusySpinner`（标题栏 + 列表） | ✅ |

### Phase 1 — P0：Turn 时长 + 基础相位文案（推荐下一迭代）

**目标：** 用户立刻知道「跑了多久」和粗粒度「在干什么」。

1. **ElapsedTicker**（running 生命周期绑定）。
2. **Turn live elapsed**：footer「进行中 · Xs」；标题栏回退 `运行中 · Xs`。
3. **基础相位**（无需 item startedAt 也可启动）：
   - 等待*（已有）
   - tool inProgress → 执行中 + title
   - reasoning → 思考中
   - message delta → 回复中
   - 否则 starting / 运行中
4. 标题栏：`[spinner] {相位} · {时长}`；相位变化 bump header。
5. 测试：相位文案、时长随 `pump(1s)` 变化、等待优先于 spinner。

**非目标：** 列表完整 phase 同步、硬卡住判定、卡片级时长。

### Phase 2 — P1：Item 计时 + 存活提示

1. `AgentToolCall`（及 think）`startedAt` / 终态 duration。
2. 卡片旁 item elapsed。
3. 标题栏优先 **segment elapsed**（与主工具/思考对齐）。
4. `lastActivityAt` + 静默文案/变色（约 30–60s）。
5. 可选：时间线 status strip。

### Phase 3 — P1/P2：列表与操作区

1. `runningThreadIds` 扩展或并列：`phase` / `busySince` / 短 label。
2. 列表短标签 + 颜色 + tooltip。
3. Composer 取消旁时长；静默时强化取消。
4. 等待态 scroll/focus 到审批或输入 UI。

### Phase 4 — P2：软卡住与可观测性

1. 分级「可能较慢」（2–3min 级，文案克制）。
2. 按相位区分阈值。
3. 诊断入口（日志/复制 thread id）可选。
4. 配置项或 debug 开关（阈值）可选。

### Phase 5 — 可选增强

1. Plan 进度叙事：`计划 2/5 · 正在改 auth.dart`（依赖 plan 质量）。
2. 桌面通知：进入「等待你」时（窗口失焦）。
3. 完成/失败 toast 强化（若尚未统一）。

---

## 10. 建议的最小有效集（MVP）

若只做一轮、投入最小：

1. 标题栏：`[spinner] {相位} · {mm:ss}`  
   相位：工具名 > 思考/回复 > 启动中/运行中。
2. Turn footer：running 时用 `startedAt` 现算并 tick。
3. 静默超过约 30s：副文案「暂无新输出」，spinner 改 warning/muted。
4. 列表：同相位一词 + tooltip；等待保持橙色。
5. **先不做**硬「已卡住」。

验收标准（MVP）：

- [ ] 发送后标题栏显示运行/相位且秒数递增。
- [ ] 出现命令工具时标题栏/卡能体现执行与时长（卡级可在 P1）。
- [ ] 等待审批时不显示普通 running spinner 为主态。
- [ ] Token 上下文环与会话总 token 仍随事件刷新。
- [ ] 流式输出时不出现整页每秒闪烁。
- [ ] 相关 widget/unit 测试不依赖 `pumpAndSettle` 等待无限动画。

---

## 11. 实现检查清单（编码时）

### Application

- [ ] `TurnActivitySnapshot`（或等价）由 timeline/事件聚合
- [ ] Tool/think `startedAt` 只 stamp 一次
- [ ] pending turn 重命名保留时间元数据
- [ ] turn complete 停 ticker、冻结 duration
- [ ] `lastActivityAt` 随关键事件更新

### Presentation

- [ ] 共享 `ElapsedTicker` / `IdeBusySpinner` 语义色可选扩展
- [ ] Header / footer / card 局部 `ListenableBuilder`
- [ ] 复用/上提 `_formatDuration`（是否显示 `0s`、`>1h` 规则）
- [ ] 列表与标题栏文案表一致

### Project threads

- [ ] running 同步包含 phase/busySince（或可推导字段）
- [ ] 非当前 thread 仍能显示「在跑 + 多久」

### 测试

- [ ] ViewModel：相位迁移、startedAt 不丢、elapsed 计算
- [ ] Widget：header/list/footer 文案；`pump(Duration(seconds: 1))`
- [ ] Token 刷新回归（header + composer）
- [ ] 取消/完成后 spinner 与 ticker 消失

---

## 12. 开放决策（实现前需产品确认）

| # | 问题 | 选项 | 建议默认 |
| --- | --- | --- | --- |
| 1 | MVP 层级 | 仅 turn / turn+segment / 含 item 卡 | turn + 基础 segment |
| 2 | 无 reasoning 时长静默 | 「运行中」vs「等待模型」 | 运行中 · turnElapsed |
| 3 | 静默阈值 | 30s / 60s | 45s 文案，120s+ 再 warning |
| 4 | 列表是否显示秒数 | 仅标签 / 标签+时长 | 标签；时长放 tooltip 或 `1m+` |
| 5 | 文案语言 | 中文 / 中英 | 与现网一致（中文胶囊 + 英文部分 UI 可并存，本方案新增偏中文） |
| 6 | 时长格式 | `24s` / `1m 5s` vs `0:24` | 复用现有 `Xm Ys` / `Xs` |

---

## 13. 相关代码索引

| 区域 | 路径 |
| --- | --- |
| 分区刷新 | `lib/src/features/agent/application/agent_conversation_ui_signals.dart` |
| Timeline / turn 状态 | `lib/src/features/agent/application/agent_conversation_timeline_store.dart` |
| VM 事件与 token flush | `lib/src/features/agent/presentation/agent_conversation_view_model.dart` |
| 标题栏 | `lib/src/features/agent/presentation/widgets/agent_pane_header.dart` |
| Footer / 时长文案 | `lib/src/features/agent/presentation/widgets/agent_pane_messages.dart` |
| 格式化 | `lib/src/features/agent/presentation/widgets/agent_pane_styles.dart` |
| Composer 上下文环 | `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` |
| Busy spinner | `lib/src/ui/core/pane_widgets.dart`（`IdeBusySpinner`） |
| Thread 列表 | `lib/src/ui/features/ide/views/project_list_pane.dart` |
| Thread 运行集 | `lib/src/features/project_threads/` |
| 工具模型 | `lib/src/features/agent/domain/agent_tool_models.dart` |
| 线程状态 | `lib/src/features/agent/domain/agent_thread_models.dart` |

---

## 14. 文档修订记录

| 日期 | 说明 |
| --- | --- |
| 2026-07-13 | 初版：合并上下文环修复、BusySpinner、进行中增强与时长实现方案，输出分阶段计划 |

---

## 15. 一句话总结

> 在现有分区刷新与 timeline 之上，用 **事件驱动的活动相位 + 本地 `startedAt` + 1 秒局部 ticker** 展示「在干什么、多久了、多久没动静」；等待人优先、静默软提示、协议 duration 仅校准终态——先做标题栏/footer 的 turn+segment，再延伸到工具卡与 thread 列表。
