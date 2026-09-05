# Agent 事件链路改造方案（套餐 C）

> 状态：**待批准**（含一个需要停线批准的前置项，见 §2.2）
> 目标读者：接手实施的开发者
> 前置阅读：[`AGENTS.md`](../../AGENTS.md) §1 硬门禁、§0 收尾协议

---

## 0. TL;DR

把一个 `AgentEvent` 从 Provider 送到屏幕的路上，要穿过 **6 个 switch、约 90 个分支**。其中 2 个（37 个信封类 + 约 470 行）不做任何决策，纯搬运；另有 2 处把"界面长什么样"和"副作用"混进了状态通道。

本方案分 5 个阶段拆掉它们：

| | 改造前 | 改造后 |
|---|---|---|
| 事件穿过的 switch | 6 个 / ~90 分支 | 3 个 / ~46 分支 |
| 加一个新事件类型要改 | 3–5 个文件 | 1 个新文件 + 1 行注册 |
| reducer 主文件 | 1158 行 | 35 个 handler（平均 40 行）+ 60 行注册表 |
| ViewModel | 4352 行 | ~3900 行（状态与事件宿主剥离） |
| 会话状态能否脱离 VM 单测 | 否 | 是 |
| Provider 特有处理 | 只能改共享层（违反 G1） | 在自己的 bundle 注册覆盖 handler |

净删除约 640 行，新增约 280 行。

---

## 1. 现状精确画像

### 1.1 链路

```
Provider raw callback
  → Provider mapper / tracker
  → AgentEvent
  → Binding.events (Stream)
  → AgentEventPipeline._handleSourceEvent          ① gate 入口校验
      → CoalescingEventBuffer                      ② 按 key 合并（6 种高频事件）
      → BoundedEventDispatcher                     ③ FIFO，每 event-loop 最多 64 个
      → AgentEventPipeline._dispatch               ④ gate 二次校验（换代检查）
      → AgentConversationEventProcessor.process
          → AgentConversationReducer.reduce        ⑤ 35 格格子墙
          → _apply()
              ├─ effects(before)
              ├─ stateChangesBeforeTimeline  ─┐
              ├─ timelineMutations           ─┼→ ⑥ 19 格格子墙（纯搬运）
              ├─ stateChanges                ─┴→ ⑦ 18 格格子墙（纯搬运 + 藏副作用）
              ├─ threadSnapshot refresh
              ├─ uiUpdate → AgentUiUpdateScheduler → AgentConversationUiStateStore
              └─ effects(after)               → ⑧ EffectRunner 4 格
```

①–④ **一个都不能省**。②③ 是帧预算机制；④ 是安全边界：buffer 的 microtask 与 dispatcher 的 `Timer.run` 之间存在异步窗口，事件出队时 listener generation 可能已换代（`agent_event_pipeline.dart:281`）。删掉 ④ 等于让旧 thread 的事件写进新 thread。

⑥⑦ 是本方案的主要目标。

### 1.2 四个具体问题

#### 问题 A · 37 个信封类只为延迟调用

`agent_conversation_mutation.dart` 定义了 19 个 `AgentTimelineMutation` 子类 + 18 个 `AgentConversationStateChange` 子类，全部只有构造函数和字段。真正的动作写在别处：

- `agent_conversation_event_processor.dart:196` 的 `_applyTimelineMutation`（140 行 switch）
- `agent_conversation_view_model.dart:4185` 的 `_AgentConversationEventStateTarget.apply`（150 行 switch）

信封的定义、创建、拆开分散在 3 个文件。加一个时间线操作，编译器只会在第 3 处提醒你。

#### 问题 B · reducer 知道界面长什么样

reducer 里 48 处 `AgentUiRegion.xxx`。抽出来的完整声明表（25 个 case）：

```
_status                  regions=[]                                     IMMEDIATE
_sessionStarted          regions=[header, composer]                     IMMEDIATE
_threadStatus            regions=[header]                               IMMEDIATE
_threadName              regions=[header]                               IMMEDIATE
_threadPreview           regions=[]                                     IMMEDIATE
_threadSettings          regions=[composer]                             IMMEDIATE
_sessionConfig           regions=[composer]                             IMMEDIATE
_conversationModeUpdated regions=[header, composer]                     IMMEDIATE
_autoApprovalReview      regions=[header, liveTurn, history]            IMMEDIATE
_turnStarted             regions=[history, liveTurnBinding, liveTurn,
                                  header, composer]                     IMMEDIATE
_turnCompleted           regions=[history, liveTurnBinding, header,
                                  composer]                             IMMEDIATE  scroll  +pendingIfState
_tokenUsage              regions=[header, composer, history, liveTurn]  IMMEDIATE
_contextUsage            regions=[liveTurn, composer]                   nextFrame
_messageDelta            regions=[liveTurn, expansion]                  nextFrame  scroll  +headerIfActivity
_reasoningDelta          regions=[liveTurn, expansion]                  nextFrame  scroll  +headerIfActivity
_messageUpdated          regions=[liveTurn]                             IMMEDIATE  scroll
_planUpdated             regions=[liveTurn]                             IMMEDIATE
_turnFileChanges         regions=[liveTurn]                             IMMEDIATE  scroll
_toolCall                regions=[liveTurn]                             IMMEDIATE  scroll  +headerIfActivity
_pendingInteraction      regions=[liveTurn, pendingInteraction]         IMMEDIATE
_modelRerouted           regions=[liveTurn, header]                     IMMEDIATE  scroll
_deprecation             regions=[liveTurn]                             IMMEDIATE  scroll
_systemItem              regions=[liveTurn]                             IMMEDIATE  scroll
_modelList               regions=[composer]                             IMMEDIATE
_error                   regions=[history, liveTurn, header]            IMMEDIATE  scroll
```

> 表里是 25 个 `_xxx` 私有 case。reducer 里实际有 **26 处** `uiUpdate:` —— 第 26 处是**公开的**
> `settleInterruptedTurn`（reducer:210，regions=[history, liveTurnBinding, header, composer]，
> IMMEDIATE，+pendingIfState）。它是一条平行归约入口，见 §6.3c，**改造时最容易漏掉的就是它**。

`AgentUiRegion` 定义在 `zeta_agent_core` 内，所以**这不是 G6 分层违规**，是概念耦合：一个纯逻辑组件在决定"要刷新头栏"。加新事件时得靠人脑推演影响面，漏了就是界面不刷新的 bug，编译器不管。

**从这张表读出的两个结论（P4 依赖它们）：**

- **regions 可以派生**：每一行的 regions 都能由"哪些数据变了"推出来。
- **urgency 和 uiEffects 不能派生**。25 个 case 里 21 个是 `immediate`，看起来像"高频事件用 nextFrame"，但 `_tokenUsage` / `_toolCall` / `_turnFileChanges` 都是被合并的高频事件却用 immediate；autoScroll 看起来像"live turn 有新内容就滚"，但 `_planUpdated` / `_pendingInteraction` / `_tokenUsage` / `_turnStarted` 都动了 liveTurn 却不滚。**没有干净规则，保留为 reducer 显式输出。**

#### 问题 C · 两个补丁 flag

`AgentConversationUiResolution.includeHeaderWhenActivityChanges`、`.includePendingInteractionWhenStateChanges`，以及 `AgentConversationStateMutationOutcome.pendingInteractionChanged`。

存在的唯一原因：**reducer 归约那一刻还不知道应用之后会发生什么**。比如 delta 是否改变了"正在做什么"的活动状态，要等 `_timeline.takeActivityDirty()` 才知道。于是在 mutation 上挂布尔让 processor 事后补刷。`_resolveUiUpdate`（processor:154）整个方法就是缝这两个补丁的。

#### 问题 D · 副作用藏在状态通道里（真实隐患，不只是美观）

`_AgentConversationEventStateTarget.apply` 的 18 个 case 里，**7 个不是赋值**：

```dart
case AgentApplyThreadPermissionSettingsChange():
  unawaited(_viewModel._permissionSelectionController.applyThreadSettings(...));  // 异步
case AgentFinalizeTurnCompletedChange():
  _viewModel._releaseTurnActivity();
  _viewModel._maybeAutoStartPlanExecution();      // 触发 Plan 执行（G5 敏感）
```

这些动作**绕过了 `DefaultAgentConversationEffectRunner.run` 的身份重校验**（`agent_conversation_effect_runner.dart:76` 的 `effect.scope.matches(...)`）。事件排队期间 runtime 换代，这些 controller 调用照样执行。P3 修掉它。

### 1.3 顺带发现的两处问题（已决策）

#### 1.3.1 `AgentConversationReducerContexts` 的 history / replay 被急切构造

生产代码只消费 `_eventReducerContexts.live`（VM:139），`.history` 和 `.replay` 从未被使用。但**它不是死代码，不能删**——两个测试靠它断言 G3 要求的隔离性：

- `agent_ui_text_catalog_canary_test.dart:19-32`：断言三个 reducer 互不 `identical`、且共享同一个 `textCatalog`
- `agent_conversation_reducer_test.dart:636`：断言去重集合、本地 id、错误 identity 三者跨 scope 不串扰

**它是 G3 的守卫夹具**，也是"三个 scope 必须各持独立实例"这条规则的唯一正确构造点。

**决策：改为懒构造，不删。** 当前初始化列表急切 `new` 三个 reducer，每构造一个 VM 就白造两个。改成 `late final` 字段初始化器即可——首次访问才构造：

```dart
final class AgentConversationReducerContexts {
  AgentConversationReducerContexts({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? liveTimelineIds,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) : _clock = clock,
       _liveTimelineIds = liveTimelineIds,
       _textCatalog = textCatalog;

  final AgentConversationClock? _clock;
  final AgentConversationLocalTimelineIdGenerator? _liveTimelineIds;
  final AgentUiTextCatalog _textCatalog;

  /// 生产路径唯一消费者。
  late final AgentConversationReducer live = AgentConversationReducer.live(
    clock: _clock,
    timelineIds: _liveTimelineIds,
    textCatalog: _textCatalog,
  );

  /// 历史加载路径预留；当前仅测试消费（G3 隔离守卫）。
  late final AgentConversationReducer history = AgentConversationReducer.history(
    clock: _clock,
    textCatalog: _textCatalog,
  );

  /// 回放路径预留；当前仅测试消费（G3 隔离守卫）。
  late final AgentConversationReducer replay = AgentConversationReducer.replay(
    clock: _clock,
    textCatalog: _textCatalog,
  );
}
```

**排期：P1**（2 行改动，零 API 变化，两个测试断言零修改）。

#### 1.3.2 三个 thread 事件走 `_noOp()`

`AgentThreadArchivedEvent` / `AgentThreadUnarchivedEvent` / `AgentThreadDeletedEvent`。

**决策：保留，P5 注册为显式的 `NoOpHandler`，不从 pipeline 摘掉。** 三条理由：

1. 它们仍需通过 gate 并计入 pipeline 诊断；摘掉会让 §2.3 的基线数字漂移。
2. "不进 pipeline"意味着要改 Provider adapter 让它们不发出——那是 Provider 侧改动，越过了 G1/G2 边界，得不偿失。
3. G4 的精神是"显式表态优于沉默"。一个注册在案的 `NoOpHandler` 是"我们知道有这个事件，故意什么都不做"；从注册表里缺席则会撞上 §8.3 的 `UnsupportedError`。

P5 的写法（一个泛型类注册三次）：

```dart
/// 已知但不产生任何会话变化的事件。
///
/// 与"未注册"严格区分：未注册会抛 [UnsupportedError]（G4）。
final class NoOpHandler<E extends AgentEvent> implements AgentEventHandler<E> {
  const NoOpHandler();

  @override
  AgentConversationReduction handle(event, state, context, scratch) =>
      AgentConversationReduction(accepted: true, state: state);
}

// default_agent_handlers.dart
builder.register<AgentThreadArchivedEvent>(const NoOpHandler());
builder.register<AgentThreadUnarchivedEvent>(const NoOpHandler());
builder.register<AgentThreadDeletedEvent>(const NoOpHandler());
```

> 注意 `_noOp()` 现状返回的 mutation **不带 `uiUpdate`**（`uiUpdate == null` 表示完全不发布，与"空 request"不同，见 `AgentConversationMutation.uiUpdate` 的注释）。新的 `NoOpHandler` 必须保持这一点：不设 `urgency`、不给 `uiEffects`，P4 之后也不点亮任何脏位。

---

