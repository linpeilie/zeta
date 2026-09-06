# WP-2 · Conversation 统一命令入口

> 对应问题：问题 2（命令双路径）。工作包：WP-2。状态：已完成，验收记录见文末。
> 前置：[WP-3C 单一 Conversation owner](03-wp3-state-ownership.md)、[WP-6 Session config 结果契约](06-wp6-session-config.md)。返回 [开发总入口](00-index.md)。
> §2.1–2.10 保留实施前的只读核查、开发设计与伪代码；当前实现校正见 §2.11，验证结果以验收记录为准。既有发布流程改动不属于本工作包。


### 2.1 问题、目标与依赖

**代码事实**：`agent_pane.dart:218-237` 的发送经过 `agentConversationCommandProvider`，但该 provider 在 `presentation/conversation_slice/agent_conversation_slice_providers.dart:47-53` 直接返回 RuntimeController。`agent_pane_sections.dart:886/934/1000` 的问题回答、权限回答、取消直接调用 controller。与此同时，`application/conversation_slice/agent_conversation_slice_store.dart:228-422` 已定义完整的命令入口；intent/reducer/effect runner 记录 OperationId 和 pendingOperations，真实 UI 却未统一经过它。

**已有测试的限度**：`agent_conversation_view_model_test.dart:4710/4781` 显式调用 `store.sendMessage`；`agent_conversation_slice_scope_guard_test.dart:42` 检查 runner 源码。它们证明该路径内部可用，不能证明真实按钮连接了它。

**固定目标**：UI 写命令只有 `AgentConversationActions` 一个入口，Live 状态下的实际实例是 WP3 放到 application 的 `AgentConversationSliceNotifier`；Closing/Closed 只提供无状态的拒绝句柄；executor 仍是 `AgentConversationCommandPort`/`AgentConversationRuntimeController`。MVI reducer 保持同步，执行器仍经 effect runner 调用，RuntimeController 的流式管线、TimelineStore、Binding/lease 生命周期不改。

依赖：WP3 先提供 application Notifier、稳定的 entry owner 身份和依赖注入；WP6 可先独立落地，再由本包接入 session-config action。WP2 不再临时增加一个 Store→Notifier 镜像或反向 bind 注册表。

**完成判据**：生产 UI 无法从 Actions provider 取得 RuntimeController；所有下表列出的写命令可由同一个 Notifier 记录开始/完成，异步操作的 Future 必定恰好完成一次；只读 region/live-turn/elapsed 查询仍可保留独立读取路径。

### 2.2 文件增改删清单

下列路径均相对项目根目录 `/Users/linpeilie/Development/Workspace/zeta`。

| 动作 | 文件 | 修改内容 |
|---|---|---|
| 新增 | `lib/src/features/agent/application/conversation_slice/agent_conversation_actions.dart` | UI Actions 完整接口、provider 声明；只依赖中立模型与 application 契约 |
| 新增 | `.../application/conversation_slice/agent_conversation_command_payload.dart` | 封闭的 typed command payload，独立的四类审批动作；集合递归冻结 |
| 新增 | `.../application/conversation_slice/agent_conversation_command_result.dart` | 单次结果信封与 typed fork 结果；不得含 Flutter/Ref/Completer |
| 新增 | `.../application/conversation_slice/agent_conversation_command_result_sink.dart` | runner 回流的窄接口，消除 runner↔Store 文件循环 |
| 修改（WP3 已建立） | `.../application/conversation_slice/agent_conversation_slice_notifier.dart` | implements Actions 与 result sink；OperationId、Completer 表、关闭结算 |
| 修改 | `.../application/conversation_slice/agent_conversation_slice_ports.dart` | executor 补齐 UI 现有写操作；保持 read-source 与 executor 分开 |
| 修改 | `.../application/conversation_slice/agent_conversation_command_effect_runner.dart` | 只依赖 executor、scope source、result sink；前后验证、异常分类、typed fork 保留 |
| 修改 | `.../application/conversation_slice/agent_conversation_slice_{intent,effect,reducer,state}.dart` | 统一命令信封、OperationSettled、pendingOperations；保留 RegionsRefreshed，删除重复转发壳类 |
| 修改 | `.../application/conversation_slice/agent_conversation_command_scope.dart` | 保留现有执行/提交差异；owner 生命周期 token 在信封中验证，不改变 core Binding |
| 修改 | `.../application/conversation_slice/agent_conversation_runtime_controller.dart` | 补齐 executor 面及 typed 结果；WP6 session config；不搬动流式 reducer/pipeline |
| 修改 | `.../application/agent_conversation_model_selection_controller.dart` | 为每次选择/保存产生明确的调用结果，区分兼容提示、未改变、保存失败和旧 generation；保留已有串行合并保存机制 |
| 修改 | `.../application/agent_command_outcome.dart` | 增加所需 ignored reason：`requiresConfirmation`、`superseded`、`alreadyPending`；成功/失败分类沿用现有类型 |
| 修改 | `.../presentation/conversation_slice/agent_conversation_slice_providers.dart` | 移除直接返回 controller 的 command provider；需要旧名称时只 export 新 Actions provider，不维护第二条实现 |
| 修改 | `.../presentation/agent_pane.dart`、`agent_pane_composer_session.dart` | 发送回调返回 Future；slash/skill 加载改用 Actions；编辑正文、焦点、附件暂存仍归 Widget session |
| 修改 | `.../presentation/widgets/agent_pane_{header,sections,cards,messages,plan_panel}.dart` | 所有写回调用通过 Actions；下表逐项勾销 |
| 修改 | `.../presentation/timeline_rendering/agent_timeline_renderer.dart` 及调用其命令的 renderer | RenderContext 增加独立 actions 与 bindingKey；删除 `commands => controller` 的伪隔离 |
| 修改 | `.../presentation/widgets/agent_model_config.dart`、`agent_pane_composer.dart` | 回调由 bool/void 改成 typed outcome 或采用单一 presentation 翻译器；保留当前交互行为 |
| 修改 | `lib/src/app/shell/ide_shell_controller.dart` | 用户动作衍生的新 entry 初始发送、retry-open 改调用目标 entry 的 Actions；bootstrap/纯内部 lifecycle 保持 executor 路径并有显式注释 |
| 删除（WP3 负责） | `.../application/conversation_slice/agent_conversation_slice_store.dart`、`agent_conversation_slice_store_registry.dart` | 不在本包另留 facade 兼容真实 UI；WP3 删除后修全部 import |
| 修改/新增 | `test/src/features/agent/{application/conversation_slice,presentation,architecture}/...` | 真实 UI 接线、typed result、关闭/迟到/并发测试；见 2.10 |

`...` 仅是表格缩写，分别承接 `lib/src/features/agent`。开发时不得创建省略号路径。

### 2.3 UI Actions 完整签名（拟新增）

普通 UI 动作统一返回 `Future<AgentCommandOutcome>`。唯一携带产物的公开动作 `forkCurrentThread` 返回 `Future<AgentForkCommandOutcome>`，调用者不再用 nullable session 推测成功。`editLastUserMessageAndRetry` 保持普通结果，因为其产品语义是“创建分支并交接发送”，不是让 UI 拿 session 再发一次。

