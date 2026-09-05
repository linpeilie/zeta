# WP-5 · 首页探测流程归入 Management application 单一 owner

> 状态：未开始。前置：WP-3M。运行状态归属沿用 WP-1。 统一约束见 [总入口](00-index.md)。本章新 API 与代码块均为目标设计。

### 5.1 基线事实与确定方案

依赖WP-3的 `AgentManagementSliceNotifier` 单一owner；WP-1提供最新运行事实覆盖层。实施时不新增第二个Home store，也不保留一个镜像Notifier。

现状：IdeHome维护 `_homeProvidersLoading`、`_installedHomeProviders`、`_homeProviderError`、load token、缓存回滚及post-frame重建；其 `_loadHomeProviders` 分成注入loader路径与真实 `initialize → detect` 路径。management reducer则在每次partial progress时直接覆盖 `agentsById`，每个Provider成功继续覆盖；全局失败保留部分结果。首页失败时又回退整份Widget缓存。因此两页可能展示不同轮次的“已安装/登录/版本”事实。

确定方案是**同一个management state管理逐Provider确认结果、单轮暂存结果和探测状态**：

- 两页的正式安装/账号/版本列表都来自同一份confirmed结果；同一个Provider仅在其探测完整成功后提交。progress partial只进入该轮pending区域，不能把未知/半成品覆盖已成功事实。
- 一轮里A成功、B失败时保留A的新成功与B的上次成功，明确标记本轮partialFailure。不把A也回滚；不存在首页独自回滚的路径。
- 首次无成功数据时显示“尚无确认结果+探测中/失败”，不得将探测异常解释成“未安装”。`notInstalled` 只能由一次成功探测明确返回。
- 管理页可以额外展示当前pending进度/部分字段，必须清楚属于“探测中”，正式行的安装状态与首页仍使用同一confirmed selector。首页行本身不展示未经确认的新Provider。
- 每个Provider成功时提交探测字段；enabled、配置能力、runtime摘要来自各自当前owner。探测开始时捕获的旧 `ManagedAgent.enabled/runtimeState` 不得反向覆盖新设置或WP-1运行事实。
- 整个Workbench生命周期内单轮探测single-flight，初始化期间的并发请求也共享同一个Future。页面切换与暂时无Widget订阅不会取消或重新探测。

### 5.2 目标文件与API

| 位置 | 变更 |
|---|---|
| 拟新增 `lib/src/features/agent_management/application/agent_management_detection_port.dart` | 所有生产与测试使用同一探测依赖接口；operation/取消只在application与app之间传递 |
| 拟新增 `lib/src/features/agent_management/application/agent_management_detection_state.dart` | confirmed、pending、outcome、run状态等纯Dart不可变值 |
| 修改WP-3的 `agent_management_slice_notifier.dart`、既有state/reducer/intents/effects | 唯一探测状态owner、single-flight入口、typed result ingress |
| 拟新增 `lib/src/app/agent_management_slice/contributed_agent_management_detection_adapter.dart` | 通过已校验contributions取得repository，复用现有探测/白名单持久化逻辑 |
| 拟新增 `lib/src/features/agent_management/application/agent_management_home_state.dart` | `HomeProviderStatus`、`HomeProviderSummary`、`AgentManagementHomeState` 与纯selector；从UI文件迁出纯模型 |
| 拟新增 `lib/src/features/agent_management/presentation/agent_management_details_catalog.dart`；app添加同目录适配实现 | 只负责详细资料的安全显示标签和用户显式复制动作；句柄不进入Home行模型 |
| 修改 `global_home_page.dart` 与 `ide_home.dart` | 只传/订阅home state，删除缓存、load token、post-frame同步、测试loader分支 |
| 修改WP-3组合providers与测试助手 | 覆写统一 `AgentManagementDetectionPort`，删除 `HomeProviderDetectionLoader` 专用接缝 |