## 2. 硬约束（动手前必须确认）

### 2.1 门禁映射

| 门禁 | 关系 | 落实方式 |
|---|---|---|
| **G1** 共享适配层零 Provider 依赖 | P4 要改 `agent_conversation_timeline_store.dart`（G1 名单内）；P5 引入"Provider 可覆盖 handler"能力，是潜在后门 | 见 §2.2 与 §8.6 |
| **G2** 身份由 Provider 决定 | 不触及。脏位只记"哪块变了"，不参与 identity 推断 | 现有 `agent_core_raw_payload_freeze_test` 继续守 |
| **G3** reducer 纯同步 | **本方案加强 G3**：P3 把 7 个副作用从状态通道搬回 EffectRunner | 新增 §4.4 守卫 |
| **G4** 不支持必须显式抛错 | P5 注册表未命中必须 `throw UnsupportedError`，禁止静默 no-op | 见 §8.3 |
| **G5** 四种审批语义隔离 + 绝不预授权 | P3 搬 `_maybeAutoStartPlanExecution` 时最高风险 | 见 §6.6 专章 |
| **G6** 分层单向 | `AgentConversationSessionState` 放 `zeta_agent_core/application`，禁 import Flutter | 见 §6.7 守卫 |
| **G7** 不落盘敏感内容 | 不触及持久化；观察者与诊断只记类型不记正文 | — |
| **G8** 主题走 token | 不触及 UI | — |

### 2.2 ⚠️ 阻塞项：TimelineStore 处于 T18 内容冻结

`test/src/features/agent/architecture/claude_code_shared_layer_purity_test.dart` 对 G1 五文件做了**内容指纹冻结**：

```dart
'packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart':
    lineCount: 2012,
    byteLength: 67887,
    fingerprint: 'bd6bd5a988733b38',
```

测试注释原文：

> 接入 Claude Code 期间这些文件必须 `git diff` 为空；若实现不得不改共享层，**必须先停线取得明确批准并记录边界**，批准后才能更新本基线。

**P4（脏区派生）必须修改这个文件**，无法绕开——脏位只能由写入方置位。

**决策：走批准流程（选项 A）。**

曾评估过另两条路，都不采用：

- **延后 P4**：P5 的 35 个 handler 会带着 region 声明落地，解冻后要再遍历一遍删掉，等于同样的工作做两遍。
- **脏位外挂**（不改 store，在 processor 侧按 mutation 类型推断脏区）：推断**不如 store 自己知道准确**——store 能判断"这次写入值没变，不置位"，外挂做不到，§10 的 R2 过度刷新风险直接回来。这条路是在用架构债换一次批准。

停线批准正是这个机制设计出来要处理的情况：一次有充分理由、有记录、有基线更新的共享层改动，而不是绕过。

#### 2.2.1 批准所需材料（PR 描述里写清楚）

1. **为什么必须改**：脏位只能由写入方置位；外挂推断会丢掉"值未变化"的判断，导致每 token 点亮 header。
2. **改动边界**：只增加 `_dirty` 集合、`takeDirtyRegions()` 与各写方法的置位语句；**不改任何 merge / identity / 终态判定逻辑**（G2 不受影响）。
3. **不引入 Provider 依赖**：新增代码中不出现 `codex` / `grok` / `claude` / `cursor`，G1 自查脚本继续为空。
4. **删除项**：`takeActivityDirty()`（:186）与 `_activityDirty`（:73）并入 `_dirty`。
5. **验证证据**：§2.3 的 5 个基线数字不变 + §7.5 的三条新测试。

#### 2.2.2 基线重算步骤

`claude_code_shared_layer_purity_test.dart` 的失败信息只报 "drift"，不打印实际值。改完后按测试自身的算法重算（`_normalizedUtf8Bytes` + `LineSplitter` + FNV-1a 64-bit）：

```dart
// 临时贴进任一测试文件跑一次，取值后删掉。
test('TEMP: print T18 baseline', () {
  const path =
      'packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart';
  // 与 claude_code_shared_layer_purity_test.dart 的 _normalizedUtf8Bytes 同算法
  final raw = utf8.decode(File(path).readAsBytesSync());
  final bytes = utf8.encode(raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in bytes) {
    hash = ((hash ^ BigInt.from(b)) * prime) & mask;
  }
  debugPrint('lineCount: ${const LineSplitter().convert(utf8.decode(bytes)).length}');
  debugPrint('byteLength: ${bytes.length}');
  debugPrint('fingerprint: ${hash.toRadixString(16).padLeft(16, '0')}');
});
```

**行尾必须按 LF 计算**（测试已做归一化）。Windows checkout 下直接对原始字节做哈希会得到错误值。

#### 2.2.3 注释追加格式

沿用该文件已有的 4 条先例（`2026-08-22（二）(三)(四)`、`2026-08-17`），在 `g1ContentBaselines` 上方追加：

```dart
/// 2026-XX-XX：TimelineStore 基线因**事件链路改造 P4** 刷新——Store 增加
/// `AgentTimelineDirtyRegion` 脏位集合与 `takeDirtyRegions()`，各写方法在
/// **值真正变化时**置位，取代原先只有 `_activityDirty` 一个布尔的做法。
/// 目的：让 UI region 由"谁改了数据谁举手"派生，而不是由 reducer 硬编码
/// （见 docs/plan/agent_event_chain_refactor.md §7）。
/// 本次不触碰 merge / identity / 终态判定，G2 边界不变。已按停线流程批准。
```

### 2.3 性能基线（改造后必须原值不变）

`test/src/features/agent/application/agent_streaming_metrics_baseline_test.dart`：

```dart
const int _expectedReceived   = 10825;
const int _expectedAccepted   = 309;
const int _expectedRejected   = 0;
const int _expectedCoalesced  = 10516;
const int _expectedDispatched = 309;
```

这 5 个指标全部产生于 **processor 上游**（pipeline / buffer / dispatcher）。本方案一行都不动上游，**所以这 5 个数字必须一字不改**——它们是"改造没有误伤管线"的量化证据。每个阶段收尾都要跑一次。`agent_event_storm_fixture_test.dart` 同理。

### 2.4 受影响的既有测试（11 个文件）

```
test/src/features/agent/application/agent_conversation_event_processor_test.dart
test/src/features/agent/application/agent_conversation_reducer_test.dart
test/src/features/agent/application/agent_event_pipeline_test.dart
test/src/features/agent/application/agent_event_storm_fixture_test.dart
test/src/features/agent/application/agent_streaming_metrics_baseline_test.dart
test/src/features/agent/application/agent_ui_update_request_test.dart
test/src/features/agent/architecture/agent_ui_text_catalog_canary_test.dart
test/src/features/agent/data/datasources/claude_code/claude_code_event_mapper_test.dart
test/src/features/agent/presentation/agent_conversation_ui_state_test.dart
test/src/features/agent/presentation/agent_conversation_view_model_test.dart
test/src/features/agent/presentation/agent_ui_update_scheduler_test.dart
```

**P1/P2 阶段这些文件应当一行都不用改**（零行为变化的证据）。P3 起 reducer 测试需要跟随签名调整。

### 2.5 文档同步清单（AGENTS.md §6 要求）

本方案改动了**事件管线与分层契约**，属于 AGENTS.md §6 「改了架构边界，同步这几处」的管辖范围。以下文件必须与代码同批提交，不能只改一处：

| 文件 | 改什么 | 触发阶段 |
|---|---|---|
| `AGENTS.md` | G1 正文追加 Provider 覆盖 handler 条款（§8.6 给了成文）；G3 正文补充"reducer 返回 nextState，副作用一律走 EffectRunner" | P3、P5 |
| `docs/zh/architecture/engineering_standards.md` | §4.1 / §4.2 门禁正文同步 handler 注册表与共享层边界 | P5 |
| `docs/zh/architecture/overview.md` + `docs/en/architecture/overview.md` | 事件链路图更新（§12 的对照图可直接用） | P3、P4 |
| `docs/zh/architecture/design_document.md` | 归约层结构描述 | P5 |
| `docs/zh/development/developer_guide.md` | "新增一个事件类型"的操作步骤从 3–5 个文件改为 1 文件 + 1 行注册 | P5 |
| `docs/zh/development/glossary.md` | 新术语：脏区（dirty region）、handler 注册表、SessionState、覆盖 handler | P3、P4、P5 |
| `CONTRIBUTING.md` + `CONTRIBUTING.en.md` | 人类贡献者版的架构红线摘要 | P5 |
| `CLAUDE.md` | **不改**——门禁编号与数量不变 | — |

> `docs/zh/development/glossary.md` 有英文版要求时同步 `docs/en/development/glossary.md`；
> `docs/en/architecture/` 目前只有 `overview.md`，其余英文档缺失属既有状态，本方案不补齐。

---

## 3. 阶段划分与依赖

```
P1 铺路（零行为变化，四件事一起做）  ─┐
   · Timeline mutation 自应用          │
   · isCriticalDetachedEvent 搬出 reducer（§4.7）
   · ReducerContexts 改懒构造（§1.3.1）│
   · G3 纯度守卫落地（§4.4）           │
P2 事件观察者                          ─┘  独立，零行为变化

P3 typed SessionState         ← 依赖 P1（mutation 形态稳定、静态方法已解绑）
                                 P4/P5 都依赖它

P4 脏区派生 UI region         ← 依赖 P3（state 侧 diff 需要可比较的 state）
                                 需先完成 §2.2 的停线批准

P5 Handler 注册表             ← 依赖 P3（handler 签名含 state）
                                 排在 P4 之后（handler 落地时就不带 region）
```

每个阶段独立可发布、独立可回滚，**每个阶段结束是一个 commit 边界**。

**为什么 P3 在 P5 之前**：P3 要改 reducer 的方法签名。在一个 1158 行的文件里改 35 个方法的签名是一次机械操作，编译器全程护航；先拆成 35 个文件再改签名等于同样的工作量分散到 35 个文件。

**为什么 `isCriticalDetachedEvent` 的搬移放在 P1**：它是 Pipeline 的依赖而非归约逻辑，被 9 处引用。放在 P1 是纯搬移、零风险，且提前解开 P5 掏空 reducer 时的一个死结——放到 P5 再做，就得在拆 35 个 handler 的同时处理管线装配，两件事纠缠在一个 PR 里。

---

## 4. P1 · 铺路（四件零行为变化的事）

### 4.1 目标

本阶段做四件互不依赖、都不改变任何运行时行为的事，为 P3–P5 清场：

1. **Timeline mutation 自应用**（§4.3）——删掉 `_applyTimelineMutation` 的 140 行 switch
2. **G3 纯度守卫落地**（§4.4）——把"reducer 不得执行副作用"变成机器可查
3. **`ReducerContexts` 改懒构造**（§4.5）——生产路径不再白造两个 reducer
4. **`isCriticalDetachedEvent` 搬出 reducer**（§4.6）——解开 P5 的死结

四件事可以合成一个 PR，也可以拆四个 commit，都能独立 revert。

### 4.2 改动文件

| 文件 | 改动 | 子项 |
|---|---|---|
| `packages/zeta_agent_core/lib/src/application/agent_conversation_mutation.dart` | 19 个子类各加一个 `applyTo` | §4.3 |
| `packages/zeta_agent_core/lib/src/application/agent_conversation_event_processor.dart` | 删 `_applyTimelineMutation`（:196–:258），调用点改 1 行 | §4.3 |
| `packages/zeta_agent_core/lib/src/application/agent_conversation_reducer.dart` | `AgentConversationReducerContexts` 三个字段改 `late final`；删除 `isCriticalDetachedEvent` | §4.5 §4.6 |
| `packages/zeta_agent_core/lib/src/application/agent_detached_event_policy.dart` | **新增** | §4.6 |
| `lib/src/features/agent/presentation/agent_conversation_view_model.dart` | :3461 改用 `AgentDetachedEventPolicy.isCritical` | §4.6 |
| `test/src/features/agent/application/agent_event_pipeline_test.dart` 等 4 个测试 | 同上，共 8 个调用点 | §4.6 |
| `test/src/features/agent/architecture/agent_reducer_purity_guard_test.dart` | **新增** | §4.4 |

### 4.3 Timeline mutation 自应用

基类加抽象方法：

