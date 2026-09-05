# WP-1 · 按 Provider 实例聚合会话运行事实

> 状态：未开始。前置：无。先适配现有 workspace；WP-3 更换源 owner 时保留同一事实端口。 统一约束见 [总入口](00-index.md)。本章新 API 与代码块均为目标设计。

### 1.1 问题、实施前提与边界

本章修复管理状态的数据归属，不改变 Provider 协议、权限策略或会话生命周期。本包没有 WP-3 前置：先接入当前 `AgentManagementSliceStore` 与现有 composition，独立完成归属修复。WP-3 后续把同一 ingress 迁至 Notifier，不能重新定义事实范围。下文标记“拟新增”的类型、文件和方法均是开发设计，不代表当前已有可编译 API。

基线事实：

| 当前位置 | 已确认事实 | 导致的限制 |
|---|---|---|
| `lib/src/ui/features/ide/views/ide_home.dart`，`_managementRuntimeState` / `_managementRuntimeSnapshot` | 状态来自 selected controller；id 来自全局 settings.activeProviderId | 选择 Grok 会话时，可能把 Grok 的状态更新到默认 Codex 卡片 |
| `lib/src/app/agent_management_slice/agent_management_slice_runner.dart`，`AgentManagementRuntimeSnapshot` | 只有 `(activeAgentId, runtimeState)` | 无法表达同一时刻多个 Provider、多个 runtime |
| `lib/src/app/agent_management_slice/agent_management_slice_composition.dart`，`_handleRuntimeChanged` | 用上述 tuple 更新单张管理卡片 | 管理运行事实依赖 Canvas 选择 |
| `packages/zeta_agent_core/lib/src/application/agent_provider_runtime_registry.dart` | registry 是 `AgentChangeNotifier`；创建、移除实例会通知；`_entries` 私有，生产接口未提供可枚举 runtime 快照 | 不能假设已有“订阅全局所有 runtime 状态”的现成 API；debug 计数不可当生产数据源 |
| `packages/zeta_agent_core/lib/src/application/agent_conversation_binding_manager.dart` | 提供 `bindings` 只读视图及成员变化监听 | 可以覆盖前台、后台以及仍保有 runtime 的无消费者 Binding |
| `packages/zeta_agent_core/lib/src/application/agent_conversation_binding.dart` | Binding 可监听，提供 `runtimeLifecycle`、`currentRuntime`、`runtimeSnapshot`；后者含精确 runtime identity 与 activeOperationCount | 可判别 dormant、starting、attached、cleared；activeOperationCount 同时包含短操作，不能冒充活跃 turn 数 |
| `packages/zeta_agent_core/lib/src/application/agent_conversation_thread_snapshot.dart` | 有 `providerId`、`isTurnRunning`、`runtimeStatus`、waiting 字段；没有连接枚举和 runtime identity | 不应把 thread 的 idle、历史 active 或 notLoaded 当成 CLI 已连接 |

**确定的数据范围：本应用 Workbench 管理的 session Binding 与其会话运行事实。** 所有打开的 workspace entry 都参与，是否选中、页面是否可见均不影响统计；BindingManager 中暂时无 entry 但仍持有 runtime 的 Binding 也参与连接数量。global scope 的模型目录预热、连接测试临时进程，以及用户在 Zeta 之外启动的 CLI 不在该范围内。不把此摘要命名为“操作系统所有 Agent 进程状态”。本工作包不扩充 registry 的生产枚举 API，也不为观测 acquire 租约或激活插件。

### 1.2 身份与状态规则