```dart
// 全部拟新增；名字可按WP-3统一，职责不可改成第二个state owner。
enum ManagementDetectionPhase {
  neverRequested, initializing, running,
  succeeded, partialFailure, failed, canceled,
}
enum ProviderDetectionOutcome { pending, succeeded, failed, canceled }
enum DetectionFreshness { noConfirmedData, restoredCache, confirmedThisRun, stale }

enum DetectionRunStatus { succeeded, partialFailure, failed, canceled, closed }
final class AgentManagementDetectionRunResult {
  const AgentManagementDetectionRunResult._(this.status, [this.failure]);
  static const succeeded = AgentManagementDetectionRunResult._(DetectionRunStatus.succeeded);
  static const partialFailure = AgentManagementDetectionRunResult._(DetectionRunStatus.partialFailure);
  static const canceled = AgentManagementDetectionRunResult._(DetectionRunStatus.canceled);
  static const closed = AgentManagementDetectionRunResult._(DetectionRunStatus.closed);
  factory AgentManagementDetectionRunResult.failed(AgentManagementFailure failure) =>
      AgentManagementDetectionRunResult._(DetectionRunStatus.failed, failure);
  final DetectionRunStatus status;
  final AgentManagementFailure? failure; // 只含规范化种类；详细失败按provider在state查询
}
// 下文 RunResult/ConfirmedRecord 仅是AgentManagementDetectionRunResult 与 AgentDetectionConfirmedRecord 的伪代码简称。

@immutable
final class AgentDetectionConfirmedRecord {
  final AgentDetectionDetails details; // 拟新增探测专属字段值对象，见下方白名单。
  final DateTime? confirmedAt;
  final DetectionFreshness freshness;
}

// 新application DTO只传语义，不再复制当前ManagedAgent的私有路径字段。
@immutable
final class AgentManagementDetailsHandle {
  final Object token; // 不透明、不可序列化；未知/关闭句柄不能执行动作。
}

@immutable
final class AgentDetectionDetails {
  final AgentInstallationState installationState;
  final bool executableLocated;
  final String? currentVersion;
  final String? latestVersion;
  final AgentAccountState accountState;
  final String? accountLabel;
  final AgentVersionState versionState;
  final DateTime? lastDetectedAt;
  final AgentDiagnosticStage? errorStage;
  final String? safeErrorMessage;
  final String? safeSuggestion;
  final bool configExists;
  final int availableLogFileCount;
  final List<AgentModelInfo> detectedModels;
  final DateTime? modelsUpdatedAt;
  final String? modelSource;
  final AgentManagementDetailsHandle? detailsHandle; // 无资料/旧缓存时可为空。
  // 无executablePath/configPath/logPaths/rawErrorSummary；
  // 连接诊断只保留success/failureStage等中立语义，详细资料通过handle引用。
}

@immutable
final class AgentManagementDetectionState {
  final ManagementDetectionPhase phase;
  final OperationId? operationId;
  final Map<String, AgentDetectionConfirmedRecord> confirmedByProviderId;
  final Map<String, AgentDetectionPartial> pendingPartialByProviderId;
  final Map<String, AgentDetectionProgress> progressByProviderId;
  final Map<String, ProviderDetectionOutcome> outcomesByProviderId;
  final Map<String, AgentManagementFailure> failuresByProviderId;
  final Set<String> cacheWriteWarningProviderIds;
  final bool automaticAttemptConsumed;
}

// 拟新增于同一ManagementSliceState；迁移既有ConnectionTestSucceeded拥有的字段。
// 这是显式连接测试结果，区别于repository.detect内部可能做的诊断检查。
@immutable
final class AgentManagementConnectionCheckState {
  final AgentManagementConnectionCheckSummary result;
  final List<AgentModelInfo> models;
  final DateTime? modelsUpdatedAt;
  final String? modelSource;
}

// 拟新增安全摘要；app从现有AgentConnectionTestResult投影。
final class AgentManagementConnectionCheckSummary {
  final bool success;
  final DateTime testedAt;
  final Duration elapsed;
  final bool cliCallable;
  final bool accountValid;
  final bool protocolReady;
  final AgentDiagnosticStage? failureStage;
  final String? safeMessage;
  final AgentManagementDetailsHandle? detailsHandle;
  // 不包含rawErrorSummary或路径；详细诊断走显示catalog。
}

sealed class AgentManagementDetectionEvent {}
final class DetectionProviderStarted extends AgentManagementDetectionEvent {...}
final class DetectionProviderProgress extends AgentManagementDetectionEvent {...}
final class DetectionProviderSucceeded extends AgentManagementDetectionEvent {...}
final class DetectionProviderFailed extends AgentManagementDetectionEvent {...}
final class DetectionCacheWriteWarning extends AgentManagementDetectionEvent {...}
// DetectionRunFinished是owner发出的terminal intent，不属于port可emit的event。

abstract interface class AgentManagementDetectionPort {
  Future<void> detect({
    required OperationId operationId,
    required List<String> providerIds,
    required int catalogGeneration,
    required AgentManagementCancellation cancellation,
    required bool Function(AgentManagementDetectionEvent) emit,
  });
}

// cancellation是本轮逻辑取消；其实现不创建Timer，不控制Provider会话权限。
abstract interface class AgentManagementCancellation {
  bool get isCanceled;
  void throwIfCanceled();
}

// WP-3唯一owner的拟新增入口；ensure/refresh返回同一种明确结果。
Future<AgentManagementDetectionRunResult> ensureDetected();
Future<AgentManagementDetectionRunResult> refreshDetection();
void cancelDetection();

@immutable
final class AgentManagementHomeState {
  final List<HomeProviderSummary> installedProviders;
  final bool isLoading;
  final ManagementDetectionPhase phase;
  final bool hasConfirmedData;
  final bool showingStaleData;
  final AgentManagementFailure? detectionFailure;
}

final agentManagementHomeProvider = Provider<AgentManagementHomeState>((ref) {
  return selectManagementHome(ref.watch(agentManagementSliceProvider));
});
```

