# WP-3 · 单一状态 owner 与完整组合生命周期

> 状态：WP-3M/P 已完成；WP-3C 未开始。前置：WP-1；WP-3P 另需 WP-4。阶段顺序：M → P → C。
> 统一决策见 [总入口](00-index.md)。本章代码块均为 Dart 风格伪代码，新增类型属于目标设计；现有 `Store` 不能通过改名继续保留镜像发布链。

## 1. 问题、范围与可观察目标

现状锚点：

| 当前文件/符号 | 实际责任 | 改造目标 |
|---|---|---|
| `agent/application/conversation_slice/agent_conversation_slice_store.dart` | `_listeners`、regions 投影、命令账本 | application Notifier 直接拥有轻量切片 |
| `agent/presentation/conversation_slice/agent_conversation_slice_providers.dart` | `state = store.state` 镜像 | 只保留读 selector；真实 owner 移到 application |
| `agent_management/.../agent_management_slice_store.dart` | listeners、pending、业务入口 | application Notifier，保留 reducer/operations |
| `project_threads/.../project_threads_slice_store.dart` | listeners、同步规则、operation | WP-4 收口后整体迁成 Notifier |
| `app/*_slice/*_slice_composition.dart` | 先 DeferredRunner 再 delegate | owner build 时用 runner factory(owner/sink) 构造 |
| `app/conversation_workspace_slice/*providers.dart` | workspace Store 的镜像与可变 registry | Workspace Notifier 直接拥有 workspace state |
| `agent_conversation_slice_store_registry.dart` | Widget 后补 resolver | 删除；从实际资源 owner 的显式 provider 解析 |
| `IdeHome.initState/dispose` | 创建 Shell、bind/unbind、关闭业务 owner | 只消费已就绪 workbench；窗口/应用负责关闭 |

目标行为：首次无 UI 装配即可读取 Shell 和切片；多个 Canvas 独立；切页、Widget 重挂不创建新 CLI runtime；草稿晋升不替换切片；entry 真正关闭时在途调用必定结算且资源只释放一次。

本工作包移除两个 Conversation registry、两个 `_Deferred*Runner` 及四组业务状态镜像。临时 Widget 状态、core 的 `AgentListenable`、对外部/core 通知源的必要 adapter 不属于镜像债务，保持。现有桌面通知路由确认桥和原生菜单 Widget 回调不在本包删除范围；它们不得承载或回填本包的业务 owner。不要为满足文本 grep 而破坏离开设置页的未保存确认。

## 2. 状态、资源和生命周期必须分开

| 对象 | 唯一 owner | 生存期 | 可否由无人订阅自动销毁 |
|---|---|---|---|
| Management state/pending/detection | `AgentManagementSliceNotifier` | app session | 否 |
| Project Threads state/唯一索引/pending | `ProjectThreadsSliceNotifier` | app session | 否 |
| workspace entries/selection/mappings | `AgentConversationWorkspaceNotifier`（app） | app session | 否 |
| Binding lease + RuntimeController | workspace entry 资源对象；由 lifetime coordinator 显式释放 | entry | 否 |
| Conversation regions/pending/lastFailure | `AgentConversationSliceNotifier`（application） | entry | 否 |
| Pipeline/TimelineStore/live text | 原 RuntimeController/core | 原 runtime/entry 语义 | 否 |
| selector/终止后的空投影 | 纯派生 provider | UI 观察期 | 可以；不控制上表资源 |
| popover/composing/焦点/滚动 | 原 Widget/session | Widget | 按现状 |

资源对象引用不是第二份业务 state。Workspace 可保留私有 `Map<OwnerKey, EntryResources>` 以持有它自己创建的 lease/controller；禁止把这张表做成需要 IdeHome `bind()` 的独立服务定位器。公开不可变 state 中不存 controller、Ref、Widget、回调或 raw payload。

## 3. 文件迁移清单

路径均相对于仓库根；目录简写在表中展开，开发时按真实路径修改。

| 操作 | 文件/目录 | 责任 |
|---|---|---|
| 新增 | `lib/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart` | M 阶段唯一 owner；实现现有 Operations |
| 新增 | 同目录 `agent_management_slice_dependencies.dart` | 初始数据/配置校验窄端口/runner factory 声明 |
| 修改 | `lib/src/app/agent_management_slice/agent_management_slice_composition.dart` | 改为 provider body/依赖装配；删除持有 store 的 composition 与 Deferred 类 |
| 修改 | `lib/src/app/agent_management_slice/agent_management_slice_runner.dart` | 改用具名ResultSink，run返回真实Future，供owner跟踪排空 |
| 删除 | 原 management Store 文件 | 调用者与测试迁移完成后同提交删除 |
| 修改 | management presentation providers、page、configuration editor、log view | 不再以 Store 对象作为 family 参数/Widget 构造参数 |
| 新增 | `lib/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart` | P 阶段迁移 WP-4 的最终 Store |
| 新增 | 同目录 `project_threads_slice_dependencies.dart` | 纯应用依赖与 runner factory |
| 修改 | `lib/src/app/project_threads_slice/project_threads_slice_composition.dart` | provider 装配与 factory，删除 Deferred |
| 修改 | `lib/src/app/project_threads_slice/project_threads_slice_runner.dart` | 保留WP-4的void run/close，跟踪真实后台任务并新增drainExecutions |
| 删除 | 原 Project Threads Store 文件 | 保留 Operations/StateOwner 的语义，更新实现名 |
| 新增 | `lib/src/app/composition/agent_session_resource_providers.dart` | P 阶段 app 唯一 BindingManager/global runtime 与 sweep timer factory |
| 新增 | `lib/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart` | 稳定 entry 身份 |
| 新增 | 同目录 `agent_conversation_session_dependencies.dart` | regions/executor/scope/ownerKey 的不可变依赖 |
| 新增 | 同目录 `agent_conversation_slice_notifier.dart` | C 阶段真实 owner，接收批处理 regions |
| 调整 | 同目录 `agent_conversation_slice_ports.dart` | runner 接口、窄 result sink 从 Store 文件移出 |
| 删除 | 同目录原 slice Store/StoreRegistry | owner/handle 调用者迁移后删除；不保留 forwarding 类 |
| 新增 | `lib/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart` | 原 Store 的 workspace state 与资源操作 |
| 新增 | 同目录 `agent_conversation_entry_resources.dart` | 从原 workspace Store 提取 entry，去掉 SliceStore 字段 |
| 新增 | 同目录 `conversation_slice_lifetime_coordinator.dart` | 统一创建/关闭 entry slice 与资源 |
| 修改 | 原 workspace state/reducer/providers | 保留 reducer；添加 stable ownerKey/closing 投影，删镜像和 registry |
| 删除 | 原 `agent_conversation_workspace_store.dart` | 迁移完后删除，名字不能仅变成包着新 owner 的外壳 |
| 新增 | `lib/src/app/composition/workbench_session_providers.dart` | 组合完整 workbench，注入 Shell 所需 operations |
| 修改 | `ide_workbench_composition.dart`、`zeta_app_composition.dart`、`app.dart`、`ide_shell_controller.dart`、`ide_home.dart` | 组合前移、构造与启动分离、移除 Widget 反向接线 |
| 修改 | `zeta_state_snapshot.dart` 与相关 tests | 从 app owner 读取白名单摘要；删除 Shell state snapshot relay |

本表的目标文件只新增到现有目录，不建立新的广义 core/state 层。Management API 的厂商贡献仍通过已激活并校验的 contribution provider 读取；禁止复制 manifest 表。

## 4. WP-3M：Management owner 迁移

### 4.1 具名结果入口与完整回流面

保留现有 AgentManagementOperations 与 reducer 的业务语义。Runner 只从具体 Store 改为接收具名 ResultSink，不能把所有结果压成 dispatchResult(Intent)：现有初始化失败、配置保存失败需要把原 error + stackTrace 交给调用方 Future，但对应 intent 故意不保存它们。

下列是本阶段完整的拟新增接口。方法参数来自当前 Store；runtime 一项接续已经完成的 WP-1，使用 RuntimeFactsReplaced 对应的全量事实输入，不能恢复旧的单 Canvas tuple。接口放在 agent_management_slice_dependencies.dart，或同目录单独的 agent_management_result_sink.dart；若采用后者，实施文件清单必须同步登记。

~~~dart
abstract interface class AgentManagementResultSink {
  bool get isClosed;
  AgentManagementSliceState get current; // Runner 原 state.agentsById 的只读查询

  void providerSettingsChanged(AgentProviderSettings settings);
  void runtimeFactsReplaced(AgentManagementRuntimeFacts facts); // WP-1 契约

  void initializationSucceeded(
    OperationId id, AgentProviderSettings settings,
    Map<String, ManagedAgent> agentsById,
  );
  void initializationFailed(OperationId id, Object error, StackTrace stackTrace);