```dart
sealed class AgentTimelineMutation {
  const AgentTimelineMutation({this.trackActivityChange = false});

  final bool trackActivityChange;

  /// 把本次变化应用到 Store。
  ///
  /// **只允许 [AgentConversationEventProcessor] 调用。**
  /// reducer 内调用即违反 G3（reducer 必须纯同步、不得触碰 Store）。
  /// 守卫：`agent_reducer_purity_guard_test.dart`。
  void applyTo(AgentConversationTimelineStore store);
}
```

平凡子类（17 个都是这个形状）：

```dart
final class AgentAppendMessageDeltaTimelineMutation extends AgentTimelineMutation {
  const AgentAppendMessageDeltaTimelineMutation(this.event)
    : super(trackActivityChange: true);

  final AgentMessageDeltaEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.appendMessageDelta(event);
}
```

两个非平凡的，逐字给出：

```dart
final class AgentSettleInterruptedTimelineMutation extends AgentTimelineMutation {
  const AgentSettleInterruptedTimelineMutation(this.fallbackTurnId);

  final String fallbackTurnId;

  @override
  void applyTo(AgentConversationTimelineStore store) {
    // 原 processor:207-214 逻辑原样搬入；比散在 processor 里更内聚。
    if (!store.isTurnRunning) {
      return;
    }
    store.completeLiveTurnGroup(
      store.selectedRunningTurnId ?? fallbackTurnId,
      status: AgentHistoryTurnStatus.interrupted,
    );
  }
}

final class AgentAddConversationMessageTimelineMutation extends AgentTimelineMutation {
  const AgentAddConversationMessageTimelineMutation(this.message);

  final AgentConversationMessageMutationData message;

  @override
  void applyTo(AgentConversationTimelineStore store) {
    // 原 processor:216-232：白名单字段逐个搬运，禁止直接透传对象。
    // 注意 addConversationMessage 返回 String（entryId）；这里与原实现一致丢弃返回值。
    store.addConversationMessage(
      AgentConversationMessage(
        id: message.id,
        sourceMessageId: message.sourceMessageId,
        role: message.role,
        text: message.text,
        kind: message.kind,
        phase: message.phase,
        status: message.status,
        duration: message.duration,
        localImagePaths: message.localImagePaths,
        raw: message.raw,
      ),
    );
  }
}
```

processor 调用点：

```dart
// 改造前（processor:127-133）
for (final timelineMutation in mutation.timelineMutations) {
  _applyTimelineMutation(timelineMutation);
  if (timelineMutation.trackActivityChange) { ... }
}

// 改造后
for (final timelineMutation in mutation.timelineMutations) {
  timelineMutation.applyTo(_timeline);
  if (timelineMutation.trackActivityChange) { ... }
}
```

> `trackActivityChange` 与这段 `takeActivityDirty` 逻辑在 P4 一并删除；P1 保持原样，确保零行为变化。

### 4.4 新增守卫：`agent_reducer_purity_guard_test.dart`

```dart
/// G3 守卫：reducer 只能"描述"变化，不能"执行"变化。
void main() {
  const reducerSources = <String>[
    'packages/zeta_agent_core/lib/src/application/agent_conversation_reducer.dart',
    // P5 之后追加 handlers/ 目录下全部文件（用 glob 展开）
  ];

  const forbidden = <String, String>{
    r'\.applyTo\(':      'reducer 不得执行 timeline mutation（G3）',
    r'\bunawaited\(':    'reducer 不得发起异步（G3）',
    r'\bTimer\b':        'reducer 不得创建 Timer（G3）',
    r'\bawait\b':        'reducer 必须纯同步（G3）',
    r'SchedulerBinding': 'reducer 不得触碰 Flutter scheduler（G3）',
  };

  test('reducer 源码不含副作用调用', () {
    for (final path in reducerSources) {
      // 注释里提及是允许的。沿用既有惯例：按行过滤，不做 AST 解析。
      // 参考 agent_file_change_presentation_purity_test.dart:102-105。
      final codeLines = File(path)
          .readAsLinesSync()
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      for (final entry in forbidden.entries) {
        expect(RegExp(entry.key).allMatches(codeLines), isEmpty,
            reason: '$path: ${entry.value}');
      }
    }
  });
}
```

> 行级过滤会漏掉块注释 `/* */` 内的匹配和行尾注释。仓库现有守卫都接受这个精度，
> 不要为此引入 `analyzer` 依赖。

### 4.5 同批完成：`ReducerContexts` 改懒构造

见 §1.3.1。2 行改动，两个测试断言零修改。放在 P1 是因为它和本阶段一样属于"零行为变化的铺路"。

### 4.6 同批完成：`isCriticalDetachedEvent` 搬出 reducer

`AgentConversationReducer.isCriticalDetachedEvent`（reducer:143）是一个**静态白名单**，判断哪些事件在 runtime detach 后仍可交付。它的消费者全在 reducer 外部：

| 消费者 | 位置 |
|---|---|
| Pipeline 装配 | `agent_conversation_view_model.dart:3461` |
| Pipeline 测试 | `agent_event_pipeline_test.dart:328` |
| 风暴 fixture 测试 | `agent_event_storm_fixture_test.dart:371` |
| 指标基线测试 | `agent_streaming_metrics_baseline_test.dart:67, 114, 182, 206` |
| reducer 测试 | `agent_conversation_reducer_test.dart:228, 237` |

**P5 会把 `AgentConversationReducer` 掏空成门面，这个静态方法不能留在里面**——否则管线（G1 名单内文件的直接依赖方）会依赖一个正在被拆解的类。P1 先做纯搬移：

```dart
// packages/zeta_agent_core/lib/src/application/agent_detached_event_policy.dart

/// runtime detach 后仍允许交付的事件白名单。
///
/// 这是**管线级**策略，不是归约逻辑：Pipeline 用它决定是否放行，
/// 因此不能依附于 reducer 的生命周期。
abstract final class AgentDetachedEventPolicy {
  /// detached runtime 仍可交付的精确 critical allowlist。
  ///
  /// [AgentThreadNameUpdatedEvent] / [AgentThreadPreviewUpdatedEvent] 纳入：
  /// Grok 在 turn 结束后异步下发标题或 last_turn_summary，事件可能略晚于
  /// runtime detach 边界，仍需更新列表展示。
  static bool isCritical(AgentEvent event) => /* reducer:143-155 原样搬入 */;
}
```

**迁移策略**：原静态方法保留为 `@Deprecated` 转发一版，9 个调用点在同一个 PR 内全部迁移完，然后**在同一个 PR 里删掉转发**。不要跨 PR 留 deprecated 转发——这类"临时兼容"最容易变成永久。

> ⚠️ 注释里提到了 Grok。`agent_detached_event_policy.dart` **不在 G1 名单里**
> （名单是 pipeline / coalescing policy / buffer / dispatcher / timeline store 五个文件），
> 且 G1 自查脚本明确允许"注释里出现 Provider 名做说明"。搬移时保留原注释即可。

### 4.7 验收

- [ ] `dart format .` + `flutter analyze` 干净
- [ ] `bash tool/test_affected.sh` 全绿，**且 §2.4 的 11 个测试文件断言零修改**
- [ ] 性能基线 5 个数字不变
- [ ] processor 从 260 行降到约 120 行
- [ ] 新守卫测试通过
- [ ] `AgentConversationReducer.isCriticalDetachedEvent` 全仓零引用，`@Deprecated` 转发已删除
- [ ] `AgentConversationReducerContexts` 的三个 reducer 已改 `late final`

### 4.8 回滚

单 commit revert（或按 §4.5 / §4.6 / §4.3 三个子项各一个 commit，都可独立 revert）。无数据迁移、无持久化格式变化。

---

## 5. P2 · 事件观察者

### 5.1 目标

把 processor 里跟主线无关的旁路（turn context 记录）收敛成只读观察者列表。

### 5.2 现状

`agent_conversation_event_processor.dart:96` 的 `_recordTurnContext`：25 行，为它 processor 要 import `agent_turn_context_recorder.dart` 和 logger，还要自己判断 `context.scope == live`、自己 catch。

### 5.3 代码

新文件 `packages/zeta_agent_core/lib/src/application/agent_event_observer.dart`：

```dart
/// 事件处理完成后的只读旁路观察者。
///
/// **契约（违反即回退）：**
/// - 只读。不得回写 TimelineStore、不得产生 effect、不得触发 UI 发布。
/// - 观察者抛出的异常由 processor 吞掉并降级为诊断日志，绝不影响主线。
/// - 看到的是**已经应用完**的结果；想在应用前介入请用 effect，不要用观察者。
///
/// 典型实现：turn 上下文记录、事件录制、调试面板。
abstract interface class AgentEventObserver {
  void onProcessed(
    AgentEvent event,
    AgentConversationMutation mutation,
    AgentConversationReducerContext context,
  );
}
```

processor：

```dart
AgentConversationMutation process(AgentEvent event) {
  final context = _context();
  final mutation = _reducer.reduce(event, context);
  _apply(mutation);
  _notifyObservers(event, mutation, context);
  return mutation;
}

void _notifyObservers(event, mutation, context) {
  for (final observer in _observers) {
    try {
      observer.onProcessed(event, mutation, context);
    } catch (error) {
      // 旁路失败不影响已接受事件；只记类型不记正文（G7）。
      _log.w('Agent event observer failed (${error.runtimeType})');
    }
  }
}
```

现有 recorder 改造：

```dart
final class AgentTurnContextObserver implements AgentEventObserver {
  const AgentTurnContextObserver(this._recorder);

  final AgentTurnContextRecorder _recorder;

  @override
  void onProcessed(event, mutation, context) {
    if (!mutation.accepted ||
        context.scope != AgentConversationReductionScope.live) {
      return;
    }
    final providerId = context.effectScope.providerId;
    switch (event) {
      case AgentTurnStartedEvent():
        _recorder.recordStarted(providerId: providerId, event: event);
      case AgentTurnCompletedEvent():
        _recorder.recordCompleted(providerId: providerId, event: event);
      default:
        break;
    }
  }
}
```

> 原实现自己 catch 了异常（processor:110）。搬进观察者后由 processor 统一 catch，**观察者内部不要再 catch**，否则错误被静默两次。

VM 装配（:139-149）：

```dart
_eventProcessor = AgentConversationEventProcessor(
  reducer: _eventReducerContexts.live,
  context: _buildEventReducerContext,
  timeline: _timeline,
  stateTarget: _eventStateTarget,
  uiUpdates: _eventUiUpdates,
  effectRunner: _effectRunner,
  observers: <AgentEventObserver>[
    if (turnContextStore != null)
      AgentTurnContextObserver(
        DefaultAgentTurnContextRecorder(store: turnContextStore!),
      ),
  ],
);
```

### 5.4 验收

- [ ] processor 不再 import `agent_turn_context_recorder.dart`
- [ ] `bash tool/test_affected.sh` 全绿，测试断言零修改
- [ ] 性能基线 5 个数字不变

### 5.5 明确不做

指标上报（VM 的 :3496 / :3500 / :3514 / :4152）**保持现状**。`_pipelineMetrics.report` 目前是按**帧边界**采样（在 `_publishScheduledUiChanges` 里调），不是按事件；搬进观察者会改变采样频率并使 §2.3 的基线漂移。不要顺手改。

---

## 6. P3 · typed SessionState

### 6.1 目标

- 用一个不可变值对象取代散落在 VM 的 20 多个可变字段。
- 删掉 18 个 `AgentConversationStateChange` 类和 150 行 `apply` switch。
- 把 7 个藏在状态通道里的副作用搬回 EffectRunner，恢复身份校验。
- 合并 `stateChangesBeforeTimeline` / `stateChanges` 两个列表，消除隐式时序耦合。

### 6.2 新增：`AgentConversationSessionState`

放在 `packages/zeta_agent_core/lib/src/application/agent_conversation_session_state.dart`。