1. `providerId` 是精确配置实例 id，即 `AgentProviderConfig.id` / Binding.providerId，不是 providerType、厂商名、管理页当前选择或默认 id。同一种协议的两个实例不合并；不得从 command、extra、显示名推断品牌。
2. 全局默认 Provider 仅用于新建任务的偏好。Canvas 选中项仅用于视图导航。两者都不参与本聚合的 identity 或状态选择。
3. 一个 Binding 对象是本次观测生命周期的稳定身份；draft 晋升为 thread 只更新其逻辑 key，不增减 runtime 数。runtime 以完整 `AgentProviderRuntimeIdentity(providerId, generation)` 去重，不能只按 threadId 或 providerId 去重。
4. `ready` 表示当前 session runtime 已初始化、可连接；`running` 表示当前有效会话存在活跃 turn 或等待交互中的 turn。连接 ready、读取模型目录、短 RPC、历史列表中的 active 标记均不能单独推出 running。
5. dormant 且无当前失败是“本应用尚未启动该会话 runtime”；cleared 是实例已经清除，不能继续计入 connected/running。旧 thread 快照尚未刷新时，Binding 的 cleared/current identity 校验优先，防止短暂幽灵 running。
6. startup 失败可发生在未获得 runtime identity 时。它归属当前 entry/Binding 的观测 generation，作为当前启动失败保留至下一次成功重试、显式清理或 entry 移除；不得伪造 attached identity。
7. provider 被禁用是配置策略，不是“进程已关闭”的事实。`enabled=false` 禁止新动作；事实中的现存 running/connected 仍保留，直到实际 clear/remove。卡片可同时表达“已禁用”和仍在运行；不能把所有 count 清零。
8. 所有聚合都保留 `activeTurnCount`、`connectedRuntimeCount`、`startingBindingCount`、`errorBindingCount`、`unavailableBindingCount`、`unobservedTurnRuntimeCount`。最后一项表示有 runtime 但无当前会话快照，不能断言 idle turn；不从 activeOperationCount 推断 turn。
9. 面向旧 `AgentRuntimeState` 的兼容主状态按固定顺序投影：有活跃 turn → running；否则有当前错误 → error；否则正在启动 → starting；否则 unavailable；否则有 ready runtime → idle；否则禁用 → disabled；否则 notRunning。运行与错误并存时 running 只表示主状态，`hasErrors` 必须独立保留并在管理行展示错误提示，不能丢掉错误事实。
10. 对没有管理 contribution 的自定义实例，事实 map 仍保留精确 id；管理卡片 selector 仅按 exact id 查找。不得把其活动并入同厂商内置卡片，也不得偷偷创建厂商定义。

### 1.3 目标文件与拟新增 API

| 位置 | 责任 |
|---|---|
| 拟新增 `lib/src/features/agent/application/conversation_slice/agent_conversation_runtime_observation.dart` | 当前会话的中立、无正文观测值；通过现有 controller 发布边界生成 |
| 修改 `agent_conversation_runtime_controller.dart` | 发布上述观测值，集中保证 thread facts、connection state 与 runtime identity 的一致性 |
| 拟新增 `lib/src/features/agent_management/application/agent_management_runtime_facts.dart` | 管理 feature 所需的不可变事实、聚合结果与只读端口 |
| 拟新增 `lib/src/app/agent_management_slice/workspace_agent_runtime_fact_source.dart` | 唯一跨 feature 适配器；监听 BindingManager、workspace entries 和全部 entry 的中立观测值 |
| 拟新增 `lib/src/features/agent_management/application/agent_management_runtime_aggregation.dart` | 纯同步聚合与主状态投影，不包含订阅、Timer 或 UI |
| 修改现有 management Store、state、runner；WP-3 后续迁移实现 | 接收全量 typed facts；删除单 tuple runtime 注入；runner 的探测结果不再覆盖 live runtime |
| 修改现有 Shell/management composition、`ide_home.dart` | app 组合 source、管理其销毁；删除 UI runtime 桥 |