```dart
// 拟新增：application/conversation_slice/agent_conversation_actions.dart
abstract interface class AgentConversationActions {
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  });
  Future<AgentCommandOutcome> cancelActiveTurn();
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText);
  Future<AgentCommandOutcome> retryOpenThread();

  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const [],
  });
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const {},
  });
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  });
  Future<AgentCommandOutcome> startPlanExecution(AgentPlanExecutionRequest request);
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {String? revisionMessage});
  Future<AgentCommandOutcome> dismissPlanExecution(AgentPlanExecutionRequest request);
  Future<AgentCommandOutcome> selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request, AgentPermissionOption option);
  Future<AgentCommandOutcome> approveGuardianDeniedAction();

  Future<AgentForkCommandOutcome> forkCurrentThread();
  Future<AgentCommandOutcome> renameCurrentThread(String name);
  Future<AgentCommandOutcome> archiveCurrentThread();
  Future<AgentCommandOutcome> compactCurrentThread();

  Future<AgentCommandOutcome> toggleToolCall(String toolCallId);
  Future<AgentCommandOutcome> togglePlanMessage(String messageId);
  Future<AgentCommandOutcome> toggleActivePlan(String turnId);
  Future<AgentCommandOutcome> toggleCommandGroup(String commandGroupId);
  Future<AgentCommandOutcome> toggleFileEditItem(String fileEditItemId);

  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false});
  Future<AgentCommandOutcome> ensureSkillsCatalog();
  Future<AgentCommandOutcome> retryConversationModes();
  Future<AgentCommandOutcome> selectConversationMode(AgentConversationModeId modeId);
  Future<AgentCommandOutcome> selectModel(String modelId);
  Future<AgentCommandOutcome> selectReasoningEffort(String? effort);
  Future<AgentCommandOutcome> selectFastEnabled(bool enabled);
  Future<AgentCommandOutcome> resolveModelCompatibilityConflict();
  Future<AgentCommandOutcome> retryModelConfigurationSave();
  Future<AgentCommandOutcome> clearModelConfigurationTransientState();
  Future<AgentCommandOutcome> selectPermissionOption(AgentPermissionOption option);
  Future<AgentCommandOutcome> retryPermissionPreferencePersistence();
  Future<AgentCommandOutcome> selectSessionConfigOption(String configId, Object value);
  Future<AgentCommandOutcome> switchActiveProvider(String providerId);
}
```

接口明确不包含：`loadSettings`/`updateContext`/`dispose`/`syncThreadTitleIfCurrent`，它们是组合层的初始化、上下文同步、生命周期动作；不包含 `takePermissionApplyHint`，它是破坏性的读取，改由既有 composer region 的 hint 渲染；不包含文件 picker 开合、输入法、滚动、附件删除，这些仍由 presentation 的 Widget session/附件端口承接。

### 2.4 结果契约与 executor（拟新增/拟调整）

```dart
// 拟新增。普通命令 never throws 的 UI 边界；executor 仍可抛 UnsupportedError。
// diagnostic 原文不进入 result sink、状态、持久化或 UI toast。
final class AgentForkCommandOutcome {
  const AgentForkCommandOutcome._({
    required this.outcome, required this.createdSession, required this.activated,
  });
  factory AgentForkCommandOutcome.completed(AgentSession session) =>
    AgentForkCommandOutcome._(
      outcome: const AgentCommandOutcome.succeeded(),
      createdSession: session, activated: true);
  factory AgentForkCommandOutcome.failed(
    AgentCommandFailureKind kind, {AgentSession? createdSession}) =>
    AgentForkCommandOutcome._(
      outcome: AgentCommandOutcome.failed(kind),
      createdSession: createdSession, activated: false);
  factory AgentForkCommandOutcome.ignored(AgentCommandIgnoreReason reason) =>
    AgentForkCommandOutcome._(
      outcome: AgentCommandOutcome.ignored(reason),
      createdSession: null, activated: false);
  factory AgentForkCommandOutcome.fromRegularFailure(AgentCommandOutcome value) =>
    switch (value) {
      AgentCommandFailed(:final kind) => AgentForkCommandOutcome.failed(kind),
      AgentCommandIgnored(:final reason) => AgentForkCommandOutcome.ignored(reason),
      // 内部接线错误也不能制造没有 session 的成功；测试固定此分支。
      _ => AgentForkCommandOutcome.failed(AgentCommandFailureKind.requestFailed),
    };
  final AgentCommandOutcome outcome;
  final AgentSession? createdSession; // 只在内存返回，绝不写进切片/日志。
  final bool activated;
}

// 拟新增：runner 到 owner 的单次结果信封；私有构造/工厂校验两字段一致。
final class AgentConversationCommandResult {
  const AgentConversationCommandResult.regular(this.outcome) : fork = null;
  AgentConversationCommandResult.fork(AgentForkCommandOutcome value)
    : outcome = value.outcome, fork = value;
  final AgentCommandOutcome outcome;
  final AgentForkCommandOutcome? fork;
}

// 拟新增：不依赖 Store/Notifier/Ref，不持有状态和 listener。
abstract interface class AgentConversationCommandResultSink {
  void settle(OperationId id, AgentConversationCommandResult result);
  bool isOpenOperation(OperationId id, Object ownerLifetimeToken);
}

// 拟调整：现有 AgentConversationCommandPort 为 executor 面。
// 缺失 capability/port 抛 UnsupportedError，runner 翻译为 failed(unsupported)。
// 五种展开、mode 选择、本地 Plan 权限/关闭、model transient 清理仍同步；
// Actions 对它们包装成已完成 Future，保留原同步状态更新时序。
// 四类审批仍是四组独立方法，不合成 respondToApproval(Object)。
abstract interface class AgentConversationCommandPort {
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  });
  Future<AgentCommandOutcome> cancelActiveTurn();
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText);
  Future<AgentCommandOutcome> retryOpenThread();

  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const [],
  });
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const {},
  });
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  });
  Future<AgentCommandOutcome> startPlanExecution(AgentPlanExecutionRequest request);
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {String? revisionMessage});
  AgentCommandOutcome dismissPlanExecution(AgentPlanExecutionRequest request);
  AgentCommandOutcome selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request, AgentPermissionOption option);
  Future<AgentCommandOutcome> approveGuardianDeniedAction();

  Future<AgentForkCommandOutcome> forkCurrentThread();
  Future<AgentCommandOutcome> renameCurrentThread(String name);
  Future<AgentCommandOutcome> archiveCurrentThread();
  Future<AgentCommandOutcome> compactCurrentThread();

  AgentCommandOutcome toggleToolCall(String toolCallId);
  AgentCommandOutcome togglePlanMessage(String messageId);
  AgentCommandOutcome toggleActivePlan(String turnId);
  AgentCommandOutcome toggleCommandGroup(String commandGroupId);
  AgentCommandOutcome toggleFileEditItem(String fileEditItemId);

  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false});
  Future<AgentCommandOutcome> ensureSkillsCatalog();
  Future<AgentCommandOutcome> retryConversationModes();
  AgentCommandOutcome selectConversationMode(AgentConversationModeId modeId);
  Future<AgentCommandOutcome> selectModel(String modelId);
  Future<AgentCommandOutcome> selectReasoningEffort(String? effort);
  Future<AgentCommandOutcome> selectFastEnabled(bool enabled);
  Future<AgentCommandOutcome> resolveModelCompatibilityConflict();
  Future<AgentCommandOutcome> retryModelConfigurationSave();
  AgentCommandOutcome clearModelConfigurationTransientState();
  Future<AgentCommandOutcome> selectPermissionOption(AgentPermissionOption option);
  Future<AgentCommandOutcome> retryPermissionPreferencePersistence();
  Future<AgentCommandOutcome> selectSessionConfigOption(String configId, Object value);
  Future<AgentCommandOutcome> switchActiveProvider(String providerId);
}
```

