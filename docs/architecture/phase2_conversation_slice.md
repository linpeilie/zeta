# Phase 2 开工文档：Agent Conversation 切片

> 对应 [目标架构 §14 Phase 2](target_architecture_riverpod_mvi_plugins_packages.md)。
> 这份文档是 Phase 2 的**前置条件交付物**，不是实现记录：先把字段映射钉死、把
> [§15 十条门禁](target_architecture_riverpod_mvi_plugins_packages.md) 答完，再动代码。
>
> 规则优先级：`AGENTS.md` > `engineering_standards.md` > 本文件。

---

## 0. 前置条件对照

| Phase 2 前置条件 | 状态 |
| --- | --- |
| Phase 1 Package / DI 边界稳定 | ✅ 5 个包已拆出，边界图守卫在 CI |
| conversation canonical signature 与性能基线固定 | ✅ `grok_live_history_canonical_test` + [Phase 0 基线](phase0_observability_baseline.md) §2.2 |
| `AgentConversationUiStateStore` 与新 slice 字段一一映射，不新增业务事实 | ✅ 本文件 §2 |

---

## 1. 迁移范围

### 1.1 迁

单个 Agent Conversation 的 **presentation / application 外壳**：

- 新建 `AgentConversationSliceState`（§2 的五个 region 合成一个不可变切片）；
- 新建 keyed `AgentConversationIntent` + 薄 `AgentConversationStore` + Riverpod family adapter（§4）；
- adapter 作为现有 `AgentConversationUiStateStore` 的**只读消费者**：把同一帧的 region 更新合成一次 slice transition；
- `AgentPane` 子树改用 selector 订阅（现在是 `viewModel.<region>StateListenable`）；
- 发送 / 取消 / 审批 / 提问 / Plan 仍调用现有 application port，但统一经 Intent → effect 路径；
- 只迁**一个** conversation workspace entry，旧 ViewModel 直连路径保留为 feature flag 回退。

### 1.2 不迁（本阶段明确不动）

| 不动 | 理由 |
| --- | --- |
| `AgentEventPipeline` / `CoalescingPolicy` / `CoalescingEventBuffer` / `BoundedEventDispatcher` / `AgentConversationTimelineStore` | G1 内容冻结五文件；Phase 2 目标是外壳，不是管线 |
| reducer identity、entryId、segment / phase 归属 | G2；改这些会让 canonical signature 失效 |
| Provider 协议 / CLI 基线升级 | 与本阶段正交，同期改会让回归定位不了 |
| Conversation UI 视觉与布局 | 同上 |
| 多 conversation / settings / workspace 同时迁 | Phase 3 分批 |
| `zeta_agent_core` 的 `flutter/foundation` 依赖（17 文件） | 随 Phase 2/3 切片自然消解，本阶段不专门清 |

---

## 2. 字段映射（`AgentConversationUiStateStore` → `AgentConversationSliceState`）

### 2.1 关键前提：五个 region 已经是纯派生

`AgentConversationViewModel` 的五个 `_build*State()` 全部是**无副作用的读取组合**，数据只来自三处：

1. `AgentConversationTimelineStore`（会话事实的 owner）；
2. ViewModel 自己的标量字段（thread 级 UI 事实）；
3. 三个既有 controller（conversation mode / permission selection / plan execution handoff）。

因此切片可以由**同样的输入**组装，**不新增任何业务事实**——这是"字段一一映射"这条前置条件成立的根据。

### 2.2 Header → `slice.header`

| 现有字段 | slice 字段 | 事实 owner | 备注 |
| --- | --- | --- | --- |
| `title` | 同名 | ViewModel `_currentThreadTitle` | thread 标题，非会话正文 |
| `threadOpenPhase` | 同名 | ViewModel `_threadOpenPhase` | 打开阶段枚举 |
| `systemNoticeLabel` | 同名 | ViewModel `_modelRerouteNotice` | 已本地化标签 |
| `statusCapsuleLabel` | 同名 | ViewModel 派生 | 已本地化标签 |
| `waitingOnApproval` / `waitingOnUserInput` | 同名 | ViewModel thread 标量 | |
| `showRunningIndicator` / `runningActivityLabel` | 同名 | TimelineStore `currentActivity` + 文本目录 | 标签由 `AgentUiTextCatalog` 产出 |
| `segmentStartedAt` / `turnStartedAt` | 同名 | TimelineStore | UI 按 now 现算 elapsed，切片不存 duration |
| `tokenUsage` | 同名 | TimelineStore `currentThreadTokenUsage` | 数值型，非正文 |
| `isTurnRunning` / `isReadOnly` / `canFork` / `canRename` / `canArchive` / `isPlanMode` | 同名 | ViewModel 派生（含 capability） | 能力位按 G4 来自 capability，不猜 |