```dart
// 拟新增；仅根 app 内使用，纯 Dart，不扩充 Provider 协议。
@immutable
final class AgentConversationRuntimeObservation {
  final AgentConversationBindingKey bindingKey;
  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final AgentRuntimeScope? connectionScope;
  final int attemptEpoch;
  final AgentConversationRuntimeLifecyclePhase lifecycle;
  final AgentProviderConnectionState connectionState;
  final bool isTurnRunning;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  // 上述bool来自同次构建的中立ThreadSnapshot；不复制标题/preview。
  // connectionState仅取枚举，不复制status.message/details。
}

// 拟给 controller 增加，复用现有安全发布边界。
AgentValueListenable<AgentConversationRuntimeObservation>
    get runtimeObservationListenable;
int get runtimeObservationAttemptEpoch;

// 拟新增；所有集合不可变，均不含标题、preview、正文、路径或原始错误。
@immutable
final class AgentManagementRuntimeFact {
  final Object observationKey; // source 私有opaque token，不参与日志/落盘。
  final String providerId;
  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final AgentRuntimeScope? connectionScope;
  final AgentConversationRuntimeLifecyclePhase lifecycle;
  final AgentProviderConnectionState? connectionState;
  final bool hasCurrentThreadObservation;
  final bool connected; // 已由source校验attached/identity/底层ready及连接枚举。
  final bool activeTurn;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final bool currentError;
  final bool unavailable;
}

@immutable
final class AgentManagementRuntimeFacts {
  final List<AgentManagementRuntimeFact> bindings;
}

abstract interface class AgentManagementRuntimeFactSource {
  AgentManagementRuntimeFacts get current;
  void Function() subscribe(void Function(AgentManagementRuntimeFacts) receive);
  // subscribe只注册，不立即回调；调用方随后同步读取current，期间没有await。
  // close由组合根调用；消费者只能退订，不持有生命周期控制权。
}

@immutable
final class AgentManagementProviderRuntimeSummary {
  final String providerId;
  final bool enabled;
  final int activeTurnCount;
  final int connectedRuntimeCount;
  final int startingBindingCount;
  final int errorBindingCount;
  final int unavailableBindingCount;
  final int unobservedTurnRuntimeCount;
  final bool hasErrors;
  final AgentRuntimeState state;
}

Map<String, AgentManagementProviderRuntimeSummary> aggregateManagementRuntime(
  AgentManagementRuntimeFacts facts,
  Map<String, bool> enabledByProviderId,
);
```

`Object observationKey` 只为内存内等值区分：由 source 对每个 Binding 对象注册时生成，不暴露实例引用、地址字符串或递增业务 id；source 重建后生成全新 token。按对象identity比较，不调用toString、不编码成路径或业务id。

### 1.4 观测和聚合伪代码