  void detectionStarted(OperationId id, String agentId);
  void detectionProgressReported(
    OperationId id, String agentId,
    AgentDetectionProgress progress, ManagedAgent partial,
  );
  void agentDetected(OperationId id, String agentId, ManagedAgent detected);
  void detectionCompleted(OperationId id);
  void detectionFailed(OperationId id, String message);

  void providerEnabledUpdated(
    OperationId id, String agentId, bool enabled, AgentProviderSettings settings,
  );
  void providerEnabledUpdateFailed(OperationId id, String agentId, String message);
  void accountDataEnrichmentUpdated(
    OperationId id, String agentId, AgentProviderSettings settings,
  );
  void accountDataEnrichmentUpdateFailed(
    OperationId id, String agentId, String message,
  );

  void connectionTestSucceeded({
    required OperationId operationId,
    required String agentId,
    required AgentConnectionTestResult result,
    required List<AgentModelInfo> models,
    required String modelSource,
    required DateTime modelsUpdatedAt,
  });
  void connectionTestFailed(OperationId id, String agentId, String message);
  void configurationLoaded(
    OperationId id, String agentId, AgentConfigurationDocument document,
  );
  void configurationLoadFailed(OperationId id, String agentId, String message);
  void configurationSaved(
    OperationId id, String agentId, String originalSignature,
    AgentConfigurationSaveResult result,
  );
  void configurationSaveFailed(
    OperationId id, String agentId, Object error, StackTrace stackTrace,
  );
  void logsLoaded(
    OperationId id, String agentId, List<String> paths, List<AgentLogEntry> entries,
  );
  void logsLoadFailed(OperationId id, String agentId, String message);
}

typedef AgentManagementRunnerFactory =
    AgentManagementSliceEffectRunner Function(AgentManagementResultSink sink);

// 同在 application dependencies 文件声明；由 app 组合用于关停，不暴露给 UI。
abstract interface class AgentManagementOwnerLifecycle {
  void stopAcceptingCommandsAndSettleWaiters();
  Future<void> drainExecutions();
}

abstract interface class AgentManagementSliceEffectRunner {
  Future<void> run(AgentManagementSliceEffect effect);
  String? validateConfiguration(String agentId, String content);
}
~~~

Runner 中原 _store.state.agentsById 改读 sink.current.agentsById，其余 _store.xxx(...) 回流逐项改为 sink.xxx(...)。同步 validateConfiguration 继续走现有 Runner/repository 的纯校验端口，不把配置内容加入 state、日志或新缓存。UI 只消费 Operations/selector，不获得 ResultSink，也不允许直接 dispatch 一个 requested intent 冒充 result。

本阶段同时把现有 void run 改为 Future<void> run：8 个 effect 分支分别直接返回 _initialize / _detect / _updateProviderEnabled / _updateAccountDataEnrichment / _testConnection / _loadConfiguration / _saveConfiguration / _loadLogs 的真实执行 Future，分支内部不再 unawaited，也不返回伪造的已完成 Future。结果仍由上述具名 sink 结算 command Future；执行 Future 只证明该分支已开始的 I/O 与后续步骤结束。两类 Future 的完成时刻与错误语义不能混为一谈。

WP-5 在此接口上为探测增加 bool acceptDetectionResult(DetectionResultIntent result)，用来确认 opaque details handle 所属结果已经原子提交；它替换该工作流的逐项结果回流，不另建业务账本。本阶段不提前改变探测字段或引入其 outcome。WP-5 的 detect 由 ActiveDetectionRun 等待同一 run 返回值，非 detect effect 继续使用本章 trackAndReport。

### 4.2 Future 结算表：保留当前兼容语义

本表按当前 Store 的具名 ingress 和命令入口核实。M 阶段只迁 owner，不能把所有失败统一为 AgentCommandOutcome、null 或异常；WP-2/6 的 Conversation 命令结果契约不覆盖 Management。表中“关闭”指 owner 关闭时尚在等待的 Future；已完成的 Future 不再次结算。关闭后发起新命令沿用 StateError 拒绝。

| Operations / Future 类型 | 成功回流 | 失败回流与调用方结果 | 已关闭时未完成 Future | 保留的短路/重复请求行为 |
|---|---|---|---|---|
| initialize → Future<void> | initializationSucceeded；仅当前初始化 operationId 接受后完成 | initializationFailed 将原 error + stackTrace 交给 completeError；失败 intent 不带原异常 | StateError | 已初始化立即完成；并发初始化复用同一 Future；autoDetect 只触发后台 detect，不等待完整探测 |
| loadAvailableThreadProviders → Future<List<AgentProviderConfig>> | await initialize 后返回当前 availableThreadProviders | 初始化失败原样传播 | 若仍在等初始化，则同上抛 StateError | 不另建目录 waiter 或缓存 |
| detect → Future<void> | detectionCompleted 完成 void | detectionFailed 写入现有可展示错误，Future 正常完成 void；若 initialize 先失败，则传播初始化异常 | StateError | 已在 detecting 时直接正常完成，不再发一轮 detect |
| setEnabled → Future<void> | providerEnabledUpdated 完成 void | providerEnabledUpdateFailed 更新错误/回滚等现有 reducer 状态，Future 正常完成 void | StateError | 当前值相同直接完成 |
| setAccountDataEnrichmentEnabled → Future<void> | accountDataEnrichmentUpdated 完成 void | accountDataEnrichmentUpdateFailed 更新错误，Future 正常完成；初始化异常传播；能力不支持在 effect 前抛 UnsupportedError | StateError | 更新进行中或值未变时直接完成 |
| testConnection → Future<AgentConnectionTestResult?> | connectionTestSucceeded 返回完整 result；其 success 字段仍由 repository 给出 | connectionTestFailed 写现有错误并返回 null | StateError | 已在 testing 时立即返回 null，不新建 waiter |
| loadConfiguration → Future<AgentConfigurationDocument?> | configurationLoaded 返回 document | configurationLoadFailed 写现有错误并返回 null | StateError | 正在加载时立即返回当前 configuration，允许为 null |
| saveConfiguration → Future<AgentConfigurationSaveResult> | configurationSaved 返回 result | configurationSaveFailed 用原 error + stackTrace 完成错误；state 只收到不含原异常的 ConfigurationSaveFailed | StateError | 未载入 configuration 时，在发 effect 前抛现有 StateError；不新增保存互斥/合并语义 |
| loadLogs → Future<List<AgentLogEntry>> | logsLoaded 返回不可变 entries | logsLoadFailed 写现有错误，返回空列表 | StateError | 正在加载时立即返回当前 logs |
| validateConfiguration → String? | repository 返回原校验结果 | 同步异常按现有路径传播；不创建 Future | 不适用；关闭后调用抛 StateError | null 继续表示校验未发现错误 |
| selectAgent / providerSettingsChanged / runtimeFactsReplaced | 同步 intent 更新 | 没有 command Future | 公开选择命令关闭后拒绝；结果 ingress 关闭后忽略 | 设置/运行事实本身不创建 operation waiter |

detectionStarted / detectionProgressReported / agentDetected 是进度或实体结果，不终结 detect Future；detectionCompleted / detectionFailed 才结算。这里保留 WP-1 之后、WP-5 之前的探测缓存语义，WP-5 再按自己的测试修改已确认值/partial 行为。

保留原有分类型 completer，不引入 Map<OperationId, Completer<Object?>> 后再散落强转：

~~~dart
Completer<void>? initializeCompleter;
Future<void>? initializeFuture;
final voidCompleters = <OperationId, Completer<void>>{};
final connectionCompleters =
    <OperationId, Completer<AgentConnectionTestResult?>>{};
final configurationLoadCompleters =
    <OperationId, Completer<AgentConfigurationDocument?>>{};
final configurationSaveCompleters =
    <OperationId, Completer<AgentConfigurationSaveResult>>{};
final logsCompleters = <OperationId, Completer<List<AgentLogEntry>>>{};

void initializationFailed(OperationId id, Object error, StackTrace trace) {
  if (closed) return;
  final accepted = acceptsInitialize(id); // 在 reduce 清 pending 之前读取
  dispatchResultIntent(ManagementInitializationFailed(id));
  final waiter = initializeCompleter;
  if (accepted && waiter != null && !waiter.isCompleted) {
    waiter.completeError(error, trace);
  }
}

void configurationSaveFailed(
  OperationId id, String agentId, Object error, StackTrace trace,
) {
  if (closed) return;
  dispatchResultIntent(
    ConfigurationSaveFailed(operationId: id, agentId: agentId),
  );
  final waiter = configurationSaveCompleters.remove(id);
  if (waiter != null && !waiter.isCompleted) {
    waiter.completeError(error, trace);
  }
  // error/trace 到此为止：不拼进 intent、state、JSON、日志或 metrics。
}