```dart
/// 单个会话由事件归约产生的状态。
///
/// 纯数据：不 import Flutter，全 final 字段，实现 == / hashCode。
/// 可单测、可 diff（P4 的 region 派生依赖这一点）。
@immutable
final class AgentConversationSessionState {
  const AgentConversationSessionState({
    required this.status,
    required this.session,
    required this.restoredSessionId,
    required this.threadOpenPhase,
    required this.threadRuntimeStatus,
    required this.threadWaitingOnApproval,
    required this.threadWaitingOnUserInput,
    required this.currentThreadTitle,
    required this.currentThreadPreview,
    required this.modelRerouteNotice,
    required this.sessionConfigOptions,
    required this.autoReviewsByTurnId,
    required this.latestDeniedAutoReview,
    required this.requiresResumedSelectedThread,
  });

  const AgentConversationSessionState.initial({required String defaultTitle})
    : status = const AgentProviderStatus.idle(),
      session = null,
      restoredSessionId = null,
      threadOpenPhase = AgentThreadOpenPhase.idle,
      threadRuntimeStatus = null,
      threadWaitingOnApproval = false,
      threadWaitingOnUserInput = false,
      currentThreadTitle = defaultTitle,
      currentThreadPreview = '',
      modelRerouteNotice = null,
      sessionConfigOptions = const <AgentSessionConfigOption>[],
      autoReviewsByTurnId = const <String, AgentAutoApprovalReviewEvent>{},
      latestDeniedAutoReview = null,
      requiresResumedSelectedThread = false;

  final AgentProviderStatus status;
  final AgentSession? session;
  final String? restoredSessionId;
  final AgentThreadOpenPhase threadOpenPhase;
  final AgentThreadRuntimeStatus? threadRuntimeStatus;
  final bool threadWaitingOnApproval;
  final bool threadWaitingOnUserInput;
  final String currentThreadTitle;
  final String currentThreadPreview;
  final String? modelRerouteNotice;
  final List<AgentSessionConfigOption> sessionConfigOptions;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final AgentAutoApprovalReviewEvent? latestDeniedAutoReview;
  final bool requiresResumedSelectedThread;

  AgentConversationSessionState copyWith({ /* 逐字段，用哨兵对象表达"设为 null" */ });

  @override bool operator ==(Object other) { /* 集合用 zeta_foundation 的助手 */ }
  @override int get hashCode => /* ... */;
}
```

**不进这个 state 的字段（重要，别顺手搬）：**

| VM 字段 | 为什么不进 |
|---|---|
| `_modelsRefreshing` / `_modelRefreshError` / `_modelSelectionSeededFromProviderConfig` | 归 `_modelSelectionController`，不是事件归约产物 |
| `_projectPath` / `_contextFilePath` / `_boundThreadSummary` | 外部注入的上下文，由命令侧写 |
| `_threadSwitchToken` / `_conversationModeCatalogLoadGeneration` | 并发代次令牌，命令侧独有 |
| `_disposed` / `_settingsLoadFuture` / `_compactRequestInProgress` | 生命周期与在途标记 |
| `_threadCreatedAt` / `_threadLastActiveAt` | 从 thread 摘要填充，非事件产物 |
| `_turnActivity` | Binding 活动令牌，有释放语义，不是值 |

### 6.3 reducer 签名

```dart
// 改造前
AgentConversationMutation reduce(AgentEvent event, AgentConversationReducerContext context);

// 改造后
AgentConversationReduction reduce(
  AgentEvent event,
  AgentConversationSessionState state,
  AgentConversationReducerContext context,
);

final class AgentConversationReduction {
  const AgentConversationReduction({
    required this.accepted,
    required this.state,                 // ← 取代 18 个 StateChange
    this.rejectionReason,
    this.timelineMutations = const [],
    this.effects = const [],
    this.urgency = AgentUiUpdateUrgency.nextFrame,
    this.uiEffects = const <AgentUiEffect>[],
    this.uiRegions,                      // ← P4 之前保留；P4 之后删除
    this.threadSnapshot,
  });

  final bool accepted;
  final AgentConversationSessionState state;
  final String? rejectionReason;
  final List<AgentTimelineMutation> timelineMutations;
  final List<AgentConversationEffect> effects;
  final AgentUiUpdateUrgency urgency;
  final List<AgentUiEffect> uiEffects;
  final Set<AgentUiRegion>? uiRegions;
  final AgentThreadSnapshotMutation? threadSnapshot;
}
```

`rejected` 工厂需要携带原状态：

```dart
factory AgentConversationReduction.rejected(
  String reason,
  AgentConversationSessionState state, {
  Iterable<AgentConversationEffect> effects = const [],
}) => AgentConversationReduction(
      accepted: false, state: state, rejectionReason: reason, effects: effects,
    );
```

> ⚠️ 35 个 case 里每一个 `return AgentConversationMutation.rejected(...)` 都要补上 `state` 参数。编译器会全部报出来。

### 6.3b processor 的状态读写端口

`AgentConversationStateMutationTarget` 删除后，processor 仍需要两件事：**读当前 state 喂给 reduce**、**写回 nextState**。用一个窄接口取代原来的 18 分支 target：

```dart
/// processor 与状态宿主之间的唯一边界。
abstract interface class AgentConversationStateSink {
  /// 当前会话状态。processor 每次 process 前读一次。
  AgentConversationSessionState get sessionState;

  /// 写回归约结果。宿主只做赋值，不得在此触发 Flutter 通知。
  void applyReducedState(AgentConversationSessionState next);

  /// 请求在下一次安全 UI 发布边界刷新 thread snapshot。
  /// 语义与原 [AgentConversationStateMutationTarget.requestThreadSnapshotRefresh] 一致。
  void requestThreadSnapshotRefresh();
}
```

VM 实现（取代 `_AgentConversationEventStateTarget` 整个类）：

```dart
final class _AgentConversationStateSink implements AgentConversationStateSink {
  const _AgentConversationStateSink(this._viewModel);

  final AgentConversationViewModel _viewModel;

  @override
  AgentConversationSessionState get sessionState => _viewModel._state;

  @override
  void applyReducedState(AgentConversationSessionState next) =>
      _viewModel._state = next;

  @override
  void requestThreadSnapshotRefresh() =>
      _viewModel._threadSnapshotRefreshPending = true;
}
```

processor：

```dart
AgentConversationReduction process(AgentEvent event) {
  final context = _context();
  final before = _stateSink.sessionState;          // ← P4 的 diff 需要它
  final reduction = _reducer.reduce(event, before, context);
  _apply(reduction, before: before);
  _notifyObservers(event, reduction, context);
  return reduction;
}
```

### 6.3c ⚠️ 别漏了 `settleInterruptedTurn`

这是一条**与 `reduce` 平行的第二条归约入口**，容易漏改：

| 位置 | 说明 |
|---|---|
| `agent_conversation_reducer.dart:210` | `AgentConversationReducer.settleInterruptedTurn({required fallbackTurnId})` |
| `agent_conversation_reducer.dart:354` | `_threadClosed` **内部**调用它 |
| `agent_conversation_event_processor.dart:81` | processor 的公开同名方法，走同一个 `_apply` |
| `agent_conversation_view_model.dart:3050` | Binding runtime 被清除时调用 |
| `agent_conversation_view_model.dart:3485` | Provider 事件流 onDone 时调用 |
| `agent_conversation_reducer_test.dart:247` | 直接对 `AgentConversationReducer.live()` 调用 |

**P3 必须同步改造：**

```dart
// reducer
AgentConversationReduction settleInterruptedTurn({
  required String fallbackTurnId,
  required AgentConversationSessionState state,      // ← 新增
});

// processor
AgentConversationReduction settleInterruptedTurn({required String fallbackTurnId}) {
  final before = _stateSink.sessionState;
  final reduction = _reducer.settleInterruptedTurn(
    fallbackTurnId: fallbackTurnId,
    state: before,
  );
  _apply(reduction, before: before);
  return reduction;
}
```

它产出的两个 change 就是 §6.4 的 #14 / #15，按同一张表处理。**注意 processor 的 `settleInterruptedTurn` 不走观察者**（原实现也不走），保持这一点。

### 6.4 18 个 StateChange 的逐个归属

| # | StateChange | 现在做什么 | 归属 |
|---|---|---|---|
| 1 | `AgentSetProviderStatusChange` | `_status = ...` | → `state.status` |
| 2 | `AgentApplySessionStartedChange` | 写 `_session` / `_restoredSessionId` / `_threadOpenPhase` / `_requiresResumedSelectedThread`；调 `_bindConversationModeThreadPreservingDraft`、`setTurnRunning`、`_applySessionTitle` | → state 4 字段 + **新 effect** `AgentBindConversationModeThreadEffect` |
| 3 | `AgentApplyThreadRuntimeStatusChange` | `_applyThreadRuntimeStatus(...)` | → state 3 字段 |
| 4 | `AgentApplyThreadNameChange` | `_applyThreadTitle` | → `state.currentThreadTitle`（**采标题的过滤规则一并搬进 reducer**，见 §6.5） |
| 5 | `AgentApplyThreadPreviewChange` | `_applyThreadPreview` | → `state.currentThreadPreview` |
| 6 | `AgentApplyThreadPermissionSettingsChange` | `unawaited(controller.applyThreadSettings(...))` | → **新 effect** `AgentApplyThreadPermissionEffect`（`requireThread: false`，事件可能不属当前 thread） |
| 7 | `AgentApplyThreadSettingsChange` | `_applyThreadSelectionFromThreadSettings` + `conversationModeController.applyThreadSettings` | → **新 effect** `AgentApplyThreadSettingsEffect` |
| 8 | `AgentApplySessionConfigChange` | `_sessionConfigOptions = ...` + `_applyThreadSelectionFromSessionConfigOptions` | → `state.sessionConfigOptions` + **新 effect** `AgentSyncThreadSelectionEffect` |
| 9 | `AgentApplyConversationModeChange` | `_applyServerConversationMode` | → **新 effect** `AgentApplyServerConversationModeEffect` |
| 10 | `AgentApplyAutoApprovalReviewChange` | 写 `_autoReviewsByTurnId` / `_latestDeniedAutoReview` | → state 2 字段（纯计算，逻辑照搬 VM:4251-4258） |
| 11 | `AgentPrepareTurnCompletedChange` | `_updatePlanExecutionRequestForCompletedTurn` → 回传 `pendingInteractionChanged` | → **新 effect** `AgentPreparePlanHandoffEffect`（`timing: beforeMutation`） |
| 12 | `AgentFinalizeTurnStartedChange` | `setTurnRunning(true)` + `_consumeActivityDirty()` + `_syncElapsedTicker()` | → **新 effect** `AgentSyncTurnRunningEffect` |
| 13 | `AgentFinalizeTurnCompletedChange` | 见 §6.5 展开 | → state 3 字段 + 3 个 effect |
| 14 | `AgentPrepareInterruptedTurnChange` | `_clearThreadRuntimeStatus()` + `planExecutionHandoffController.clear()` | → state 3 字段 + **新 effect** `AgentClearPlanHandoffEffect` |
| 15 | `AgentFinalizeInterruptedTurnChange` | `setTurnRunning` + `_releaseTurnActivity` + `_consumeActivityDirty` + `_syncElapsedTicker` | → **新 effect** `AgentSyncTurnRunningEffect`（与 #12 复用） |
| 16 | `AgentApplyToolStatusChange` | 用 `toolCall.displayTitle(textCatalog)` 生成 `_status` | → `state.status`（reducer 已持有 `textCatalog`，见 reducer:133） |
| 17 | `AgentSetModelRerouteNoticeChange` | `_modelRerouteNotice = ...` | → `state.modelRerouteNotice` |
| 18 | `AgentHandleModelListChange` | `_applyModelList` | → **新 effect** `AgentApplyModelListEffect` |

**结论：11 个变纯字段，7 个变 effect，18 个类全部删除。**

### 6.5 最难的一处：`AgentFinalizeTurnCompletedChange` 依赖"应用后"的状态

原实现（VM:4265-4295）：

```dart
case AgentFinalizeTurnCompletedChange():
  _viewModel._conversationModeController.setTurnRunning(_viewModel.isTurnRunning);
  _viewModel._modelRerouteNotice = null;
  if (!_viewModel.isTurnRunning &&
      _viewModel._status.state == AgentProviderConnectionState.running) {
    _viewModel._status = AgentProviderStatus(state: ready, message: ...);
  }
  if (!_viewModel.isTurnRunning &&
      _viewModel._threadRuntimeStatus == AgentThreadRuntimeStatus.active) {
    _viewModel._applyThreadRuntimeStatus(status: idle, ...);
  }
  if (!_viewModel.isTurnRunning) {
    _viewModel._releaseTurnActivity();
  }
  ...
```

`isTurnRunning` 读的是 `_timeline.isTurnRunning`（= `selectedRunningTurnId != null`），而这个 change 跑在 **timeline mutation 之后**——这正是 `stateChanges` / `stateChangesBeforeTimeline` 分成两个列表的原因。