现有 `AgentCommandOutcome` 的 succeeded/ignored/failed 不替换成 `bool`。拟新增 ignored 枚举 `requiresConfirmation` 用于模型 Fast/思考冲突待用户确认，`superseded` 用于被后续请求替代的同一保存操作，`alreadyPending` 用于审批重复提交。它们都不冒充成功，也不显示通用错误。

原 model selection owner 的 bool Future 不能简单 `false => requestFailed`：当前 `selectReasoningEffort`/`selectFastEnabled` 在建立 compatibilityConflict 后也返回 false。实施时在每个原分支明确返回 typed outcome，已有 `_saveWaiters` 改为 `Completer<AgentCommandOutcome>`，不通过读取“当前最后一个错误”猜某个旧请求的结果。相同选择为 ignored(unchanged)，产生冲突为 ignored(requiresConfirmation)，落盘失败为 failed(requestFailed)，generation 覆盖为 ignored(superseded)，合法且持久化确认才是 succeeded；保持已有快照回滚、save loop 与关联字段原子保存。

权限选择仍调用现有 core permission owner，WP2 不改变其权限/G5状态机。RuntimeController 在发起前校验 option 与 capability，执行后从既有 `takeLastError()` 是否非空得到失败而不解析文案；成功且 scope 有效才返回 succeeded。**权限选择和“重试权限偏好保存”在同一 per-entry 轻量串行队列内执行**，防止后一请求覆盖这个破坏性错误读取。审批、问题、取消和 Plan 执行完全不进该队列。提示仍由 composer 的 `permissionApplyScopeHint`/失败 region 显示，不为 toast 新造 localized 状态；presentation 删除 `takePermissionApplyHint()` 调用。

### 2.5 typed payload 与命令身份

拟新增 sealed `AgentConversationCommandPayload`。下面每一行为一个独立 payload 变体的完整参数集合；名称前统一加 `Agent` 后加 `Command`。禁止 `Map<String,Object?> payload`、字符串命令名和动态方法查找。

| 变体 | 构造参数 | 固定 OperationId scope |
|---|---|---|
| SendMessage | `String text; List<String> localImagePaths; List<({String name,String path})> mentions; List<AgentSkillRef> skills; AgentPermissionRequestSnapshot? permissionSnapshotOverride` | `conversation.send` |
| CancelActiveTurn / EditLastUserMessage / RetryOpenThread | `()` / `(String newText)` / `()` | `conversation.cancel` / `conversation.editLastMessage` / `conversation.retryOpen` |
| RespondPermission | `(AgentPermissionRequest request, bool approved, bool cancelTurn, AgentCommandApprovalDecisionKind? commandDecision, List<String> execpolicyAmendment)` | `conversation.permission` |
| RespondQuestion | `(AgentQuestionRequest request, Map<String,List<String>> answers)` | `conversation.question` |
| RespondPlanApproval | `(AgentPlanApprovalRequest request, AgentPlanApprovalDecisionKind kind, String? reason)` | `conversation.planApproval` |
| StartPlanExecution / RevisePlanExecution / DismissPlanExecution | `(AgentPlanExecutionRequest request)` / `(AgentPlanExecutionRequest request, String? revisionMessage)` / `(AgentPlanExecutionRequest request)` | `conversation.planExecution` |
| SelectPlanExecutionPermission | `(AgentPlanExecutionRequest request, AgentPermissionOption option)` | `conversation.planExecutionPermission`（拟新增常量） |
| ApproveGuardianDeniedAction | `()` | `conversation.guardianOverride` |
| ForkCurrentThread / RenameCurrentThread / ArchiveCurrentThread / CompactCurrentThread | `()` / `(String name)` / `()` / `()` | `conversation.threadMutation` |
| ToggleExpansion | `(AgentConversationExpansionTarget target, String id)` | `conversation.expansion`（拟新增常量） |
| LoadModels / EnsureSkillsCatalog / RetryConversationModes | `(bool forceRefresh)` / `()` / `()` | `conversation.catalog` |
| SelectConversationMode | `(AgentConversationModeId modeId)` | `conversation.modeSelection`（拟新增常量） |
| SelectModel / SelectReasoningEffort / SelectFastEnabled | `(String modelId)` / `(String? effort)` / `(bool enabled)` | `conversation.modelSelection`（拟新增常量） |
| ResolveModelCompatibility / RetryModelSave / ClearModelTransientState | `()` / `()` / `()` | `conversation.modelSelection` |
| SelectPermissionOption / RetryPermissionPersistence | `(AgentPermissionOption option)` / `()` | `conversation.permissionPreference`（拟新增常量） |
| SelectSessionConfigOption | `(String configId, Object value)` | `conversation.sessionConfig`（拟新增常量） |
| SwitchProvider | `(String providerId)` | `conversation.providerSelection`（拟新增常量） |

同步展开命令同样通过 Actions 和 typed effect；executor 同步返回 typed outcome，但 runner 在当次同步调用栈直接执行并 settle，不人为增加 microtask，保留一次点击立即改变展开事实的行为。虽然返回已经完成的 Future，状态更新时序仍同步。它们不复用审批 pending 表。

发起时冻结 payload：复制图片路径、mentions/skills list；answers 外层 Map 和每个 List 都冻结；execpolicyAmendment 复制；WP6 config value 只接受现有控件产生的 String/bool/num 等受支持标量，不接收任意可变对象。权限快照保持明确来源，不以默认值重新构造。冻结发生在 Action 入口，不在 await 之后。

**补齐现有丢字段处**：当前 Store 的 SendMessageRequested/SendMessageEffect 缺 `permissionSnapshotOverride`，迁移时必须加入 payload 并原样透传 executor；当前 `AgentConversationPlanExecutionEffect` 用 `revisionFeedback == null` 区分 start/revise，无法表达 `revisePlanExecution(request, revisionMessage:null)`。改为独立 Start/Revise 变体，null 修订只关闭交接并恢复 Plan Composer，绝不能路由为执行计划。

### 2.6 Notifier、runner、scope 与结果完整流程（拟新增伪代码）