void stopAcceptingCommandsAndSettleWaiters() {
  if (closed) return;
  closed = true; // 先封闭新命令、typed ingress 与 Runner 后续步骤
  final error = StateError('AgentManagementSliceStore is closed');
  // 保留既有关闭异常类型/兼容文字；不是新增用户可见文案。
  completePendingWithError(initializeCompleter, error);
  initializeCompleter = null;
  initializeFuture = null;
  for (final waiter in voidCompleters.values) completePendingWithError(waiter, error);
  for (final waiter in connectionCompleters.values) completePendingWithError(waiter, error);
  for (final waiter in configurationLoadCompleters.values) completePendingWithError(waiter, error);
  for (final waiter in configurationSaveCompleters.values) completePendingWithError(waiter, error);
  for (final waiter in logsCompleters.values) completePendingWithError(waiter, error);
  voidCompleters.clear();
  connectionCompleters.clear();
  configurationLoadCompleters.clear();
  configurationSaveCompleters.clear();
  logsCompleters.clear();
  // WP-5 接入后，在此同步 stopDetectionForShutdown()，再由 drain 等物理退出。
  // ref.onDispose 处理 ref.listen 的订阅；不读取已销毁 Ref，不关闭借用的 registry。
}

void closeOwner() => stopAcceptingCommandsAndSettleWaiters();
// ref.onDispose 的幂等兜底；只封入口/结算 waiter，不写 state、不假装完成异步排空。
~~~

completePendingWithError 是私有泛型 helper，仅当 waiter 非空且未完成时 completeError；不得改变已完成 Future。dispatchResultIntent 是私有 reducer 入口，关闭时直接返回，不执行 public command 的 requireOpen；各 result method 自己结算其匹配 operationId 的 waiter。state 是否接受迟到结果仍由既有 reducer 的 agentId/operationId 校验决定，不能只按“当前选中 Agent”替代；实体结果仍可更新原 Agent，同时不得覆盖当前选择。旧 operation 的 waiter 与新 operation 的 waiter 不互相结算。

Runner 接收 sink 后，run 开头及异步循环继续下一 Provider 前检查 sink.isClosed；关闭只停止新步骤和结果写入，不宣称已发出的 repository 配置写入被取消。旧 runner 捕获的是旧 sink，即使下一 app session 的 OperationId 序号重复，结果也不能经 provider 查找写到新 owner。

物理执行由 owner 跟踪 Runner 返回的 Future；不能拿 initializeFuture、voidCompleters 等调用方 waiter 作为资源释放证据。以下是本阶段的最小关停实现，physicalExecutions 不进入 Notifier.state：

~~~dart
final physicalExecutions = <Future<void>>{};
Future<void>? drainFuture;

void trackAndReport(Future<void> execution) {
  physicalExecutions.add(execution); // 同步登记，早于下一次事件循环/关停调用。
  unawaited(() async {
    try {
      await execution;
    } catch (error, trace) {
      // 已知业务失败已由 Runner 的具名 failure ingress 结算原调用方 Future。
      // 此处只兜意外执行异常；仅报告稳定分类，不打印原 error/trace，不再改 state。
      reportUnhandledSafeFailure(); // 错误报告端口自身不得抛出。
    } finally {
      physicalExecutions.remove(execution);
    }
  }());
}

Future<void> drainExecutions() {
  if (!closed) throw StateError('Management owner must stop before drain');
  return drainFuture ??= _drainPhysicalExecutions();
}

Future<void> _drainPhysicalExecutions() async {
  while (physicalExecutions.isNotEmpty) {
    await Future.wait<void>(
      List<Future<void>>.of(physicalExecutions),
      eagerError: false, // 同一批即使失败，也等其他已开始执行全部终结后才抛。
    );
  }
  // WP-5 接入后还要等待 drainDetectionExecutions()；它等待 executionDone，
  // 不能等待已被 canceled/closed 提前结算的 callerFuture。
}
~~~

close 只清逻辑 waiter，不能清 physicalExecutions；每个执行仅在 finally 终态移除。_detect 的 Future 包括顺序探测和其已开始的 _persistDetectionSummary 写入，_loadLogs 包括 discoverLogPaths 后的 readLogs，不能仅跟踪第一段 repository 调用。关停先封入口；已运行函数若不支持物理取消，就等其返回。正常关闭由 §7 app shutdown 先调用 stopAcceptingCommandsAndSettleWaiters，再 await drainExecutions，随后才释放借用的 runtime/registry/plugin 和 dispose container。意外执行失败若被本次 drain 捕获，保持原失败 Future，不重试、不谎报完成；错误对象/stackTrace 只在执行/调用方 Future 路径传播。

### 4.3 冻结 build 依赖，不因设置或运行事实重建 owner

本阶段 Management 是 app-session owner。初始 state、文本目录、repository/配置校验端口、时钟/operation generator、runner factory 都在创建该 app session 时解析，build 只用 ref.read 取得一次。它们不得把 Provider settings/runtime summary 作为 ref.watch 的构造依赖；后续设置和运行事实只通过具名 ingress 更新。

~~~dart
final agentManagementRunnerFactoryProvider =
    Provider<AgentManagementRunnerFactory>(
  (ref) => throw StateError('management runner factory not installed'),
);
final agentManagementSliceProvider = NotifierProvider<
    AgentManagementSliceNotifier, AgentManagementSliceState>(
  AgentManagementSliceNotifier.new, // 非 autoDispose，非 family(store)
);

class AgentManagementSliceNotifier extends Notifier<AgentManagementSliceState>
    implements AgentManagementOperations, AgentManagementResultSink,
        AgentManagementOwnerLifecycle {
  late final AgentManagementSliceEffectRunner runner;
  bool built = false;
  bool closed = false;
  // 使用 §4.2 的分类型 waiters；Operations 和具名 ingress 逐项迁入。

  AgentManagementSliceState build() {
    if (built) {
      // 不在同一个 Notifier incarnation 上重新创建 runner/reset state。
      throw StateError('Management owner requires a new app session');
    }
    built = true;
    final initial = ref.read(agentManagementInitialStateProvider);
    final createRunner = ref.read(agentManagementRunnerFactoryProvider);
    runner = createRunner(this); // 工厂不得在构造期回流或读取尚未返回的 state
    ref.onDispose(closeOwner);
    return initial;
  }

  bool get isClosed => closed;
  AgentManagementSliceState get current => state;

  void dispatchResultIntent(AgentManagementSliceIntent intent) {
    if (closed) return;
    final before = state;
    final transition = agentManagementSliceReduce(before, intent);
    if (!identical(transition.state, before)) state = transition.state;
    for (final effect in transition.effects) {
      trackAndReport(runner.run(effect)); // WP-5 前包括 detect；WP-5 后 detect 仅执行一次。
    }
  }
  // public Operations 先 requireOpen、登记对应 waiter，再调用上述 reducer 入口。
}
~~~

built 防护是非法接线的 fail-closed，不是日常重建策略。生产不允许 invalidate/refresh 这个活跃 owner；动态配置、运行事实、界面切换不得使它重建。若更换 repository/factory、语言冻结上下文或 app session，需要先 await 旧组合关闭，再创建新容器/新 owner；不得在已关闭 Notifier 中把 closed 重置为 false。测试从新 ProviderContainer 注入另一组依赖，不在运行中的业务 owner 上动态覆盖工厂。

factory 的 app 装配闭包只捕获当次 app-session 的稳定 repositories/文本目录/配置端口；它接收已存在的 sink，不持 Ref 回读自己的 Notifier。没有安全默认值的 application provider 只在 app 唯一入口安装，测试覆盖同一接缝；不重复 override。

活跃设置/WP-1 facts 的接线在 app 的独立 ingress provider 中完成，先取得已经 build 完的 sink，再 ref.listen 中立状态源。该 ingress provider 是单向的消费端，Management Notifier 不依赖它。要求：

1. 先同步注册后续更新，再同步读取 current 并分别调用 providerSettingsChanged / runtimeFactsReplaced；这段没有 await，不丢订阅与初始值之间的更新。
2. sink.current 在 build 返回后才可读；factory 构造不探测、不加载、不发送进度回调。
3. 对同一输入可做现有结构相等去重，但不再维护“最后一份 management state”镜像。
4. 订阅清理由持有 ref.listen 的 provider 处理；owner close 后具名 ingress 都先检查 closed，关停过程不依赖页面是否挂载。
5. 根组合 eager 创建 management owner 与该 ingress provider 后，才调用 initialize；这保证同步 fake/repository 回流时 waiter 已存在，状态发布不发生在 Widget 构造途中。

### 4.3.1 WP-3M 实施接缝校正（2026-09-06）