新设计里 reducer 一次性算出 nextState，**拿不到"应用后"的 timeline 状态**。解法是给 reducer 一个查询端口，让它自己算得出来（沿用 context 里已有的 `hasTurn` / `isHistoryTurnId` 端口模式）：

```dart
final class AgentConversationReducerContext {
  // ...既有字段...

  /// 排除指定 turn 后，是否仍有 running turn。
  ///
  /// 供 turn 终态归约判断"这一回合结束后会话是否仍在运行"，
  /// 避免 reducer 依赖 timeline mutation 的应用顺序。
  final bool Function(String excludedTurnId) hasRunningTurnExcluding;
}
```

VM 侧实现（`_buildEventReducerContext`）：

```dart
hasRunningTurnExcluding: (turnId) {
  final running = _timeline.selectedRunningTurnId;
  return running != null && running != turnId;
},
```

reducer 里：

```dart
final willBeRunning = context.hasRunningTurnExcluding(event.turnId);
var next = state.copyWith(modelRerouteNotice: null);
if (!willBeRunning && state.status.state == AgentProviderConnectionState.running) {
  next = next.copyWith(
    status: AgentProviderStatus(
      state: AgentProviderConnectionState.ready,
      message: textCatalog.providerReady(context.activeProviderName),
    ),
  );
}
if (!willBeRunning && state.threadRuntimeStatus == AgentThreadRuntimeStatus.active) {
  next = next.copyWith(
    threadRuntimeStatus: AgentThreadRuntimeStatus.idle,
    threadWaitingOnApproval: false,
    threadWaitingOnUserInput: false,
  );
}
```

剩下三件事（`setTurnRunning`、`_releaseTurnActivity`、`_maybeAutoStartPlanExecution`）变成 effect，由 EffectRunner 在 timeline 应用完之后执行，那时读 `isTurnRunning` 自然是准的。

**`AgentPrepareInterruptedTurnChange`（#14）同理**：它的 `_clearThreadRuntimeStatus` 是无条件的，不依赖 timeline，直接 `copyWith(threadRuntimeStatus: null, threadWaitingOnApproval: false, threadWaitingOnUserInput: false)`。

**#4 采标题的过滤规则**：`_applyThreadTitle` 里有"空/占位标题不覆盖、已有非默认标题不覆盖"的判断（VM 注释在 :3960 附近）。这是纯函数，搬进 reducer；不要留在 VM，否则 state 里的 title 与实际显示不一致。

### 6.6 ⚠️ G5 专章：`_maybeAutoStartPlanExecution`

这是全方案风险最高的一处。它触发 **Plan 执行交接**，属于 G5「四种审批语义隔离 / 绝不预授权」的管辖范围。

搬成 effect 时必须满足：

```dart
final class AgentAutoStartPlanExecutionEffect extends AgentConversationEffect {
  const AgentAutoStartPlanExecutionEffect({
    required super.scope,       // 必须带 turnId：scope.forTurn(event.turnId)
  }) : super(
         requireThread: true,   // ← 必须 true，不得放宽
         timing: AgentConversationEffectTiming.afterMutation,
       );
}
```

**逐条自查（PR 里必须逐条回答）：**

1. `requireThread` 是否为 `true`？（放成 false 意味着跨 thread 触发执行）
2. scope 是否带 `turnId`？
3. `AgentConversationEffectScope.matches` 会校验 `listenerGeneration` / `runtimeId` / `connectionEpoch`——**改造前这个 change 完全没有这些校验**。所以行为会变严格：runtime 换代后不再自动启动。

**关于第 3 条的决策：接受变严格，并补测试固化。**

理由：改造前的行为是「Provider 重启 / runtime 换代之后，一个属于旧 generation 的 turn 完成事件仍能触发 Plan 自动执行」。这不是特性，是 G5「绝不预授权」的一个缺口——用户在旧会话里批准的执行意图，被带到了新 runtime 上。effect 化顺手把它关上了。

必须补的两条测试（放在 `agent_conversation_view_model_test.dart` 或新建 Plan 交接测试文件）：

```dart
test('runtime 换代后不再自动启动 Plan 执行', () {
  // 1. 构造 planExecutionRequest pending 的状态
  // 2. 让 turn 完成事件进入 processor，但在 effect 执行前使 runtime 换代
  //    （invalidate pipeline / 推进 connectionEpoch）
  // 3. 断言 startPlanExecution 未被调用
});

test('同 generation 内 turn 完成仍会自动启动 Plan 执行', () {
  // 回归保护：别把修复做成"永远不触发"
});
```

第二条同样重要——只加严不验证正向路径，很容易把功能改没。
4. `DefaultAgentConversationEffectRunner` 的 `Expando` once 语义（runner:73）保证同一 effect 实例只执行一次——确认 reducer 不会为同一个 turn 产出两个 effect 实例。
5. 现有的 Plan 交接测试必须全绿且断言零修改。

**同一专章适用于 #6（权限设置回写）**：`AgentApplyThreadPermissionEffect` 的 `requireThread` 必须是 **false**（settings 事件可能不属于当前 Canvas thread，原注释 VM:4223 已说明），但**不得**因此放宽 `listenerGeneration` 校验。

### 6.7 VM 侧改造

```dart
// 新增单一状态字段
AgentConversationSessionState _state =
    const AgentConversationSessionState.initial(defaultTitle: defaultThreadTitle);

// 20 多个字段删除，getter 改为读它
AgentProviderStatus get status => _state.status;
AgentSession? get session => _state.session;
bool get isReadOnly => /* 原逻辑，读 _state */;

// StateMutationTarget 接口整体删除，改为
void applyReducedState(AgentConversationSessionState next) {
  _state = next;
}
```

`AgentConversationStateMutationTarget` 接口、`_AgentConversationEventStateTarget` 类、`AgentConversationStateMutationOutcome` 全部删除。

processor 的 `_apply` 简化为：

```dart
void _apply(AgentConversationReduction reduction) {
  _runEffects(reduction, AgentConversationEffectTiming.beforeMutation);
  if (!reduction.accepted) {
    _runEffects(reduction, AgentConversationEffectTiming.afterMutation);
    return;
  }
  _stateSink.applyReducedState(reduction.state);   // ← 一行取代两轮 18 分支 switch
  var activityChanged = false;
  for (final m in reduction.timelineMutations) {
    m.applyTo(_timeline);
    if (m.trackActivityChange) {
      activityChanged = _timeline.takeActivityDirty() || activityChanged;
    }
  }
  if (reduction.threadSnapshot != null) {
    _stateSink.requestThreadSnapshotRefresh();
  }
  _publishUi(reduction, activityChanged: activityChanged);
  _runEffects(reduction, AgentConversationEffectTiming.afterMutation);
}
```

> **注意状态写入位置从"timeline 前后各一次"变成"timeline 之前一次"。** 因为 nextState 已经把"应用后"的结论算进去了（§6.5）。这个顺序变化必须被 `agent_conversation_event_processor_test.dart` 的顺序断言覆盖——如果现有测试断言了 before/after 顺序，需要更新，且在 PR 说明原因。

### 6.8 新增守卫

`agent_reducer_purity_guard_test.dart` 追加：

```dart
test('SessionState 不 import Flutter（G6）', () {
  final source = File(
    'packages/zeta_agent_core/lib/src/application/agent_conversation_session_state.dart',
  ).readAsStringSync();
  expect(source.contains('package:flutter/'), isFalse);
});

test('StateChange 类已彻底删除', () {
  final source = File('.../agent_conversation_mutation.dart').readAsStringSync();
  expect(source.contains('AgentConversationStateChange'), isFalse);
});
```

### 6.9 实施顺序（建议拆 3 个 commit）

1. **commit 1**：新建 `AgentConversationSessionState` + `copyWith` + `==`，VM 增加 `_state` 字段并把 11 个纯字段的 getter 改为读它；`_AgentConversationEventStateTarget` 暂时保留、改为写 `_state = _state.copyWith(...)`。**行为不变，编译器全程护航。**
2. **commit 2**：改 reducer 签名，11 个纯字段 change 删除，reducer 直接产出 nextState。
3. **commit 3**：7 个副作用 change 逐个转 effect（**一个 effect 一个小 commit 更稳**），`AgentConversationStateChange` / target / outcome 删除。

### 6.10 验收

- [ ] `AgentConversationStateChange`、`AgentConversationStateMutationTarget`、`AgentConversationStateMutationOutcome` 三个类型在全仓消失
- [ ] 新增 `agent_conversation_session_state_test.dart`：不依赖 VM，直接断言 `reduce(event, state, ctx).state`
- [ ] Plan 交接与权限相关测试全绿，断言零修改（§6.6 第 3 条例外，需 PR 说明）
- [ ] 性能基线 5 个数字不变
- [ ] **`bash tool/test_full.sh`**（AGENTS.md §0：重构必须全量）

---

## 7. P4 · 脏区派生 UI region

> ⚠️ 开始前先解决 §2.2 的 T18 冻结。

### 7.1 目标

删掉 reducer 里 48 处 region 硬编码、`AgentConversationUiResolution`、`_resolveUiUpdate`，改由"谁改了数据谁举手"。

### 7.2 TimelineStore 改动

```dart
/// 时间线写入后被点亮的脏区。
///
/// 只描述"哪块数据变了"，不描述 UI 布局；到 UI region 的映射在 processor。
enum AgentTimelineDirtyRegion {
  history,
  liveTurn,
  liveTurnBinding,
  activity,
  expansion,
  pendingInteraction,
}

class AgentConversationTimelineStore {
  final Set<AgentTimelineDirtyRegion> _dirty = <AgentTimelineDirtyRegion>{};

  /// 取走并清空当前脏区。
  Set<AgentTimelineDirtyRegion> takeDirtyRegions() {
    if (_dirty.isEmpty) {
      return const <AgentTimelineDirtyRegion>{};
    }
    final taken = Set<AgentTimelineDirtyRegion>.of(_dirty);
    _dirty.clear();
    return taken;
  }
}
```

**置位铁律：值真的变了才置位，不是被调用就置位。**

```dart
void appendMessageDelta(AgentMessageDeltaEvent event) {
  if (event.delta.isEmpty) {
    return;                                   // 没变 → 不置位
  }
  // ...原有逻辑...
  _dirty.add(AgentTimelineDirtyRegion.liveTurn);
  if (event.kind == AgentMessageKind.plan) {
    _dirty.add(AgentTimelineDirtyRegion.expansion);
  }
}
```

现有 `_activityDirty`（:73、:1384、:1403、:1408、:1412）整体并入 `_dirty` 的 `activity` 位。`:1408` 那行 `!_activityDirty` 短路正是"值没变不置位"的现成范例，其余写方法照抄这个模式。

`takeActivityDirty()`（:186）删除，调用方（VM:3027 的 `_consumeActivityDirty`、processor 的循环）一并调整。

**受影响的写方法（逐个补置位，别漏）：**

| 方法 | 脏位 |
|---|---|
| `appendMessageDelta` / `appendReasoningDelta` / `updateMessage` | liveTurn (+expansion if plan) |
| `upsertToolCall` | liveTurn, activity |
| `addConversationMessage` / `addHistoryEvent` | liveTurn |
| `beginLiveTurnGroup` | liveTurn, liveTurnBinding, history |
| `completeLiveTurnGroup` | history, liveTurnBinding, activity |
| `updateTurnTokenUsage` / `updateContextWindowUsage` | liveTurn（+history 当 `usageOnHistory`） |
| `replaceActivePlan` / `upsertTurnFileChanges` | liveTurn |
| `add/removePermissionRequest`、`add/removeQuestionRequest`、`add/removePlanApprovalRequest` | liveTurn, pendingInteraction |
| `toggleToolCall` / `togglePlanMessage` / `toggleActivePlan` / `toggleCommandGroup` / `toggleFileEditItem` | expansion |
| `applyHistorySnapshot` / `clearConversation` | history, liveTurn, liveTurnBinding |
| `_setActivity` / `_clearActivity` | activity |

### 7.3 processor 侧映射

```dart
static const Map<AgentTimelineDirtyRegion, AgentUiRegion> _uiRegionOf = {
  AgentTimelineDirtyRegion.history:            AgentUiRegion.history,
  AgentTimelineDirtyRegion.liveTurn:           AgentUiRegion.liveTurn,
  AgentTimelineDirtyRegion.liveTurnBinding:    AgentUiRegion.liveTurnBinding,
  AgentTimelineDirtyRegion.activity:           AgentUiRegion.header,  // 活动状态显示在头栏
  AgentTimelineDirtyRegion.expansion:          AgentUiRegion.expansion,
  AgentTimelineDirtyRegion.pendingInteraction: AgentUiRegion.pendingInteraction,
};
```

