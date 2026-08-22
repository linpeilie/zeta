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

### 4.3 scope-aware 执行（已落地）

每个命令 effect 都携带 `AgentConversationCommandScope`——发起时的
**Binding key + runtimeId + connectionEpoch + listenerGeneration + threadId**
快照，由 store 在铸造 `OperationId` 的同一时刻拍下（组合层注入读取器，复用 ViewModel
已有的 `_currentEffectScope()`）。runner 校验两次：

| 时机 | 规则 | 理由 |
| --- | --- | --- |
| 执行前 | `matchesForExecution`：身份 + listener 代数全比 | 命令还没开始跑，代数没有理由变化 |
| 结果回写前 | `matchesForCommit`：只比身份，不比代数 | 命令自己就可能建立/重挂 listener（草稿首发要创建 session），据此判失效会把正常流程判成 `staleTarget` |

身份比对的三条容让规则，每条都对应一个真实生命周期，且都有测试：

- **draft → thread 是同一个世界**：`promoteToThread` 是同一 Binding 的一次性晋升，
  草稿发第一条消息时必然发生；内核禁止 thread key 再改绑，所以这是唯一合法迁移；
- **发起时没有 runtime**：草稿首发时 runtime 还不存在，命令的职责之一就是把它建起来；
- **当前没有 runtime**：失败后 runtime 被拆掉是"现在没有世界"，不是"换了个世界"——
  否则命令自己造成的失败会被改判成 `staleTarget`，真实失败原因就丢了。

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
**两者都要**（§6.2 原文是"operation ID、Binding、runtime identity/generation 和 disposed
状态"，是并列不是选择）：命令携带 `OperationId` **加** 作用域快照，runner 在执行前与回写
前各校验一次，见 §4.3；事件流沿用 `listenerGeneration` + runtime epoch；disposed 由 store
随 workspace entry 关闭兜住。

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
| E | `AgentPane` 子树改用 selector 订阅、workspace entry 按 flag 创建 binding | ✅ 见 §9.6 |
| F | 两 thread 并存 / UiEffect / 性能预算等验收测试（§8 表） | ✅ 见 §9.7 |

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

### review 修复：分层方向（2026-08-22）

第一版把五个 region state 从 presentation import 进 application，和
`agent_conversation_ui_state.dart → application/agent_conversation_mode_controller.dart`
形成闭环（G6）。动机是"零新增业务事实"——复用现有 region 类，避免第二份字段定义；
但这个动机不需要靠反向依赖实现。已按下面四步修正：

1. **拆 `agent_conversation_ui_state.dart`**：五个 region state 类 +
   `AgentModelConfigUiState` 移到 `application/conversation_slice/`，
   `AgentConversationUiStateStore`（`ValueNotifier` + 帧调度发布）留在 presentation。
   前者是**状态契约**，后者是**发布机制**，这条线才是分层该切的地方。
2. **Riverpod providers 移到 presentation**：目标架构 §6.2 把「Riverpod adapter」
   单列成一层，provider 不该和 reducer 挤在 application。
3. **切片核心去 Flutter 化**：state / intent / effect / reducer 四个文件现在是
   **纯 Dart**（`final class` + 全 final 字段保证不可变，相等性用
   `zeta_foundation` 的 `zetaSetEquals`）。将来要下沉 `zeta_agent_core` 不用返工。
   ~~store 仍用 `ChangeNotifier`，region state 仍用 `@immutable`——application 允许
   依赖 `flutter/foundation`~~ —— **这句话是错的**，见下一节。
4. **补 `feature_layering_guard_test`**：断言 application 不得 import
   presentation、Riverpod 只能在 presentation/app、domain 保持纯 Dart。
   两处既有反向依赖（agent / project_threads 的 workspace controller，它们负责
   构造 ViewModel）进燃尽清单，只允许变少。守卫做过 mutation 验证：把 import 加
   回去、把 riverpod 塞进 application，两条都会红。

**根因记录**：这不是留待以后处理的临时方案，是遗漏。仓库此前只有 Package 边界
守卫，没有 feature 内部分层守卫，`analyze` 和全量测试都拦不住；而既有的
`agent_thread_workspace_controller` 早就 import presentation，让这个方向看起来
像仓库常态。守卫补上后，同类问题会在 CI 上直接红。

### review 修复：application 的 Flutter 依赖与 popover 状态（2026-08-22）

上一节写的"application 允许依赖 `flutter/foundation`"**是错的**。依据是目标架构
§6.2 的分层要点（那里只点了 Domain 的纯度），但 §12「必须禁止的依赖或编码模式」
第 5 条写得很明确：