WP-3M 阶段边界：管理 owner 与设置 ingress 在应用组合中、Widget 之前建立并初始化；Shell 尚由 IdeHome 创建（WP-3C 再前移），因此首次事实订阅在挂载后的回调中借用 Shell source，先订阅再同步重读 current。这里不缓存 management state、不延迟 Runner 结果。多个借用者共享订阅，最后一个释放时只退订；同一 source 立即重接可用。IdeHome 卸载不关闭管理 owner。

现有中立源通过 `subscribe` 端口消费；独立 ingress provider 持有订阅并在 `ref.onDispose` 清理，不另外复制成 Riverpod 状态源。`AgentManagementCompositionInputs` 冻结 repository、定义、设置端口与文案。`ide_workbench_composition.dart` 当前只声明 `ManagementRuntimeFactsConnector`，不再创建管理组合。源码存在的 Project Threads/Conversation Deferred 和 registry 仍属于 P/C 阶段。

物理任务在调用可能同步回流的 Runner 之前登记完成桥，桥只随 Runner 的真实 Future 完成；因此 Runner 内重入关闭也能被 drain 等待，不将 caller waiter 当执行结果。

### 4.4 原子切换与验收

1. 按 §4.1 完整接口替换 Runner 的所有 Store 调用；原 _store.state 只读点改为 current。生产 Runner 与 fake 一起改为返回真实 Future；保留 fake 同步回流能力，不能靠多加一轮调度掩盖 waiter 登记顺序。
2. 迁移 state、Operations、各类 completer、_accepts 与 operation generator；只移除 listeners，不统一错误结果类型。
3. 使用冻结依赖建立 Notifier，再单向接入 Provider settings 与 WP-1 facts；build 不探测，initialize 显式执行。
4. Page/Editor/LogView 从 provider 读取 state 和 Operations；删除 Store 构造参数与 family(store)。
5. 删除镜像、DeferredRunner、旧 Store；WP-1 runtime facts 接口保持，WP-5 行为尚未执行。
6. 原测试逐一验证 §4.2 的成功/失败/关闭结果，补充原 error 对象和 stackTrace 能到达等待方、state 不包含它们的断言。
7. 在 settings/runtime source 连续变化时，Notifier/runner identity 不变、pending 不丢、factory 只调用一次；销毁旧容器再建新容器后，旧结果只能命中已关闭旧 sink。
8. 用可控 repository Future 验证 stop 后调用方收到既有 StateError、state 不再变化，但 drain 仍未完成；释放最后一个真实 I/O Future 后 drain 才完成。覆盖 detect 的后续写入和日志两段读取，关停期间不得提前关闭借用依赖；正常业务失败仍遵循 §4.2，不被执行跟踪器改写。

## 5. WP-3P：Project Threads owner 迁移

### 5.1 以前置 WP-4 为唯一业务基线

WP-4 必须先完成：同步规则和唯一映射已在 Store；Runner 保留真实 effect、I/O、分页合并与调度。这里只把该单 owner 迁为 application Notifier，保留 ProjectThreadsOperations、WP-4 收口后的 ProjectThreadsStateOwner 和生产 Shell 的操作路径，不恢复旧 Runner 同步 API。

本阶段不更换裸 threadId、selected/running/completed 字段、session v4 或现有 _runForThread 空结果语义。它也不依赖 WP-2 的 Conversation Future/outcome 设计。

### 5.2 冻结依赖与索引初始化

~~~dart
typedef ProjectThreadsRunnerFactory =
    ProjectThreadsSliceEffectRunner Function(ProjectThreadsStateOwner owner);

abstract interface class ProjectThreadsOwnerLifecycle {
  void stopAcceptingCommandsAndSettleWaiters();
  Future<void> drainExecutions();
}

abstract interface class ProjectThreadsSliceEffectRunner {
  void run(ProjectThreadsSliceEffect effect); // 保留 WP-4 的真实 effect 调度入口。
  void close(); // 只封闭调度并取消 Timer/失效 token。
  Future<void> drainExecutions(); // 拟新增：等待全部已经启动的物理执行。
}