state 侧 diff（P3 的产物在这里兑现）：

```dart
Set<AgentUiRegion> _regionsFromStateDiff(
  AgentConversationSessionState before,
  AgentConversationSessionState after,
) {
  if (identical(before, after)) {
    return const {};
  }
  final regions = <AgentUiRegion>{};
  if (before.status != after.status ||
      before.currentThreadTitle != after.currentThreadTitle ||
      before.threadRuntimeStatus != after.threadRuntimeStatus ||
      before.threadWaitingOnApproval != after.threadWaitingOnApproval ||
      before.threadWaitingOnUserInput != after.threadWaitingOnUserInput ||
      before.modelRerouteNotice != after.modelRerouteNotice ||
      before.threadOpenPhase != after.threadOpenPhase) {
    regions.add(AgentUiRegion.header);
  }
  if (before.sessionConfigOptions != after.sessionConfigOptions ||
      before.threadOpenPhase != after.threadOpenPhase ||
      before.session != after.session) {
    regions.add(AgentUiRegion.composer);
  }
  return regions;
}
```

> 这张 diff 表是**手写的**，必须跟 `_buildHeaderState` / `_buildComposerState`（VM:4038、:4059）实际读了哪些字段对齐。§7.5 的守卫测试就是防它们漂移。

### 7.4 reducer 侧收窄

`AgentConversationReduction.uiRegions` 字段删除，`AgentConversationUiResolution` 类删除。25 个 case 只留 urgency 和 uiEffects：

```dart
// _messageDelta：28 行 → 8 行
AgentConversationReduction _messageDelta(event, state, context) {
  if (!_shouldHandleCurrent(context, sessionId: event.sessionId, turnId: event.turnId)) {
    return AgentConversationReduction.rejected('currentThreadMismatch', state);
  }
  return AgentConversationReduction(
    accepted: true,
    state: state,
    timelineMutations: [AgentAppendMessageDeltaTimelineMutation(event)],
    urgency: AgentUiUpdateUrgency.nextFrame,
    uiEffects: const [AgentRequestAutoScroll()],
  );
}
```

### 7.5 ⚠️ 必须新增的帧预算回归测试

**这条测试目前不存在，是 P4 唯一的安全网。**

`test/src/features/agent/application/agent_dirty_region_budget_test.dart`：

```dart
test('1000 个 message delta 不会连带刷新 header/composer', () async {
  // 用现有 AgentEventStormFixture 的 delta 序列
  final published = <AgentUiUpdateRequest>[];
  // ...装配 processor + fake scheduler，收集 publish...

  final headerPublishes = published.where((r) => r.regions.contains(AgentUiRegion.header));
  // 活动状态只在"开始响应"那一刻变一次，之后 1000 个 delta 都不该再点亮 header
  expect(headerPublishes.length, lessThanOrEqualTo(2));
  expect(
    published.every((r) => !r.regions.contains(AgentUiRegion.composer)),
    isTrue,
  );
});

test('值未变化的写入不点亮脏位', () {
  final store = AgentConversationTimelineStore(...);
  store.appendMessageDelta(deltaWithEmptyText);
  expect(store.takeDirtyRegions(), isEmpty);
});
```

另加一条守卫，防 §7.3 的 diff 表与 `_buildHeaderState` 漂移：

```dart
test('header diff 表覆盖 AgentHeaderState 的全部 state 来源字段', () {
  // 逐个改一个 state 字段，断言 _buildHeaderState 的输出确实变了 ⇒ diff 表必须包含它
});
```

### 7.6 验收

- [ ] §2.2 的批准已取得并在 PR 记录
- [ ] `claude_code_shared_layer_purity_test.dart` 基线已更新，注释追加"日期 + 原因"
- [ ] reducer 中 `AgentUiRegion` 出现次数 = 0
- [ ] `AgentConversationUiResolution` / `_resolveUiUpdate` 删除
- [ ] §7.5 三条新测试通过
- [ ] 性能基线 5 个数字不变
- [ ] `bash tool/test_full.sh`

### 7.7 明确不做

**命令侧的 `_publishUiChanges` 保持现状。** VM 里有约 45 处命令入口（`sendMessage`、`toggleToolCall`、`loadModels`…）直接构造带 region 的 `AgentUiUpdateRequest`。那些调用在 presentation 层，**知道 UI region 是合理的**，不是本方案要消灭的耦合。P4 只处理事件侧。

### 7.8 已知遗留（P4 之后仍然存在）

`AgentConversationUiStateStore.publish` 里有一处抽象泄漏：

```dart
// agent_conversation_ui_state.dart:126-130
if (request.regions.contains(AgentUiRegion.liveTurn)) {
  _timeline.liveTurnState?.markDirty();
  _timeline.liveTurnState?.flushNow();
}
```

一个"UI 状态存储"在直接操作另一个 Store 的内部脏标记。P4 之后这里会更别扭——TimelineStore 自己有脏位了，UI store 却还在外面戳它。

**决策：本方案不修，留给 Riverpod 迁移。**

理由：它属于"下游多通道收敛"——现在通知界面有四条并行路径（5 个 `ValueNotifier`、TimelineStore 局部路径、`_effectController` broadcast stream、`AgentConversationSliceStore` 自己的 listener 列表）。收敛这四条要动 `AgentConversationSliceStore` 的 ingress，而 git 历史显示 Riverpod 迁移正在进行（`4ad4d0f7`、`7230fb09`、`b64d4158`）。**单独动会跟迁移打架**，合并冲突的代价远大于收益。

**记录在案，迁移排期时一并处理。** 届时的最小修法：给 TimelineStore 一个显式的 `flushLiveTurn()` 公开方法，由 processor 在发布前调用，UI store 不再反手戳另一个 Store 的内部脏标记。

> 注意 P4 **不会**让这个泄漏变得更糟——`liveTurn` / `liveTurnBinding` 两个 region
> 继续走 TimelineStore 的局部重建路径不变（这条豁免的理由见
> `agent_conversation_slice_state.dart:44` 的注释：per-token 发布会撞穿帧预算）。
> P4 只是让**其余 5 个 region** 改由脏位派生。

---

## 8. P5 · Handler 注册表

### 8.1 目标

把 1158 行、35 个 case 的 reducer 拆成 35 个自带测试的小文件，并让 Provider 能在自己的 bundle 里注册覆盖 handler，不再需要改共享层。

### 8.1b 前置检查：`isCriticalDetachedEvent` 已在 P1 搬出

本阶段开工前，`AgentConversationReducer.isCriticalDetachedEvent` 必须已按 **§4.6** 迁移到 `AgentDetachedEventPolicy.isCritical`，且原静态方法零引用。

**这是 P5 的硬前置**：reducer 被掏空成门面后，管线装配（VM:3461）不能再依赖它。开工前先确认：

```sh
grep -rn "AgentConversationReducer.isCriticalDetachedEvent" --include=*.dart lib packages test
# 期望：无输出
```

### 8.2 接口

```dart
/// 单个事件类型的归约器。
abstract interface class AgentEventHandler<E extends AgentEvent> {
  AgentConversationReduction handle(
    E event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  );
}

/// 跨事件的可变归约状态。
///
/// 原先是 reducer 的实例字段（reducer:134-136），拆 handler 后必须显式传递。
/// live / history / replay 各自持有独立实例（G3）。
final class AgentReducerScratch {
  AgentReducerScratch({
    required this.timelineIds,
    required this.textCatalog,
  });

  final AgentConversationLocalTimelineIdGenerator timelineIds;
  final AgentUiTextCatalog textCatalog;

  /// 已展示过的弃用提示摘要，用于去重。
  final Set<String> shownDeprecationSummaries = <String>{};

  /// 最近一次已展示的错误文案，用于去重。
  String? lastShownErrorMessage;

  String nextLocalTimelineId(String prefix) => timelineIds.next(prefix);
}
```

### 8.3 注册表（含泛型逆变处理）

Dart 泛型默认协变，`AgentEventHandler<AgentMessageDeltaEvent>` **不是** `AgentEventHandler<AgentEvent>` 的子类型。用注册时闭包捕获做类型擦除：

```dart
final class AgentEventHandlerRegistry {
  AgentEventHandlerRegistry._(this._entries);

  final Map<Type, _HandlerEntry> _entries;

  static AgentEventHandlerRegistryBuilder builder() =>
      AgentEventHandlerRegistryBuilder();

  bool hasHandlerFor(AgentEvent event) =>
      _entries.containsKey(event.runtimeType);

  AgentConversationReduction dispatch(
    AgentEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    final entry = _entries[event.runtimeType];
    if (entry == null) {
      // G4：不支持必须显式失败，禁止静默 no-op。
      throw UnsupportedError(
        'No AgentEventHandler registered for ${event.runtimeType}',
      );
    }
    return entry.invoke(event, state, context, scratch);
  }
}

final class AgentEventHandlerRegistryBuilder {
  final Map<Type, _HandlerEntry> _entries = <Type, _HandlerEntry>{};

  /// 注册一个 handler。同一类型重复注册即覆盖（Provider 覆盖用，见 §8.6）。
  void register<E extends AgentEvent>(AgentEventHandler<E> handler) {
    _entries[E] = _HandlerEntry(
      (event, state, context, scratch) =>
          handler.handle(event as E, state, context, scratch),
    );
  }

  AgentEventHandlerRegistry build() =>
      AgentEventHandlerRegistry._(Map.unmodifiable(_entries));
}

typedef _Invoke = AgentConversationReduction Function(
  AgentEvent, AgentConversationSessionState,
  AgentConversationReducerContext, AgentReducerScratch,
);

final class _HandlerEntry {
  const _HandlerEntry(this.invoke);
  final _Invoke invoke;
}
```

> **`_entries[E]` 用静态类型参数做键，`dispatch` 用 `event.runtimeType` 查找。二者相等的前提是每个事件类都是叶子类。** 全部 35 个类目前都直接 `extends AgentEvent`，无中间层级 —— §8.5 的守卫锁死这一点。

### 8.4 目录结构

```
packages/zeta_agent_core/lib/src/application/reduction/
  agent_event_handler.dart            # 接口 + AgentReducerScratch
  agent_event_handler_registry.dart   # 注册表 + builder + _nonOverridable（§8.6.1）
  default_agent_handlers.dart         # 35 行注册清单
  handlers/
    no_op_handler.dart                # 泛型空 handler，注册 3 次（§1.3.2）
    status_handler.dart
    session_started_handler.dart
    turn_started_handler.dart
    turn_completed_handler.dart
    message_delta_handler.dart
    ...（共 35 个，其中 3 个复用 no_op_handler）
    _support/
      current_thread_guard.dart       # 原 _shouldHandleCurrent
      pending_interaction_support.dart# 原 _pendingInteraction（6 个 handler 共用）
      error_text_support.dart         # 原 _errorMessageText / _modelRerouteReasonLabel
```

`AgentConversationReducer` 保留为门面，内部改为持 registry + scratch：

```dart
final class AgentConversationReducer {
  AgentConversationReduction reduce(event, state, context) =>
      _registry.dispatch(event, state, context, _scratch);
}
```

这样 processor、VM、测试的调用点一行都不用改。

**registry 与 scratch 的实例关系（别搞反）：**

| 对象 | 共享还是独立 | 原因 |
|---|---|---|
| `AgentEventHandlerRegistry` | **全局共享一个** | 无可变状态，handler 都是 `const` |
| `AgentReducerScratch` | **live / history / replay 各一个** | 持有 `timelineIds`、`lastShownErrorMessage`、`shownDeprecationSummaries`，跨 scope 共享会导致错误去重和 entryId 串扰（G3） |

即：`AgentConversationReducerContexts` 三个 reducer 共用同一个 registry，但各自 `new` 一个 scratch。`live` 的 scratch 的 `timelineIds` 必须继续注入 VM 的 `_localTimelineIds`（现状 VM:99-102），保持命令侧和事件侧 entryId 单调唯一。

### 8.5 ⚠️ 穷尽性守卫（把编译期检查补回来）

拆成注册表会丢掉 sealed switch 的穷尽性检查。用**编译期 + 运行时双护栏**补回：

`test/src/features/agent/architecture/agent_event_handler_coverage_test.dart`：