WP3 已固定身份方案：拟新增不可变 `AgentConversationOwnerKey(entryId, lifetimeToken:Object)`，真实 `agentConversationSliceOwnerProvider.family(...OwnerKey)` 非 autoDispose。公开 selector/Actions facade 仍接 `AgentConversationBindingKey`，由 app workspace 持有 draft/current binding aliases→同一个 OwnerKey。草稿晋升 thread 不新建 Notifier，`agentConversationSessionDependenciesProvider(ownerKey)` 在真实 owner.build 中通过 ref.read 一次取得并冻结，不使用 ref.watch 让关闭/alias 更新重建 owner。owner token 不序列化；只有同 token 才允许既有 scope 的 draft→thread 例外。切片不得依赖 `workbenchSessionProvider`；resolver 显式区分 Live/Closing/Closed/Unknown。外置 lifetime coordinator 先将 entry 标为 Closing、关闭命令/结算 waiter、退订 region；公共 facade 对 Closing/Closed 返回不带历史/controller 的空终止投影，Actions 拒绝新命令。再移除可见 entry、释放 controller/lease；终止 alias/projection 在最后一个 facade 退订后清理。真正 Unknown 的 BindingKey 仍 fail-closed。资源释放不等待 UI frame；不能让合法退场的旧 pane 因 alias 先消失而抛错。