### 2.3 Composer → `slice.composer`

| 现有字段 | slice 字段 | 事实 owner |
| --- | --- | --- |
| `canSubmitMessage` / `isTurnRunning` / `threadOpenPhase` / `isReadOnly` | 同名 | ViewModel 派生 |
| `contextUsage` | 同名 | TimelineStore 末次 token usage |
| `canAttachImages` / `canMentionResources` / `canUseSkills` | 同名 | Provider capability（G4） |
| `conversationModeStatus` / `conversationModeOptions` / `selectedConversationMode` / `conversationModeAppliesToNextTurn` / `conversationModeStatusMessage` / `conversationModeContextId` | 同名 | `AgentConversationModeController` |
| `showModelSelection` / `modelConfigState` | 同名 | 模型配置 UI 状态（已是不可变类型） |
| `showPermissionPolicy` / `permissionPolicyLabel` / `permissionOptions` / `selectedPermissionOptionId` / `permissionApplyScopeHint` | 同名 | `PermissionSelectionController` |
| `sessionConfigOptions` | 同名 | ViewModel 派生 |

> **Composer 文本不进切片**。`composer_document.dart` 的编辑态仍由 Widget 层持有，切片只存 `canSubmitMessage` 这类布尔判定——否则每次按键都会触发一次 slice publish。

### 2.4 Pending interactions → `slice.pendingInteractions`

| 现有字段 | slice 字段 | 事实 owner | 备注 |
| --- | --- | --- | --- |
| `permissions` | 同名 | TimelineStore | **G5 四种语义严格隔离，不合并成一个列表** |
| `questions` | 同名 | TimelineStore | |
| `planApprovals` | 同名 | TimelineStore | |
| `planExecutionHandoff` | 同名 | `PlanExecutionHandoffController` | 第四种语义：本地执行交接 |
| `isReadOnly` | 同名 | ViewModel 派生 | |
| `autoReviewsByTurnId` / `latestDeniedAutoReview` | 同名 | ViewModel Map | guardian 审阅结果 |

### 2.5 Expansion → `slice.expansion`

| 现有字段 | slice 字段 | 事实 owner |
| --- | --- | --- |
| `toolCallIds` / `planMessageIds` / `activePlanTurnIds` / `commandGroupIds` / `fileEditItemIds` | 同名 | TimelineStore 的展开集合 |

> 展开态**继续由 TimelineStore 持有**，切片只做只读投影。它与 timeline 条目寿命绑定，搬进切片会造出第二个 owner。

### 2.6 History → `slice.history`

| 现有字段 | slice 字段 | 事实 owner | 备注 |
| --- | --- | --- | --- |
| `standbyTurn` | 同名 | TimelineStore `standbyTurnState.snapshot()` | 已有快照方法，切片存引用不复制正文 |
| `visibleTurns` | 同名 | TimelineStore `visibleHistoryTurns` | **存的是 turn group 引用，不是正文副本** |
| `threadOpenPhase` | 同名 | ViewModel | `isLoading` 是派生 getter，不单独存 |
| `providerId` / `providerKind` / `providerName` | 同名 | Provider 目录 | |

### 2.7 live turn 不进切片

`AgentUiRegion.liveTurn` 与 `liveTurnBinding` **不映射成 slice 字段**。流式 turn 的局部内容继续走
TimelineStore 的 `liveTurnState` + 局部重建路径（目标架构 §6.3 的流式专用路径）。

理由：把流式 delta 灌进 Riverpod 状态树，等于让每个 token 触发一次全局 publish——直接违反
Phase 0 基线里"普通流式更新不超过一帧一次"和"Shell / Header / Composer 重建为 0"两条预算。

### 2.8 汇总

| 项 | 数量 |
| --- | ---: |
| 现有 region state 类 | 5 |
| 五个 region 的公开字段位 | 57 |
| 去重后的不同事实 | 52（`threadOpenPhase` / `isTurnRunning` / `isReadOnly` 跨 region 重复） |
| 新增业务事实 | **0** |
| 复制大正文的字段 | **0**（`visibleTurns` / `standbyTurn` 存引用） |
| 明确不进切片的 region | 2（`liveTurn` / `liveTurnBinding`） |