`AgentManagementFailure`现有kind/operationId/agentId/message可以复用；需要聚合失败时新增typed汇总，不拿“当前管理选中Agent的operationError”作为首页全局探测失败。首页文案通过presentation的l10n或application注入的纯Dart文本目录生成，不把BuildContext传入Notifier，不持久化文案。


新增路径边界的确定实现：`AgentManagementDetailsHandle`仅引用详细资料资源，不含任何路径字符串。现有源码中management页面读取`agent.executablePath`用于显示/复制，读取`agent.logPaths`只用于计数与启用日志按钮；这几处随本包迁为`executableLocated`、`availableLogFileCount`以及presentation的窄catalog，不把Provider路径迁入新application对象。catalog的app实现仅保留既有repository提供的路径/详细诊断资源，用途沿用现有用户操作；它不保存installation/account/version/runtime/enabled等业务字段、不发布镜像状态。

```dart
// 拟新增presentation端口；app装配实现，application不import这个文件。
abstract interface class AgentManagementDetailsCatalog {
  AgentManagementDetailDisplay display(AgentManagementDetailsHandle? handle);
  Future<void> copyExecutableLocation(AgentManagementDetailsHandle handle);
}
final class AgentManagementDetailDisplay {
  final bool available;
  final String executableLocationLabel; // 已缩略/遮挡的显示标签，不是可执行路径。
  final String diagnosticDescription;  // 已脱敏说明，不是rawErrorSummary。
}
```

catalog不提供`getPath/toMap`等出口；复制动作沿用现有明确点击，由app在内部解析原始路径并调用原Clipboard适配器，UI不再取得原始字符串。未知/关闭handle返回`available=false`的无内容显示，动作抛`UnsupportedError`。详细资源仅由app adapter持有，每个(providerId, detailsKind)最多保留一个已确认handle；detailsKind仅为detection或explicitConnectionCheck，两类互不淘汰；新成功结果同步提交后替换，旧句柄失效。适配器在emit前创建临时handle（持有该token时即可只读显示，避免同步发布窗口显示为空），`emit`返回false或提交前抛错时立即丢弃，成功提交才保留；operation取消释放未确认handle，关闭catalog清空所有资源。此处bool回执属于WP-3窄result sink的拟新增方法`acceptDetectionResult`，只报告结果已接受，不建立另一份业务账本。回执要求提交原子：一旦state已提交即返回true，observer异常走WP-3独立错误边界，不把已提交结果伪报为失败。部分进度不分配详情handle，使用拟新增`AgentDetectionPartial`（相同语义字段均可缺省，无handle）暂存；只有正式Details可以携带handle；旧缓存或没有可显示资料时保持null，不制造空资源。

此改动不新增Provider协议/API，不修改凭据来源、存储schema或配置编辑/日志读取业务端口。已存在配置文档/日志正文的用户请求链按原端口处理，不复制到Home探测state。`composeManagedAgent`在本章为兼容命名：目标应返回根feature的安全`AgentManagementAgentView`，其中definition仅含显示目录、详情仅为handle；不得重新拼回含路径的旧ManagedAgent再传给application。`AgentManagementOperations.agent/agents`及本feature视图消费处同步改为此只读view；Provider返回的ManagedAgent只作为app adapter输入，不再作为探测application state。