```dart
// controller中新增观测值。既有ThreadSnapshot端口继续供Shell/侧栏使用。
void publishAtExistingUiSafeBoundary() {
  final thread = buildThreadSnapshot();
  final bindingState = conversationBinding.runtimeLifecycle;
  final current = conversationBinding.currentRuntime;
  final observation = AgentConversationRuntimeObservation(
    bindingKey: conversationBinding.key,
    runtimeIdentity: current?.runtimeIdentity,
    connectionScope: current?.bundle.runtime.runtimeScope,
    attemptEpoch: runtimeObservationAttemptEpoch,
    lifecycle: bindingState.phase,
    connectionState: status.state,
    isTurnRunning: thread.isTurnRunning,
    waitingOnApproval: thread.waitingOnApproval,
    waitingOnUserInput: thread.waitingOnUserInput,
  );
  // 必須在现有generation/epoch已校验的controller state上投影。
  // 连接状态变化、turn开始/结束、approval/question变化、Binding生命周期变化
  // 均需将observation刷新标为pending，不能只在thread字段变化时发布。
  publishIfStructurallyDifferent(runtimeObservationListenable, observation);
  publishIfStructurallyDifferent(threadSnapshotListenable, thread);
}

final class WorkspaceAgentRuntimeFactSource {
  final Map<AgentConversationBinding, ObservationHandle> handles =
      Map.identity();
  bool closed = false;
  bool started = false;
  bool reconciling = false;
  bool reconcileAgain = false;
  int sourceGeneration = 0;

  void start() {
    if (closed) throw StateError("Runtime fact source is closed");
    if (started) return;
    started = true;
    // 构造时依赖已就绪。subscribe都在app组合层，无Widget参与。
    manager.addListener(reconcile);
    workspace.addListener(reconcile);
    try { reconcile(); } catch (_) { close(); rethrow; }
  }

  void reconcile() {
    if (closed) return;
    if (reconciling) { reconcileAgain = true; return; }
    reconciling = true;
    try {
      do {
      reconcileAgain = false;
      final currentBindings = manager.bindings.values.toSetIdentity();
      final entriesByBinding = workspace.entries.indexByBindingIdentity();
      // 一个Binding不允许对应两个不同controller；冲突直接fail-closed，
      // 不采用last-write-wins。draft晋升不产生第二个handle。
      removeHandlesNotIn(currentBindings); // 先停订阅，再从事实移除。
      for (final binding in currentBindings) {
        final handle = ensureHandle(binding); // 生成独立opaque token。
        handle.rebindEntryIfIdentityChanged(entriesByBinding[binding]);
        // handle监听Binding和该entry.runtimeObservationListenable。
        // 每个回调捕获handle、sourceGeneration与订阅generation；
        // 只有handles[binding]仍identical(handle)且generation匹配才reconcile。
      }
      final facts = <AgentManagementRuntimeFact>[];
      for (final handle in handles.values) {
        facts.add(readCurrentFact(handle)); // 同步重读，不应用回调携带的旧patch。
      }
      publishIfStructurallyDifferent(AgentManagementRuntimeFacts(facts));
      } while (reconcileAgain && !closed);
    } finally {
      reconciling = false; // 校验/发布异常也不能永久关闭后续重算。
    }
  }

  AgentManagementRuntimeFact readCurrentFact(ObservationHandle handle) {
    final binding = handle.binding;
    final lifecycle = binding.runtimeLifecycle;
    final runtime = binding.currentRuntime;
    final observation = handle.entry?.controller.runtimeObservationListenable.value;
    final sameOwner = observation != null &&
        observation.bindingKey.providerId == binding.providerId &&
        observation.attemptEpoch ==
          handle.entry.controller.runtimeObservationAttemptEpoch;
    final sameRuntime = sameOwner && runtime != null &&
        observation.runtimeIdentity == runtime.runtimeIdentity &&
        observation.connectionScope == runtime.bundle.runtime.runtimeScope;
    final attached = lifecycle.phase ==
        AgentConversationRuntimeLifecyclePhase.attached && runtime != null;

    // runtime已clear、替换或仍starting时，旧thread.active绝不继续计数。
    final active = attached && sameRuntime &&
        (observation.isTurnRunning ||
         observation.waitingOnApproval ||
         observation.waitingOnUserInput);

    // 无entry的retained Binding只读已有runtime.lifecycleState，不新建controller。
    // runtime ready是连接事实；activeOperationCount不转为activeTurn。
    final connection = sameRuntime ? observation.connectionState
        : mapExistingRuntimeLifecycle(runtime?.bundle.runtime.lifecycleState);
    // 没有identity的启动失败仅接受同一当前owner的observation，且binding
    // 不在新starting/attached轮次中；观测代数的重试切换会先清该失败。
    final startupFailure = currentOwnerStartupFailureKind(handle, observation, lifecycle);
    final currentError = startupFailure == StartupFailureKind.error
        || (sameRuntime && observation.connectionState == AgentProviderConnectionState.error);
    final unavailable = startupFailure == StartupFailureKind.unavailable
        || connection == AgentProviderConnectionState.unavailable;
    final connected = attached &&
        runtime.bundle.runtime.lifecycleState == AgentProviderLifecycleState.ready &&
        (handle.entry == null || connection == AgentProviderConnectionState.ready ||
         connection == AgentProviderConnectionState.running);
    return factWithWhitelistedFields(...);
  }

  void close() {
    if (closed) return;
    closed = true;
    sourceGeneration++;
    manager.removeListener(reconcile);
    workspace.removeListener(reconcile);
    for (final handle in handles.values) handle.detachAll();
    handles.clear();
    // 组合根已经先关闭消费者；close只清监听，不再发布。
    // 不释放lease、不cancel turn、不invalidate registry。
  }
}

Map<String, RuntimeSummary> aggregate(facts, enabledById) {
  final groups = groupByExactProviderId(facts);
  final ids = {...enabledById.keys, ...groups.keys};
  return immutableMap({
    for (final id in ids) id: summarize(
      id: id,
      enabled: enabledById[id] ?? false,
      activeTurnCount: countDistinctObservationKeys(groups[id], isActiveTurn),
      connectedRuntimeCount: countDistinctRuntimeIdentities(groups[id], (fact) => fact.connected),
      startingBindingCount: countDistinctObservationKeys(groups[id], isStarting),
      errors: currentErrors(groups[id]),
      unknownTurnRuntimes: attachedWithoutCurrentThreadObservation(groups[id]),
    ),
  });
}

// WP-1现有app composition：source已由Shell在workspace创建后构造并start。
final initial = projectRuntimeFacts(
  existingInitialState,
  source.current,
  providerSettings.settings,
);
final store = AgentManagementSliceStore(initialState: initial, /* 既有依赖 */);
final unsubscribe = source.subscribe((facts) {
  store.runtimeFactsReplaced(facts); // 只会在store构造完成之后发生。
});
// composition.close先unsubscribe/store.close，Shell随后close source/workspace。

// 下述source/settings source provider为拟新增application依赖接缝，由app实现；
// WP-3迁移时保留契约；独立source provider只依赖workspace+BindingManager，
// 不得依赖workbenchSessionProvider（它自己依赖management）。
// WP-3M最终接线以该章§4.3为准：owner build只返回冻结初始state。
// 独立app ingress provider在owner构造完成后连接源；owner不依赖本provider。
final agentManagementIngressProvider = Provider<void>((ref) {
  final sink = ref.read(agentManagementSliceProvider.notifier);
  final source = ref.read(agentManagementRuntimeFactSourceProvider);
  final settings = ref.read(agentManagementSettingsSourceProvider);
  final unsubscribeFacts = source.subscribe(sink.runtimeFactsReplaced);
  final unsubscribeSettings = settings.subscribe(sink.providerSettingsChanged);
  ref.onDispose(unsubscribeFacts);
  ref.onDispose(unsubscribeSettings);
  sink.providerSettingsChanged(settings.current);
  sink.runtimeFactsReplaced(source.current);
});
// composition依次eager读取owner、ingress，再initialize，最后暴露Widget。
// 不再在Notifier.build中重复subscribe同一facts source。
```