---

## 3. Intent 清单

命名按 [Phase 1 §3 MVI 规范](phase1_boundaries.md)：变体用**发生的事**命名，不用 `SetXxx`。

### 3.1 会话主流程

| Intent | 触发 | 现有入口 |
| --- | --- | --- |
| `SendMessageRequested` | 用户点发送 | `sendMessage(...)` |
| `ActiveTurnCancelRequested` | 用户取消 | `cancelActiveTurn()` |
| `LastUserMessageEditRequested` | 编辑并重发 | `editLastUserMessageAndRetry(...)` |
| `ThreadOpenRetried` | 打开失败重试 | `retryOpenThread()` |
| `ThreadSnapshotRefreshRequested` | 外部刷新 | `requestThreadSnapshotRefresh()` |

### 3.2 四种审批语义（G5：严格隔离，四条独立链路）

| Intent | 语义 | 现有入口 |
| --- | --- | --- |
| `PermissionResponded` | 权限 | `respondToPermission(...)` |
| `QuestionResponded` | 提问 | `respondToQuestion(...)` |
| `PlanApprovalResponded` | Plan 审批 | `respondToPlanApproval(...)` |
| `PlanExecutionStarted` / `PlanExecutionRevised` / `PlanExecutionDismissed` | Plan 执行交接 | `startPlanExecution` / `revisePlanExecution` / `dismissPlanExecution` |
| `GuardianDeniedActionApproved` | guardian 覆盖 | `approveGuardianDeniedAction()` |

> **绝不预授权**：四条链路各自独立地把用户决定回传 Provider，禁止任何一条复用另一条的已授权状态。

### 3.3 配置与目录

`ConversationModeSelected` / `ConversationModesRetried` / `ModelSelected` / `ReasoningEffortSelected` /
`ServiceTierSelected` / `FastToggled` / `PermissionOptionSelected` / `SessionConfigOptionSelected` /
`ModelCatalogLoadRequested` / `SkillsCatalogLoadRequested` / `ActiveProviderSwitched`

### 3.4 thread 管理

`ThreadForkRequested` / `ThreadRenameRequested` / `ThreadArchiveRequested` / `ThreadCompactRequested`

### 3.5 纯 UI 展开态

`ToolCallToggled` / `PlanMessageToggled` / `ActivePlanToggled` / `CommandGroupToggled` /
`FileEditItemToggled` / `ContextPanelToggled`

> 这一组只改 TimelineStore 的展开集合，reducer 里是纯状态转移，不产生 effect。

---

## 4. Effect 与 result intent

### 4.1 现存 UI effect

目前只有一个：`AgentRequestAutoScroll`（一次性、结构相等去重）。切片保持这个类型不变，
继续经 `AgentUiUpdateRequest.effects` 传递。

### 4.2 新增的切片 effect（描述，不是执行）

| Effect | 执行者 | result intent |
| --- | --- | --- |
| `SendMessageEffect` | 现有 application port | `SendMessageSucceeded` / `SendMessageFailed` |
| `CancelTurnEffect` | 同上 | `CancelTurnSucceeded` / `CancelTurnFailed` |
| `RespondPermissionEffect` / `RespondQuestionEffect` / `RespondPlanApprovalEffect` / `PlanExecutionEffect` | 同上，四条独立 | 各自的 `...Succeeded` / `...Failed` |
| `LoadModelCatalogEffect` / `LoadSkillsCatalogEffect` | 同上 | `ModelCatalogLoaded` / `SkillsCatalogLoaded` |
| `ThreadMutationEffect`（fork / rename / archive / compact） | 同上 | `ThreadMutationSucceeded` / `ThreadMutationFailed` |

规则：**reducer 纯同步**（G3），effect 只是描述；执行由 scope-aware runner 负责，回写状态只能经 result intent。

### 4.3 复用现有 scope 校验

`DefaultAgentConversationEffectRunner` 已经在每个 effect 前校验 `listenerGeneration` /
`runtimeId` / `connectionEpoch` / thread scope，且同一 effect 实例最多执行一次。切片 effect
沿用同一套 scope 语义，不另造一份。

---

## 5. 操作身份与迟到结果