### 5.3 Single-flight、缓存及取消语义

`ensureDetected()`：初始化+本Workbench的一次自动尝试；已经自动尝试过则返回上次结果，不因失败、切页或回挂自动循环重试。`refreshDetection()`：用户显式重试；正在初始化/探测时加入现有Future，未运行时新建一轮。取消后下次自动ensure不偷偷重启，用户refresh才能重试。构造/启动时在app层按原来的触发条件（initialRestoreCompleted且无activeProject）调用ensure；管理页首次需要探测也调用同一个ensure。取消不依赖页面可见性。

操作必须在第一次await之前占住single-flight Future。Provider目录在每轮开始时冻结为贡献目录的exact id列表；中途变化的enabled只在有效值selector上即时反映。目录成员变更则使当前轮逻辑取消，并允许一次显式的新轮请求，不把旧结果贴到同id的新定义；WP-3组合generation加入入口检查。

```dart
// 唯一执行入口。所有分支返回真实执行Future，禁止返回已完成的空Future。
abstract interface class AgentManagementSliceEffectRunner {
  Future<void> run(AgentManagementSliceEffect effect);
  String? validateConfiguration(String agentId, String content);
}

final class CancellationSource implements AgentManagementCancellation {
  bool _canceled = false;
  bool get isCanceled => _canceled;
  void cancel() { _canceled = true; }
  void throwIfCanceled() {
    if (_canceled) throw LogicalCancellation();
  }
}

final class ActiveDetectionRun {
  ActiveDetectionRun(this.operationId, this.ownerGeneration, this.catalogGeneration);
  final OperationId operationId;
  final int ownerGeneration;
  final int catalogGeneration;
  final cancellation = CancellationSource();
  final callerCompleter = Completer<RunResult>();
  final executionDone = Completer<void>();
  RunResult? terminalResult;
  void settleCaller(RunResult result) {
    terminalResult ??= result;
    if (!callerCompleter.isCompleted) callerCompleter.complete(terminalResult!);
  }
}

ActiveDetectionRun? _activeRun;
// 复用WP-3M唯一owner的closed字段；此处不声明第二个关闭标志。
int _ownerGeneration = 0;

bool accepts(ActiveDetectionRun run) => !closed &&
    identical(_activeRun, run) && _ownerGeneration == run.ownerGeneration &&
    currentCatalogGeneration == run.catalogGeneration &&
    !run.cancellation.isCanceled;

void ensureCurrentRunOrThrow(ActiveDetectionRun run) {
  if (closed || !identical(_activeRun, run) ||
      _ownerGeneration != run.ownerGeneration || run.cancellation.isCanceled) {
    throw LogicalCancellation();
  }
  if (currentCatalogGeneration != run.catalogGeneration) {
    throw CatalogGenerationChanged();
  }
}

Future<RunResult> _requestDetection({required bool explicit}) {
  ensureOwnerOpen();
  final active = _activeRun;
  if (active != null) return active.callerCompleter.future;
  if (!explicit && state.detection.automaticAttemptConsumed) {
    return Future.value(lastRunResult(state));
  }
  // generatorFor沿用owner现有按固定scope缓存OperationIdGenerator的工厂。
  final run = ActiveDetectionRun(generatorFor('agent-management/detect').next(),
      _ownerGeneration, currentCatalogGeneration);
  _activeRun = run; // 第一次dispatch/await之前占槽。
  // _executeRun包住第一次dispatch，连同步异常也能结算与释放槽。
  unawaited(_executeRun(run).catchError(reportUnhandledSafeFailure));
  return run.callerCompleter.future;
}

Future<void> _executeRun(ActiveDetectionRun run) async {
  try {
    dispatch(DetectionLifecycleStarted(run.operationId)); // stateOnly，无effect。
    await initialize(autoDetect: false); // 不得递归启动另一轮detect。
    ensureCurrentRunOrThrow(run);
    final targets = List<String>.unmodifiable(validatedCatalog.orderedProviderIds);
    dispatch(DetectionRunStarted(run.operationId, targets)); // stateOnly。
    await runner.run(DetectAgentsEffect(
      operationId: run.operationId,
      ownerGeneration: run.ownerGeneration,
      catalogGeneration: run.catalogGeneration,
      providerIds: targets,
      cancellation: run.cancellation,
    )); // 此处是唯一一次执行。不能又从reducer effects列表发一次。
    ensureCurrentRunOrThrow(run);
    final outcome = classifyTerminalProviderOutcomes(state.detection);
    run.terminalResult = outcome;
    dispatch(DetectionRunFinished(run.operationId, outcome));
  } on LogicalCancellation {
    run.terminalResult ??= RunResult.canceled;
    if (!closed && identical(_activeRun, run)) {
      dispatch(DetectionRunCanceled(run.operationId));
    }
  } on CatalogGenerationChanged {
    run.cancellation.cancel();
    run.terminalResult = RunResult.canceled;
    if (!closed && identical(_activeRun, run)) {
      dispatch(DetectionRunCanceled(run.operationId));
    }
  } catch (error) {
    run.terminalResult = RunResult.failed(classifySafeFailure(error));
    if (accepts(run)) {
      dispatch(DetectionInfrastructureFailed(run.operationId,
          run.terminalResult!.failure));
    }
  } finally {
    // 即使失败投影/observer抛错，这个finally仍结算；error上报不能再抛回此处。
    run.settleCaller(run.terminalResult ??
        (closed ? RunResult.closed : RunResult.canceled));
    if (!run.executionDone.isCompleted) run.executionDone.complete();
    if (identical(_activeRun, run)) _activeRun = null;
  }
}

void cancelDetection() {
  final run = _activeRun;
  if (run == null || run.cancellation.isCanceled) return;
  run.cancellation.cancel();
  run.settleCaller(RunResult.canceled); // caller立即完成，执行槽仍保留。
  dispatch(DetectionRunCanceled(run.operationId));
}

// 由WP-3的stopAcceptingCommandsAndSettleWaiters同步调用。
void stopDetectionForShutdown() {
  final run = _activeRun;
  closed = true;
  _ownerGeneration++;
  run?.cancellation.cancel();
  run?.settleCaller(RunResult.closed);
}

// 由WP-3的drainExecutions等待；绝不使用callerFuture作为排空证明。
Future<void> drainDetectionExecutions() async {
  final run = _activeRun;
  if (run != null) await run.executionDone.future;
}

// Runner回流使用WP-3窄sink，不在effect里放UI callback。
bool acceptDetectionResult(DetectionResultIntent result) {
  final run = _activeRun;
  if (run == null || !accepts(run) || result.operationId != run.operationId) return false;
  dispatch(result);
  return true; // 返回值仅确认当前result已提交，不是另一份state。
}
```