```dart
// 拟新增：放在 payload/result 周边的不可变命令信封。
final class AgentConversationCommandEnvelope {
  const AgentConversationCommandEnvelope({required this.id, required this.scope,
    required this.ownerLifetimeToken, required this.payload});
  final OperationId id;
  final AgentConversationCommandScope scope;
  final Object ownerLifetimeToken;
  final AgentConversationCommandPayload payload;
}

// 拟新增 intent/effect；替换旧的逐字段转发 intent/effect 壳。
final class AgentConversationCommandRequested extends AgentConversationSliceIntent {
  const AgentConversationCommandRequested(this.command);
  final AgentConversationCommandEnvelope command;
}
final class AgentConversationExecuteCommandEffect extends AgentConversationSliceEffect {
  const AgentConversationExecuteCommandEffect(this.command);
  final AgentConversationCommandEnvelope command;
}
final class AgentConversationOperationSettled extends AgentConversationSliceIntent {
  const AgentConversationOperationSettled(this.id, this.failureKind);
  final OperationId id;
  final AgentCommandFailureKind? failureKind; // 不带结果 payload/文案/session。
}

// 拟新增伪代码：Notifier 为唯一切片 owner。WP3 的 build/DI 细节沿用 WP3。
final class AgentConversationSliceNotifier extends Notifier<AgentConversationSliceState>
    implements AgentConversationActions, AgentConversationCommandResultSink {
  final Map<OperationId, Completer<AgentConversationCommandResult>> _waiters = {};
  final Map<OperationId, AgentConversationCommandEnvelope> _inFlight = {};
  final Map<String, OperationIdGenerator> _generators = {};
  AgentConversationSliceNotifier(this.ownerKey);
  final AgentConversationOwnerKey ownerKey; // WP3 拟新增稳定身份。
  Object get ownerLifetimeToken => ownerKey.lifetimeToken;
  bool _closed = false;

  Future<AgentConversationCommandResult> _submit(AgentConversationCommandPayload payload) {
    if (_closed) return Future.value(failureResult(AgentCommandFailureKind.staleTarget));
    final id = generatorFor(payload.fixedScope).next();
    final envelope = AgentConversationCommandEnvelope(id: id,
      scope: dependencies.regions.currentCommandScope(),
      ownerLifetimeToken: ownerLifetimeToken, payload: freeze(payload));
    final waiter = Completer<AgentConversationCommandResult>();
    _waiters[id] = waiter; _inFlight[id] = envelope;
    // 必须先注册 waiter 再 dispatch：同步命令可能立即回流。
    try { dispatch(AgentConversationCommandRequested(envelope)); }
    catch (_) { settle(id, failureResult(AgentCommandFailureKind.requestFailed)); }
    return waiter.future;
  }

  Future<AgentCommandOutcome> sendMessage(String text, { /* 2.3 全部参数 */ }) =>
    _submit(AgentSendMessageCommand(text: text, localImagePaths: localImagePaths,
      mentions: mentions, skills: skills,
      permissionSnapshotOverride: permissionSnapshotOverride))
      .then((result) => result.outcome);
  Future<AgentForkCommandOutcome> forkCurrentThread() =>
    _submit(const AgentForkCurrentThreadCommand()).then((result) =>
      result.fork ?? AgentForkCommandOutcome.fromRegularFailure(result.outcome));
  // 其他 action 按 2.5 表逐项构造明确 payload，不用反射。

  void settle(OperationId id, AgentConversationCommandResult result) {
    final waiter = _waiters.remove(id);
    final envelope = _inFlight.remove(id);
    if (waiter == null || envelope == null) return; // 重复/迟到，不能二次 complete。
    try {
      if (!_closed) dispatch(AgentConversationOperationSettled(id, result.failureKind));
    } finally {
      if (!waiter.isCompleted) waiter.complete(result.withoutDiagnostic());
    }
  }
  bool isOpenOperation(OperationId id, Object token) =>
    !_closed && identical(token, ownerLifetimeToken) && _inFlight.containsKey(id);

  void closeCommandIngress() {
    if (_closed) return;
    _closed = true; // 先关入口，禁止 reentrant dispatch。
    for (final waiter in _waiters.values.toList()) {
      if (!waiter.isCompleted) waiter.complete(failureResult(AgentCommandFailureKind.staleTarget));
    }
    _waiters.clear(); _inFlight.clear(); _generators.clear();
    // 不再 publish disposed Notifier。runner queue 取消未执行项，已发请求不伪造撤销。
  }
}

// 拟新增/调整：runner factory 由 WP3 注入，在 Notifier.build 中拿 this 构造。
typedef AgentConversationRunnerFactory = AgentConversationCommandEffectRunner Function(
  AgentConversationCommandResultSink sink, Object ownerLifetimeToken);
// runner 禁止持 Ref 反读 notifier；只拿 executor、regions/currentScope 和 sink。

bool canExecute(Envelope e) =>
  sink.isOpenOperation(e.id, e.ownerLifetimeToken) &&
  e.scope.matchesForExecution(currentScope());
bool canCommit(Envelope e) =>
  sink.isOpenOperation(e.id, e.ownerLifetimeToken) &&
  e.scope.matchesForCommit(currentScope());

Future<void> runAsync(Envelope e) async {
  if (!canExecute(e)) { sink.settle(e.id, staleResult()); return; }
  AgentConversationCommandResult result;
  try { result = await invokeTyped(e.payload); }
  on UnsupportedError { result = failureResult(AgentCommandFailureKind.unsupported); }
  on Object catch (error, stack) {
    // 原文不写入结果/日志。仅允许既有结构化错误记录器的白名单信息。
    reportNormalizedFailure(error.runtimeType);
    result = failureResult(AgentCommandFailureKind.requestFailed);
  }
  if (!canCommit(e)) {
    // fork 若已产生 session，保留在仅内存 typed 返回值中，但 activated=false。
    result = result.asStaleKeepingCreatedSession();
  }
  sink.settle(e.id, result);
}

// 拟新增：同步命令不走 await，保持展开集合/本地选择当次更新。
void run(AgentConversationExecuteCommandEffect effect) {
  final e = effect.command;
  if (!isSynchronousPayload(e.payload)) { unawaited(runAsync(e)); return; }
  if (!canExecute(e)) { sink.settle(e.id, staleResult()); return; }
  AgentConversationCommandResult result;
  try { result = AgentConversationCommandResult.regular(invokeSync(e.payload)); }
  on UnsupportedError { result = failureResult(AgentCommandFailureKind.unsupported); }
  on Object { result = failureResult(AgentCommandFailureKind.requestFailed); }
  sink.settle(e.id, canCommit(e) ? result : result.asStaleKeepingCreatedSession());
}

AgentCommandOutcome invokeSync(AgentConversationCommandPayload p) => switch (p) {
  AgentToggleExpansionCommand(:final target, :final id) => switch (target) {
    AgentConversationExpansionTarget.toolCall => executor.toggleToolCall(id),
    AgentConversationExpansionTarget.planMessage => executor.togglePlanMessage(id),
    AgentConversationExpansionTarget.activePlan => executor.toggleActivePlan(id),
    AgentConversationExpansionTarget.commandGroup => executor.toggleCommandGroup(id),
    AgentConversationExpansionTarget.fileEditItem => executor.toggleFileEditItem(id),
  },
  AgentDismissPlanExecutionCommand(:final request) => executor.dismissPlanExecution(request),
  AgentSelectPlanExecutionPermissionCommand(:final request, :final option) =>
    executor.selectPlanExecutionPermissionOption(request, option),
  AgentSelectConversationModeCommand(:final modeId) => executor.selectConversationMode(modeId),
  AgentClearModelTransientStateCommand() => executor.clearModelConfigurationTransientState(),
  _ => throw StateError('Asynchronous command sent to synchronous runner'),
};

Future<AgentConversationCommandResult> invokeTyped(AgentConversationCommandPayload p) async {
  if (p case AgentForkCurrentThreadCommand()) {
    return AgentConversationCommandResult.fork(await executor.forkCurrentThread());
  }
  final outcome = await switch (p) {
    AgentSendMessageCommand() => executor.sendMessage(p.text,
      localImagePaths: p.localImagePaths, mentions: p.mentions, skills: p.skills,
      permissionSnapshotOverride: p.permissionSnapshotOverride),
    AgentCancelActiveTurnCommand() => executor.cancelActiveTurn(),
    AgentEditLastUserMessageCommand(:final newText) => executor.editLastUserMessageAndRetry(newText),
    AgentRetryOpenThreadCommand() => executor.retryOpenThread(),
    AgentRespondPermissionCommand() => executor.respondToPermission(p.request,
      approved: p.approved, cancelTurn: p.cancelTurn,
      commandDecision: p.commandDecision, execpolicyAmendment: p.execpolicyAmendment),
    AgentRespondQuestionCommand() => executor.respondToQuestion(p.request, answers: p.answers),
    AgentRespondPlanApprovalCommand() => executor.respondToPlanApproval(p.request, p.kind, reason: p.reason),
    AgentStartPlanExecutionCommand(:final request) => executor.startPlanExecution(request),
    AgentRevisePlanExecutionCommand() => executor.revisePlanExecution(p.request, revisionMessage: p.revisionMessage),
    AgentApproveGuardianDeniedActionCommand() => executor.approveGuardianDeniedAction(),
    AgentRenameCurrentThreadCommand(:final name) => executor.renameCurrentThread(name),
    AgentArchiveCurrentThreadCommand() => executor.archiveCurrentThread(),
    AgentCompactCurrentThreadCommand() => executor.compactCurrentThread(),
    AgentLoadModelsCommand(:final forceRefresh) => executor.loadModels(forceRefresh: forceRefresh),
    AgentEnsureSkillsCatalogCommand() => executor.ensureSkillsCatalog(),
    AgentRetryConversationModesCommand() => executor.retryConversationModes(),
    AgentSelectModelCommand(:final modelId) => executor.selectModel(modelId),
    AgentSelectReasoningEffortCommand(:final effort) => executor.selectReasoningEffort(effort),
    AgentSelectFastEnabledCommand(:final enabled) => executor.selectFastEnabled(enabled),
    AgentResolveModelCompatibilityCommand() => executor.resolveModelCompatibilityConflict(),
    AgentRetryModelSaveCommand() => executor.retryModelConfigurationSave(),
    AgentSelectPermissionOptionCommand(:final option) => executor.selectPermissionOption(option),
    AgentRetryPermissionPersistenceCommand() => executor.retryPermissionPreferencePersistence(),
    AgentSelectSessionConfigOptionCommand() => executor.selectSessionConfigOption(p.configId, p.value),
    AgentSwitchProviderCommand(:final providerId) => executor.switchActiveProvider(providerId),
    _ => throw StateError('Synchronous or fork command sent to ordinary async runner'),
  };
  return AgentConversationCommandResult.regular(outcome);
}

// reducer 拟调整：只有状态转移，绝不能 complete Future/查 runtime/调用 executor。
switch (intent) {
  case AgentConversationCommandRequested(:final command):
    return Transition(state.copyWith(
      pendingOperations: Set.unmodifiable({...state.pendingOperations, command.id}),
      clearLastFailure: true), [AgentConversationExecuteCommandEffect(command)]);
  case AgentConversationOperationSettled(:final id, :final failureKind):
    if (!state.pendingOperations.contains(id)) return Transition.none(state);
    return Transition.stateOnly(state.copyWith(
      pendingOperations: Set.unmodifiable(state.pendingOperations.where((x) => x != id)),
      lastFailure: failureKind == null ? state.lastFailure
        : AgentConversationOperationFailure(operationId: id, kind: failureKind)));
  case AgentConversationRegionsRefreshed():
    // 继续原有 region 合并；不复制 live token/history 正文。
}
```

以上 `failureResult`、`staleResult`、`withoutDiagnostic`、`asStaleKeepingCreatedSession`、`freeze`、`generatorFor`、`fromRegularFailure`、`isSynchronousPayload`、`failureKind` getter 均为拟新增私有辅助 API，行为已在注释中限定，实施时必须实现并测试。`fromRegularFailure` 遇到无 session 的 succeeded 按内部接线失败返回 requestFailed，测试必须将该情况判为缺陷；它发生在 Actions 的 then 中，不能声称 runner 会替它捕获异常。不可造一个空 session 成功。

**scope 不做错误简化**：保留 `matchesForExecution` 验证 listenerGeneration；提交使用 `matchesForCommit`，因为首发/重订阅可能合法更新 listenerGeneration。runtime identity/epoch 已变化则 stale；首次发送从无 runtime 建立 runtime 合法；目标临时变成无 runtime 的真实失败不能被无条件改判 stale。owner token 防止现有 `_matchesBinding` 的同 provider draft→thread 规则误收另一个 entry 的结果。不得为了只读 key 固定而禁止正常 draft 晋升。