```dart
/// 每个 AgentEvent 变体的一个样本。
const List<AgentEvent> allEventSamples = <AgentEvent>[
  AgentStatusEvent(...), AgentSessionStartedEvent(...), /* ...35 个 */
];

/// 编译期护栏：新增事件变体时这个 switch 编译失败，逼你补样本。
String _exhaustivenessGuard(AgentEvent e) => switch (e) {
  AgentStatusEvent() => 'status',
  AgentSessionStartedEvent() => 'sessionStarted',
  /* ...35 个分支，少一个编译不过... */
};

void main() {
  test('每个 AgentEvent 变体都有注册 handler', () {
    final registry = buildDefaultAgentHandlerRegistry();
    expect(allEventSamples.length, 35, reason: '样本数必须与事件变体数一致');
    for (final sample in allEventSamples) {
      _exhaustivenessGuard(sample);                       // 编译期
      expect(registry.hasHandlerFor(sample), isTrue,      // 运行时
          reason: '${sample.runtimeType} 未注册 handler');
    }
  });

  test('AgentEvent 子类必须是叶子类（runtimeType 分发的前提）', () {
    final source = File('.../agent_event_models.dart').readAsStringSync();
    for (final m in RegExp(r'class (\w+) extends (\w+)').allMatches(source)) {
      expect(m.group(2), 'AgentEvent',
          reason: '${m.group(1)} 继承了 ${m.group(2)}；'
                  'runtimeType 分发要求所有事件类直接继承 AgentEvent');
    }
  });

  test('未注册类型必须抛 UnsupportedError（G4）', () {
    final empty = AgentEventHandlerRegistry.builder().build();
    expect(() => empty.dispatch(allEventSamples.first, ...),
        throwsA(isA<UnsupportedError>()));
  });
}
```

### 8.6 ⚠️ G1 后门：Provider 覆盖 handler

这是 P5 最大的收益，也是最大的滥用风险。**必须同时写进 `AGENTS.md`。**

**允许的形态：**

```dart
// packages/zeta_agent_provider_grok/lib/src/grok_provider_bundle.dart
AgentEventHandlerRegistry buildGrokHandlers() {
  final builder = defaultAgentHandlerRegistryBuilder();
  builder.register<AgentThreadNameUpdatedEvent>(GrokThreadNameHandler());
  return builder.build();
}
```

**禁止的形态：**

```dart
// default_agent_handlers.dart —— 共享层
if (providerId == 'grok') { ... }        // ✗ 违反 G1
```

守卫，新建 `test/src/features/agent/architecture/agent_handler_registry_purity_test.dart`：

```dart
/// G1 守卫：共享 handler 目录零 Provider 依赖。
void main() {
  const reductionDir =
      'packages/zeta_agent_core/lib/src/application/reduction';

  test('共享 handler 目录不出现 Provider 标识（G1）', () {
    final providerIdentifier = RegExp(r'(codex|grok|claude|cursor)', caseSensitive: false);
    for (final entity in Directory(reductionDir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      // 与 G1 自查脚本一致：注释里做说明是允许的。
      // 过滤方式对齐 agent_file_change_presentation_purity_test.dart:102-105。
      final codeLines = entity.readAsLinesSync().where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('///');
      });
      for (final line in codeLines) {
        expect(providerIdentifier.hasMatch(line), isFalse,
            reason: '${entity.path} 在代码（非注释）中出现 Provider 标识');
      }
    }
  });

  test('共享注册表不按 providerId 分支（G1）', () {
    final source = File('$reductionDir/default_agent_handlers.dart').readAsStringSync();
    expect(source.contains('providerId =='), isFalse);
    expect(source.contains('switch (providerId'), isFalse);
  });
}
```

#### 8.6.1 `AGENTS.md` 的成文（直接粘贴，追加在 G1 正文末尾、"自查"代码块之前）

```markdown
**Provider 覆盖 handler 的边界。** 事件归约允许 Provider 用自己的实现覆盖某个事件
类型的共享 handler，但只能这样做：

- 覆盖 handler **只能注册在该 Provider 自己的 bundle 里**
  （`packages/zeta_agent_provider_<provider>/lib/src/`），通过
  `defaultAgentHandlerRegistryBuilder()` 之上的 `register<E>()` 覆盖。
- 共享 handler 目录 `packages/zeta_agent_core/lib/src/application/reduction/`
  **禁止**出现任何 Provider 标识、`providerId` 分支或按实现类型分支——它和 G1
  五文件适用同一条纯度规则。
- 每个覆盖 handler 必须在 PR 描述里回答："共享实现为什么不适用？"回答不了，
  说明问题该在该 Provider 的 adapter/reducer 里消化，而不是在归约层分叉。
- 覆盖 handler 不得放宽权限、审批或 Plan 交接语义（G5）。四种审批语义的
  handler（permission / question / planApproval / planExecution）**不允许覆盖**。

自查（应无输出）：

​```sh
grep -rnE "(codex|grok|claude|cursor)" \
  packages/zeta_agent_core/lib/src/application/reduction/ \
  | grep -viE "^\S+:[0-9]+:\s*(///|//|\*)"
​```
```

> 注意最后一条。**修正（实施后 review 发现）**：原措辞写的是"四种审批语义的
> handler 不允许覆盖"，但 G5 的第四种语义「Plan 执行交接」**没有对应的
> `AgentEvent`**，因而没有 handler 可以保护——它由 `AgentTurnCompletedEvent`
> 的 handler 产出 `AgentAutoStartPlanExecutionEffect` 触发，保护在 **effect 层**
> （`requireThread: true` + scope 带 turnId + 执行前重校验 generation/runtime/epoch）。
> `AgentTurnCompletedEvent` 本身可覆盖。禁止覆盖清单实际覆盖三类共 6 个事件类型：
> 实施时在 `AgentEventHandlerRegistryBuilder.register` 里硬编码：
>
> ```dart
> static const _nonOverridable = <Type>{
>   AgentPermissionRequestedEvent, AgentPermissionResolvedEvent,
>   AgentQuestionRequestedEvent, AgentQuestionResolvedEvent,
>   AgentPlanApprovalRequestedEvent, AgentPlanApprovalResolvedEvent,
> };
>
> void register<E extends AgentEvent>(AgentEventHandler<E> handler) {
>   if (_sealed && _nonOverridable.contains(E)) {
>     throw StateError('审批语义 handler 不允许被 Provider 覆盖（G5）：$E');
>   }
>   _entries[E] = ...;
> }
> ```
>
> `_sealed` 在 `defaultAgentHandlerRegistryBuilder()` 返回前置为 `true`，
> 使共享层自己的首次注册不受限，Provider 的后续覆盖受限。

### 8.7 单个 handler 长什么样

```dart
// handlers/message_delta_handler.dart
/// 追加一段流式消息增量。
///
/// identity 由 adapter 生成的 messageId 决定（G2）；本 handler 不推断边界。
final class MessageDeltaHandler implements AgentEventHandler<AgentMessageDeltaEvent> {
  const MessageDeltaHandler();

  @override
  AgentConversationReduction handle(event, state, context, scratch) {
    if (!shouldHandleCurrent(context,
        sessionId: event.sessionId, turnId: event.turnId)) {
      return AgentConversationReduction.rejected('currentThreadMismatch', state);
    }
    return AgentConversationReduction(
      accepted: true,
      state: state,
      timelineMutations: [AgentAppendMessageDeltaTimelineMutation(event)],
      urgency: AgentUiUpdateUrgency.nextFrame,
      uiEffects: const [AgentRequestAutoScroll()],
    );
  }
}
```

配套 `test/.../handlers/message_delta_handler_test.dart`，不需要任何 mock。

### 8.8 实施顺序

0. **前置检查**：§8.1b 的 grep 无输出。
1. 建接口 + `AgentReducerScratch` + 注册表（含 `_nonOverridable` 与 `_sealed`），`AgentConversationReducer` 内部改为委托 registry，**但先把 35 个 case 原样包成 35 个 handler**（机械搬运，一次一批 5–8 个，每批跑一次 `test_affected`）。
2. 把 `_shouldHandleCurrent` / `_nextLocalTimelineId` / `_modelRerouteReasonLabel` / `_errorMessageText` / `_pendingInteraction` 抽到 `handlers/_support/`。
3. 三个 `_noOp()` 事件改注册 `NoOpHandler`（§1.3.2），确认不产生 uiUpdate。
4. 删掉 reducer 里的 35 个私有方法和顶层 switch，`settleInterruptedTurn` 保留在门面上（它不是事件归约，不进注册表）。
5. 加 §8.5 三条守卫 + §8.6 两条纯度守卫。
6. 更新 `AGENTS.md`（§8.6.1 成文）与 §2.5 的其余 7 份文档。

> **第 4 步的注意点**：`settleInterruptedTurn` 不由事件触发，没有对应的 `AgentEvent` 类型，
> 因此**不能**放进按 `runtimeType` 分发的注册表。它继续留在 `AgentConversationReducer`
> 门面上作为独立方法，直接持有 scratch。§6.3c 已说明它的调用点。

### 8.9 验收

- [ ] §8.1b 前置检查通过
- [ ] `agent_conversation_reducer.dart` ≤ 120 行（门面 + scratch 装配 + `settleInterruptedTurn`）
- [ ] 35 个 handler 各有独立测试文件（3 个 `NoOpHandler` 共用一个）
- [ ] §8.5 三条守卫通过（穷尽性 / 叶子类 / `UnsupportedError`）
- [ ] §8.6 两条纯度守卫通过（目录零 Provider 标识 / 注册表零 `providerId` 分支）
- [ ] 审批语义 handler 覆盖被拒绝：`register` 抛 `StateError`，有测试覆盖
- [ ] `AGENTS.md` 已按 §8.6.1 成文追加，`grep` 自查为空
- [ ] §2.5 的 8 份文档已同批更新
- [ ] 性能基线 5 个数字不变
- [ ] `bash tool/test_full.sh`

---

## 9. 测试策略总览

| 阶段 | 既有测试是否需改 | 强制档位 |
|---|---|---|
| P1 | **否**（零行为变化的证据） | `test_affected` |
| P2 | **否** | `test_affected` |
| P3 | reducer 测试跟随签名调整；processor 顺序断言可能需更新（PR 说明） | **`test_full`** |
| P4 | UI 发布相关测试可能需调整 | **`test_full`** |
| P5 | reducer 测试拆分到 35 个文件 | **`test_full`** |

**贯穿全程的三条不变量**（每阶段收尾都跑）：

1. `agent_streaming_metrics_baseline_test` 的 5 个数字不变。
2. `agent_event_storm_fixture_test` 全绿。
3. `flutter analyze` 零告警。

**新增测试清单：**

| 文件 | 阶段 | 作用 |
|---|---|---|
| `architecture/agent_reducer_purity_guard_test.dart` | P1 | G3 纯度（禁 `applyTo` / `await` / `Timer` / scheduler） |
| `application/agent_conversation_session_state_test.dart` | P3 | 状态归约脱离 VM 单测 |
| Plan 交接正反两条用例（§6.6） | P3 | 换代后不自动启动 / 同代仍启动 |
| `application/agent_dirty_region_budget_test.dart` | P4 | 帧预算回归（**当前不存在，是 P4 的安全网**） |
| header diff 表覆盖度守卫（§7.5 第三条） | P4 | 防 diff 表与 `_buildHeaderState` 漂移 |
| `architecture/agent_event_handler_coverage_test.dart` | P5 | 穷尽性 + G4 + 叶子类 |
| `architecture/agent_handler_registry_purity_test.dart` | P5 | G1：目录零 Provider 标识 + 注册表零 `providerId` 分支 |
| 审批 handler 不可覆盖用例（§8.6.1） | P5 | G5：`register` 抛 `StateError` |

**既有测试的基线更新（只有这一处）：**

`claude_code_shared_layer_purity_test.dart` 的 TimelineStore T18 三元组（P4，按 §2.2.2 重算、§2.2.3 追加注释）。**除此之外，本方案不允许更新任何既有基线常量。** 尤其是 §2.3 的 5 个流式指标——它们一旦需要改，说明动到了管线，应当停下来重新审视。

---

## 10. 风险登记