`ActiveDetectionRun`只保存操作执行资源与调用方完成器，不拥有业务探测数据；confirmed/pending/outcomes只存在Notifier.state。取消排空期间refresh加入当前已经完成为canceled的callerFuture，不启动并行探测、不排队自动重试。底层repository不支持取消时，等待其既有超时/完成；不能声称已经结束子进程。`_executeRun`的最外层Future要安装只记录稳定分类的错误边界（例如调度时 `.catchError(reportUnhandledSafeFailure)`）；该边界不得再次写state、打印原始error或吞掉记录结算。runner.run只有在repository及本轮已开始的白名单写入全部结束后才完成。

WP-3 shutdown先调用management/threads的 `stopAcceptingCommandsAndSettleWaiters`，其中management同步调用`stopDetectionForShutdown`；再await各owner的`drainExecutions`，其中management等待`drainDetectionExecutions`。然后退订management/source，最后才关闭entries、BindingManager/runtime/plugin；container同步dispose只封入口和结算caller，不能代替物理排空的完成证明。初始化结果必须合并初始化拥有的字段，不得以初始state整份覆盖正在登记的detection operation。

### 5.4 Runner与reducer伪代码

```dart
// app adapter；不读取UI。生产/测试均走这一个接口。
Future<void> run(AgentManagementSliceEffect effect) {
  return switch (effect) {
    DetectAgentsEffect() => detectionPort.detect(
      operationId: effect.operationId,
      providerIds: effect.providerIds,
      catalogGeneration: effect.catalogGeneration,
      cancellation: effect.cancellation,
      emit: (event) => resultSink.acceptDetectionResult(
        event.toIntent(ownerGeneration: effect.ownerGeneration)),
    ),
    // 其它既有effect也返回真正的执行Future，不在分支内unawaited。
    _ => runExistingEffectAndAwaitCompletion(effect),
  };
}

Future<void> detect(request) async {
  for (final providerId in request.providerIds) {
    request.cancellation.throwIfCanceled();
    final repository = validatedRepositories[providerId];
    if (repository == null) throw StateError('Missing detection contribution');
    emit(DetectionProviderStarted(request.operationId, providerId));
    try {
      final latestConfig = settings.providerConfigById(providerId);
      if (latestConfig == null) throw CatalogGenerationChanged();
      final detected = await repository.detect(
        providerConfig: latestConfig,
        enabled: latestConfig.enabled,
        onProgress: (progress, partial) {
          if (!request.cancellation.isCanceled) emit(
            DetectionProviderProgress(
              operationId: request.operationId,
              providerId: providerId,
              progress: progress,
              details: extractSafePartialFields(partial),
            ),
          );
        },
      );
      request.cancellation.throwIfCanceled();
      validateExactDefinitionIdentity(providerId, detected.definition.id);
      final handle = detailCatalog.stageFromDetected(detected: detected);
      var accepted = false;
      try {
        accepted = emit(DetectionProviderSucceeded(request.operationId, providerId,
          extractSafeDetectionFields(detected, detailsHandle: handle)));
      } finally {
        if (accepted) detailCatalog.confirmAndRetirePrevious(providerId, DetailsKind.detection, handle);
        else detailCatalog.discard(handle);
      }
      if (!accepted) throw LogicalCancellation();

      // 探测成功和缓存写入成功是不同事实。后者失败不撤销真实探测结论。
      try {
        request.cancellation.throwIfCanceled();
        await persistWhitelistedDetectionSummary(
          providerId: providerId,
          detected: detected,
          cancellation: request.cancellation,
        );
      } on LogicalCancellation { rethrow; }
      catch (error) {
        emit(DetectionCacheWriteWarning(request.operationId, providerId));
      }
    } on LogicalCancellation { rethrow; }
    on CatalogGenerationChanged { rethrow; }
    catch (error) {
      emit(DetectionProviderFailed(
        request.operationId, providerId, classifyDetectionFailure(error),
      ));
      // 一个Provider探测失败不阻断另一个Provider。
    }
  }
}

Transition reduceDetection(state, intent) {
  // 请求先登记；不能拿尚不存在的operationId过滤第一次请求。
  if (intent is DetectionLifecycleStarted) {
    return stateOnly(registerDetectionOperation(state, intent,
      phase: initializing, automaticAttemptConsumed: true));
  }
  if (!matchesCurrentOperationAndOwner(state, intent)) return noChange(state);
  if (intent is DetectionRunStarted) {
    return stateOnly(registerTargetsAndMarkRunning(state, intent)); // 无effect。
  }
  switch (intent) {
    case DetectionProviderProgress():
      return stateOnly(state.withDetection(
        pendingPartialByProviderId: put(providerId, intent.details),
        progressByProviderId: put(providerId, intent.progress),
      )); // confirmed原样保留。
    case DetectionProviderSucceeded():
      return stateOnly(state.withDetection(
        confirmedByProviderId: put(providerId,
          ConfirmedRecord(intent.details, nowFromIntent, confirmedThisRun)),
        pendingPartialByProviderId: remove(providerId),
        outcomesByProviderId: put(providerId, succeeded),
        failuresByProviderId: remove(providerId),
      )); // 不写enabled/runtime/state.agentsById中的非探测字段。
    case DetectionProviderFailed():
      return stateOnly(state.withDetection(
        confirmedByProviderId: markExistingRecordStale(providerId),
        pendingPartialByProviderId: remove(providerId),
        outcomesByProviderId: put(providerId, failed),
        failuresByProviderId: put(providerId, intent.failure),
      ));
    case DetectionRunFinished():
      assert(allTargetsHaveTerminalOutcomes);
      return finishAndClearPending(
        successCount == targetCount ? succeeded
            : successCount > 0 ? partialFailure : failed,
      );
    case DetectionRunCanceled():
      return finishAndClearPending(canceled,
        preserveConfirmed: true, markUnfinishedCanceled: true);
  }
}

AgentManagementAgentView selectEffectiveManagedAgent(state, id) {
  final definition = state.displayDefinitionsByProviderId[id];
  final detection = state.detection.confirmedByProviderId[id];
  return composeManagedAgent(
    definition: definition,
    detection: detection?.details ?? unknownDetectionFields(),
    enabled: latestSettingsEnabled(state.providerSettings, id),
    runtime: state.runtimeByProviderId[id], // WP-1唯一事实源。
    currentConnectionTest: state.confirmedConnectionChecksByProviderId[id],
  );
}

AgentManagementHomeState selectManagementHome(state) {
  final agents = [for (final id in state.orderedAgentIds)
      selectEffectiveManagedAgent(state, id)];
  return HomeState(
    installedProviders: immutableList(agents
      .where((a) => a.installationState == installed)
      .map(HomeProviderSummary.fromAgentView)),
    isLoading: state.detection.phase in {initializing, running},
    phase: state.detection.phase,
    hasConfirmedData: state.detection.confirmedByProviderId.isNotEmpty,
    showingStaleData: hasStaleConfirmedRecords(state),
    detectionFailure: summarizeCurrentDetectionFailures(state),
  );
}
```