### 2.7 并发、关闭与错误发布的固定规则

1. **OperationId 不与 scope 字符串混用**。相同 scope 的 A/B 两次调用有不同 id，各自清理；A 完成不能删除 B。不要把“最新 id”当所有并发命令的唯一 pending 值。
2. **没有全局串行锁**。发送/steer、cancel、权限/问题响应必须可及时进入现有 executor；不能排在模型目录、权限默认值写入或 fork 后面。底层既有 ProviderOperationScheduler 与 G5 保护继续有效。
3. **局部串行**仅用于权限偏好选择（见 2.4）与 [WP-6](06-wp6-session-config.md) 同一 config key（见其 §6.4）。队列排队时保留原 scope，轮到执行再校验；entry 关闭后排队项不调用 Provider。
4. **审批重复点击**按 `(owner token, 审批种类, request.id)` 做运行期 admission 去重，重复调用返回 ignored(alreadyPending)，不复用另一类请求的 waiter。四个注册集合分开，动作完成/失败/关闭都释放键；当前已有 G5 registry 不改为同一张表。
5. **模型快速选择**沿用 model owner 的合并保存算法，每个 waiter 都以其真实确认/覆盖结果完成；不拿较晚一条选择的 saveError 归因早期操作。后到成功不抹除别人的 pending。
6. **关闭**立即完成未决 UI Future 为 staleTarget、清空 owner 内存表、关闭 ingress；底层已发出的 CLI 操作可能完成，不能宣称已取消。真正取消只有 cancelActiveTurn 动作。迟到结果不会重新 publish 或激活另一 entry。
7. **有 intent、无 effect/runner 抛错**的内部断言也要 finally 清 waiter；测试用 throwing runner 固定这一点。新事务注册失败不能留下 pendingOperations。
8. **错误显示只一次**。最后失败快照仅供状态/诊断投影；不能同时对每个 `lastFailure` 做全局 toast 又在按钮 await 后 toast。RuntimeController 已有 header/model region 错误时沿用该面；WP6 由局部控件显示 typed error。staleTarget、superseded、alreadyPending 静默完成，不在已离开的 Canvas 弹错。
9. **无新增持久化**。OperationId、Completer、scope、command payload、fork session、permission snapshot 全是内存对象；日志/指标不记录正文、路径、raw error。固定 scope 常量不得拼 configId/threadId/requestId。

### 2.8 两类 fork 与发送 payload 的不可丢语义

**直接 fork**：当前 `forkCurrentThread()` 返回 `AgentSession?`；甚至在 `_isCurrentSwitch` 失败时也可能返回已创建 session（当前 controller:2575 附近）。拟改 executor 返回 `AgentForkCommandOutcome`：Provider 创建失败→failed、session=null；创建成功且 Shell 激活完成→completed(session)；创建成功但 source 失效或激活失败→failed(staleTarget/requestFailed, createdSession:session)。保留 session 是为了不把已发生的外部副作用描述成“没有创建”，不能因此重试再 fork。它只供本次返回/调试，切片状态与日志不保存。

**编辑后分支重试**：当前 `editLastUserMessageAndRetry` 选上一用户消息之前的 `AgentForkThroughTurn` 边界，调用 `_openCreatedThread(session, initialMessage:trimmed)`，返回普通 outcome。保持该顺序和返回面。不得把它改成对当前 thread steer，也不原地改绑 source。若创建成功但后续激活/发送失败，向用户返回失败，已创建分支仍在 Shell 正常 thread 目录中，不自动删除/再次创建。其内部可复用 typed fork helper，但外层 action 只 await 整个流程，不由 UI 重新调用发送。

**新 entry 的 initialMessage**：Shell 当前在 `ide_shell_controller.dart:1063` 直接 `entry.controller.sendMessage`。迁移为新 entry 的 `actions.sendMessage`，获取的 owner 必须是新 entry，而不是 source 的 Notifier。这样 source 的 edit action 与新 entry 的 send 各有自己的 OperationId/scope；不能共享/偷用 source 的 permission snapshot。Shell 的 `_openCreatedThread` callback 至多激活一次。

**回调结果必须贯穿 Shell**：当前 `AgentCreatedThreadCallback`、RuntimeController 的 `_openCreatedThread`、Shell 的 `_openCreatedThread` 都返回 Future<void>，Shell await 新发送后丢弃 outcome。若只改最外层 Actions，编辑重试仍可能把新 entry 发送失败报告为成功。因此本包明确调整这三处返回类型，参数及不可变构造注入方式保持：

```dart
// 拟调整；不引入可变 relay，WP3 在创建 entry 时注入固定 callback。
typedef AgentCreatedThreadCallback = Future<AgentCommandOutcome> Function({
  required AgentSession session,
  required AgentContext context,
  String? initialMessage,
});

// 拟调整 Shell 方法：原 register/select/context 校验顺序保持。
Future<AgentCommandOutcome> _openCreatedThread({
  required AgentSession session, required AgentContext context, String? initialMessage,
}) async {
  final thread = registerCreatedSession(session, context, initialMessage); // 现有逻辑提称。
  await selectProjectThread(context.projectPath!, thread);
  final entry = workspace.selectedEntry;
  validateEntryMatchesCreatedSession(entry, session); // 失败抛错，不回退另一个 entry。
  entry.controller.updateContext(projectPath: context.projectPath, contextFilePath: context.filePath);
  final text = initialMessage?.trim();
  if (text == null || text.isEmpty) return const AgentCommandOutcome.succeeded();
  // app coordinator 读取该 entry 的稳定 OwnerKey actions；不能读取 source actions。
  return actionsForOwner(entry.ownerKey).sendMessage(text);
}

// 拟调整 RuntimeController：_openCreatedThread 返回 callback 的结果，不 await 后丢弃。
Future<AgentCommandOutcome> _openCreatedThread(AgentSession session, {String? initialMessage}) {
  validateCreatedSession(session); // 现有 provider/source-thread 身份校验。
  return onCreatedThread!(session: session, context: currentContext,
    initialMessage: initialMessage);
}
// editLastUserMessageAndRetry：fork 后校验 source scope；
// final result = await _openCreatedThread(session, initialMessage: trimmed);
// _restoreSourceAfterBranchCreated(); return result;
// forkCurrentThread：没有 initialMessage；仅 callback succeeded 时 completed(session)；
// callback failed -> failed(kind, createdSession:session)；意外 ignored -> failed(staleTarget,createdSession:session)。
```

这里 `registerCreatedSession`、`validateEntryMatchesCreatedSession`、`actionsForOwner`、`validateCreatedSession`、`currentContext` 是对既有代码/拟新增 app 接缝的语义占位，实施时沿用现有校验与 WP3 OwnerKey 解析。所有相关 fake callback 必须返回 outcome，不能 `async {}` 自动变成 void 成功。真实 UI 回归另加“分支创建成功、新 entry 发送失败”的用例。

**普通 send**逐字段验证：text（保留原 Unicode，executor 继续已有 trim/context 拼装）、localImagePaths、mentions 的 name/path、skills（不删空文本+skill）、permissionSnapshotOverride 全量透传。UI 不计算 Provider raw payload、不对 mentions UTF-8 offset 再做一次映射。集合冻结仅防止调用后被改，不改变顺序/去重语义。