| 场景 | 判定依据 |
| --- | --- |
| 发送 / 取消 / 审批 / thread 变更 | `OperationId`（`zeta_foundation`），scope 常量如 `conversation.send`；发起时存进 state，结果先比对 id 再写回 |
| Provider 事件流 | 现有 `listenerGeneration` + `runtimeId` + `connectionEpoch`，不变 |
| 目录类加载（模型 / 会话模式） | 现有单调 generation 计数器（如 `_conversationModeCatalogLoadGeneration`），迁移时换成 `OperationId` |
| 乐观用户 turn | `pending-<microseconds>` 由 **TimelineStore** 铸造，切片不参与身份分配（G2） |

`OperationId` 只含常量 scope + 进程内序号，**不含 thread id / 路径 / prompt**，可以安全进日志与指标。

---

## 6. 生命周期与 dispose 归属

| 对象 | 创建者 | 释放者 |
| --- | --- | --- |
| `AgentConversationBinding` | `AgentConversationBindingManager`（按 `AgentConversationBindingKey`，draft / thread 两种） | lease 释放 + 空闲 TTL 回收（默认 10 min，1 min 扫描） |
| Provider runtime | `AgentProviderRuntimeRegistry` | binding 释放时按 epoch 判定 |
| `AgentConversationStore`（新） | Riverpod family provider，key = `AgentConversationBindingKey` | family autoDispose 跟随 binding lease，**不早于 lease 释放** |
| `AgentConversationUiStateStore`（旧，本阶段仍在） | ViewModel | ViewModel `dispose()` |
| effect runner | binding scope | 同 binding |

**风险点（写进实现清单）**：`autoDispose` 不能把还持有 lease 的 binding 释放掉。验收测试要覆盖
"两个 thread 同时打开 → dispose 其中一个 → 另一个的 state / reducer / effect 完全不受影响"。

---

## 7. §15 门禁答卷

**1. 迁移后该业务事实的唯一 owner 是谁？**
会话事实（turns / tool calls / pending requests / 展开态 / token usage）仍归 `AgentConversationTimelineStore`；
thread 级 UI 事实（title / openPhase / waiting 标志 / 通知）归切片；配置类归三个既有 controller。
切片对前两类是**只读投影**，不产生第二个 owner。

**2. Intent、State、Effect、Result Intent 分别是什么？**
见 §3 / §2 / §4。State = `AgentConversationSliceState`（§2 的 52 个不同事实，零新增）。

**3. 是否有 raw Provider / 文件 / Flutter / Riverpod 类型越过稳定边界？**
没有。协议原文是不透明的 `AgentProviderRawPayload`，只在上下文面板展示（守卫 `agent_core_raw_payload_freeze_test`）；
`dart:io` 不进切片；Riverpod 类型只存在于 app 层 adapter，不进 `zeta_agent_core`。

**4. store、Binding、runtime、plugin 各自由谁创建和 dispose？**
见 §6。plugin 由编译期 catalog 注册、`PluginRegistry` 统一 `close()`，本阶段不变。

**5. 迟到结果用什么 operation / generation 判断？**
见 §5：命令类用 `OperationId`，事件流用 `listenerGeneration` + runtime epoch，两套不混用。

**6. 是否复制了大正文或提高了流式 publish / rebuild 频率？**
没有复制正文（§2.8）。流式路径不进切片（§2.7），普通更新仍由 `AgentUiUpdateScheduler` 合并到一帧一次。
验收以 Phase 0 §2.2 预算为准：UI region publish ≤ 400，pendingKeys ≤ 64，queue ≤ 64，
`IdeHome` / `AgentPane` / Header / Composer / Timeline 重建各 ≤ 2；
纯 message delta 与 reasoning/tool progress 子场景下 Shell / Header / Composer 重建必须为 **0**。

**7. 缓存的 source of truth、key、invalidation、budget 是什么？**
本阶段**不新增缓存**。现有 `agent_timeline_projection_cache` / `agent_file_change_projection_cache` /
`agent_markdown_cache` 保持原样，key 与失效策略不动。

**8. 持久化白名单与 schema version 是否变化？**
不变。切片是纯内存状态，不落盘。G7 白名单与现有版本号原封不动。

**9. 旧路径如何回滚、何时删除，是否存在双写？**
app 级 feature flag 二选一；新 adapter 是现有 store 的只读消费者，回滚不涉及数据迁移。
**不存在双写 owner**：同一时刻只有一条路径驱动 UI。删除旧路径排在 Phase 4。

**10. 哪些行为、契约、性能和架构测试证明迁移等价？**
见 §8。

---

## 8. 验收测试清单