`nowFromIntent`由effect runner使用注入Clock生成，reducer不调用DateTime.now。WP-3阶段的`state.agentsById`是原可写owner字段；WP-5必须删除其backing field与所有`copyWith(agentsById:)`入口，改成effective selector的只读派生出口。`displayDefinitionsByProviderId`是拟新增不可变显示目录，仅含id/displayName/vendor等中立显示字段；由app对既有已校验contributions投影，在owner构造时注入，不在application读取插件或私有配置路径。配置文档、日志正文仍在既有独立字段，不由探测回滚清除。`confirmedConnectionChecksByProviderId`是本工作包拟新增状态字段，当前基线尚不存在；当前 `ConnectionTestSucceeded` 直接改写ManagedAgent中的connectionTest/models/runtime/error字段，实施时要一起迁移，不能假定只动探测分支就完整。

显式连接测试结果采用确定的覆盖规则：它保存自己的result/models，不产生“session runtime idle/running”事实；connectionTest详情始终显示最近一次显式测试，未做显式测试时才展示成功探测内的diagnostic check。非空显式测试models覆盖探测models；空models保留探测目录，与当前“空结果不覆盖已有目录”约束一致。Provider进程相关配置变化时清除该Provider的显式连接测试覆盖层，重新回到unknown/成功探测记录；目录查询本身仍走既有app级模型目录仓储。本章不修改权限配置、不把连接测试成功当成预授权，也不增加自动连接测试。