**关闭时 fork 产物的认识边界**：若 owner 在 Provider fork 尚未返回时关闭，UI Future 已按关闭契约完成 staleTarget，之后不能再更新这个已完成的返回值。`createdSession == null` 在这种情况下只表示“完成当时未知”，不能解释为“Provider 没创建”。迟到 session 不激活旧 Canvas、不自动重试 fork、不写入命令状态；用户仍可经正常 thread 列表刷新发现 Provider 已创建的分支。只有在 settle 前已拿到 session 的失败才通过 typed outcome 返回 session。

**Plan execute 内部 send**：`startPlanExecution` 仍在 executor 内校验本地 request、恢复有效权限选择、显式 Default 新 turn，再调用 executor 的 sendMessage(permissionSnapshotOverride: executionPermission.toRequestSnapshot())。这一内部子调用不要重新进入 UI Actions 递归记第二个“用户发送”，也不能自动预授权计划里的命令。除明确定义的 Shell 新 entry 交接，executor 内部组合命令保持内部调用。

### 2.9 全部现有 UI 命令覆盖清单

以下清单按当前源码真实调用列出；实施 PR 应逐行填写“已迁移路径 + 测试名”。没有 UI 调用的 executor 能力明确标出，不能为了展示入口而新增产品 UI。

| 当前入口/文件 | 现有调用 | 目标 Action / 注意事项 |
|---|---|---|
| `agent_pane.dart:218` + composer session send | sendMessage | sendMessage；Future typed；payload 全量透传 |
| `agent_pane_sections.dart:1000` | cancelActiveTurn | cancelActiveTurn；不受偏好/目录队列阻塞 |
| `agent_pane_messages.dart:595` 编辑确认 | editLastUserMessageAndRetry | 同名；保留 fork 边界和新 entry 发送 |
| `agent_pane_header.dart:271` | forkCurrentThread | typed fork；UI 不重复导航/创建 |
| `agent_pane_header.dart:280/374` | archiveCurrentThread / renameCurrentThread | 同名 typed Actions；rename 对话框仍在 presentation |
| `agent_pane_composer_session.dart:599` slash compact | compactCurrentThread | 同名 Action；slash 输入处理不进 application |
| `agent_pane_sections.dart:886/934` | respondToQuestion / respondToPermission | 独立动作，保留空 answers=Skip 和全部 permission 参数 |
| `agent_pane_sections.dart:926` | approveGuardianDeniedAction | 同名 Action；与权限审批独立 |
| `agent_pane_cards.dart:2028/2036/2042` | respondToPlanApproval 的三种 decision | 同名 Action，保留 reason；不映射权限 approve |
| `agent_pane_messages.dart:108` | selectPlanExecutionPermissionOption | 同名 Action；只改本地一次性权限 |
| `agent_pane_messages.dart:110/114/115` | revise/start/dismissPlanExecution | 三个独立 payload；null revision 必测 |
| `agent_pane_plan_panel.dart:90` | toggleActivePlan | 同步效果的 Action |
| `agent_pane_cards.dart:55/180/358` | toggleCommandGroup / toggleFileEditItem / toggleToolCall | 同名 Actions；稳定绑定/展开集合 owner 不变 |
| `agent_pane_messages.dart:687` | togglePlanMessage | 同名 Action |
| `agent_pane_sections.dart:1012` + composer session:596 | selectConversationMode | 同名 Action；slash Plan 与工具栏同一路径 |
| `agent_pane_sections.dart:1021-1029` | selectModel / selectReasoningEffort / selectFastEnabled / resolveModelCompatibilityConflict / retryModelConfigurationSave / clearModelConfigurationTransientState | 六个独立 typed Actions；popover 关闭仍只是 UI 事件，清理 application transient 的动作通过入口 |
| `agent_pane_cards.dart:757-762` 历史/上下文模型配置入口 | 同上六个模型调用 | 同一 Actions，不能漏掉 Composer 之外入口 |
| `agent_pane_sections.dart:1031/1043` | selectPermissionOption / takePermissionApplyHint | selectPermissionOption Action；删除 take 调用，由现有 region hint 展示 |
| `agent_pane_sections.dart:1048` | selectSessionConfigOption | WP6 typed action、控件 await 结果 |
| `agent_pane_composer_session.dart:659/704` | ensureSkillsCatalog | Action；查询 skillCandidates 仍是只读 |
| Shell 用户触发的 Provider 切换（`ide_shell_controller.dart:871`） | switchActiveProvider | entry actions.switchActiveProvider；仍由 onProviderSwitchRequested 新建/选择别的 entry |
| Shell 用户重试打开 thread（`ide_shell_controller.dart:923`） | retryOpenThread | 目标 entry actions.retryOpenThread；初始化 `_openBoundThread` 不绕回 UI |
| app 用户衍生的新 thread 初始发送（`:1063`） | entry.controller.sendMessage | 新 entry Actions；见 2.8 |
| 目前主要是 app bootstrap 或公开能力，未见本 feature UI 直接调用 | loadModels / retryConversationModes / retryPermissionPreferencePersistence | 保留 Actions 能力并测试；bootstrap 可走有说明的 executor 路径，未来 UI 必须接 Actions |

`AgentPaneBody` 和 renderer 需要传递的是 Actions 或一个按稳定 entry 身份读取 Actions 的函数，不是继续把 `controller` 当万能命令对象。保留只读 controller 的过渡文件必须被符号级守卫禁止上述写方法调用；最终 RenderContext 的 `actions` 由构造参数注入，`bindingKey` 独立注入，不能 `get actions => controller`。

```dart
// 拟新增 provider，真正定义在 application；使用现有 flutter_riverpod。
final agentConversationActionsProvider = Provider.autoDispose.family<
    AgentConversationActions, AgentConversationBindingKey>((ref, bindingKey) {
  final resolution = ref.watch(agentConversationOwnerResolutionProvider(bindingKey));
  return switch (resolution) {
    AgentConversationOwnerLive(:final ownerKey) =>
      ref.read(agentConversationSliceOwnerProvider(ownerKey).notifier),
    AgentConversationOwnerClosing() || AgentConversationOwnerClosed() =>
      const AgentClosedConversationActions(),
    AgentConversationOwnerUnknown() => const AgentClosedConversationActions(),
  };
});
// 上述 resolver 变体为 WP3 拟新增类型；确切定义与 WP3 保持一份。
// Live 返回当时解析出的实际 Notifier，已捕获 ownerKey+lifetime。
// Actions 对象的每次命令不能再按 BindingKey ref.read/resolve；关闭后旧句柄拒绝调用。
// AgentClosedConversationActions 是拟新增无状态终止面：普通方法统一返回
// Future.value(failed(staleTarget))，fork返回typed failed(staleTarget)，无资源/无owner。
// Unknown 同样没有可执行目标，拒绝调用；未安装resolver override仍抛装配错误。
// 纯facade可autoDispose；Closed/Unknown都不能重新创建一个实际Notifier。
// 不接受“return ref.watch(agentConversationRuntimeProvider(...))”。

// 拟调整 presentation 回调：创建/更新该 entry 的 UI session 时捕获动作句柄。
final AgentConversationActions capturedActions =
  ref.read(agentConversationActionsProvider(bindingKey));
Future<AgentCommandOutcome> submitMessage(String text, { /*完整参数*/ }) =>
  capturedActions.sendMessage(text,
    localImagePaths: localImagePaths, mentions: mentions, skills: skills,
    permissionSnapshotOverride: permissionSnapshotOverride);
// Widget 换 entry 时更换自己的 capturedActions；旧异步闭包继续持旧句柄并被关闭门禁拒绝。
// 不能在旧回调触发时重新解析相同 BindingKey，使其落到“重开的新entry”。
```