| # | 测试 | 证明 |
| --- | --- | --- |
| 1 | 两 thread 并存契约测试 | 两个 Binding 的 state / reducer / effect 完全隔离 |
| 2 | dispose 隔离测试 | dispose 其一不影响另一个；lease 未释放时不被 autoDispose 回收 |
| 3 | stale generation 测试 | 迟到结果按 `OperationId` / generation 丢弃，不写回 |
| 4 | 普通 / urgent 流式测试 | 普通合并到一帧一次；urgent interaction 及时显示 |
| 5 | UiEffect exactly-once 测试 | rebuild 不重放一次性 effect |
| 6 | canonical signature 测试 | live / history 签名不变（复用 `grok_live_history_canonical_test`） |
| 7 | 四语义 wire 参数测试 | 发送 / 取消 / 审批 / 提问 / Plan 的真实 wire 参数与迁移前逐字节一致 |
| 8 | Phase 0 性能预算测试 | §7 门禁 6 的全部数值 |
| 9 | 架构守卫 | 边界图 + G1 五文件冻结 + raw payload 守卫全绿 |
| 10 | feature flag 双路径测试 | 两条路径下 Widget 行为一致 |

---

## 9. 需要你拍板的两个点

1. **feature flag 的粒度**：按 workspace entry（只有被选中的那个 conversation 走新路径）还是全局开关？
   建议前者——Phase 2 的验收标准本来就是"只迁一个 conversation workspace entry"，全局开关会让
   回退颗粒太粗。

2. **切片放哪个包**：`AgentConversationSliceState` + reducer 是放 `zeta_agent_core`（纯 Dart 语义，
   与 UI 无关），还是先落在根 app 的 `features/agent/application/`？
   建议后者——目标架构 §1.1 第 8 条"不建无人使用的抽象"，先在 app 里跑通一个真实切片，
   Phase 3 扩到第二个 feature 时再决定是否下沉。这也顺带避免给 `zeta_agent_core` 增加新的
   `flutter/foundation` 依赖面。

---

## 9.5 实施进度

两个待拍板点已定：**feature flag 按 workspace entry**、**切片先落在根 app 的
`features/agent/application/conversation_slice/`**（不下沉 `zeta_agent_core`，
避免给它增加新的 `flutter/foundation` 依赖面）。

| 增量 | 内容 | 状态 |
| --- | --- | --- |
| A | `AgentConversationSliceState` / Intent / Effect / 纯同步 reducer | ✅ 9 条 reducer 测试 |
| B | `AgentConversationSliceStore`（铸造 `OperationId`、状态不变不发布、迟到结果计数、dispose 关闭） | ✅ 10 条 store 测试 |
| C | `AgentConversationSliceBinding`：region ingress 合并 + effect 打到现有 ViewModel port | ✅ 3 条对真实 ViewModel 的接线测试 |
| D | Riverpod family：`agentConversationSliceProvider` + 五个 region selector + fail-closed 覆盖 + 开关 | ✅ 6 条 provider 测试 |
| E | `AgentPane` 子树改用 selector 订阅、workspace entry 按 flag 创建 binding | ⏳ 未开始 |
| F | 两 thread 并存 / UiEffect exactly-once / 性能预算等验收测试（§8 表） | ⏳ 未开始 |

已落地的关键不变量（都有测试钉住）：

- reducer 纯同步，不铸造 id、不碰时钟（G3）；
- 命令**不直接改 region**，只登记在途身份并产出 effect；真实变化经 ingress 回流，
  因此不存在双写 owner；
- 迟到结果按 `OperationId` 丢弃，并计入 `staleResultCount`；
- 同一批 region 变化合并成**一次**切片发布；状态未变时零发布；
- 四种审批语义各自独立作用域与独立 effect 类型（G5）；
- Riverpod 容器 dispose 只摘监听，**不释放 store**——store 寿命跟随 workspace
  entry 的 binding lease；
- 未覆盖 store 的子树读切片直接抛错，不静默降级。

E 之前不把 binding 接进 `AgentThreadWorkspaceEntry`：没有消费者就先创建对象，
等于在生产路径上挂一个没人用的监听。

---

## 10. 不做清单（重申）

- 不重写 `AgentEventPipeline` / TimelineStore / coalescing / reducer identity；
- 不升 Provider 协议或 CLI 基线；
- 不改 conversation UI 视觉与布局；
- 不同时迁 settings / workspace / 多 conversation；
- 不新增缓存、不改持久化格式。

任一条被破坏，本阶段停线重新过 §15。