class ProjectThreadsSliceNotifier extends Notifier<ProjectThreadsSliceState>
    implements ProjectThreadsOperations, ProjectThreadsStateOwner,
        ProjectThreadsOwnerLifecycle {
  late final ProjectThreadsSliceEffectRunner runner;
  late final DateTime Function() now;
  final projectByThread = <String, String>{};
  final voidCompleters = <OperationId, Completer<void>>{};
  final forkCompleters = <OperationId, Completer<AgentSession?>>{};
  bool built = false;
  bool closed = false;
  Future<void>? drainFuture;

  ProjectThreadsSliceState build() {
    if (built) {
      throw StateError('Project Threads owner requires a new app session');
    }
    built = true;
    final deps = ref.read(projectThreadsSliceDependenciesProvider);
    final createRunner = ref.read(projectThreadsRunnerFactoryProvider);
    now = deps.now;
    rebuildIndexFrom(deps.initialState); // 从参数读取，不提前读取 Notifier.state
    runner = createRunner(this); // 不在 factory 构造时执行 effect 或读取 owner.state
    ref.onDispose(closeOwner);
    return deps.initialState;
  }

  void applyProjectState(String project, ProjectThreadListState next) {
    if (closed) return;
    commitThroughExistingReducer(project, next);
    updateOwnerIndex(project, next); // 沿用 WP-4；不清除窗口外的显式映射
  }

  void stopAcceptingCommandsAndSettleWaiters() {
    if (closed) return;
    closed = true;
    for (final waiter in voidCompleters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    for (final waiter in forkCompleters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    voidCompleters.clear();
    forkCompleters.clear();
    projectByThread.clear();
    runner.close(); // 清 load tokens/搜索 Timer；不关闭借用的 runtime/BindingManager
  }

  Future<void> drainExecutions() {
    if (!closed) throw StateError('Project Threads owner must stop before drain');
    return drainFuture ??= runner.drainExecutions();
  }

  void closeOwner() => stopAcceptingCommandsAndSettleWaiters();
  // ref.onDispose 仅兜底封入口/结算，不写 state；正常路径先由 app await drain。
}
~~~

projectThreadsSliceDependenciesProvider 是本阶段文件清单中 dependencies 文件的明确声明，包含不可变 initialState、稳定 now 和 operation generator 工厂；runner factory 另用 projectThreadsRunnerFactoryProvider 声明。build 均使用 ref.read；Provider settings、项目 retain/restore/selection 变化继续通过 Operations/StateOwner 进入，不使 build 再跑。与 M 阶段相同，业务资源更换通过显式关闭旧 app session、创建新容器完成，禁止 invalidate 活跃 owner 后悄悄重建索引和 pending。

rebuildIndexFrom 只在第一次构造或现有 applyStatesReplacement 路径按 WP-4 规则运行，不能因设置更新、翻页或前台切换全量重建。保留每项目 _loadTokens、搜索 Timer、聚合 cursor 的 Runner 所有权；旧 Runner 在新容器建立后回流时仍指向旧 StateOwner，旧 closed ingress 不改 state/map。

Project Threads 保留 WP-4 的 void run / close 调度契约，因此其物理执行集合放在实际 Runner 内，由新增 drainExecutions 暴露等待。Runner 将每个 unawaited 启动点改为类似 §4.2 的 trackAndReport：同步登记真实 Future，终态 finally 才移除，意外执行错误只报告稳定分类；业务错误仍经既有 operationFailed 或分页 errorMessage 回流。至少逐一覆盖以下启动来源，不能只枚举 run 中有 operationId 的分支：

| 启动来源 | 必须跟踪至终态的 Future |
|---|---|
| restore effect 与 activate effect | 每个后台首屏 loadInitial；无 command waiter 也必须被 drain 等待 |
| search effect 的防抖 Timer | Timer 尚未触发时 close 取消；已触发的 loadInitial 跟踪到底 |
| toggle / archived view / initial / more | _completeVoid 的整个 Future，包括其 await 的首屏/翻页 Provider 聚合查询 |
| rename / archive / unarchive / delete | _completeVoid 的整个 Future，包括 Provider 操作、现有回流与已开始的清空步骤 |
| fork | _fork 的整个 Future，直到 Provider fork 与 forkSucceeded/operationFailed 回流结束 |

已经被某个已跟踪顶层 Future await 的内部调用无需再建第二份账本；真正脱离 await 链的后台启动必须单独登记。close 先使 Runner disposed，取消搜索 Timer、失效加载 token，但不清物理执行集合；dispose/token 只影响结果是否接受，不等于 Provider I/O 已取消。drain 在 close 之后等待集合中的全部真实 Future，使用 eagerError: false 等整批结束再传播失败；本次 drain 失败保持同一失败 Future。若无底层取消能力，只能等待其已有完成/超时，不能以本层短 timeout 继续释放 runtime/BindingManager/plugin。索引的清空和借用资源的释放仍分别属于 owner stop 与 app shutdown。

### 5.3 Project Threads Future 与关闭语义冻结表

| Operations / 回执 | 成功 | 失败 | owner 关闭时未完成请求 |
|---|---|---|---|
| toggleProject / setArchivedView / loadInitial / loadMore → Future<void> | operationSucceeded 完成 void；已有加载中/无下一页短路仍正常完成 | _loadPage 当前已消费的查询失败写现有 errorMessage 并保留缓存，外层仍可正常完成；真正抛至 _completeVoid 的异常由 operationFailed 用原 error + stackTrace 完成错误 | 正常完成 void |
| renameThread / archiveThread / unarchiveThread / deleteThread → Future<void> | Provider 操作及 Store 回流后 operationSucceeded 完成 void | 抛出的能力/端口/Provider 异常通过 operationFailed 原样完成错误；现有归属缺失/Provider 禁用导致 _runForThread 返回 null 的正常结束保持，不借本章改成 typed failure | 正常完成 void |
| forkThread → Future<AgentSession?> | forkSucceeded 返回 session；现有合法空结果仍返回 null | operationFailed 用原 error + stackTrace 完成错误 | 返回 null |
| restoreSession / activateProject / retainProjects / setSearchTerm | 保持现有同步命令及后台 effect，不新增等待 Future | 保持现有 Runner 调度/错误呈现，不编造新的结果类型 | 后续 typed ingress/Timer 不改已关闭 state/map |
| selection / runtime/title/preview/registration 同步操作 | WP-4 的唯一 Store 规则原样迁移 | 保持其既有前置校验与 _ensureOpen 口径 | 迟到 StateOwner ingress 忽略；不把关闭的 owner 复活 |

operationSucceeded / operationFailed / forkSucceeded 继续只结算匹配 OperationId。未知或重复回执按原 staleResultCount 规则处理，不能结算其他 waiter；dispose 后忽略回流。ProjectThreadsOperationFailed 继续作为临时 typed intent 携带 error/stackTrace，只用于 Future 结算，reducer 不把二者放进 ProjectThreadsSliceState、session v4、日志或指标。

该表与 Management 的关闭行为有意不同：Management 未完成请求抛 StateError，Project Threads void 正常完成、fork 返回 null。当前任务迁移所有权，不能为了“统一风格”改变调用方的结果契约。

### 5.4 组合顺序与迁移验收

创建顺序为：全局 runtime/BindingManager → Project Threads 稳定 dependencies → Notifier → Shell。将 BindingManager 的创建提升为 app provider；Shell 和 Workspace 借用同一个实例，不能分别创建两个管理器。现有 onActiveThreadCleared 只在 Shell 完整构造后安装一次，并在 Shell 关闭时解除；这是业务对象间已存在的 typed 回调，不是把 owner 注入 provider 的 relay。一次删除/归档只触发一次清空。

本阶段的必须保留证据：

- WP-4 的 33 条测试迁移结果全部保留，接收者从 Store 换成 Notifier 的 Operations/StateOwner；不得改回直接测试 Runner 的同名同步业务。
- 构造/restore/page/显式窗口外登记/remove/retain/close 的唯一索引行为保持；相同输入得到相同 state、排序、标题、运行指示和 v4 快照。
- 同步 fake effect 回流时 waiter 已登记，受影响 Future 按 §5.3 完整结算；关闭与重复回执不产生二次完成。
- Provider settings 与前台选中项目变化不重建 Notifier/runner；factory 在 app session 内一次，_now 仍可由测试固定。
- 新容器重建使用新 owner；旧 Runner 的迟到回流不写新 state，旧 map 不复活。
- shutdown 先 stop 再 drain：关闭时 void/fork 调用方立即按 §5.3 结算；一个可控 Provider 查询/写入尚未完成时，drain 仍 pending。额外覆盖没有 command waiter 的 restore/activate/Timer 触发查询，以及跨 Provider 聚合中仍未返回的最后一个 Future；直到全部结束，借用 runtime/BindingManager/plugin 都保持有效。
- 不依赖未来 WP-2 才出现的 outcome/waiter 辅助类型，P 阶段本身能够独立构建与全量验证。

### 5.5 WP-3P 实施接缝校正（2026-09-06）

- 依赖在 `project_threads_slice_dependencies.dart` 声明；app 的 `ProjectThreadsCompositionInputs` 是根 overrides 可替换的外部资源/初态接缝。application factory 只安装一次，不经 Ref 回读 Notifier。
- StateOwner 的手写 `subscribe` 与 Operations 的 `dispose` 从业务端口移除：Shell 借用 `projectThreadsChangesProvider` 提供的真实 Riverpod 订阅；关闭由 `ProjectThreadsOwnerLifecycle` 交给 app。业务 Operations 签名与 §5.3 结果契约保持。
- `activeThreadCleared` 是具名 typed ingress；Runner 不再持公共回调，owner 只在未关闭时调用现有 `onActiveThreadCleared`。Shell 完成构造后安装，卸载解除。
- `agent_session_resource_providers.dart` 提供唯一 manager/global runtime；Shell 不再自行创建或关闭 registry/global/manager，Workspace 不再有 manager fallback。普通 Widget 测试通过 `agentBindingSweepTimerFactoryProvider` 注入可控定时器；不因 Widget 卸载回收 app 资源，核心 idle sweep 行为继续由 BindingManager 专项测试验证。
- app 在显示语言冻结后、Widget 前建立 Project Threads owner；退出先 stop M/P，等待两者全部真实执行，再关闭 manager、registry、plugin、container。完整 Shell/workspace entry 生命周期与 snapshot relay 仍待 C，不提前登记 O-01 的 workspace 或 O-09/O-10 的完整 Shell 重挂保证。

## 6. WP-3C：稳定身份与 Conversation 单 owner

### 6.1 草稿晋升不能重建 owner

当前 core 的 `AgentConversationBindingKey` 从 `draft(providerId, entryId)` 晋升到 `thread(providerId, threadId)`。若真实 Notifier 直接按此 key 建 family，第一次发送中途会产生新 owner。因此保留公共 BindingKey selector，真实 owner 改为稳定内存身份。

```dart
// 拟新增；Object token 只比较同一对象，禁止序列化/日志/指标。
final class AgentConversationOwnerKey {
  const AgentConversationOwnerKey(this.entryId, this.lifetimeToken);
  final String entryId;
  final Object lifetimeToken;
  bool operator ==(Object other) => other is AgentConversationOwnerKey
      && other.entryId == entryId
      && identical(other.lifetimeToken, lifetimeToken);
  int get hashCode => Object.hash(entryId, identityHashCode(lifetimeToken));
}

final class AgentConversationSessionDependencies {
  const AgentConversationSessionDependencies({
    required this.ownerKey, required this.regions, required this.executor,
    required this.scopeSnapshot, required this.onProjectionUnobserved,
  });
  final AgentConversationOwnerKey ownerKey;
  final AgentConversationRegionSource regions;
  final AgentConversationCommandPort executor;
  final AgentConversationCommandScope Function() scopeSnapshot;
  final void Function(AgentConversationOwnerKey) onProjectionUnobserved;
}
```

Workspace 的资源表记录 `ownerKey`、初始 draft key、当前 BindingKey 和显式 lifecycle。晋升时原子增加真实 thread alias，两个 alias 指向同一 owner；冲突按 core 原规则拒绝。关闭先把 alias 标为 closing/closed，使旧 selector 能退出；投影回收后再删除 alias。同一 Thread 后续重开分配新 token，绝不复用原 pending 账本。旧 owner 回收只能删除仍指向旧 token 的 alias，不能误删重开后的映射。

### 6.2 Provider DAG 与装配

```text
Workspace dependencies（BindingManager、runtime 工厂、文本目录）
  → WorkspaceNotifier（私有资源表 + 不可变 entry/alias state）
    → sessionDependencies(ownerKey) → ConversationSliceOwner(ownerKey)
    → bindingKey→ownerKey selector → 公共 region/action facade

WorkspaceNotifier + BindingManager
  → runtimeFactsSourceProvider（独立 app provider）
    → ManagementNotifier

workbenchSessionProvider
  → WorkspaceNotifier / ProjectThreadsNotifier / ManagementNotifier
  → Shell + ConversationSliceLifetimeCoordinator
  →（协调器创建/关闭时）ConversationSliceOwner

禁止 WorkspaceNotifier → workbenchSessionProvider 或 → ConversationSliceOwner。
禁止 ConversationSliceOwner → Shell/workbenchSessionProvider。
禁止 runtimeFactsSourceProvider → workbenchSessionProvider / ManagementNotifier。
```

依赖对象的 factory 在 app 定义生产实现；application 只声明 fail-closed 接缝。Workspace 的资源表是真实 owner，不需要在 IdeHome mount 后注入 resolver。

```dart
// application 中声明；app 在唯一接线处安装实现。
final agentConversationSessionDependenciesProvider = Provider.autoDispose.family<
    AgentConversationSessionDependencies, AgentConversationOwnerKey>(
  (ref, key) => throw StateError('conversation dependencies not installed'),
);

// app 的实现骨架：仅在 owner 初建时解析一次完整资源。
AgentConversationSessionDependencies resolveSessionDependencies(Ref ref, OwnerKey key) {
  return ref.read(agentConversationWorkspaceProvider.notifier)
      .requireLiveSessionDependencies(key); // 验证 token；不创建 CLI/session
}

sealed class AgentConversationOwnerResolution {}
final class AgentConversationOwnerLive extends AgentConversationOwnerResolution {
  final AgentConversationOwnerKey ownerKey;
}
final class AgentConversationOwnerClosing extends AgentConversationOwnerResolution {}
final class AgentConversationOwnerClosed extends AgentConversationOwnerResolution {}
final class AgentConversationOwnerUnknown extends AgentConversationOwnerResolution {}

// application 声明，app override：纯查询 workspace 的不可变 alias/lifecycle。
// 未安装 override 抛 StateError；已安装但 alias 不存在返回 Unknown。
final agentConversationOwnerResolutionProvider = Provider.autoDispose.family<
    AgentConversationOwnerResolution, AgentConversationBindingKey>(resolveAlias);

final agentConversationSliceOwnerProvider = NotifierProvider.family<
    AgentConversationSliceNotifier, AgentConversationSliceState,
    AgentConversationOwnerKey>(AgentConversationSliceNotifier.new);

// 原公开名字变成派生 Provider；外部仍通过 BindingKey 查询。
final agentConversationSliceProvider = Provider.autoDispose.family<
    AgentConversationSliceState, AgentConversationBindingKey>((ref, bindingKey) {
  final resolution = ref.watch(agentConversationOwnerResolutionProvider(bindingKey));
  return switch (resolution) {
    AgentConversationOwnerLive(:final ownerKey) =>
      ref.watch(agentConversationSliceOwnerProvider(ownerKey)),
    AgentConversationOwnerClosing() || AgentConversationOwnerClosed() =>
      AgentConversationSliceState.closedProjection(),
    AgentConversationOwnerUnknown() =>
      AgentConversationSliceState.unavailableProjection(),
  };
});
```

上面示意类型 `OwnerKey` 是 `AgentConversationOwnerKey` 的简称；生产文件不得另建等价 key 类型。`resolveAlias` 的生产实现只 watch 指定 BindingKey 的不可变解析结果；Closing/Closed/Unknown 不得读取 owner family 或 session dependencies。`closedProjection/unavailableProjection` 是拟新增的空 regions + 终止/不可用标记，不包含正文、controller、历史引用，也不能作为命令成功结果。未安装组合接缝仍立即报错，不能用 Unknown 吞掉装配缺失。

物理 owner 的初始依赖用 `ref.read` 冻结在本次 lifetime 内；动态 region/settings/runtime 通过具名 ingress 更新，不让 build 因依赖变化重跑。应用运行期间禁止直接 invalidate 活跃 owner；测试 override 在首次创建前安装，需要更换依赖时显式关闭旧 entry 并创建新 token。WP-2 的 Actions 在**取得时**捕获 Live 的 ownerKey/lifetime；执行时只检查该 handle 的有效性，不按 BindingKey 重新寻找 owner。这样重开同 Thread 后，旧回调也不能落到新会话。

### 6.3 Conversation owner 的构造与通知

```dart
class AgentConversationSliceNotifier extends Notifier<AgentConversationSliceState>
    implements AgentConversationCommandResultSink {
  AgentConversationSliceNotifier(this.ownerKey);
  final AgentConversationOwnerKey ownerKey;
  late AgentConversationSessionDependencies deps;
  late AgentConversationCommandEffectRunner runner;
  bool _closed = false; // 与 WP-2 的 Actions/账本共享唯一标志

  AgentConversationSliceState build() {
    deps = ref.read(agentConversationSessionDependenciesProvider(ownerKey));
    runner = AgentConversationCommandEffectRunner(
      commands: deps.executor, sink: this,
      scopeSnapshot: deps.scopeSnapshot, ownerLifetime: ownerKey.lifetimeToken,
    );
    final initial = snapshotRegions(deps.regions);
    // addUiUpdateListener 按当前约定不立即回调；如改为会回调则先暂存，build 后提交。
    deps.regions.addUiUpdateListener(onRegionsChanged);
    ref.onDispose(cleanupWithoutPublishingState);
    installClosedProjectionEvictionHooks(); // §7.2；不负责释放业务资源
    return initial;
  }

  void onRegionsChanged(AgentUiUpdateRequest request) {
    if (_closed || request.isEmpty) return;
    final intent = snapshotOnlyRequestedRegions(request, deps.regions);
    if (!intent.isEmpty) state = agentConversationSliceReduce(state, intent).state;
  }

  void closeForEntryRelease() {
    if (_closed) return;
    closeCommandIngress(); // 先设置同一个 _closed，再恰好结算一次全部waiter
    deps.regions.removeUiUpdateListener(onRegionsChanged);
    runner.stopAcceptingAndDiscardQueuedCommands(); // 不持第二份owner账本
    state = AgentConversationSliceState.closedProjection();
    clearRegionExecutorAndPendingPayloadReferences();
    // 这里不 dispose controller，不 release lease。
  }
}
```

一次 `AgentUiUpdateRequest` 仍对应一次 RegionsRefreshed；live-turn 与一次性 UI effects 不经此 state 复制。Notifier 不再继承/包装旧 Store，不把 `ref` 或 Notifier 下沉到 core。上面 `deps/runner` 实现时使用可清空字段；关闭先保存必要局部引用再退订、结算、置空。`ref.onDispose` 只调用不发布 state 的幂等兜底清理；显式 `closeForEntryRelease` 才在 Ref 有效时发布终止投影。已关闭 Actions 的返回不得再次访问已 dispose 的 Ref。

`closeCommandIngress` 是本章与 WP-2 **同一个方法**：设置 `_closed`、按该阶段结果契约结算所有 owner waiters、清空账本；不再另留 `closed` 或 `settleOwnerWaitersAsClosed` 第二实现。WP-3C 先按旧命令契约迁移，WP-2 替换为其 §2.6 的 typed outcome 实现。该方法内部只在入口检查一次 `_closed`，不能设置后再调用一个因 `_closed` 而提前返回的结算 helper。`cleanupWithoutPublishingState` 在 Ref 销毁时调用同一个 closeCommandIngress，再幂等退订/清引用，但不读取或写入 state。

SessionDependencies/OwnerResolution/Actions 三种纯查询 family 统一 autoDispose：它们不关闭资源，避免关闭后缓存还持有旧 controller 或 BindingKey。真实 owner 仍非 autoDispose，且由 coordinator 显式关闭；两者不可混淆。

WP-3C 暂时保留现有 UI 命令指向 executor 的行为，迁移状态发布不同时重写所有命令；WP-2 紧接着切换唯一 Actions 入口。该阶段不得宣称“命令已统一”，保留 WP-2 未完成状态。

## 7. 完整工作台组合与显式关闭

### 7.1 构造与启动分离

修改 `IdeShellController`：构造函数只接已创建的 Workspace/ProjectThreads operations、runtime/BindingManager、文本端口和 lifetime coordinator，不再内部 `new` 这些 state owner，不在构造期触发异步恢复。

```dart
// 拟新增 app provider。依赖的 application owner 都不依赖本 provider。
final workbenchSessionProvider = Provider<WorkbenchSession>((ref) {
  final workspace = ref.read(agentConversationWorkspaceProvider.notifier);
  final threads = ref.read(projectThreadsSliceProvider.notifier);
  final management = ref.read(agentManagementSliceProvider.notifier);
  final lifetimes = ConversationSliceLifetimeCoordinator(
    workspace: workspace,
    createSlice: (key) => ref.read(agentConversationSliceOwnerProvider(key).notifier),
    retainSliceProjection: (key) => ref.listen(
      agentConversationSliceOwnerProvider(key), (_, next) {},
    ), // 协调器持有此 subscription；用途只是避免过早回收投影
    // 清理的只是已关闭的轻量投影，不能借此杀进程。
    invalidateClosedSlice: (key) => ref.invalidate(agentConversationSliceOwnerProvider(key)),
  );
  final shell = IdeShellController(
    conversationWorkspace: workspace, projectThreads: threads,
    conversationLifetimes: lifetimes, /* 其余既有窄依赖 */
  );
  final session = WorkbenchSession(shell, lifetimes, management);
  ref.onDispose(session.disposeSynchronousFacades);
  return session;
});

// ZetaAppComposition：文本目录/Provider settings装配后、Widget挂载前。
final workbench = container.read(workbenchSessionProvider);
workbench.start(); // 幂等：bootstrap draft、settings加载、预热、恢复
// ready 的语言冻结语义不变；后台恢复不变成全局阻塞。

// IdeHome.initState 只读这份对象；dispose 不再关闭 app-session owners。
final shell = ref.read(workbenchSessionProvider).shell;
```

`start()` 先令完整 Shell 对象可用，再创建初始 entry。需要 `onCreatedThread` 的 RuntimeController，通过 Shell 发起 `openEntry` 时将已存在的 Shell 方法作为**不可变构造参数**交给 entry factory；不是先填 null 后 bind 的 provider relay。资源 factory 不持 Ref 回读 Shell。

取 `workbenchSessionProvider` 不触发真实 turn/start；新增资源仍只创建 Binding/controller，session runtime 的首次创建继续只能经 `beginTurn()`。

### 7.2 创建、晋升、关闭的顺序

```dart
EntryHandle openEntry(OpenRequest request) {
  // 本方法在 Shell/application command 或启动阶段调用，不在 Widget.build。
  final entry = workspace.ensureEntryResources(request);
  // workspace 先登记完整资源及 immutable identity，family 解析才能成功。
  final slice = lifetimes.ensureSlice(entry.ownerKey);
  // ensureSlice 幂等，不能因为前台切换重复建 notifier。
  return EntryHandle(entry.ownerKey, slice);
}

void onBindingPromoted(EntryResources entry, BindingKey next) {
  workspace.promoteAliasAtomically(entry.ownerKey, next);
  // ownerKey、notifier实例、pending id、输入/滚动仍保持。
}

Future<void> closeEntry(OwnerKey key) {
  final existing = entryCloseFutures[key];
  if (existing != null) return existing;
  if (!workspace.hasEntryResources(key)) return Future<void>.value();
  return entryCloseFutures.putIfAbsent(key, () async {
  final resources = workspace.markEntryClosing(key); // 拒绝新命令；旧句柄能辨识closed
  lifetimes.closeSliceIngressAndWaiters(key);
  workspace.removeEntryFromVisibleState(key); // alias 保留 Closing
  resources.detachSnapshotSubscriptions();
  resources.controller.dispose();
  await resources.bindingLease.release();
  workspace.finishResourceRemoval(key);
  workspace.markAliasesClosedIfStillOwnedBy(key);
  releaseCompletionMarkers.add(key); // coordinator 的短期投影回收标记
  lifetimes.releaseProjectionSubscription(key); // owner 无资源；等待纯投影无观察者
  });
}
```

`markEntryClosing` 不替换 session deps 的 lifetime token，也不通过 rebuild 关闭 owner；它只改变可接受命令的显式状态。`closeEntry` 对同 key 复用同一 Future，失败也保留同一终态，报告规范化关闭诊断并保持 Closing，不声称资源已释放。**本包不引入关闭重试协议。** 当前 core lease 的 `release()` 在转交 manager 前已清空内部 manager 引用，简单再调一次不能证明重试成功；本包不得在上层制造这种假保证。关闭失败时禁止调用 `finishResourceRemoval`，shutdown 必须传播失败，不能把容器已销毁当成资源关闭证据。成功后的 Future 缓存在投影回收时删除；再关闭已不存在的 ownerKey 直接完成，不创建资源。

`bindingLease.release()` 只是释放该 entry 的 consumer 引用，**不等于 CLI 已退出**；共享/空闲 Binding 继续遵循现有 Manager/Registry 的回收策略。进程退出的完成证据只来自 §7.3 的 registry close。O-08 应断言一次 lease 释放，而不能断言关一个 Canvas 就杀进程。

**同帧 UI 退场约束**：撤下 entry 后，旧 Widget 可能尚未完成下一次 build。公共 selector 根据 Closing/Closed 返回终止投影；回收后的 Unknown 返回不可用空投影；Actions 均拒绝新调用。两种投影都不读取真实 owner，不创建 runtime，不使退场 UI 抛错。物理 owner 也先清空持有的资源引用，保证旧 handle 不延长资源生存期。

```dart
// 物理 owner 内：只回收已经显式关闭的投影，绝不决定业务存活。
// ensureSlice 创建后立刻由协调器 retain 一份订阅，再向UI暴露entry。
bool observed = true;
int evictionRevision = 0;
void installClosedProjectionEvictionHooks() {
  ref.onCancel(() { observed = false; scheduleEviction(); });
  ref.onResume(() { observed = true; evictionRevision++; });
}
void scheduleEviction() {
  final revision = ++evictionRevision;
  scheduleMicrotask(() {
    if (!_closed || observed || revision != evictionRevision) return;
    // 注入 app 级回收回调；不调用 controller/lease/registry。
    onProjectionUnobserved(ownerKey);
  });
}

// coordinator：onProjectionUnobserved 的实现。
void evictClosedProjection(OwnerKey key) {
  if (!releaseCompletionMarkers.contains(key)) return;
  invalidateClosedSlice(key); // 此时已无订阅，不会立刻重建 owner
  workspace.removeClosedAliasesIfStillOwnedBy(key);
  ownerHandles.remove(key);
  entryCloseFutures.remove(key);
  releaseCompletionMarkers.remove(key);
}
```

`releaseCompletionMarkers` 是 coordinator 在 `finishResourceRemoval` 成功后登记的短期集合，只存 OwnerKey，不存资源；不能为此在 workspace state 保留另一套永久完成账本。`onProjectionUnobserved` 由完整 Shell 的 `openEntry` 把已构造 coordinator 的方法作为不可变资源依赖传入，和 `onCreatedThread` 一样不使用后补 bind；它只做投影回收，不是业务状态入口。关闭后的 owner 仅保留这个清理回调与 identity，清掉 regions/executor；回收后 owner 也不再被 coordinator 持有。正常 public facade 在解析 Closing 后自动解除对物理 owner 的依赖；它自身可以 `autoDispose`。仍持有原始 owner 的应用级观察者必须遵守同样退订协议，不能把它公开给 Widget。临时重新订阅通过 revision 取消过期微任务。**资源释放不等待 Flutter frame，也不等待 UI 退订。**

这是纯投影回收，不是由 autoDispose 决定业务存活。需要在测试中固定：从未挂载 Widget 的 entry 也能关闭；旧 selector 退场不抛错；反复开关后 registry/family 保留对象数不随已关闭 entry 持续增长。

### 7.3 应用退出与测试 teardown

```dart
Future<void> shutdown() => closeFuture ??= () async {
  shell.stopAcceptingCommands();
  management.stopAcceptingCommandsAndSettleWaiters();
  threads.stopAcceptingCommandsAndSettleWaiters();
  await shell.flushExistingSessionSave(); // 沿用现有持久化白名单
  // WP-5 callerFuture=canceled不等于detect已返回；同时等待全部已启动I/O。
  await management.drainExecutions();
  await threads.drainExecutions();
  runtimeFactsSubscription.close(); // 先停止消费者 ingress
  runtimeFactsSource.close(); // 再退订 Binding/Controller；该 source 不释放 runtime
  await lifetimes.closeAllEntries();
  await bindingManager.close();
  await shutdownAgentResourcesInOrder(
    closeRuntimeRegistry: runtimeRegistry.close,
    closePluginCatalog: pluginCatalog.close,
  );
}();

Future<void> closeComposition() async {
  await shutdown();
  container.dispose();
}
```

生产 native shutdown hook 必须 await；新增 `ZetaAppComposition.close(): Future<void>` 供测试 `addTearDown(composition.close)`。为兼容 Flutter 同步 dispose，可保留启动同一 closeFuture 的 `dispose()`，但它不是完成证明；需验证进程释放的测试必须 await close。资源关闭不得从 dispose 中读取已销毁的 Ref，所需 closer 在容器仍有效时取得。

Management/Project Threads 的关闭负责停止自己的任务和结算 waiter，不关闭借用的 runtime registry。BindingManager/runtime/plugin 只由 app 组合根拥有，避免 Shell、workspace、composition 重复释放。

拟新增的 `drainExecutions()` 必须跟踪实际 Runner 返回的每个已启动 Future：Management 由 owner 的 trackAndReport 跟踪，WP-5 探测另等待该轮 executionDone；Project Threads 由 Runner 跟踪其启动的执行与后台任务。完成后在 `finally` 移除，只等待物理执行终态，不为同一 Future 建两份状态账本；cancel token 只使逻辑请求结算，不从 tracked set 提前删除。关闭顺序先禁入口、再结算、再排空，禁止以 timeout 后直接 close plugin 假装退出完成。若现有依赖不提供物理取消，本包如实等待其返回，不新造成功结果。任一关闭阶段失败，`closeFuture` 仍以原失败完成，`container.dispose()` 不执行；重复 await 得到同一失败，调用者显示规范化诊断。`closeAllEntries` 应逐个尝试所有 entry 并汇总失败，避免第一个失败使其余 entry 完全未尝试；但存在失败时不能宣称整体已关闭。

### 7.4 根快照和测试注入

- `takeStateSnapshot()` 在 app 直接读取 workbench/owners 的白名单摘要；删除 `ZetaShellStateSnapshotRelay` 和 IdeHome 的 snapshot reader bind/unbind。
- UI 仍不得订阅完整 `ZetaStateSnapshot`；局部 selector 保持，诊断不得加入正文。
- 测试通过 root overrides 替换 repositories/clock/scheduler/ports；不使用 `family(store)`、nullable controller 或 registry.bind 补出一个特殊测试世界。
- 仅测 Conversation owner 时覆写其 `SessionDependencies(ownerKey)`，传 fake region/executor；测试始终构造完整 immutable deps。
- 生产 defaults 写在 app provider body；application 的 fail-closed factory 接缝只安装一次。不要让测试与根组合重复 override 同一键。

## 8. 分阶段开发清单

- [x] **M-1**：抽出 Management result sink/factory，列出 Runner 对原 Store 的调用矩阵。
- [x] **M-2**：迁 Notifier、替换 UI family(store)、删镜像/Deferred；WP-1 summary ingress 不变。
- [x] **P-1**：确认 WP-4 回归与唯一索引已合入，迁 Project Threads Notifier。
- [x] **P-2**：Shell 注入 Operations，独立 BindingManager provider 建立，删旧 composition/store。
- [ ] **C-1**：引入 OwnerKey 与资源 deps，先补草稿晋升/ABA/无 UI 装配回归。
- [ ] **C-2**：Workspace state 迁 Notifier，entry 去掉 SliceStore；保持 reducer不变量。
- [ ] **C-3**：Conversation state迁Notifier、BindingKey facade、lifetime coordinator，删除两个registry。
- [ ] **C-4**：Shell 构造/start分离、workbench组合前移、退出和snapshot接线迁移。
- [ ] **C-5**：删除旧owner/镜像/Deferred，更新架构文档和守卫，完成全部门禁。

M/P/C 各阶段可单独提交；P 阶段如暂时仍由旧 workspace 持有 BindingManager，必须作为同提交内部过渡完成到唯一 app provider，不能提交两份管理器并存的状态。

## 9. 测试矩阵与验收

| ID | 触发 | 必须断言 | 测试归属 |
|---|---|---|---|
| O-01 | root composition ready，无 Widget | 可读取 workspace、management、threads；没有 bind prerequisite；没有 CLI turn | `test/src/app/composition/` 新测试 |
| O-02 | 覆写一个fake依赖 | 调用方override生效、没有重复override断言 | 同上 |
| O-03 | 同一事件同步返回 | reducer/state/effect执行一次，waiter不丢，不需要镜像微任务 | management/threads application |
| O-04 | listener/UI 渲染异常 | 已接受的业务effect不因手写listener抛错被跳过；错误仍可观察 | management应用回归 |
| O-05 | 两Provider两Canvas同时send | 不串regions/pending/scope；后台持续 | 现有Shell/Conversation Widget测试 |
| O-06 | draft发送后晋升 | 同一个notifier与ownerKey、pending正常结算，旧draft/current alias一致 | Conversation应用+Widget |
| O-07 | 同thread关闭重开，旧请求迟到 | 新token，新owner；旧结果不改新state且旧Future结算 | Conversation应用 |
| O-08 | 命令执行中closeEntry，重复close | 一次退订/释放、所有pending终结、重复close等待同Future | app lifetime测试 |
| O-09 | old Widget同帧退场，或无UI entry | 无异常/重建runtime；闭合后无资源或family累积 | Widget+生命周期测试 |
| O-10 | 设置/统计切页与IdeHome重挂 | 原Binding/runtime/草稿/滚动/宽度保持 | `ide_shell_widget_test.dart` |
| O-11 | shutdown存在延迟lease release | release结束→registry结束→plugin关闭；teardown await | `agent_resource_shutdown_test.dart` |
| O-12 | locale未冻结/已冻结 | 未冻结不创建含文案runtime，冻结后只创建一组owner | composition本地化测试 |
| O-13 | runtime restart或别名更新 | controller允许换runtime，slice owner不替换，scope正常阻止旧结果 | Conversation scope测试 |
| O-14 | WP-1管理摘要与WP-4线程规则 | 源owner迁移后相同输入得到相同投影 | WP-1/WP-4回归全部保留 |
| O-15 | entry/registry关闭抛错，再次await | 同一失败终态；未成功阶段不标released、不先关plugin、不销毁容器掩盖失败 | app关闭顺序测试 |

现有重点文件：`test/src/features/agent/presentation/agent_conversation_slice_providers_test.dart`、`test/src/features/agent/application/conversation_slice/agent_conversation_slice_store_test.dart`、`test/src/features/agent_management/application/agent_management_slice_store_test.dart`、`test/src/features/project_threads/application/project_threads_slice_store_test.dart`、`test/src/app/ide_shell_controller_test.dart`、`test/src/app/ide_shell_widget_test.dart`、`test/src/app/composition/zeta_state_snapshot_test.dart`。测试文件可随 owner 更名；断言迁移必须保持语义，特别是“移除UI订阅不释放会话”。

M 阶段守卫已落在 `test/src/architecture/agent_management_owner_guard_test.dart`，只覆盖管理 owner/Runner/UI；P/C 再补完整 `test/src/architecture/slice_owner_boundary_guard_test.dart`（拟新增），通过 AST 扫真实生产符号：本包指定目录无镜像 Notifier、无两种registry、无Deferred；IdeHome不创建/释放业务owner；workspace不依赖slice owner；UI不构造runner。对每条规则加一个最小反例，核心AgentListenable/局部Widget State明确不在禁用范围。

验收需证明单 owner 和生产接线，而非仅旧类名消失。M/P/C 收尾分别运行格式化、analyze、受影响测试与完整门禁；最后补真实工作台的切页/后台运行/退出验收记录。没有真实桌面验收时记“待执行”，不推断通过。

## 10. 回滚与规范同步

回滚以 M/P/C 提交为单位；已依赖新 owner 的 WP-2/WP-5 必须先回退，不能重新引入并行镜像救场。数据格式不变，无数据回滚脚本。

同步 `AGENTS.md` §3、工程规范 §3.0/§3.1、开发者指南 Conversation Slice 接入、架构总览中英文、术语表 owner/BindingKey、根 snapshot/关闭设计。给旧 2026-09-03 WP-1 追加后继文档引用，不改其历史目标和验收证据。本阶段保留尚未执行的 WP-2 命令迁移状态，不能提前删除其入口测试。

## 11. WP-3M 实施验收（2026-09-06）

M 阶段已完成，P/C 仍未开始。生产结果入口、原断言审计、13 条新增行为回归和 4 条 AST 守卫，以及 format/analyze/affected/full 的当次证据见 [WP-3M 验收记录](../../refactor/2026-09-06-management-owner/00-validation.md)。完整门禁根 2024 + 内部包 1076 通过；真实桌面手动验收仍待执行。首次 Shell 事实接线的 M 阶段调整见 §4.3.1，不代表 O-01/06/07/08/09/11 的完整 Workspace/Conversation 迁移已经完成。

## 12. WP-3P 实施验收（2026-09-06）

P-1/P-2 完成，详见 [验收记录](../../refactor/2026-09-06-project-threads-owner/00-validation.md)，实现提交 `c2a5219d`。

- 唯一 Project Threads Notifier 与 app BindingManager/global runtime 已接入生产 Shell；旧 Store、镜像、Deferred、重复 manager fallback 删除。
- WP-4 的 33 条原业务测试/131 条断言全部保留；本次开始的 51 条 Store/Runner 测试及其 201 条断言保留。23 条新增回归覆盖同步结算、依赖冻结、ABA/迟到 ingress、真实执行排空、关闭资源顺序、早退出与结构负例。
- format、analyze、affected、full 均退出 0；完整门禁根 2047 条 + 内部包 1076 条，10 个内部包分析通过。依赖、协议包、v4 codec、intent/effect/reducer 和测试并发无变更。
- Shell Widget/恢复/分层回归通过；真实 CLI 和桌面手工退出未执行。完整 Shell/Workspace/Conversation 的无 UI 装配、重挂与 entry 生命周期仍由下一项 WP-3C 承接，不扩大本次完成范围。