`attemptEpoch`是拟新增controller内存观测代数，不能声称已有统一公开generation可直接读取。controller在准备调用 `beginTurn()` 且当前没有runtime时、第一次await之前递增它，同时清理该观测分区的旧启动失败；不改变Binding本身的启动、租约或权限状态。发送和Plan执行两条现有beginTurn调用路径都走一个私有观测helper，复用已有pending启动时不重复递增。`currentOwnerStartupFailureKind`只接受：handle仍绑定同一entry/controller、observation.attemptEpoch等于controller当前getter、无当前runtime、Binding当前为dormant、该observation是本attempt已通过controller原有有效性检查发布的error/unavailable。处于新starting时旧失败立即被屏蔽。runtime identity、connectionScope/epoch与attemptEpoch分别覆盖实例重建、同实例连接重建和未建成实例的启动尝试；三者都不是发布revision，也不参与持久化。controller原有pipeline/thread generation检查仍是第一层，source检查是移除/重建后的第二层。

`connectedRuntimeCount`的谓词明确为：Binding为attached、identity有效、底层中立lifecycle为ready，且当前连接枚举为ready或running；无entry时只用前两项和底层ready，并计入unobservedTurnRuntimeCount。stopped/closing/closed/failed不计连接数，starting/initializing计启动数。`currentOwnerStartupFailureKind`分别返回none/error/unavailable，不把不可用统一折成error。

正常状态通知在既有安全发布边界内完成。Binding同步通知可能先于controller观测刷新：source首先以Binding当前identity屏蔽旧事实，稍后收到新观测自然补齐；允许短暂“starting/未观测”，不允许虚构旧runtime仍在running。不能为填满中间态增加Timer、读取UI或让旧快照覆盖新identity。

### 1.5 生命周期、失败及应用范围

- WP-1中source由现有Shell在workspace Store创建后构造并start；management composition借用source并退订，不取得其所有权。现有IdeHome只向composition转交source依赖，不读取或拼装事实。关闭顺序为management composition退订/关闭Store → Shell关闭source → workspace/BindingManager。WP-3后source提升为独立app provider，仍由组合根显式关闭，provider仅依赖workspace/BindingManager，不能回读workbenchSessionProvider。
- source采用同步全量重读+结构相等发布，避免一条迟到 remove patch 删除同id的新runtime。old generation callbacks必须被丢弃；同Provider不同scope的runtime可能并存，不能拿“provider最大generation”把其他scope误判为过期。
- source close、entry remove、manager prune要幂等。解除监听必须使用当初绑定的具体对象与回调；禁止按会晋升的draft key查旧回调。
- `AgentManagementRuntimeFacts`及聚合值不落盘、不写日志，不含conversation正文、路径、raw payload或本地化文案。
- source完整性冲突（providerId错配、同Binding多个controller）是结构错误，应抛StateError并由既有应用错误边界处理，不能显示“全部空闲”。单个runtime的业务error是数据，保留其余Provider事实，不使整张表失效。