> 禁止 domain/**application** import Flutter、Riverpod、`dart:io`、generated l10n
> 或具体协议类型。

这是禁止清单里的条款，没有解释空间。**架构文档不改，改代码。**

修正内容：

1. **切片全层去 Flutter**。三个文件都是上一轮从 presentation 搬进 application 时
   把 Flutter 依赖一起带过界的（搬家前它们住 presentation，那边完全合法）：

   | 文件 | 原来的 Flutter API | 现在 |
   | --- | --- | --- |
   | `agent_model_config_ui_state.dart` | `@immutable` | `package:meta` |
   | `agent_conversation_region_state.dart` | `@immutable` / `listEquals` / `setEquals` | `package:meta` + `zetaListEquals` / `zetaSetEquals` |
   | `agent_conversation_slice_store.dart` | `ChangeNotifier` / `ValueListenable` | 自己的 listener 列表（通知前复制快照，语义与 `ChangeNotifier` 对齐） |

   根 `pubspec.yaml` 新增 `meta` 直接依赖（纯 Dart 包，不在 §12.5 的禁止之列）。

2. **popover 展开态回到 presentation**。`AgentModelConfigUiState.expandedModelId`
   按 §7.3 属于 Widget/page scope。核对后发现它在 application 侧**永远是 null**
   （ViewModel 硬编码 `expandedModelId: null`），真正赋值只发生在 popover widget
   内部——所以这是"字段定义在错误的层"，不是状态真被 application 拥有。现在拆成
   presentation 私有的 `_AgentModelConfigPopoverState { snapshot, expandedModelId }`：
   用**组合**而不是继承，且刻意不做字段转发，让"这是两层状态"在每个读取点都看得见。

3. **守卫扩到 Flutter**：`feature_layering_guard_test` 新增"application 不得 import
   Flutter"，12 个既有 `ChangeNotifier` controller 进燃尽清单（只减不增，随 Phase 2/3
   转 MVI 切片清掉）。同样做了 mutation 验证。

**根因记录**：这次不是遗漏，是**读规则读漏了一层**——只看了 §6.2 的分层要点，没有
去对 §12 的显式禁止清单，并且据此在文档里写下了一条与架构冲突的"豁免"。教训是
分层结论必须以 §12 为准，§6.2 只是解释。

### review 修复：effect 补上作用域身份（2026-08-22）

§4.3 原文声明"切片 effect 沿用内核那套 scope 校验"，**但代码里一次校验都没有**：
命令 effect 只带 `OperationId`，runner 执行前后都不看 Binding / runtime。文档描述的是
意图，不是代码。

修法见改写后的 §4.3 与门禁答卷第 5 条。三点根因记在这里：

1. **文档先写、实现没回头对**，而文档断言没有任何守卫；
2. **把并列条件读成了选择条件**：§6.2 说的是 operation ID **和** Binding **和** runtime
   identity/generation **和** disposed，我在门禁答卷里写成了"命令类用 OperationId、
   事件流用 generation，两套不混用"；
3. **`OperationId` 的唯一性给了虚假的安全感**：它只能回答"是不是同一次操作"，
   回答不了"这次操作所属的世界还在不在"。

新增 `agent_conversation_slice_scope_guard_test`：断言命令 effect 带 scope 字段、
runner 在 `await` 前后各有一次校验、快照覆盖四个维度。守卫做过 mutation 验证——删掉
回写前那次校验，守卫与端到端测试同时红。

**这是连续第三次同一模式的问题**（声明分层单向 / 声明 result intent 唯一 / 声明
scope-aware），共同缺口都是"Phase 2 文档里的断言没有守卫"。三次分别补了
`feature_layering_guard_test`、失败路径测试、本守卫。后续在文档里写下"已经做了 X"之前，
先问一句：**有什么会在 X 被破坏时变红？**

---

### review 修复：命令结果改成 typed outcome（2026-08-22）

第一版 runner 用"`Future` 有没有抛异常"判断成败。这个前提**不成立**——逐个打开被
调用方核对后：

| ViewModel 方法 | 真实失败时 | 旧 runner 看到 |
| --- | --- | --- |
| `sendMessage` | 4 处校验早退 + 3 个 catch 块吞异常 → `_markError` → 正常返回 | 成功 |
| `renameCurrentThread` | catch → 回滚标题 → `_markError` → 正常返回 | 成功 |
| `forkCurrentThread` | 失败与"不允许"都 `return null` | 成功（根本没读返回值） |
| `archiveCurrentThread` / `compactCurrentThread` | 早退 + catch 吞 | 成功 |

也就是说**每一个命令 effect 都可能把失败记成成功**。根因：我在一批没有结果契约的
port 之上发明了一个结果契约——`Future<void>` 在这些 port 里的含义是"这个动作我接下
了"，不是"这个动作成了"，它们表达失败靠的是回滚、`_markError`、`AgentErrorEvent`、
返回 `null`。

修法：

1. **新增 `AgentCommandOutcome`**（application，纯 Dart）：`succeeded` /
   `ignored(reason)` / `failed(kind, diagnostic?)`。
   - `ignored` 是必需的第三态：空输入、状态不允许这类**无操作**不该走失败分支，
     否则正常操作会弹错误提示；
   - `failed` **只有分类没有文案**，用户可见文字由 presentation 按 kind 取，
     `diagnostic` 只进日志（早期是 `error.toString()` 直接当 UI 文案，既不可
     本地化又会泄露路径/命令行，G7）。
2. **16 个命令 port 改为返回 outcome**，每个失败分支显式覆盖，不留"靠没抛异常"
   的推断。纯增量：`Future<void>` → `Future<AgentCommandOutcome>` 对现有调用方
   源码兼容。`forkCurrentThread` 保留 `AgentSession?`（它本来就带结果），由 runner
   把 `null` 翻译成失败。
3. **切片失败字段换成 typed kind**：`AgentConversationOperationFailure.message`
   → `kind`。
4. **补失败路径测试**：让 provider 抛错走进 `sendMessage` 的 catch，断言切片记的是
   失败而不是成功；空输入断言"不留在途也不报错"。反向验证过——把 runner 改回
   无条件 `completeCommand`，这条测试立刻红。

**根因记录**：不是临时方案，是三件事叠加——(a) 在没有结果契约的 port 上假设了结果
契约；(b) 写统一的 `_awaitCommand` 时一次都没打开被调用方看失败怎么处理；(c) 失败
路径没有任何测试经过（store 测试里的失败是手工调 `failCommand` 造的，测的是 reducer
不是接线）。2184 条测试全绿也拦不住，因为那条路径根本没被走过。

---

### review 修复：Provider 改成 BindingKey family（2026-08-22）

第一版把 store 用「子树 `ProviderScope` override」注入，selector 是普通
`Provider`。§6.2 要求的是 **`family` 按 `BindingKey` 隔离实例**，而且这不只是形式
问题——实测过：

```
root header: root
child header: root      // ← 子 scope 覆盖了 store，却读到父容器的会话
```

原因是不带 `dependencies` 的 provider 在**根容器**解析，嵌套 scope 里覆盖它的依赖
对它无效。也就是说同一个应用容器里开两个 workspace entry 时，**第二个会渲染第一个
的会话**。原来的测试用两个独立 `ProviderContainer`，恰好绕开了这条会出错的路径——
reviewer 对测试的判断也是对的。

改法：

- 全部 provider 改成 `Provider.family` / `NotifierProvider.family`，键是
  `AgentConversationBindingKey`（draft / thread 两种身份都覆盖）；
- 新增 `agentConversationSliceStoreResolverProvider`：组合层注入
  `BindingKey → store?` 的解析函数。它是**容器作用域的注入点**，不是全局
  service locator（§12.10）——默认实现对所有 key 返回 null；
- 启用开关不再单独维护：`agentConversationSliceEnabledProvider(key)` 的判据就是
  组合层有没有为这个 key 建 store，消掉了两处状态对不齐的可能；
- UI 镜像类 provider 打开 `autoDispose`。它们释放时只摘监听，不碰 Binding lease、
  CLI runtime 或 store 本身，因此不触犯 §12.11。

测试重写成**同一个容器、两个 key**：两个 entry 各读各的、只推一个另一个纹丝不动、
draft 与 thread 不串、`invalidate` 一个不影响另一个。

---

## 9.6 E 步进度（2026-08-22）

**已完成**

- `AgentRegionBuilder`：订阅一个 region 的**唯一接缝**。切片为该 entry 启用时走
  Riverpod selector，否则回退到 ViewModel 的 `ValueListenable`。两条路径给出的是
  同一批不可变 region 对象，所以切换只换订阅机制，不换渲染结果。
- `AgentPane` 顶层四个订阅点已切过去：header / history / composer /
  pendingInteraction。live turn 仍是 `ListenableBuilder`（§2.7：它刻意不进切片）。
- 合并订阅拆成了嵌套：原来 composer + pending + 草稿图片挤在一个
  `Listenable.merge` 里，现在各订各的——pending 变化不再重建 composer 那层。
- `AgentThreadWorkspaceEntry` 按 flag 创建 `AgentConversationSliceBinding`
  （`conversationSliceEnabled(key)`，默认 false），`dispose` 时**先释放切片再释放
  ViewModel**（切片订阅了 ViewModel 的 listenable）。控制器提供
  `sliceStoreForBinding(key)` 给 Riverpod resolver。
- **根 `ProviderScope` 从 `main.dart` 移进 `MainApp`**。原来放在外面，导致每个
  pump `MainApp` 的测试都要自己补一层，漏掉就是运行期 "No ProviderScope found"
  而不是编译期错误。移进去之后生产与测试共用同一套接线。

**深层组件也已迁完（第二批）**

`agent_pane_cards.dart`、`agent_pane_messages.dart`、`agent_pane_sections.dart`、
`agent_pane_plan_panel.dart`、`agent_pane_context_panel.dart` 里剩下的 13 处订阅
全部改走接缝。几处合并订阅顺带拆开了：

| 原来 | 现在 |
| --- | --- |
| 时间线：history + liveTurn + expansion + pending + 浮层高度一把 merge | 三个 region 各订各的，嵌一层 listenable 只管 live turn 与浮层高度 |
| Plan 浮层：liveTurn + header + pending + expansion 一把 merge | 同上 |
| 上下文面板：header + history + threadSnapshot + providerController merge | 两个 region 走 selector，thread 快照与 Provider 目录仍是 listenable |
| 工具卡：expansion + elapsed 时钟条件 merge | expansion 走 selector，elapsed 时钟单独订阅 |

结果是**pending 变化不再重建 history 那层**，反之亦然——原来任何一个 region 变都会
重建整棵合并子树。

**守卫**：`agent_region_subscription_guard_test` 断言 presentation 下不得直接订阅
`<region>StateListenable`，只有三处豁免——接缝自己、ViewModel（定义方）、切片
binding（ingress）。做过 mutation 验证：把任意一处改回 `ListenableBuilder` 立刻红。
这条守卫存在的理由是这种偏差**看起来是对的**（两条路径给的是同一批对象，功能正常），
只是那个组件永远停在旧路径上，flag 打开也不走 selector。

**验收测试**：`agent_pane_slice_wiring_test`

- 切片开启时渲染与旧路径一致；
- 未注册 store 的 entry 走旧路径且仍然渲染（回退侧可用）；
- **只往 store 推、不碰 ViewModel** 的 header 也能渲染出来——这条能区分"真的接上了
  selector"和"看起来接上了"，做过 mutation 验证：撤掉该 entry 的 store，它立刻红。

**F 步（§8 验收表剩余项）仍未开始**：两 thread 并存的 Widget 级隔离、UiEffect
exactly-once、canonical signature 回归、Phase 0 帧预算复测。注意帧预算测试目前跑的是
**flag 关闭**的旧路径，切片开启下的帧预算还没有测过——嵌套 selector 理论上只会减少
重建，但"理论上"不是基线，F 步必须实测。

---

## 9.7 F 步：验收测试（2026-08-22）

先补上一个 E 步遗留的**接线缺口**：切片在生产路径上原本无人可达——entry 会按 flag
建 binding，但没有任何地方把 store 解析器接进 Riverpod。

解析器做成 **`NotifierProvider`**，`IdeHome` 在首帧之后 `bind` workspace controller 的
`sliceStoreForBinding`。三个设计点各自对应一个具体问题：

| 选择 | 为什么 |
| --- | --- |
| `NotifierProvider` 而不是 `Provider` | 解析器的值**运行期确实会变**（根 scope 在 `MainApp`，controller 要等 `IdeHome`）。用不可变 `Provider` 建模会让依赖它的 family **缓存住 bind 之前的否定答案**——某个会话一旦被提前读过一次就永久停在旧路径，且不报错 |
| 首帧之后 bind，而不是 `initState` | Riverpod 禁止在 widget 生命周期里改 provider。首帧读到"未启用"无妨：写 `state` 会让 family 失效重算，区域随即切过去，且两条路径渲染结果一致 |
| debug 断言"已启用的 entry 必须解析得到 store" | 这条接线**坏了不会报错**，只会静默退回旧路径。删掉 bind 或改坏 `sliceStoreForBinding` 现在会直接断言失败 |

> 顺带记一个实测结论：给 family 补 `dependencies:` **并不能**让嵌套 `ProviderScope`
> 覆盖依赖后重新解析（flutter_riverpod 3.4.2）。写了个 parent/child 容器探针验证，
> 子容器仍读到父容器的 store。所以隔离靠 key，store 来源靠根级注入，两者都不靠 scope。

> 顺带记一个实测结论：给 family 补 `dependencies:` **并不能**让嵌套 `ProviderScope`
> 覆盖依赖后重新解析（flutter_riverpod 3.4.2）。写了个 parent/child 容器探针验证，
> 子容器仍读到父容器的 store。所以隔离靠 key，store 来源靠根级注入，两者都不靠 scope。

### §8 验收表对照

| # | 验收项 | 状态 |
| --- | --- | --- |
| 1 | 两 Binding 的 state / reducer / effect 隔离 | ✅ provider 级（同容器两 key）+ Widget 级（同一 `ProviderScope` 并排两个 `AgentPane`） |
| 2 | dispose 隔离 | ✅ store 级 + Widget 级（dispose 其一，另一个继续渲染且无异常）；容器 dispose 只摘监听不释放 store |
| 3 | stale generation | ✅ scope 匹配单测 + runtime 换代端到端 |
| 4 | 普通 / urgent 流式 | ✅ 同帧 region 变化合并成一次发布；urgent 走既有 `AgentUiUpdateScheduler`，切片不改其路径 |
| 5 | UiEffect 不进状态 | ✅ 反复推切片重建，`uiEffects` 零产出——effect 只走 stream。**每个动作产出哪些 effect** 仍由 `agent_conversation_view_model_test` 断言 |
| 6 | canonical signature | ✅ 既有 `grok_live_history_canonical_test` 不受影响（切片不碰 provider 层） |
| 7 | 四语义 wire 参数 | ✅ 既有 provider 契约测试；切片命令打的是同一批 port，未新增 wire 路径 |
| 8 | Phase 0 帧预算 | ✅ **两条路径各测一次**，见下 |
| 9 | 架构守卫 | ✅ 分层 / raw payload / scope-aware / region 订阅四组守卫全绿 |
| 10 | feature flag 双路径 | ✅ 渲染等价、未注册 store 时回退可用；**并断言生产接线下 flag 真的激活切片**（含 flag 关闭的反向对照） |

### 帧预算：切片开启也不退化

把 `ide_shell_widget_test` 的两条基线测试参数化成 `slice=false` / `slice=true` 各跑一次：

- **事件风暴聚合预算**（UI region publish ≤ 400、dispatcher queue ≤ 64、
  pendingKeys ≤ 64、常驻 widget 重建 ≤ 2）：两条路径都通过；
- **纯 message delta 场景**（Shell / Header / Composer / liveTimeline 重建必须为
  **0**，只允许局部时间线重建）：两条路径都通过。

这是 E 步里我特意标出"理论上只会减少重建，但理论不是基线"的那一条，现在有实测了。

### 为什么单独测"激活"

帧预算那两条 `slice=true` 只看重建次数——**生产接线断了它们照样全绿**，因为切片会
静默退回旧路径而渲染结果不变。所以另加一条断言：走完整的
`MainApp → IdeHome → controller → entry` 流程后，直接读容器确认
`agentConversationSliceEnabledProvider(key)` 与 flag 一致，且能解析到 store；
flag 关闭时必须是 false。两条都做过 mutation 验证（删掉 bind、让解析器返回 null）。

这条测试补的是本阶段反复出现的同一类漏洞：**断言结果指标，而不是断言那条路径真的
被走到了**。

### 诚实的边界

- 第 5 条测的是"**effect 不进切片状态**"，不是"已发出的 effect 不会被重放"。想直接
  测后者需要在不启动 turn 的前提下发出一次 effect（`sendMessage` 会让 fake 的 turn
  一直跑着，留下 pending timer），成本高于收益。真正的风险——effect 混进状态导致
  rebuild 重复触发滚动/导航——由这条测试覆盖。
- 帧预算是在 fake provider 的事件风暴 fixture 下测的，不是真实 CLI；这与 Phase 0
  基线的口径一致，不代表真机性能。

---

## 10. 不做清单（重申）

- 不重写 `AgentEventPipeline` / TimelineStore / coalescing / reducer identity；
- 不升 Provider 协议或 CLI 基线；
- 不改 conversation UI 视觉与布局；
- 不同时迁 settings / workspace / 多 conversation；
- 不新增缓存、不改持久化格式。

任一条被破坏，本阶段停线重新过 §15。