持久化仍使用现有白名单摘要，不新增文件或schema。必须在持久化前重读当前Provider配置，仅合并探测拥有的字段，保留期间用户修改的enabled、参数、权限和其它extra；如果配置身份/定义generation已变化，取消旧写入。逻辑cancel只能阻止尚未开始的写入：已成功完成的白名单写入不反向回滚，文档和测试需承认该事实。运行态、pending partial、error正文、Home缓存均不得落盘。

### 5.5 UI与启动接线

```dart
// WP-3 app级协调器中注册一次；不在IdeHome维护load token。
listen(initialRestoreAndActiveProjectSelector, (_, next) {
  if (next.restoreCompleted && next.activeProject == null) {
    unawaited(management.ensureDetected());
  }
});

// management页面首次激活可以请求同一个ensureDetected。
// 页面卸载/回挂只改变订阅；不存在home专用loader，也不触发cancel。

Widget buildGlobalHome(ref) {
  final home = ref.watch(agentManagementHomeProvider);
  return GlobalHomePage(
    installedProviders: home.installedProviders,
    isLoadingProviders: home.isLoading,
    providerError: localizedDetectionFailure(home.detectionFailure),
    onOpenProject: onOpenProject,
  );
}
```

首页“近期项目thread列表预热”仍属于Shell/ProjectThreads，与本探测状态独立，不把它并入management。删除 `_installedHomeProviders`、`_homeProvidersLoading`、`_homeProviderError`、`_globalHomeLoadToken`、`_loadHomeProviders`、`_handleAgentManagementChanged`、`_agentManagementHomeRefreshScheduled`；若 `_globalHomeLoadRequested` 仍服务项目列表预热，迁入相应app协调逻辑并改为只表达那一项，不能继续兼管探测。