| ID | 风险 | 阶段 | 缓解 |
|---|---|---|---|
| R1 | TimelineStore T18 冻结未获批准 | P4 | §2.2 三选一，**开工前决策** |
| R2 | 脏位过度点亮导致每 token 刷头栏 | P4 | §7.5 帧预算测试；置位铁律"值变了才置位" |
| R3 | §7.3 的 diff 表与 `_buildHeaderState` 漂移 | P4 | §7.5 第三条守卫 |
| R4 | Plan 自动执行 effect 化引入预授权缺陷 | P3 | §6.6 五条自查逐条回答 |
| R5 | effect 化后 scope 校验变严，出现"该触发没触发" | P3 | 这是修复不是回归，但需补测试 + PR 说明 |
| R6 | Provider 覆盖 handler 被滥用成 G1 后门 | P5 | §8.6 守卫 + `AGENTS.md` 条款 |
| R7 | 事件类被加子类导致 runtimeType 分发失效 | P5 | §8.5 叶子类守卫 |
| R8 | processor 状态写入顺序变化引发未预期时序问题 | P3 | §6.5 用 `hasRunningTurnExcluding` 显式建模；全量测试 |
| R9 | 阶段间半成品状态（如 P5 前 handler 仍带 region） | P4/P5 顺序 | 严格按 §3 顺序执行；D1 已排除"延后 P4"的返工路径 |
| R10 | `settleInterruptedTurn` 第二入口被漏改 | P3 | §6.3c 列了全部 6 个调用点 |
| R11 | `isCriticalDetachedEvent` 随 reducer 被掏空而失效 | P5 | 已按 D5 提前到 P1（§4.6）；P5 开工前用 §8.1b 的 grep 确认 |
| R12 | Provider 覆盖 handler 被用来绕过审批语义 | P5 | D6：四种审批 handler 在 `register` 里硬禁止覆盖（§8.6.1） |
| R13 | 停线批准迟迟拿不到，阻塞 P4 | P4 | P4 与 P5 之间无强依赖顺序之外的耦合；批准未到时可先把 P3 做透，但**不要**开工 P5（否则 handler 带 region 落地） |

### 10.1 回滚粒度

每个 commit 自身必须**编译通过且测试全绿**，可单独 `git revert`。特别是 P3 的三个 commit：

- commit 1（引入 state，target 仍在）绿 → 可停在这里
- commit 2（reducer 签名改造）绿 → 可停在这里
- commit 3（副作用转 effect）建议再拆成 7 个小 commit，一个 effect 一个

**不要出现"半个 P3"的中间状态跨越工作日。**

### 10.2 工作量粗估（仅供排期，不作为取舍依据）

| 阶段 | 估算 | 主要时间花在 |
|---|---|---|
| P1 | 1–1.5 天 | 19 个 `applyTo` 机械搬运（§4.3）+ policy 搬移与 9 个调用点迁移（§4.6）+ 懒构造（§4.5）+ 守卫（§4.4） |
| P2 | 0.5 天 | 接口 + 一个观察者改造 |
| P3 | 3–5 天 | 18 个 change 归属判断 + 7 个 effect + G5 自查 + 全量测试 |
| P4 | 2–3 天 | TimelineStore 约 20 个写方法置位 + 帧预算测试 + 基线重算 |
| P5 | 2–3 天 | 35 个 handler 拆分（机械但量大）+ 守卫 + AGENTS.md |
| 文档同步 | 1 天 | §2.5 的 8 份文档（含 2 份英文版） |

合计约 **10–14 天**，不含停线批准的等待时间。

---

## 11. 决策记录

### 11.1 已决策（本文档已按此展开，无需再问）

| # | 议题 | 决策 | 依据 | 落在 |
|---|---|---|---|---|
| D1 | TimelineStore T18 冻结 | **走停线批准流程** | 另两条路：延后 P4 要把 35 个 handler 改两遍；脏位外挂丢掉"值未变化"判断，过度刷新风险回来 | §2.2 |
| D2 | `ReducerContexts.history` / `.replay` | **改懒构造，不删** | 它是 G3 隔离性的守卫夹具，两个测试依赖它；问题只是急切构造浪费 | §1.3.1 / §4.5 |
| D3 | 三个 `_noOp()` 事件 | **保留，注册显式 `NoOpHandler`** | 摘掉会让基线数字漂移、越过 G1/G2 边界；G4 精神是显式表态优于沉默 | §1.3.2 |
| D4 | Plan 自动执行 scope 校验变严 | **接受，并补正反两条测试** | 旧行为是 G5「绝不预授权」的缺口，不是特性 | §6.6 |
| D5 | `isCriticalDetachedEvent` 搬移时机 | **提前到 P1** | 它是 Pipeline 依赖不是归约逻辑；放 P5 会和拆 handler 纠缠在一个 PR | §4.6 / §3 |
| D6 | Provider 覆盖 handler 的边界 | **允许覆盖，但四种审批语义 handler 硬禁止** | 把 G5 隔离前推到注册表层，避免覆盖能力变成绕过审批的入口 | §8.6.1 |
| D7 | UiStateStore 反手戳 TimelineStore | **不修，留给 Riverpod 迁移** | 属下游四通道收敛，与在途迁移强耦合，单独动会打架 | §7.8 |

### 11.2 仍需人工动作（不是技术决策）

1. **取得 §2.2 的停线批准**，材料清单见 §2.2.1。这是 P4 开工的硬前置。
2. **确认 §8.6.1 的 `AGENTS.md` 成文措辞**——文本已写好可直接粘贴，需要一次 review 认可。

### 11.3 开工顺序检查表

```
[ ] §8.6.1 的 AGENTS.md 措辞已 review 通过
[ ] P1  → §4.3 mutation 自应用 + §4.5 懒构造 + §4.6 policy 搬移 + §4.4 守卫
[ ] P2  → §5 观察者
[ ] §2.2 停线批准已取得（P4 前置，可与 P2/P3 并行推进）
[ ] P3  → §6，三个 commit，副作用转 effect 再拆 7 个小 commit
[ ] P4  → §7，含基线重算（§2.2.2）与注释追加（§2.2.3）
[ ] P5  → §8，前置检查 §8.1b 必须无输出
[ ] §2.5 的 8 份文档已同批更新
```

---

## 12. 附录：改造前后的链路对照

```
【改造前】
AgentEvent
  → reduce (35 格)
  → Mutation{ stateChangesBeforeTimeline, timelineMutations, stateChanges,
              uiUpdate, uiResolution, threadSnapshot, effects }
  → _apply
      → effects(before)                          [switch 4 格]
      → stateChangesBeforeTimeline               [switch 18 格]
      → timelineMutations                        [switch 19 格]
      → stateChanges                             [switch 18 格 · 同一个]
      → threadSnapshot
      → _resolveUiUpdate（缝 2 个补丁）→ publish  [if 7 分支]
      → effects(after)                           [switch 4 格 · 同一个]

【改造后】
AgentEvent
  → registry.dispatch (Map 查找，O(1))
  → Reduction{ state, timelineMutations, effects, urgency, uiEffects, threadSnapshot }
  → _apply
      → effects(before)                          [switch 4 格]
      → stateSink.applyReducedState(next)        [1 行]
      → for m in timelineMutations: m.applyTo()  [0 分支]
      → regions = timeline.takeDirtyRegions() + stateDiff(before, next)
      → publish(regions, urgency, uiEffects)     [if 7 分支]
      → effects(after)                           [switch 4 格 · 同一个]
      → observers                                [0 分支]
```

剩下的 3 个 switch：合并策略（7）、effect runner（4）、UI 发布（7）—— 每一个都在做真正的决策。

---

## 13. 本文档的自查记录

文档写完后按下列清单逐条回代码核对，**已核对**的结论如下（供 review 时抽查）：

| 断言 | 核对结果 |
|---|---|
| `AgentEvent` 是 sealed，35 个直接子类，无中间层级 | ✅ `agent_event_models.dart:17` + 35 处 `extends AgentEvent` |
| 18 个 `AgentConversationStateChange` 子类 | ✅ |
| 19 个 `AgentTimelineMutation` 子类 | ✅ |
| reducer 48 处 `AgentUiRegion.`、26 处 `uiUpdate:` | ✅（其中 1 处在 `settleInterruptedTurn`） |
| `AgentUiTextCatalog.providerReady(String)` 存在 | ✅ `agent_ui_text_catalog.dart:123` |
| `AgentToolCall.displayTitle(catalog)` 存在且核心层可用 | ✅ `agent_ui_text_catalog.dart:242`，TimelineStore:1300 已在用 |
| `TimelineStore.addConversationMessage` 存在 | ✅ `:530`，**返回 `String` 不是 `void`**（已在 §4.3 标注） |
| `TimelineStore.isTurnRunning` = `selectedRunningTurnId != null` | ✅ `:169`（§6.5 的推导依据） |
| TimelineStore 处于 T18 内容冻结 | ✅ `claude_code_shared_layer_purity_test.dart:94-98` |
| 性能基线 5 个常量 | ✅ `agent_streaming_metrics_baseline_test.dart:21-25` |
| `history` / `replay` reducer 生产代码未使用 | ✅ 全仓仅 `_eventReducerContexts.live`（VM:139） |
| 守卫测试的注释过滤惯例 | ✅ 行级过滤，`agent_file_change_presentation_purity_test.dart:104` |

**第一轮自查发现并已补进文档的 4 处遗漏：**

1. **`settleInterruptedTurn` 是第二条归约入口**，有 6 个调用点（含 reducer 内部自调用 `:354`），P3 改签名时必须一起改 → 补 §6.3c。
2. **`AgentConversationReducer.isCriticalDetachedEvent` 是 Pipeline 的依赖**，被 9 处引用（含 4 个测试文件）。P5 掏空 reducer 会打断它 → 按 D5 提前到 P1（§4.6）。
3. **processor 缺少读取当前 state 的端口**。原文只说了写回，没说从哪读；P4 的 diff 还需要 before/after 两份 → 补 §6.3b 的 `AgentConversationStateSink`。
4. **`_isInComment` helper 在仓库里不存在**，原文当成现成的用了 → 改为引用既有行级过滤写法（`agent_file_change_presentation_purity_test.dart:102-105`）。

### 13.1 第二轮补全（决策固化）

第一轮把 7 个议题挂在 §11 让人决策；第二轮按建议全部拍板并展开成可执行步骤：

| 补充项 | 内容 |
|---|---|
| §2.2.1–2.2.3 | 停线批准的**材料清单、基线重算脚本、注释追加成文**。原文只说"要批准"，没说怎么办 |
| §1.3.1 | `ReducerContexts` 的处置从"待决策"改为**懒构造**，并给出完整改法。核实后修正了原文的判断：**它不是死代码**，两个测试靠它断言 G3 隔离性 |
| §1.3.2 | `NoOpHandler` 的完整写法 + 三条保留理由 + 一个易错点（`_noOp()` 现状 `uiUpdate == null`，新实现必须保持） |
| §2.5 | **文档同步清单**（8 份文件）。这是 AGENTS.md §6 的硬要求，第一轮完全漏了 |
| §4.5 / §4.6 | 把懒构造和 policy 搬移并入 P1，含 `@Deprecated` 转发的处置纪律（同 PR 内删除，不跨 PR） |
| §6.6 | Plan 自动执行变严的**决策 + 正反两条测试**。只加严不验证正向路径容易把功能改没 |
| §8.6.1 | `AGENTS.md` 的**成文条款**（可直接粘贴）+ 一条新增约束：**四种审批语义 handler 硬禁止覆盖**，并给出 `register` 里的实现 |
| §11 | 从"决策清单"改为**决策记录**（D1–D7）+ 仍需人工动作 + 开工检查表 |
| §10 | 风险表补 R12（覆盖能力被滥用）、R13（批准迟到时的推进策略）；工作量估算补文档同步一档 |

**第二轮新识别的风险：**「Provider 可覆盖 handler」如果不加限制，会成为绕过 G5 审批语义的入口。已在 §8.6.1 用 `_nonOverridable` 清单在代码层堵死，而不是只靠文档约定。

**已知未解决（有意留下，不是遗漏）：**

- `AgentConversationUiStateStore` 反手操作 TimelineStore 的抽象泄漏（§7.8）——按 D7 归属 Riverpod 迁移。
- 命令侧约 45 处 `_publishUiChanges` 仍手写 region（§7.7）——presentation 层知道 region 是合理的。
- 事件录制 / 离线回放能力——那是"不可变时间线"路线，本方案不覆盖，但 §5.3 的观察者接口为它留了挂载点。
- `docs/en/architecture/` 目前只有 `overview.md`，其余英文档缺失属既有状态，本方案不补齐（§2.5 已标注）。