发送草稿当前在调用前清空（`agent_pane_composer_session.dart:541-565`），WP2 保留此交互时序，避免连点重复提交；本包不顺手实现“失败自动恢复草稿”。将 submit callback 改为 Future，只为结果闭环和精确反馈；图片暂存 ownership 的释放仍按原路径，不能在尚未被 Provider 消费时因为 await 失败提前删文件。若要另加草稿恢复，须独立需求与版本 guard，不包含本 WP。

### 2.10 测试、步骤与验收

**真实 UI 测试必须通过按钮/快捷键**，不能用 notifier 方法调用代替全部测试：

1. 给 executor fake 的 send 设置 Completer；输入文字并真实点击发送，断言当前 entry Notifier 的 pendingOperations 增 1、fake 精确收到 payload；完成后 Future/账本结算一次。再在真实按钮路径触发失败、取消、关闭、epoch 改变。
2. 两 Canvas A/B 同时有命令在途，A 的失败/关闭不得清理 B；A/B 都从 draft 晋升 thread，不能互收同 provider 的结果。测试不 override Actions 自身，否则绕过了待验证入口；只 override executor/dependencies。
3. 真实权限、问题、PlanApproval、PlanExecution 卡片各点一次，分别到四类 port；重复点击只调用一次；空 answers 不变；Plan revision=null 不调用 start；Plan 执行产生新的 Default turn 且权限不升级。
4. fork 菜单：executor 返回 created+activated 与 created+activation failed；断言结果 session 不丢、只导航一次。编辑重试对话框：source thread 保持不变，新 entry action 接到文本，原边界/权限参数保持。
5. 快速点击模型 A/B、Fast 冲突确认、保存失败重试：每个 outcome 精确完成，不将 requiresConfirmation 报 requestFailed；联动字段回滚仍完整。
6. slash Plan/compact、skill 目录 picker、工具/计划展开、历史模型配置菜单各有真实 UI smoke，防止只改 Composer。
7. runner/state 单测：同步 effect 在 dispatch 内完成、抛出异常、重复 settle、同 scope 并发 A/B、close-before-execute/after-await、队列未轮到时关闭、clear waiter 后迟到、draft晋升、listener 正常重挂。

**旧测试迁移**：旧 Store reducer 纯函数断言保留；原 store.sendMessage 单元路径改为 application Notifier 的 Actions；未决返回从 `OperationId` 改为 Future，OperationId 从只读 state/diagnostics 观察而不加生产 debug override。`agent_conversation_slice_providers_test` 删除“纯镜像”假设，保留 entry 隔离、只变 header 不刷新其他 region、Widget 退订不释放 Binding 的行为断言。架构守卫升级为 AST 检查 production UI 的 controller 写方法访问及 Actions provider 依赖，不能只搜 runner 存在两个字符串。

**实施顺序**：

1. WP3 完成并稳定：先确认单 owner、stable entry/token、不会因 draft 晋升 rebuild 清空 waiter；WP6 executor 与控件结果先落地。
2. 新增 Actions、payload、result/sink，按表覆盖 executor 签名与 model typed 结果；编译所有 fake，不接 UI 前先跑 executor/runner 窄测试。
3. 将旧命令 intent/effect 归并为 typed command 信封，保留 RegionsRefreshed 和 reducer 账本；在 Notifier 中注册 Future 结算，补 close/并发测试。
4. 一次性迁移表中全部真实 UI 与 Shell 用户衍生命令；UI session 捕获动作句柄，异步回调不得重新按可复用 BindingKey 解析；删除 command provider 直接返回 controller 的路径。迁移期间可在同一未合并分支临时兼容旧签名，提交收尾必须清零，不能发布双路径。
5. 更新架构文档与 guard；依次 `dart format .`、`flutter analyze`、`bash tool/test_affected.sh`；此 WP 属重构收尾，最后执行 `bash tool/test_full.sh`，检查所有涉及包。不得修改 `dart_test.yaml` 并发。

**文档同步门禁**：开发者指南现存 Plan 章节若仍写“不绑定 runtime generation”“取第一个非 planning allowed”“直接 adopt”，与 AGENTS G5 冲突时以 G5 为准：只恢复同 Binding/thread/runtime generation 有效的用户明确策略；失效使用 catalog 保守默认，目录不可用要求显式选择。WP2 不以旧指南放宽权限；提交时同步纠正冲突段并注明此包仅迁移入口。

**可验收产物**：逐项覆盖表已签收；普通动作 Future 无永久 pending；fork typed session 正确；四种审批隔离；无 UI→executor 写方法；无 runner↔Notifier import/Ref 环；相关 l10n/ARB 对齐和 localized checker 通过；全量绿，运行态和存储格式不变。

**回滚**：WP2 独立提交，回滚以完整提交为单位（Actions+UI+结果桥+测试）进行，不能仅把 provider 指回 controller 留下其余 typed 账本。WP6 独立修复可以保留；WP3 单 owner 可以保留，临时恢复旧 executor 调用也必须明确整包回滚的版本边界，不能以功能开关长期维持双入口。无数据迁移，因此无需回滚持久化。


### 2.11 实现校正与验收入口

- 沿用 WP-3 §13 的 autoDispose + 显式 keepAlive 回收机制；§2.6 原非 autoDispose 伪代码不代表当前实现。
- Actions 共 35 个方法；固定 scope 常量放在 payload 文件，与完整 typed command 信封保持同一归属。旧命令 provider 和 presentation session-config 翻译器均删除，无兼容写入口。
- 复核发现本地 `AgentPlanExecutionHandoffController` 仍以“第一个可执行选项”兜底，违反 G5/本文目标；本次一并移除此回退。另在 adopt 后、新发送前复核执行 scope。这是明确的权限行为修正，单独登记旧断言变化，不声称只迁移接口；不改 Provider 协议或 core 包。
- 普通结果同时覆盖 executor/runner/scope 读取异常；已知 fork 产物不因回写校验失败而丢失。模型保存按各 revision 结算，关闭后重试不创建新 waiter；编辑交接返回后先校验 source scope，再恢复源状态。
- [本次验收与逐项接线记录](../../refactor/2026-09-06-conversation-actions/00-validation.md)。最终完整门禁已通过，下一项为 WP-5 首页探测。