### 1.6 开发步骤

1. 在现有Shell与management composition中确定上述source构造/关闭顺序；保留现有Store唯一owner，本提交不迁Notifier、不等待WP-3。
2. 添加纯事实模型、聚合函数与独立测试；先固定身份、优先级、disabled和多runtime矩阵。
3. 给controller增加中立observation及attemptEpoch，复用现有发布调度器；覆盖连接状态单独变化时也能通知。不得重新创建第三层时间线状态镜像。
4. 实现app source，监听manager及全部entry，绑定与删除均做object identity/generation校验。
5. management state新增 `runtimeByProviderId`；以selector将其映射到管理卡片。移除runner的 `_runtimeState` 和 `(activeAgentId, runtimeState)` 接口；探测输入永远不能改写该map；`ConnectionTestSucceeded`、初始化、settings更新等所有逐字段重建也不能独立写runtimeState。WP-1在reducer统一出口按runtimeByProviderId投影兼容ManagedAgent.runtimeState，删除这些分支中的独立runtime赋值。WP-5再拆其余诊断字段。
6. 删除IdeHome的 `_managementRuntimeState`、`_managementRuntimeSnapshot` 及Shell运行订阅转接。默认Provider、Canvas切换不再触发错误归属更新。
7. 完成真实IdeHome集成测试及format/analyze/受影响测试；本包独立行为修复按总入口门禁执行。若同时涉及owner搬迁或测试基础设施调整，升级完整重构门禁；保留既有并行会话/权限/关闭断言。

### 1.7 验收矩阵

| 层 | 场景 | 必须断言 |
|---|---|---|
| 纯聚合 | 默认Codex，前台Grok running，Codex dormant | Grok running、Codex notRunning；切默认配置不交换状态 |
| 纯聚合 | Codex/Grok同时运行，切Canvas/Settings | 两者均running；结果不依赖选中页 |
| 纯聚合 | 同Provider两个runtime，一ready一running | runtime去重数量2、active turn数1、主状态running |
| 纯聚合 | 同Provider两个scope各有不同generation | 两者均保留，不能只保留最大generation |
| 纯聚合 | A运行且B错误，或同Provider一运行一错误 | running与hasErrors/count均保留，错误不串到其他Provider |
| 纯聚合 | 同kind两个自定义providerId | 独立map项；不并入内置品牌id |
| 纯聚合 | dormant、历史active、仅短RPC | 不产生active turn；global预热不产生session运行事实 |
| source | draft晋升、entry移除后重建同thread | 不重复计数；旧handle回调无法修改新entry |
| source | runtime generation替换后旧clear/onDone | 新runtime保留；旧active即时屏蔽 |
| source | starting→失败→重试starting→attached | 旧startup错误不覆盖新attempt，状态有序收敛 |
| source | orphan Binding仍有ready runtime | 连接数保留，unobservedTurnRuntimeCount增加，不猜turn是否活跃 |
| source | 禁用但runtime尚未关闭 | enabled=false；现存运行count保留；真实清理后归零 |
| source | dispose后旧回调、重复close | 无发布、无异常、没有额外acquire/release/invalidate |
| Widget | 通过真实Shell选择非默认Provider并开始turn | 管理页和首页显示相同的正确归属；不通过fake tuple绕过source |

建议新增 `test/src/app/agent_management_slice/workspace_agent_runtime_fact_source_test.dart` 与 `test/src/features/agent_management/application/agent_management_runtime_aggregation_test.dart`；真实接线用例扩展 `test/src/app/ide_shell_widget_test.dart`，现有 `ide_shell_controller_test.dart` 的跨Provider并行用例保留。

回滚：保持WP-1为独立提交，在回退该提交时同时回退source、observation端口及消费者迁移，不保留两套runtime ingress。若WP-3已经基于该端口迁移，先按依赖逆序回退相关后继提交；不向新owner并行接回旧单Provider通道。无持久化迁移，因此不需要降级数据恢复。