原 `homeProviderDetectionLoaderProvider` / `HomeProviderDetectionLoader` 从生产接口和测试助手移除。测试的 `FakeAgentManagementDetectionPort` 发出与生产相同的started/progress/succeeded/failed事件，并受相同cancellation/operation检查约束；不得直接返回 `List<ManagedAgent>` 绕过reducer。

### 5.6 开发步骤、测试矩阵与回滚

1. 在WP-3的单owner中定义confirmed/pending/outcome模型与事件，先写reducer表驱动测试。
2. 从现有runner抽出统一detection adapter；保留contribution归属校验和repository能力，所有失败映射在app完成。
3. 实现首次await前占槽的single-flight、owner generation与逻辑取消；明确调用方Future完成和物理执行结束两种状态。
4. 新增安全AgentManagementAgentView、displayDefinitionsByProviderId与窄details catalog，迁移管理视图的路径显示/复制、日志计数；catalog无业务state镜像。建立唯一effective-agent selector；管理页与首页都迁移至该selector。WP-1最新runtime与enabled即时覆盖，探测不能回写这两类事实。
5. 迁出Home纯模型、删除IdeHome缓存/loader分支/同步监听/post-frame补丁；在app协调器接一次自动ensure。
6. 更新测试helpers覆写统一port，加入真实页面切换集成；确认数据源数量为一而非“测试绿但旧Home缓存还在”。

| 层 | 场景 | 断言 |
|---|---|---|
| reducer | 已有成功数据后收到partial | confirmed不变；管理页进度区可变；首页正式数据不变 |
| reducer | A完整成功、B随后失败 | 两页均A新值+B旧值；phase=partialFailure；B标stale |
| reducer | 首次探测全部失败 | 无确认安装结论；failed有明确错误；不能生成notInstalled |
| reducer | 一次成功明确返回notInstalled | 两页同一时刻移除已安装列表中的该Provider |
| selector | running期间探测返回旧idle/旧enabled | WP-1运行态和当前enabled保持；失败回滚不影响它们 |
| notifier | ensure/refresh在initialize await期间并发 | 一次initialize、一次探测、所有调用方共享同轮结果 |
| notifier | 已失败后页面卸载/回挂 | 保留数据和失败；不自动重试；显式refresh才新operation |
| notifier | cancel时repository仍await | caller得到canceled；没有新并发探测；late partial/success被丢弃 |
| notifier | cancel后已成功A、未完成B | A保留；B旧confirmed保留；pending清空 |
| notifier | owner关闭、新owner建立、旧回调返回 | 新owner无污染；旧future被结算；无卸载后的发布 |
| adapter | 某Providerdetect抛错 | 继续其余Provider；一轮结束summary准确 |
| adapter | 探测成功但缓存保存失败 | 成功事实可见，另有缓存警告，不错误标记未安装 |
| adapter | 期间用户改enabled/权限/参数 | 缓存摘要合并保留用户新值，不以旧config整份覆盖 |
| Widget | 首页→管理页→首页，后台探测成功/失败 | 两页同Provider正式字段一致；无post-frame镜像状态 |
| Widget | 保留页面时两Provider并行运行 | 首页和管理页运行态一致，探测进度不覆盖后台running；详情显示为安全标签、复制动作仍经明确点击 |
| adapter/catalog | staged handle被拒绝、关闭后旧handle、同帧读取新handle | 临时资源回收；旧操作拒绝；新资料在state发布时已可读 |
| 结构守卫 | application探测/连接测试DTO | 无executablePath/configPath/logPaths/rawErrorSummary；仅opaque handle，不持有catalog |
| 结构守卫 | 生产/测试依赖 | 不再存在Home专用loader产品分支，application不import UI/Flutter符号 |

建议新建 `test/src/features/agent_management/application/agent_management_detection_state_test.dart`、`agent_management_detection_notifier_test.dart`、`test/src/app/agent_management_slice/contributed_agent_management_detection_adapter_test.dart`；扩展实际IdeHome集成，保留GlobalHomePage纯渲染测试。重构结束按项目规则完成format、analyze、相关守卫和完整重构门禁。

回滚：WP-5单独提交；回退时同时恢复入口、selector和UI调用，不留下两套探测port。不要用“首页临时缓存”修补探测回归。由于本方案不新增持久化schema，历史摘要仍可读；回滚不得清空用户已有Provider配置或探测缓存。WP-1/3的单owner与运行事实聚合仍保留，WP-5回滚只影响探测流程。
