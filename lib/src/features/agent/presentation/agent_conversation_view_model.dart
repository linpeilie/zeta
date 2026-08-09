import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/logging/structured_error_logging.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_binding.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect_runner.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_event_processor.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mutation.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_plan_execution_handoff_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_global_runtime.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_thread_snapshot.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_elapsed_ticker.dart';
import 'package:zeta/src/features/agent/application/agent_skills_catalog_controller.dart';
import 'package:zeta/src/features/agent/application/bounded_event_dispatcher.dart';
import 'package:zeta/src/features/agent/application/coalescing_event_buffer.dart';
import 'package:zeta/src/features/agent/application/agent_event_pipeline.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_port.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_ui_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_ui_update_scheduler.dart';
import 'package:zeta/src/features/agent/presentation/model_config_ui_state.dart';
import 'package:zeta/src/features/workspace/domain/workspace_file_query.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

export 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';

final _log = loggerFor('zeta.agent.conversation');

String _modelCatalogSource(AgentProviderConfig config) {
  return switch (config.kind) {
    AgentProviderKind.codexAppServer => 'Codex app-server',
    AgentProviderKind.acp => 'Grok ACP',
    _ => config.displayName,
  };
}

/// Provider 创建 thread 后，由 Shell 使用通用新会话流程登记并选中。
///
/// [initialMessage] 只用于“编辑后重试”：Shell 必须在新 thread 成为当前会话后，
/// 再由新 ViewModel 提交这条消息。
typedef AgentCreatedThreadCallback =
    Future<void> Function({
      required AgentSession session,
      required AgentContext context,
      String? initialMessage,
    });

/// Agent 面板的状态协调器。
///
/// 当前 ViewModel 只保留 provider/session 协调与事件路由；时间线聚合、
/// 模型选择和局部刷新节流已经下沉到 feature 级应用模块。
class AgentConversationViewModel {
  AgentConversationViewModel({
    required this.providerController,
    required this.conversationBinding,
    required this.globalRuntime,
    AgentConversationTimelineStore? timelineStore,
    AgentConversationModelSelectionController? modelSelectionController,
    AgentConversationModeController? conversationModeController,
    AgentSkillsCatalogController? skillsCatalogController,
    this.workspaceFilesProvider,
    this.workspaceFilesListenable,
    this.workspaceFilesIndexReady,
    this.onTurnCompleted,
    this.onAttention,
    this.onProviderSwitchRequested,
    this.onCreatedThread,
    String? initialProjectPath,
    String? initialContextFilePath,
    AgentThreadSummary? initialThread,
    AgentFrameScheduler? uiFrameScheduler,
  }) : _timeline = timelineStore ?? AgentConversationTimelineStore(),
       _ownsModelSelectionController = modelSelectionController == null,
       _modelSelectionController =
           modelSelectionController ??
           AgentConversationModelSelectionController(
             persistSelection: providerController.persistModelSelection,
           ),
       _ownsConversationModeController = conversationModeController == null,
       _conversationModeController =
           conversationModeController ?? AgentConversationModeController(),
       _ownsSkillsCatalogController = skillsCatalogController == null,
       _skillsCatalogController =
           skillsCatalogController ?? AgentSkillsCatalogController(),
       _permissionSelectionController = conversationBinding.permissions {
    final thread = initialThread;
    if (thread != null &&
        (thread.providerId != conversationBinding.providerId ||
            thread.id != conversationBinding.threadId)) {
      throw ArgumentError(
        'Initial thread ${thread.providerId}/${thread.id} does not match '
        'Binding ${conversationBinding.key}',
      );
    }
    _projectPath = initialProjectPath ?? thread?.projectPath;
    _contextFilePath = initialContextFilePath;
    _boundThreadSummary = thread;
    _eventReducerContexts = AgentConversationReducerContexts(
      liveTimelineIds: _localTimelineIds,
    );
    _uiStateStore = AgentConversationUiStateStore(
      timeline: _timeline,
      buildHeaderState: _buildHeaderState,
      buildComposerState: _buildComposerState,
      buildPendingInteractionState: _buildPendingInteractionState,
      buildExpansionState: _buildExpansionState,
      buildHistoryState: _buildHistoryState,
      isDisposed: () => _disposed,
    );
    _uiUpdateScheduler = AgentUiUpdateScheduler(
      _publishScheduledUiChanges,
      frameScheduler: uiFrameScheduler,
    );
    _uiUpdates = _uiUpdateScheduler;
    _eventStateTarget = _AgentConversationEventStateTarget(this);
    _eventUiUpdates = _AgentConversationEventUiUpdatePort(this);
    _effectRunner = DefaultAgentConversationEffectRunner(
      currentScope: _currentEffectScope,
      recordModelCatalog:
          ({required config, required models, required source}) =>
              providerController.modelCatalogRepository.record(
                config: config,
                models: models,
                source: source,
              ),
      onTurnCompleted: onTurnCompleted,
      onAttention: _handleAttentionSignal,
    );
    _eventProcessor = AgentConversationEventProcessor(
      reducer: _eventReducerContexts.live,
      context: _buildEventReducerContext,
      timeline: _timeline,
      stateTarget: _eventStateTarget,
      uiUpdates: _eventUiUpdates,
      effectRunner: _effectRunner,
    );
    _modelSelectionController.addListener(_handleModelSelectionChanged);
    _conversationModeController.addListener(_handleConversationModeChanged);
    _skillsCatalogController.addListener(_handleSkillsCatalogChanged);
    _permissionSelectionController.addListener(_handlePermissionStateChanged);
    providerController.addListener(_handleProviderSettingsChanged);
    conversationBinding.addListener(_handleConversationBindingChanged);
    _threadSnapshotListenable = ValueNotifier<AgentConversationThreadSnapshot>(
      _buildThreadSnapshot(),
    );
    _initialization = thread == null
        ? Future<void>.value()
        : _openBoundThread(thread);
  }

  static const String defaultThreadTitle = 'New thread';

  /// 用户确认执行计划后，用于启动 Default 回合的本地交接提示。
  static const String planExecutionPrompt =
      'Execute the plan from the previous turn. Work through it step by step '
      'and run the relevant verification before finishing.';

  /// 可选：从 shell 注入工作区文件列表，供 @mention 选择器使用。
  final List<WorkspaceNode> Function()? workspaceFilesProvider;

  /// 可选：工作区文件语料就绪/失效时通知（例如后台索引完成），供 @mention 刷新。
  final Listenable? workspaceFilesListenable;

  /// 可选：后台完整语料是否已就绪；未注入时视为就绪（直接使用 provider 结果）。
  final bool Function()? workspaceFilesIndexReady;

  /// 当前会话的回合进入终态后通知应用组合层。
  final VoidCallback? onTurnCompleted;

  /// 当前会话产生或解决待用户注意事项后通知应用组合层。
  final AgentAttentionCallback? onAttention;

  /// Binding 已锁定 Provider 时，请求 Workspace 创建并选中另一 Provider 的草稿。
  final Future<void> Function(String providerId)? onProviderSwitchRequested;

  /// Provider 创建 thread 后请求 Shell 登记并选中，禁止当前 Binding 原地改绑。
  final AgentCreatedThreadCallback? onCreatedThread;

  /// 后台文件索引是否已就绪；无注入时恒为 true。
  bool get isWorkspaceFileIndexReady =>
      workspaceFilesIndexReady?.call() ?? true;

  final AgentProviderSettingsPort providerController;
  final AgentConversationBinding conversationBinding;
  final AgentProviderGlobalRuntime globalRuntime;
  final AgentConversationTimelineStore _timeline;
  final bool _ownsModelSelectionController;
  final AgentConversationModelSelectionController _modelSelectionController;
  final bool _ownsConversationModeController;
  final AgentConversationModeController _conversationModeController;
  final bool _ownsSkillsCatalogController;
  final AgentSkillsCatalogController _skillsCatalogController;
  final AgentConversationPermissionSelectionController
  _permissionSelectionController;
  final AgentPlanExecutionHandoffController _planExecutionHandoffController =
      AgentPlanExecutionHandoffController();
  final AgentConversationLocalTimelineIdGenerator _localTimelineIds =
      AgentConversationLocalTimelineIdGenerator();
  late final AgentConversationUiStateStore _uiStateStore;
  late final AgentUiUpdateScheduler _uiUpdateScheduler;
  late final AgentUiUpdatePort _uiUpdates;
  late final AgentConversationReducerContexts _eventReducerContexts;
  late final AgentConversationStateMutationTarget _eventStateTarget;
  late final AgentUiUpdatePort _eventUiUpdates;
  late final AgentConversationEffectRunner _effectRunner;
  late final AgentConversationEventProcessor _eventProcessor;
  AgentUiUpdateRequest? _debugLastUiUpdateRequest;
  bool _threadSnapshotRefreshPending = false;
  final AgentElapsedTicker _elapsedTicker = AgentElapsedTicker();
  late final ValueNotifier<AgentConversationThreadSnapshot>
  _threadSnapshotListenable;

  /// ViewModel 只读取 Binding 暴露的中立运行时端口。
  AgentRuntimePort? get _currentRuntime =>
      conversationBinding.currentRuntime?.bundle.runtime;

  /// global 握手得到的中立能力快照；只保存 domain 值，不让 Provider 逃逸出回调。
  final Map<String, AgentProviderCapabilities> _globalCapabilitiesByProviderId =
      <String, AgentProviderCapabilities>{};

  AgentEventPipeline? _eventPipeline;

  /// 从提交被接受起持有的长生命周期活动令牌；终态或 VM dispose 时释放。
  AgentConversationTurnActivity? _turnActivity;

  AgentSession? _session;
  String? _projectPath;
  String? _contextFilePath;
  AgentThreadSummary? _boundThreadSummary;
  late final Future<void> _initialization;

  String? _restoredSessionId;
  String? _selectedProviderId;
  AgentThreadOpenPhase _threadOpenPhase = AgentThreadOpenPhase.idle;
  bool _requiresResumedSelectedThread = false;
  Future<void>? _settingsLoadFuture;
  bool _disposed = false;
  int _threadSwitchToken = 0;
  int _conversationModeCatalogLoadGeneration = 0;
  // 全局目录与 session runtime 可来自不同实例，目录去重使用中立运行时 scope。
  String? _conversationModeCatalogProviderId;
  AgentRuntimeScope? _conversationModeCatalogRuntimeScope;

  String _currentThreadTitle = defaultThreadTitle;
  AgentProviderStatus _status = const AgentProviderStatus.idle();
  AgentThreadRuntimeStatus? _threadRuntimeStatus;
  bool _threadWaitingOnApproval = false;
  bool _threadWaitingOnUserInput = false;

  /// 最近一次模型改道的目标模型；用于头栏短暂提示。
  String? _modelRerouteNotice;

  List<AgentSessionConfigOption> _sessionConfigOptions =
      const <AgentSessionConfigOption>[];

  bool _modelsRefreshing = false;
  String? _modelRefreshError;

  /// 上下文详情面板是否展开（头栏「上下文」菜单触发）。
  final ValueNotifier<bool> contextPanelVisible = ValueNotifier<bool>(false);

  /// 当前线程的创建时间；仅从恢复的 thread 摘要填充，新会话为空。
  DateTime? _threadCreatedAt;

  /// 当前线程的最后活跃时间；优先取摘要的 recency，否则 updatedAt。
  DateTime? _threadLastActiveAt;

  /// 按 turnId 跟踪 Guardian 自动评审状态。
  final Map<String, AgentAutoApprovalReviewEvent> _autoReviewsByTurnId =
      <String, AgentAutoApprovalReviewEvent>{};

  /// 最近一次被拒绝的自动评审（供放行按钮使用）。
  AgentAutoApprovalReviewEvent? _latestDeniedAutoReview;

  List<AgentConversationMessage> get messages => _timeline.messages;

  /// 等待 Entry 创建时绑定的 thread 完成首次历史加载；草稿立即完成。
  Future<void> get initialization => _initialization;

  List<AgentToolCall> get toolCalls => _timeline.toolCalls;

  List<AgentPermissionRequest> get permissionRequests =>
      _timeline.permissionRequests;

  List<AgentQuestionRequest> get questionRequests => _timeline.questionRequests;

  List<AgentPlanApprovalRequest> get planApprovalRequests =>
      _timeline.planApprovalRequests;

  /// Plan 回合完成后等待用户决定是否进入执行阶段的本地交接请求。
  AgentPlanExecutionRequest? get planExecutionRequest =>
      _planExecutionHandoffController.pendingRequest;

  List<AgentTimelineEntry> get timelineEntries => _timeline.timelineEntries;

  List<AgentConversationTurnGroup> get conversationTurns =>
      _timeline.conversationTurns;

  List<AgentConversationTurnGroup> get visibleHistoryTurns =>
      _timeline.visibleHistoryTurns;

  AgentConversationTurnState? get standbyTurnState =>
      _timeline.standbyTurnState;

  List<AgentConversationTurnState> get visibleHistoryTurnStates =>
      _timeline.visibleHistoryTurnStates;

  AgentConversationTurnState? get liveTurnState => _timeline.liveTurnState;

  /// 当前 live turn 的结构化执行计划；不会进入历史时间线。
  List<AgentPlanEntry> get activePlanEntries =>
      liveTurnState?.planEntries ?? const <AgentPlanEntry>[];

  /// Plan 面板只在非阻塞的可写运行回合中展示多步骤计划。
  bool get shouldShowActivePlan =>
      isTurnRunning &&
      !isReadOnly &&
      activePlanEntries.length >= 2 &&
      permissionRequests.isEmpty &&
      questionRequests.isEmpty &&
      planApprovalRequests.isEmpty &&
      planExecutionRequest == null &&
      !threadWaitingOnApproval &&
      !threadWaitingOnUserInput;

  AgentProviderStatus get status => _status;

  /// 旧 Cursor 选择被安全回退时需要持续展示的不可用原因。
  String? get unavailableProviderReason =>
      providerController.unavailableSelectionReason;

  /// 当前选中线程的运行时状态（来自 `thread/status/changed`）。
  AgentThreadRuntimeStatus? get threadRuntimeStatus => _threadRuntimeStatus;

  /// 当前线程是否在等待用户审批。
  bool get threadWaitingOnApproval => _threadWaitingOnApproval;

  /// 当前线程是否在等待用户输入。
  bool get threadWaitingOnUserInput => _threadWaitingOnUserInput;

  /// 状态胶囊文案；等待态优先于普通运行指示。
  String? get threadStatusCapsuleLabel {
    if (_threadWaitingOnApproval) {
      return '等待审批';
    }
    if (_threadWaitingOnUserInput) {
      return '等待输入';
    }
    if (_threadRuntimeStatus == AgentThreadRuntimeStatus.systemError) {
      return '系统错误';
    }
    return null;
  }

  /// 头栏次要提示：模型改道等非阻塞系统通知。
  String? get systemNoticeLabel => _modelRerouteNotice;

  /// 当前事件缓冲诊断；仅包含计数和 pending key 深度。
  @visibleForTesting
  CoalescingEventBufferDiagnostics? get eventCoalescingBufferDiagnostics =>
      _eventPipeline?.diagnostics.buffer;

  /// 当前有界事件调度诊断；仅包含吞吐、批次和队列深度。
  @visibleForTesting
  BoundedEventDispatcherDiagnostics? get eventDispatcherDiagnostics =>
      _eventPipeline?.diagnostics.dispatcher;

  /// 当前 Pipeline 的完整脱敏诊断。
  @visibleForTesting
  AgentEventPipelineDiagnostics? get eventPipelineDiagnostics =>
      _eventPipeline?.diagnostics;

  /// 当前 typed UI state 发布诊断；不包含消息正文或 Provider payload。
  @visibleForTesting
  AgentConversationUiStateDiagnostics get uiStateDiagnostics =>
      _uiStateStore.diagnostics;

  /// 当前统一 UI frame 调度诊断；不包含任何事件内容。
  @visibleForTesting
  AgentUiUpdateSchedulerDiagnostics get uiUpdateSchedulerDiagnostics =>
      _uiUpdateScheduler.diagnostics;

  /// 最近一次由 ViewModel 生成的无 payload UI 更新请求，仅供事件映射测试。
  @visibleForTesting
  AgentUiUpdateRequest? get debugLastUiUpdateRequest =>
      _debugLastUiUpdateRequest;

  AgentConversationHistoryState get historyState => _uiStateStore.history.value;

  ValueListenable<AgentConversationHistoryState> get historyStateListenable =>
      _uiStateStore.history;

  AgentHeaderState get headerState => _uiStateStore.header.value;

  ValueListenable<AgentHeaderState> get headerStateListenable =>
      _uiStateStore.header;

  AgentComposerState get composerState => _uiStateStore.composer.value;

  ValueListenable<AgentComposerState> get composerStateListenable =>
      _uiStateStore.composer;

  AgentPendingInteractionState get pendingInteractionState =>
      _uiStateStore.pendingInteractions.value;

  ValueListenable<AgentPendingInteractionState>
  get pendingInteractionStateListenable => _uiStateStore.pendingInteractions;

  AgentExpansionState get expansionState => _uiStateStore.expansion.value;

  ValueListenable<AgentExpansionState> get expansionStateListenable =>
      _uiStateStore.expansion;

  /// 当前挂载 AgentPane 消费的一次性 UI effect；不保存或 replay。
  Stream<AgentUiEffect> get uiEffects => _uiStateStore.effects;

  ValueListenable<AgentConversationTurnState?> get liveTurnListenable =>
      _timeline.liveTurnListenable;

  String? get projectPath => _projectPath;

  String? get contextFilePath => _contextFilePath;

  String get activeProviderId => conversationBinding.providerId;

  String get activeProviderName =>
      providerController.providerConfigById(activeProviderId)?.displayName ??
      providerController.activeProviderName;

  AgentProviderConfig get _boundProviderConfig =>
      providerController.providerConfigById(activeProviderId) ??
      providerController.activeProviderConfig;

  AgentProviderKind get activeProviderKind => _boundProviderConfig.kind;

  /// 当前 thread 所属 provider 的能力；未绑定实例时回退到 kind 的保守静态能力。
  AgentProviderCapabilities get activeCapabilities {
    final providerId =
        _session?.providerId ?? _selectedProviderId ?? activeProviderId;
    final runtime = _currentRuntime;
    if (runtime != null && runtime.config.id == providerId) {
      return runtime.capabilities;
    }
    final globalCapabilities = _globalCapabilitiesByProviderId[providerId];
    if (globalCapabilities != null) {
      return globalCapabilities;
    }
    return providerController.capabilitiesForProviderId(providerId);
  }

  /// 当前 Provider 是否提供可选择的完整对话模式目录。
  bool get canSelectConversationMode =>
      _conversationModeController.state.status ==
      AgentConversationModeLoadStatus.ready;

  /// 当前 thread 是否处于只读 Plan 会话模式。
  ///
  /// 以服务端 `current_mode_update`（Grok）为准：进入/退出 plan 模式时由
  /// provider 广播，本地不按工具调用标题推断。
  bool get isPlanMode =>
      _conversationModeController.state.confirmedMode?.kind ==
      AgentConversationModeKind.plan;

  /// 当前 Provider 的对话模式目录加载状态。
  AgentConversationModeLoadStatus get conversationModeLoadStatus =>
      _conversationModeController.state.status;

  /// 用于隔离模式选择浮层的 Provider 与 thread 上下文。
  ///
  /// presentation 只把该值作为相等性标识，不依赖内部字段；上下文切换时 Selector
  /// 可据此关闭旧浮层，避免把旧 thread 的选择写入新会话。
  Object get conversationModeContextId => (
    providerId: _session?.providerId ?? _selectedProviderId ?? activeProviderId,
    threadId: _selectedThreadId,
  );

  /// Provider 中立的对话模式选项。
  List<AgentConversationModePreset> get conversationModeOptions =>
      _conversationModeController.state.presets;

  /// 用户为下一新 turn 选择的模式。
  AgentConversationModeId? get selectedConversationMode =>
      _conversationModeController.state.draftMode;

  /// 模式目录加载或降级状态的简短提示。
  String? get conversationModeStatusMessage {
    final state = _conversationModeController.state;
    return switch (state.status) {
      AgentConversationModeLoadStatus.unavailable => null,
      AgentConversationModeLoadStatus.loading => '正在加载对话模式…',
      AgentConversationModeLoadStatus.error => state.errorMessage,
      AgentConversationModeLoadStatus.ready
          when state.draftMode?.kind == AgentConversationModeKind.unknown =>
        '当前模式暂不支持主动选择',
      AgentConversationModeLoadStatus.ready => null,
    };
  }

  /// 当前选择是否只应用于下一新 turn。
  bool get conversationModeAppliesToNextTurn =>
      _conversationModeController.state.appliesToNextTurn;

  /// 更新下一新 turn 的对话模式。
  void selectConversationMode(AgentConversationModeId modeId) {
    _conversationModeController.selectMode(modeId);
  }

  /// 确认上一 Plan 回合，并用 Default 模式启动新的执行回合。
  Future<void> startPlanExecution(AgentPlanExecutionRequest request) async {
    if (!_canResolvePlanExecution(request) ||
        isTurnRunning ||
        !canSubmitMessage) {
      return;
    }
    if (!_planExecutionHandoffController.resolve(request)) {
      return;
    }
    _resolvePlanExecutionAttention(request);
    _conversationModeController.selectMode(AgentConversationModeId.defaultMode);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.pendingInteraction,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    await sendMessage(planExecutionPrompt);
  }

  /// 继续修改计划，并确保下一回合仍使用 Plan 模式。
  ///
  /// [revisionMessage] 非空时在关闭交接后立即以 Plan 模式发送；
  /// 为空时仅关闭交接卡，恢复主 Composer 供用户继续输入。
  Future<void> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  }) async {
    if (!_canResolvePlanExecution(request) ||
        !_planExecutionHandoffController.resolve(request)) {
      return;
    }
    _resolvePlanExecutionAttention(request);
    _conversationModeController.selectMode(AgentConversationModeId.plan);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.pendingInteraction,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    final text = revisionMessage?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    if (isTurnRunning || !canSubmitMessage) {
      return;
    }
    await sendMessage(text);
  }

  /// 关闭本地执行提示，不向 Provider 回写任何审批结果。
  void dismissPlanExecution(AgentPlanExecutionRequest request) {
    if (!_canResolvePlanExecution(request) ||
        !_planExecutionHandoffController.resolve(request)) {
      return;
    }
    _resolvePlanExecutionAttention(request);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.pendingInteraction,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  /// 重试当前 Provider 的模式目录探测。
  Future<void> retryConversationModes() {
    return _conversationModeController.retryCatalog();
  }

  List<AgentModelInfo> get models => _modelSelectionController.models;

  /// 当前 session 可直接渲染的动态配置；未知类型按 ACP 约定忽略。
  List<AgentSessionConfigOption> get sessionConfigOptions =>
      List<AgentSessionConfigOption>.unmodifiable(
        _sessionConfigOptions.where(
          (option) =>
              (option.kind == AgentSessionConfigOptionKind.select &&
                  option.values.isNotEmpty) ||
              option.kind == AgentSessionConfigOptionKind.boolean,
        ),
      );

  AgentModelInfo? get selectedModel => _modelSelectionController.selectedModel;

  String? get selectedModelId => _modelSelectionController.selectedModelId;

  String? get selectedReasoningEffort =>
      _modelSelectionController.selectedReasoningEffort;

  String? get selectedServiceTierId =>
      _modelSelectionController.selectedServiceTierId;

  /// 输入框模型入口与 Popover 共用的不可变快照。
  AgentModelConfigUiState get modelConfigUiState => AgentModelConfigUiState(
    models: models,
    selectedModelId: selectedModelId,
    expandedModelId: null,
    selectedReasoningEffort: selectedReasoningEffort,
    selectedServiceTierId: selectedServiceTierId,
    preferences: _modelSelectionController.preferences,
    savingModelIds: _modelSelectionController.savingModelIds,
    isRefreshing: _modelsRefreshing,
    appliesNextTurn: isTurnRunning,
    supportsReasoningOptions: activeCapabilities.supportsReasoningOptions,
    supportsServiceTierSelection:
        activeCapabilities.supportsServiceTierSelection,
    compatibilityConflict: _modelSelectionController.compatibilityConflict,
    saveError: _modelSelectionController.saveError,
    selectionNotice: _modelSelectionController.selectionNotice,
    refreshError: _modelRefreshError,
  );

  bool get showReasoningEffort {
    if (!activeCapabilities.supportsReasoningOptions) {
      return false;
    }
    return selectedModel?.supportedReasoningEfforts.isNotEmpty ?? false;
  }

  bool get showServiceTier {
    if (!activeCapabilities.supportsServiceTierSelection) {
      return false;
    }
    return selectedModel?.serviceTiers.isNotEmpty ?? false;
  }

  /// 当前 composer 选择对应的本回合模型配置快照（用于 live turn footer）。
  AgentTurnModelConfig? _currentTurnModelConfig() {
    final model = selectedModel?.displayName.trim().isNotEmpty == true
        ? selectedModel!.displayName.trim()
        : (selectedModelId?.trim().isNotEmpty == true
              ? selectedModelId!.trim()
              : selectedModel?.model.trim());
    final effort = selectedReasoningEffort?.trim();
    final fastEnabled = _modelSelectionController.selectedFastEnabled
        ? true
        : null;
    final config = AgentTurnModelConfig(
      modelId: model == null || model.isEmpty ? null : model,
      reasoningEffort: effort == null || effort.isEmpty ? null : effort,
      // 仅在开启时记录，footer 按「有且开启」展示 Fast。
      fastEnabled: fastEnabled,
    );
    return config.hasDisplayable ? config : null;
  }

  String _effectiveConversationModeModelId() {
    final protocolModel = selectedModel?.model.trim();
    if (protocolModel != null && protocolModel.isNotEmpty) {
      return protocolModel;
    }
    return selectedModelId?.trim() ?? '';
  }

  /// Provider 暴露 [AgentPermissionPolicyPort] 时显示权限选项选择器。
  bool get showPermissionPolicy =>
      _permissionSelectionController.hasPort ||
      conversationBinding.currentRuntime?.bundle.permissionPolicy != null;

  /// Provider 支持模型切换时显示模型选择器。
  bool get showModelSelection => activeCapabilities.supportsModelSelection;

  bool get canAttachImages => activeCapabilities.supportsLocalImageInput;

  bool get canMentionResources => activeCapabilities.supportsResourceInput;

  /// Provider 声明支持结构化 skill 时开放入口；目录未就绪时 picker 可为空。
  bool get canUseSkills => activeCapabilities.supportsSkillInput;

  /// Skill picker 候选；按 name/description 过滤。
  List<AgentSkillMetadata> skillCandidates({String query = ''}) {
    if (!canUseSkills) {
      return const <AgentSkillMetadata>[];
    }
    return _skillsCatalogController.query(query);
  }

  /// 预热 skill 目录（打开 picker 前调用）。
  Future<void> ensureSkillsCatalog() async {
    if (!canUseSkills) {
      return;
    }
    // catalog：skill 目录属于「会话之前的信息」（04 §0.4），不建立订阅。
    await _runGlobalBundle(
      _ensureSkillsCatalog,
      preferredProviderId: _selectedProviderId,
    );
  }

  bool get canRenameCurrentThread =>
      sessionId != null && !isReadOnly && activeCapabilities.canRenameThread;

  bool get canArchiveCurrentThread =>
      sessionId != null && !isReadOnly && activeCapabilities.canArchiveThread;

  bool get canForkCurrentThread =>
      sessionId != null &&
      onCreatedThread != null &&
      canSubmitMessage &&
      !isTurnRunning &&
      activeCapabilities.canForkThread;

  /// 可切换的全局 provider 列表（已启用）。
  List<AgentProviderConfig> get availableProviders =>
      providerController.enabledProviders;

  /// 切换 active provider（双后端共存）。
  Future<void> switchActiveProvider(String providerId) async {
    if (providerId == activeProviderId) {
      return;
    }
    final unavailable = providerController.unavailableReasonForProviderId(
      providerId,
    );
    if (unavailable != null) {
      throw UnsupportedError(unavailable);
    }
    if (!providerController.isProviderEnabled(providerId)) {
      throw StateError('Provider $providerId is not enabled');
    }
    final switchRequest = onProviderSwitchRequested;
    if (switchRequest == null) {
      throw StateError(
        'Conversation ${conversationBinding.key} is bound to '
        '${conversationBinding.providerId}',
      );
    }
    await switchRequest(providerId);
  }

  AgentPermissionSelection? get permissionSelection =>
      _permissionSelectionController.effectiveSelection;

  /// 为外层 application 工作流冻结指定 thread 的请求权限来源。
  AgentPermissionRequestSnapshot permissionSnapshotForThread(
    String? threadId,
  ) => _permissionSelectionController.snapshotForRequest(threadId: threadId);

  String get permissionPolicyLabel =>
      _permissionSelectionController.displayLabel;

  String? get permissionApplyScopeHint =>
      _permissionSelectionController.applyScopeHint;

  /// Provider apply 已成功但默认偏好保存失败时，允许 UI 显示重试入口。
  bool get canRetryPermissionPreferencePersistence =>
      _permissionSelectionController.canRetryPersistence;

  AgentAutoApprovalReviewEvent? get latestDeniedAutoReview =>
      _latestDeniedAutoReview;

  /// 当前回合的自动评审状态（若有）。
  AgentAutoApprovalReviewEvent? autoReviewForTurn(String? turnId) {
    if (turnId == null) {
      return null;
    }
    return _autoReviewsByTurnId[turnId];
  }

  /// 供 @mention 选择器使用的工作区文件（已扁平化 + 模糊子序列排序）。
  List<WorkspaceNode> mentionCandidateFiles({String query = ''}) {
    final source = workspaceFilesProvider?.call() ?? const <WorkspaceNode>[];
    return fuzzyRankWorkspaceFiles(
      _flattenFileNodes(source),
      query: query,
      limit: 40,
    );
  }

  /// 递归收集 file 节点；provider 返回扁平语料时等价于一次廉价复制。
  List<WorkspaceNode> _flattenFileNodes(List<WorkspaceNode> nodes) {
    final files = <WorkspaceNode>[];
    void walk(WorkspaceNode node) {
      if (node.isDirectory) {
        for (final child in node.children) {
          walk(child);
        }
        return;
      }
      files.add(node);
    }

    for (final node in nodes) {
      walk(node);
    }
    return files;
  }

  String? get sessionId => _session?.id ?? _restoredSessionId;

  /// 当前 thread/draft 的轻量运行时快照。
  AgentConversationThreadSnapshot get threadSnapshot =>
      _threadSnapshotListenable.value;

  ValueListenable<AgentConversationThreadSnapshot>
  get threadSnapshotListenable => _threadSnapshotListenable;

  /// 已由 provider 创建或恢复成功的当前会话；草稿和待恢复状态返回 null。
  AgentSession? get currentSession => _session;

  /// 当前会话所属 provider 被禁用后，历史仍可读但禁止任何写操作。
  bool get isReadOnly {
    final providerId =
        _session?.providerId ?? _selectedProviderId ?? activeProviderId;
    return !providerController.isProviderEnabled(providerId);
  }

  String get currentThreadTitle => _currentThreadTitle;

  /// 当前 thread 逻辑归属的 provider id。
  String get threadProviderId =>
      _session?.providerId ?? _selectedProviderId ?? activeProviderId;

  bool get showRunningIndicator =>
      isTurnRunning && threadStatusCapsuleLabel == null;

  /// 当前项目名称；标题栏仅显示路径的最后一级目录。
  String? get projectName {
    final path = _projectPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    final name = fileName(path).trim();
    return name.isEmpty ? null : name;
  }

  /// 共享 1 秒时钟；对话流和工具卡用其计算 live elapsed。
  Listenable get elapsedClockListenable => _elapsedTicker;

  /// 最近一次 tick 的本地时间。
  DateTime get elapsedNow => _elapsedTicker.now;

  /// 当前主活动段（思考/执行/回复等）。
  AgentTurnActivitySnapshot get currentActivity => _timeline.currentActivity;

  /// 当前 running turn 本地开始时间。
  DateTime? get currentTurnStartedAt => _timeline.currentTurnStartedAt;

  /// 标题栏主 segment 文案（不含时长）。
  String? get runningActivityLabel =>
      agentActivitySegmentLabel(currentActivity);

  /// 当前 turn 总耗时（running 现算，结束后读 turn.duration）。
  Duration? turnElapsedAt(DateTime now) {
    final runningId = _timeline.selectedRunningTurnId;
    if (runningId != null) {
      return resolveAgentElapsed(
        now: now,
        startedAt: _timeline.currentTurnStartedAt,
      );
    }
    final live = _timeline.liveTurnState;
    if (live != null) {
      return resolveAgentElapsed(
        now: now,
        startedAt: live.startedAt,
        completedAt: live.completedAt,
        frozenDuration: live.duration,
      );
    }
    return null;
  }

  /// 当前主活动段耗时。
  Duration? segmentElapsedAt(DateTime now) {
    final activity = currentActivity;
    if (!activity.isActive) {
      return null;
    }
    return resolveAgentElapsed(now: now, startedAt: activity.segmentStartedAt);
  }

  /// 工具/思考卡耗时。
  Duration? toolElapsedAt(AgentToolCall toolCall, DateTime now) {
    return resolveAgentElapsed(
      now: now,
      startedAt: toolCall.startedAt,
      completedAt: toolCall.completedAt,
      frozenDuration: toolCall.duration,
    );
  }

  AgentThreadOpenPhase get threadOpenPhase => _threadOpenPhase;

  bool get requiresResumedSelectedThread => _requiresResumedSelectedThread;

  AgentTokenUsage? get currentThreadTokenUsage =>
      _timeline.currentThreadTokenUsage;

  /// 当前 thread 最近一次请求的 token 用量。
  AgentTokenUsage? get currentThreadLastTokenUsage {
    final usage = _timeline.currentThreadLastTokenUsage;
    if (usage == null) {
      return null;
    }
    final modelContextWindow =
        usage.modelContextWindow ?? selectedModel?.contextWindowTokens;
    if (modelContextWindow == usage.modelContextWindow) {
      return usage;
    }
    return AgentTokenUsage(
      inputTokens: usage.inputTokens,
      cachedInputTokens: usage.cachedInputTokens,
      outputTokens: usage.outputTokens,
      reasoningOutputTokens: usage.reasoningOutputTokens,
      totalTokens: usage.totalTokens,
      lastInputTokens: usage.lastInputTokens,
      lastCachedInputTokens: usage.lastCachedInputTokens,
      lastOutputTokens: usage.lastOutputTokens,
      lastReasoningOutputTokens: usage.lastReasoningOutputTokens,
      lastTotalTokens: usage.lastTotalTokens,
      modelContextWindow: modelContextWindow,
    );
  }

  /// 当前线程的创建时间；新会话无摘要时为空。
  DateTime? get threadCreatedAt => _threadCreatedAt;

  /// 当前线程的最后活跃时间；新会话无摘要时为空。
  DateTime? get threadLastActiveAt => _threadLastActiveAt;

  /// 切换上下文详情面板的展开状态。
  void toggleContextPanel() {
    contextPanelVisible.value = !contextPanelVisible.value;
  }

  /// 关闭上下文详情面板。
  void hideContextPanel() {
    contextPanelVisible.value = false;
  }

  /// 空闲、版本支持指定 turn 分支，且存在稳定前置边界时可创建分支重试。
  bool get canEditLastUserMessage {
    if (onCreatedThread == null ||
        !activeCapabilities.canForkThreadAtTurn ||
        !canSubmitMessage ||
        isTurnRunning) {
      return false;
    }
    final message = _lastEditableUserMessage();
    return message != null &&
        _timeline.forkBoundaryBeforeMessage(message.id) != null;
  }

  /// 最近一条可编辑的用户消息文本；无可编辑消息时为空。
  String? get lastEditableUserMessageText => _lastEditableUserMessage()?.text;

  /// 最近一条可编辑用户消息的 id。
  String? get lastEditableUserMessageId => _lastEditableUserMessage()?.id;

  bool get isTurnRunning => _timeline.isTurnRunning;

  bool get isRunning => isTurnRunning;

  bool get canSubmitMessage =>
      _threadOpenPhase == AgentThreadOpenPhase.idle &&
      !isReadOnly &&
      activeCapabilities.canPrompt &&
      (!isTurnRunning || activeCapabilities.canSteerTurn);

  bool isToolCallExpanded(String toolCallId) {
    return _timeline.isToolCallExpanded(toolCallId);
  }

  bool isPlanMessageExpanded(String messageId) {
    return _timeline.isPlanMessageExpanded(messageId);
  }

  bool isActivePlanExpanded(String turnId) {
    return _timeline.isActivePlanExpanded(turnId);
  }

  bool isCommandGroupExpanded(String commandGroupId) {
    return _timeline.isCommandGroupExpanded(commandGroupId);
  }

  bool isFileEditItemExpanded(String fileEditItemId) {
    return _timeline.isFileEditItemExpanded(fileEditItemId);
  }

  void toggleToolCall(String toolCallId) {
    _timeline.toggleToolCall(toolCallId);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.expansion},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void togglePlanMessage(String messageId) {
    _timeline.togglePlanMessage(messageId);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.expansion},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void toggleActivePlan(String turnId) {
    _timeline.toggleActivePlan(turnId);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.expansion},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void toggleCommandGroup(String commandGroupId) {
    _timeline.toggleCommandGroup(commandGroupId);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.expansion},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void toggleFileEditItem(String fileEditItemId) {
    _timeline.toggleFileEditItem(fileEditItemId);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.expansion},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  /// 加载全局 provider 设置。
  ///
  /// 这个方法允许重复调用，但实际只加载一次；加载失败会转成 UI 状态，不向外抛。
  Future<void> loadSettings() {
    final existing = _settingsLoadFuture;
    if (existing != null) {
      return existing;
    }

    final future = _loadSettings();
    _settingsLoadFuture = future;
    return future;
  }

  Future<void> _loadSettings() async {
    try {
      await providerController.loadSettings();
      final unavailableReason = providerController.unavailableSelectionReason;
      if (unavailableReason != null) {
        _markUnavailable(
          'Cursor Agent unavailable',
          details: unavailableReason,
        );
      } else {
        _status = AgentProviderStatus(
          state: AgentProviderConnectionState.idle,
          message: '$activeProviderName ready',
        );
      }
      _log.t('Loaded Agent provider settings: $activeProviderId');
    } catch (error) {
      _log.w('Could not load Agent provider settings (${error.runtimeType})');
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.error,
        message: 'Could not load Agent providers',
        details: error.toString(),
      );
    }
    _publishUiChanges(
      AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate),
    );
  }

  /// 预加载模型列表。
  ///
  /// 在 IDE 启动时调用，触发 provider initialize 握手并拉取 `model/list`，
  /// 使输入框下方的模型/思考/速率控件在用户发送消息前就可用。
  Future<void> loadModels({bool forceRefresh = false}) async {
    await loadSettings();
    if (!providerController.hasRuntimeProvider) {
      _modelsRefreshing = false;
      _modelRefreshError = null;
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.composer},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
      return;
    }
    final config = _boundProviderConfig;
    _modelSelectionController.seedFromConfig(config);
    _permissionSelectionController.seedFromConfig(
      config.resolvedPermissionOptionId,
    );
    final capabilities = providerController.capabilitiesForProviderId(
      config.id,
    );
    final bootstrapPolicy = capabilities.bootstrapPolicy;
    if (!bootstrapPolicy.allowsEagerModelPreload) {
      _log.t('Deferring ${config.displayName} preload until session bootstrap');
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.composer},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
      return;
    }
    final hasWorkspace = _projectPath?.trim().isNotEmpty ?? false;
    if (bootstrapPolicy.requiresWorkspace && !hasWorkspace) {
      _log.t(
        'Deferring ${config.displayName} preload until a workspace is ready',
      );
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.composer},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
      return;
    }
    _modelsRefreshing = true;
    _modelRefreshError = null;
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    try {
      final result = await providerController.modelCatalogRepository.load(
        config: config,
        source: _modelCatalogSource(config),
        forceRefresh: forceRefresh,
        onCacheHit: (snapshot) => _handleModelList(snapshot.models),
        // catalog：模型列表是「会话之前的信息」（04 §0.4：listModels → 全局实例）。
        refreshLoader: () => _runGlobalBundle((bundle) {
          final modelCatalog = bundle.modelCatalog;
          if (modelCatalog == null) {
            return Future<AgentModelList>.value(
              const AgentModelList(models: <AgentModelInfo>[]),
            );
          }
          return fetchAgentProviderModels(modelCatalog, forceRefresh: true);
        }),
      );
      _handleModelList(result.models);
      if (result.refreshError != null) {
        _modelRefreshError = '模型目录刷新失败，正在使用本地缓存。';
      }
      await _runGlobalBundle((_) async {}, hydrateCatalogs: true);
      await _permissionSelectionController.refreshOptions();
    } catch (error) {
      _log.w('Could not preload Agent models (${error.runtimeType})');
      _modelRefreshError = '模型列表刷新失败，已保留现有配置。';
    } finally {
      _modelsRefreshing = false;
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.composer},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
    }
  }

  Future<bool> selectModel(String modelId) =>
      _modelSelectionController.selectModel(modelId);

  Future<bool> selectReasoningEffort(String? effort) =>
      _modelSelectionController.selectReasoningEffort(effort);

  /// 用户选择权限选项；返回错误文案（供 UI toast），成功时返回 null。
  Future<String?> selectPermissionOption(AgentPermissionOption option) async {
    await _permissionSelectionController.selectOption(option);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    return _permissionSelectionController.takeLastError();
  }

  /// 最近一次权限 apply 的紧凑提示（下次会话生效等）。
  String? takePermissionApplyHint() =>
      _permissionSelectionController.takeApplyHint();

  /// 只重试默认偏好持久化，不重复调用 Provider apply。
  Future<bool> retryPermissionPreferencePersistence() async {
    final succeeded = await _permissionSelectionController
        .retryPersistOptionId();
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    return succeeded;
  }

  /// Guardian 拒绝后的人工放行。
  Future<void> approveGuardianDeniedAction() async {
    final review = _latestDeniedAutoReview;
    final threadId = review?.threadId ?? sessionId;
    if (review == null || threadId == null) {
      return;
    }
    try {
      await _runCurrentBundle<void>((bundle) async {
        final interactions = bundle.interactions;
        if (interactions == null) {
          return;
        }
        await interactions.approveGuardianDeniedAction(
          threadId: threadId,
          event: review.raw,
        );
      });
      _latestDeniedAutoReview = null;
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.liveTurn,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
    } catch (error) {
      _log.w('Could not approve guardian-denied action (${error.runtimeType})');
    }
  }

  Future<bool> selectServiceTier(String? tierId) =>
      _modelSelectionController.selectServiceTier(tierId);

  Future<bool> selectFastEnabled(bool enabled) =>
      _modelSelectionController.selectFastEnabled(enabled);

  Future<bool> resolveModelCompatibilityConflict() =>
      _modelSelectionController.resolveCompatibilityConflict();

  Future<bool> retryModelConfigurationSave() =>
      _modelSelectionController.retryFailedSelection();

  void clearModelConfigurationTransientState() =>
      _modelSelectionController.clearTransientState();

  Future<void> selectSessionConfigOption(String configId, Object value) async {
    final sessionId = _selectedThreadId;
    if (sessionId == null) {
      return;
    }
    try {
      await _runCurrentBundle<void>((bundle) async {
        final sessionConfiguration = bundle.sessionConfiguration;
        if (sessionConfiguration == null) {
          return;
        }
        await sessionConfiguration.setSessionConfigOption(
          sessionId: sessionId,
          configId: configId,
          value: value,
        );
      });
    } catch (error) {
      _log.w(
        'Could not update Agent session config $configId '
        '(${error.runtimeType})',
      );
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.error,
        message: 'Could not update session option',
        details: error.toString(),
      );
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
    }
  }

  void _handleModelList(AgentModelList modelList) {
    _applyModelList(modelList);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void _applyModelList(AgentModelList modelList) {
    _modelRefreshError = null;
    _modelSelectionController.handleModelList(modelList);
  }

  void _applyThreadSelectionFromHistory(AgentThreadHistorySnapshot history) {
    final fallback = _latestHistorySelectionPatch(history.turns);
    final current = _selectionPatchFromHistoryTurn(history.currentTurn);
    _applyThreadSelectionPatch(_mergeThreadSelectionPatches(fallback, current));
  }

  void _applyThreadSelectionFromThreadSettings({String? modelId}) {
    final cleanedModelId = _nonEmptyValue(modelId);
    if (cleanedModelId == null) {
      return;
    }
    _applyThreadSelectionPatch(
      _ThreadModelSelectionPatch(modelId: cleanedModelId),
    );
  }

  void _applyThreadSelectionFromSessionConfigOptions(
    List<AgentSessionConfigOption> options,
  ) {
    String? modelId;
    Object? reasoningEffort = _threadModelSelectionUnset;
    Object? serviceTierId = _threadModelSelectionUnset;
    Object? fastEnabled = _threadModelSelectionUnset;
    for (final option in options) {
      if (option.category == 'model') {
        final value = _stringValue(option.currentValue);
        if (value != null) {
          modelId = value;
        }
        continue;
      }
      if (option.category == 'thought_level') {
        if (option.currentValue == null) {
          reasoningEffort = null;
        } else {
          final value = _stringValue(option.currentValue);
          if (value != null) {
            reasoningEffort = value;
          }
        }
        continue;
      }
      if (option.category == 'model_config') {
        if (option.kind == AgentSessionConfigOptionKind.boolean) {
          final value = _boolValue(option.currentValue);
          if (value != null) {
            fastEnabled = value;
          }
          continue;
        }
        if (option.currentValue == null) {
          serviceTierId = null;
          continue;
        }
        final value = _stringValue(option.currentValue);
        if (value != null) {
          serviceTierId = value;
        }
      }
    }
    final patch = _ThreadModelSelectionPatch(
      modelId: modelId,
      reasoningEffort: reasoningEffort,
      serviceTierId: serviceTierId,
      fastEnabled: fastEnabled,
    );
    if (!patch.hasAny) {
      return;
    }
    _applyThreadSelectionPatch(patch);
  }

  void _applyThreadSelectionPatch(_ThreadModelSelectionPatch? patch) {
    if (patch == null || !patch.hasAny) {
      return;
    }
    final currentSelection = _modelSelectionController.selection;
    final requestedModelId = _nonEmptyValue(patch.modelId);
    final resolvedModel = _resolveModelInfo(
      requestedModelId ?? currentSelection.modelId,
    );
    final targetModelId =
        resolvedModel?.id ?? requestedModelId ?? currentSelection.modelId;
    if (targetModelId == null || targetModelId.isEmpty) {
      return;
    }

    String? reasoningEffort;
    String? serviceTierId;
    if (resolvedModel != null) {
      final basePreference = currentSelection.modelId == resolvedModel.id
          ? AgentModelPreference(
              modelId: resolvedModel.id,
              reasoningEffort: currentSelection.reasoningEffort,
              fastEnabled:
                  agentFastServiceTier(resolvedModel)?.id ==
                  currentSelection.serviceTierId,
              serviceTierId: currentSelection.serviceTierId,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            )
          : modelConfigUiState.effectivePreference(resolvedModel);
      reasoningEffort =
          identical(patch.reasoningEffort, _threadModelSelectionUnset)
          ? basePreference.reasoningEffort
          : patch.reasoningEffort as String?;
      if (!identical(patch.fastEnabled, _threadModelSelectionUnset)) {
        final fastTier = agentFastServiceTier(resolvedModel);
        serviceTierId = (patch.fastEnabled as bool?) == true
            ? fastTier?.id
            : null;
      } else if (!identical(patch.serviceTierId, _threadModelSelectionUnset)) {
        serviceTierId = _normalizeThreadServiceTierId(
          resolvedModel,
          patch.serviceTierId as String?,
        );
      } else {
        serviceTierId = basePreference.serviceTierId;
      }
    } else {
      final modelChanged =
          requestedModelId != null &&
          requestedModelId != currentSelection.modelId;
      reasoningEffort =
          identical(patch.reasoningEffort, _threadModelSelectionUnset)
          ? (modelChanged ? null : currentSelection.reasoningEffort)
          : patch.reasoningEffort as String?;
      if (!identical(patch.fastEnabled, _threadModelSelectionUnset)) {
        serviceTierId = (patch.fastEnabled as bool?) == true && !modelChanged
            ? currentSelection.serviceTierId
            : null;
      } else if (!identical(patch.serviceTierId, _threadModelSelectionUnset)) {
        serviceTierId = patch.serviceTierId as String?;
      } else {
        serviceTierId = modelChanged ? null : currentSelection.serviceTierId;
      }
    }

    _modelSelectionController.applyRuntimeSelection(
      AgentModelSelection(
        modelId: targetModelId,
        reasoningEffort: reasoningEffort,
        serviceTierId: serviceTierId,
      ),
    );
  }

  _ThreadModelSelectionPatch? _latestHistorySelectionPatch(
    List<AgentHistoryTurn> turns,
  ) {
    for (var index = turns.length - 1; index >= 0; index -= 1) {
      final patch = _selectionPatchFromHistoryTurn(turns[index]);
      if (patch != null && _nonEmptyValue(patch.modelId) != null) {
        return patch;
      }
    }
    for (var index = turns.length - 1; index >= 0; index -= 1) {
      final patch = _selectionPatchFromHistoryTurn(turns[index]);
      if (patch != null && patch.hasAny) {
        return patch;
      }
    }
    return null;
  }

  _ThreadModelSelectionPatch? _selectionPatchFromHistoryTurn(
    AgentHistoryTurn? turn,
  ) {
    if (turn == null) {
      return null;
    }
    final turnContext = _objectMap(turn.raw['turnContext']);
    final source = turnContext.isEmpty ? turn.raw : turnContext;

    Object? reasoningEffort = _threadModelSelectionUnset;
    if (source.containsKey('effort')) {
      reasoningEffort = _stringValue(source['effort']);
    } else if (source.containsKey('reasoningEffort')) {
      reasoningEffort = _stringValue(source['reasoningEffort']);
    }

    Object? serviceTierId = _threadModelSelectionUnset;
    if (source.containsKey('serviceTier')) {
      serviceTierId = _stringValue(source['serviceTier']);
    } else if (source.containsKey('service_tier')) {
      serviceTierId = _stringValue(source['service_tier']);
    } else if (source.containsKey('serviceTierId')) {
      serviceTierId = _stringValue(source['serviceTierId']);
    } else if (source.containsKey('service_tier_id')) {
      serviceTierId = _stringValue(source['service_tier_id']);
    }

    Object? fastEnabled = _threadModelSelectionUnset;
    if (source.containsKey('fast')) {
      fastEnabled = _boolValue(source['fast']);
    } else if (source.containsKey('fastMode')) {
      fastEnabled = _boolValue(source['fastMode']);
    } else if (source.containsKey('isFast')) {
      fastEnabled = _boolValue(source['isFast']);
    } else if (source.containsKey('fast_enabled')) {
      fastEnabled = _boolValue(source['fast_enabled']);
    }

    final patch = _ThreadModelSelectionPatch(
      modelId: _nonEmptyValue(turn.model) ?? _stringValue(source['model']),
      reasoningEffort: reasoningEffort,
      serviceTierId: serviceTierId,
      fastEnabled: fastEnabled,
    );
    return patch.hasAny ? patch : null;
  }

  _ThreadModelSelectionPatch? _mergeThreadSelectionPatches(
    _ThreadModelSelectionPatch? base,
    _ThreadModelSelectionPatch? overlay,
  ) {
    if (base == null) {
      return overlay;
    }
    if (overlay == null) {
      return base;
    }
    final merged = _ThreadModelSelectionPatch(
      modelId: _nonEmptyValue(overlay.modelId) ?? base.modelId,
      reasoningEffort:
          identical(overlay.reasoningEffort, _threadModelSelectionUnset)
          ? base.reasoningEffort
          : overlay.reasoningEffort,
      serviceTierId:
          identical(overlay.serviceTierId, _threadModelSelectionUnset)
          ? base.serviceTierId
          : overlay.serviceTierId,
      fastEnabled: identical(overlay.fastEnabled, _threadModelSelectionUnset)
          ? base.fastEnabled
          : overlay.fastEnabled,
    );
    return merged.hasAny ? merged : null;
  }

  AgentModelInfo? _resolveModelInfo(String? modelId) {
    final candidate = _nonEmptyValue(modelId);
    if (candidate == null) {
      return null;
    }
    for (final model in models) {
      if (model.id == candidate || model.model == candidate) {
        return model;
      }
    }
    return null;
  }

  String? _normalizeThreadServiceTierId(
    AgentModelInfo model,
    String? serviceTierId,
  ) {
    final candidate = _nonEmptyValue(serviceTierId);
    if (candidate == null) {
      return null;
    }
    for (final tier in model.serviceTiers) {
      if (tier.id == candidate) {
        return tier.id;
      }
    }
    final lowerCandidate = candidate.toLowerCase();
    final fastTier = agentFastServiceTier(model);
    if (fastTier != null) {
      final fastTierId = fastTier.id.trim().toLowerCase();
      final fastTierName = fastTier.name.trim().toLowerCase();
      if (lowerCandidate == fastTierId ||
          lowerCandidate == fastTierName ||
          lowerCandidate == 'fast' ||
          lowerCandidate == 'priority') {
        return fastTier.id;
      }
    }
    return candidate;
  }

  Map<String, Object?> _objectMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  String? _stringValue(Object? value) {
    if (value == null) {
      return null;
    }
    return _nonEmptyValue(value.toString());
  }

  bool? _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    return null;
  }

  String? _nonEmptyValue(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 更新当前 Entry 的项目/文件上下文，不改变其 draft/thread 身份或时间线。
  void updateContext({
    required String? projectPath,
    required String? contextFilePath,
  }) {
    final projectChanged = projectPath != _projectPath;
    _projectPath = projectPath;
    _contextFilePath = contextFilePath;
    if (projectChanged && canUseSkills) {
      unawaited(ensureSkillsCatalog());
    }
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  /// 发送用户消息。
  ///
  /// 没有 active turn 时创建新回合；已有 active turn 时发送 steer，保持完整工具循环。
  /// [localImagePaths] 为随文本一并发送的本地图片绝对路径。
  /// [mentions] 为 composer 中选中的 @文件引用。
  Future<void> sendMessage(
    String text, {
    List<String> localImagePaths = const <String>[],
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
    List<AgentSkillRef> skills = const <AgentSkillRef>[],
  }) async {
    final trimmed = text.trim();
    final imagePaths = List<String>.unmodifiable(
      canAttachImages
          ? localImagePaths.where((path) => path.trim().isNotEmpty)
          : const <String>[],
    );
    final resolvedMentions = canMentionResources
        ? mentions
        : const <({String name, String path})>[];
    final resolvedSkills = canUseSkills ? skills : const <AgentSkillRef>[];
    if ((trimmed.isEmpty &&
            imagePaths.isEmpty &&
            resolvedMentions.isEmpty &&
            resolvedSkills.isEmpty) ||
        !canSubmitMessage) {
      return;
    }

    if (_requiresResumedSelectedThread && _selectedThreadId == null) {
      return;
    }

    final switchToken = _threadSwitchToken;
    final selectedThreadId = _selectedThreadId;
    final runningTurnId = _timeline.selectedRunningTurnId;
    final inputs = _buildUserInputs(
      text: trimmed,
      localImagePaths: imagePaths,
      mentions: resolvedMentions,
      skills: resolvedSkills,
    );
    final clientUserMessageId = _nextClientUserMessageId();

    final isNewTurn = runningTurnId == null;
    final clearedPlanExecution =
        isNewTurn && _planExecutionHandoffController.clear();
    var providerOperation = 'provider/settings';
    AgentRuntimePort? requestRuntime;
    AgentSession? requestSession;
    AgentConversationModeSelection? requestModeSelection;
    var modeRequestAccepted = false;
    if (isNewTurn) {
      // 在发送瞬间冻结本回合模型配置，避免 footer 被后续改配置污染。
      _timeline.startPendingLiveTurn(modelConfig: _currentTurnModelConfig());
      _conversationModeController.setTurnRunning(true);
      _consumeActivityDirty();
    } else {
      _timeline.currentTurnGroupId = runningTurnId;
    }
    _timeline.addConversationMessage(
      AgentConversationMessage(
        id: _nextLocalTimelineId('user'),
        role: AgentMessageRole.user,
        text: trimmed,
        localImagePaths: imagePaths,
      ),
    );
    _status = const AgentProviderStatus(
      state: AgentProviderConnectionState.running,
      message: 'Agent is working',
    );
    _syncElapsedTicker();
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: <AgentUiRegion>{
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
          if (clearedPlanExecution) AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );

    try {
      await loadSettings();
      providerOperation = 'provider/ensure';
      // 已选中 thread 时必须落到该 thread 所属 provider，避免用 Codex 去 resume Grok id。
      // session：sendMessage 是唯一应该触发首次启动运行实例的入口（04 §0.4 / 02 §2.4）。
      final AgentProviderBundle bundle;
      final selectedProviderId = _selectedProviderId?.trim();
      if (selectedProviderId != null &&
          selectedProviderId.isNotEmpty &&
          selectedProviderId != conversationBinding.providerId) {
        throw StateError(
          'Conversation ${conversationBinding.key} is bound to '
          '${conversationBinding.providerId}, not $selectedProviderId',
        );
      }
      _turnActivity ??= await conversationBinding.beginTurn();
      bundle = _turnActivity!.runtime.bundle;
      _modelSelectionController.bindRuntime(bundle.runtime);
      await _bindLiveRuntime(
        bundle,
        runtimeIdentity: _turnActivity!.runtime.runtimeIdentity,
        threadId: _selectedThreadId,
      );
      requestRuntime = bundle.runtime;
      // steer 复用同一个仍在运行的活动令牌；终态前 Binding 不会被空闲回收。
      final context = AgentContext(
        projectPath: _projectPath,
        filePath: _contextFilePath,
      );
      final permissionSnapshot = _permissionSelectionController
          .snapshotForRequest(threadId: selectedThreadId);
      providerOperation = 'session/ensure';
      final session = await _ensureSession(
        bundle,
        context,
        switchToken: switchToken,
        expectedThreadId: selectedThreadId,
        permissionSnapshot: permissionSnapshot,
      );
      requestSession = session;
      if (conversationBinding.threadId == null) {
        await conversationBinding.promoteToThread(session.id);
      }
      final conversation = bundle.conversation;
      // 模式 + 当前 thread 权限一并冻结进请求快照，避免共享 provider 可变状态串 thread。
      final modeSnapshot = isNewTurn
          ? _conversationModeController.snapshotForNewTurn(
              effectiveModelId: _effectiveConversationModeModelId(),
              selectedReasoningEffort: selectedReasoningEffort,
            )
          : const AgentTurnConfiguration();
      final turnConfiguration = AgentTurnConfiguration(
        conversationMode: modeSnapshot.conversationMode,
        permissionSnapshot: permissionSnapshot,
      );
      requestModeSelection = turnConfiguration.conversationMode;
      // 新会话在 Grok 异步 generated_title 出现前，先用首条用户消息作临时标题。
      if (_isStillSelectedThread(switchToken, session.id) &&
          _currentThreadTitle == defaultThreadTitle &&
          trimmed.isNotEmpty) {
        _applyThreadTitle(_provisionalThreadTitle(trimmed));
        _publishUiChanges(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.header},
            urgency: AgentUiUpdateUrgency.immediate,
          ),
        );
      }
      _log.i('Sending Agent request with provider ${bundle.runtime.config.id}');
      if (isNewTurn) {
        providerOperation = 'conversation/sendMessage';
        final turn = await conversation.sendMessage(
          session: session,
          inputs: inputs,
          context: context,
          clientUserMessageId: clientUserMessageId,
          configuration: turnConfiguration,
        );
        _conversationModeController.markTurnAccepted(
          threadId: session.id,
          selection: requestModeSelection,
        );
        modeRequestAccepted = true;
        final pendingId = _timeline.pendingTurnGroupId;
        if (pendingId != null &&
            _isStillSelectedThread(switchToken, session.id)) {
          _timeline.beginLiveTurnGroup(turn);
          _publishUiChanges(
            AgentUiUpdateRequest(
              regions: const <AgentUiRegion>{
                AgentUiRegion.liveTurnBinding,
                AgentUiRegion.liveTurn,
                AgentUiRegion.header,
                AgentUiRegion.composer,
              },
              urgency: AgentUiUpdateUrgency.immediate,
            ),
          );
        }
      } else {
        providerOperation = 'turn/steer';
        final turnSteering = bundle.turnSteering;
        if (turnSteering == null) {
          throw UnsupportedError(
            '${bundle.runtime.config.displayName} '
            'does not support steering turns',
          );
        }
        await turnSteering.steerTurn(
          session: session,
          expectedTurnId: runningTurnId,
          inputs: inputs,
          context: context,
          clientUserMessageId: clientUserMessageId,
        );
      }
    } on ProcessException catch (error, stackTrace) {
      _logProviderOperationFailure(
        error: error,
        stackTrace: stackTrace,
        operation: providerOperation,
        runtime: requestRuntime,
        session: requestSession,
        selectedThreadId: selectedThreadId,
        runningTurnId: runningTurnId,
        extra: <String, Object?>{
          'category': 'process',
          'errorCode': error.errorCode,
          'executable': error.executable,
        },
      );
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _failPendingLiveTurn();
      _markUnavailable(error.message, details: error.toString());
    } on UnsupportedError catch (error, stackTrace) {
      _logProviderOperationFailure(
        error: error,
        stackTrace: stackTrace,
        operation: providerOperation,
        runtime: requestRuntime,
        session: requestSession,
        selectedThreadId: selectedThreadId,
        runningTurnId: runningTurnId,
        extra: const <String, Object?>{'category': 'unsupported'},
      );
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _failPendingLiveTurn();
      _markError(error.message ?? 'Provider is not supported');
    } catch (error, stackTrace) {
      _logProviderOperationFailure(
        error: error,
        stackTrace: stackTrace,
        operation: providerOperation,
        runtime: requestRuntime,
        session: requestSession,
        selectedThreadId: selectedThreadId,
        runningTurnId: runningTurnId,
        extra: const <String, Object?>{'category': 'request'},
      );
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _failPendingLiveTurn();
      _markError('Agent request failed', details: error.toString());
    } finally {
      if (isNewTurn && !modeRequestAccepted && requestSession != null) {
        _conversationModeController.markTurnFailed(
          threadId: requestSession.id,
          selection: requestModeSelection,
        );
      }
      if (isNewTurn && !modeRequestAccepted) {
        // 未被 server 接受时不会有终态事件，必须在本地释放活动令牌。
        _releaseTurnActivity();
      }
      _timeline.clearPendingTurnGroupId();
    }
  }

  /// 记录任意 Provider 调用抛出的异常；不包含本次用户输入正文。
  void _logProviderOperationFailure({
    required Object error,
    required StackTrace stackTrace,
    required String operation,
    required AgentRuntimePort? runtime,
    required AgentSession? session,
    required String? selectedThreadId,
    required String? runningTurnId,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    logStructuredFailure(
      _log,
      message: 'Agent provider operation failed',
      error: error,
      stackTrace: stackTrace,
      context: <String, Object?>{
        ..._providerRuntimeLogContext(runtime),
        'operation': operation,
        'sessionId': session?.id ?? selectedThreadId,
        'turnId': runningTurnId ?? _timeline.pendingTurnGroupId,
        ...extra,
      },
    );
  }

  /// 取消正在运行的回合。
  Future<void> cancelActiveTurn() async {
    final turnId = _timeline.selectedCancelableTurnId();
    final sessionId = _selectedThreadId;
    if (turnId == null || sessionId == null) {
      return;
    }
    _log.i('Cancelling Agent turn $turnId');
    await _runCurrentBundle<void>(
      (bundle) => bundle.conversation.cancelTurn(
        AgentTurn(id: turnId, sessionId: sessionId),
      ),
    );
  }

  /// 重新加载当前 Entry 唯一绑定的 thread；只用于首次打开失败后的显式重试。
  Future<void> retryOpenThread() {
    final thread = _boundThreadSummary;
    if (thread == null) {
      throw StateError('Draft conversation has no thread to reopen');
    }
    if (_threadOpenPhase != AgentThreadOpenPhase.openFailed) {
      return Future<void>.value();
    }
    return _openBoundThread(thread);
  }

  /// 加载 Entry 创建时已经冻结的 thread 身份。
  Future<void> _openBoundThread(AgentThreadSummary thread) async {
    final switchToken = ++_threadSwitchToken;
    if (_planExecutionHandoffController.clear()) {
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.pendingInteraction,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
    }
    // 在第一个 await 前让旧 thread listener 失效，避免其微任务事件污染新时间线。
    _invalidateProviderEventListener();
    if (thread.providerId != conversationBinding.providerId) {
      _threadOpenPhase = AgentThreadOpenPhase.openFailed;
      final unavailable = providerController.unavailableReasonForProviderId(
        thread.providerId,
      );
      if (unavailable != null) {
        _markUnavailable('Cursor Agent unavailable', details: unavailable);
      } else {
        _markError(
          'Could not open thread',
          details:
              'Conversation is bound to ${conversationBinding.providerId}; '
              '${thread.providerId} requires a separate workspace entry.',
        );
      }
      return;
    }
    final boundThreadId = conversationBinding.threadId;
    if (boundThreadId != null && boundThreadId != thread.id) {
      throw StateError(
        'Conversation Binding for $boundThreadId cannot open ${thread.id}',
      );
    }
    _conversationModeController.bindThread(threadId: thread.id);
    _permissionSelectionController.bindThread(thread.id);
    // Provider 配置可能仍在应用启动阶段读取；必须等待其完成后再判断 thread 归属，
    // 否则会先看到内置 Codex、随后却从磁盘加载出 Grok，并用错误后端读取历史。
    await loadSettings();
    if (!_isCurrentSwitch(switchToken)) {
      return;
    }
    final unavailable = providerController.unavailableReasonForProviderId(
      thread.providerId,
    );
    if (unavailable != null) {
      _threadOpenPhase = AgentThreadOpenPhase.openFailed;
      _markUnavailable('Cursor Agent unavailable', details: unavailable);
      return;
    }
    // 离开旧会话时先记下 id，切走后取消服务端订阅，减少无关通知。
    final previousThreadId = _selectedThreadId;
    _flushPendingStreamChangesNow();
    _session = null;
    _sessionConfigOptions = const <AgentSessionConfigOption>[];
    _restoredSessionId = thread.id;
    _selectedProviderId = thread.providerId;
    _conversationModeController.bindThread(threadId: thread.id);
    _permissionSelectionController.bindThread(thread.id);
    _requiresResumedSelectedThread = true;
    _threadOpenPhase = AgentThreadOpenPhase.loadingHistory;
    _currentThreadTitle = thread.displayName;
    _threadCreatedAt = thread.createdAt;
    _threadLastActiveAt = thread.lastActiveAt;
    // 列表/历史里的 active 可能来自外部客户端（如 Codex 应用），Zeta 未持有 live
    // 时不得标成执行中或等待交互；仅 systemError 等非忙碌态可保留展示。
    _applyThreadRuntimeStatus(
      status: _runtimeStatusWithoutExternalBusy(thread.status),
      waitingOnApproval: false,
      waitingOnUserInput: false,
    );
    _timeline.clearConversation();
    _modelRerouteNotice = null;
    _status = const AgentProviderStatus(
      state: AgentProviderConnectionState.connecting,
      message: 'Loading history',
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );

    try {
      await loadSettings();
      // 读历史和目录只借用 global runtime；打开 thread 不创建 session runtime，
      // 也不建立 live 事件订阅。下一次用户提交时才由 beginTurn resume。
      // Thread entry 是独立 VM：共享 catalog 预热不会写入本实例的 _modelList。
      // 打开历史时与读 history 并行 hydrate，避免 composer 因 models 为空隐藏选择器。
      final modelsFuture = loadModels();
      if (previousThreadId != null && previousThreadId != thread.id) {
        // 不阻塞历史加载：退订失败只记日志。
        unawaited(
          _unsubscribeThreadBestEffort(
            conversationBinding.providerId,
            previousThreadId,
          ),
        );
      }
      final history = await _runGlobalBundle((bundle) {
        final threadCatalog = bundle.threadCatalog;
        if (threadCatalog == null) {
          throw UnsupportedError(
            '${bundle.runtime.config.displayName} '
            'does not support thread history',
          );
        }
        return threadCatalog.readThreadHistory(
          threadId: thread.id,
          sessionPath: thread.sessionPath,
          projectPath: thread.projectPath,
        );
      }, preferredProviderId: thread.providerId);
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      await modelsFuture;
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _timeline.applyHistorySnapshot(history, thread);
      _applyThreadSelectionFromHistory(history);
      _conversationModeController.bindThread(
        threadId: thread.id,
        historyMode: history.latestCollaborationMode,
      );
      _permissionSelectionController.bindThread(thread.id);
      _conversationModeController.setTurnRunning(isTurnRunning);
      // 再次锁定 resume：避免异步路径把 requiresResumed 清掉。
      _restoredSessionId = thread.id;
      _selectedProviderId = thread.providerId;
      _requiresResumedSelectedThread = true;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.ready,
        message: '$activeProviderName ready',
      );
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.history,
            AgentUiRegion.liveTurnBinding,
            AgentUiRegion.header,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );
    } catch (error) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _threadOpenPhase = AgentThreadOpenPhase.openFailed;
      _log.w(
        'Could not load Agent thread history ${thread.id} '
        '(${error.runtimeType})',
      );
      _markError('Could not load thread history', details: error.toString());
    }
  }

  /// 处理审批卡片的 approve/deny。
  ///
  /// UI 先移除卡片，再异步回写 provider，避免按钮点击后卡片停留造成重复提交。
  Future<void> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const <String>[],
  }) async {
    _timeline.removePermissionRequest(request.id);
    _resolvePendingAttention(
      kind: AgentAttentionKind.permissionRequired,
      sourceId: request.id,
      threadId: request.sessionId,
      turnId: request.turnId,
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    _log.i(
      'Responding to Agent permission ${request.kind.name}: approved=$approved',
    );
    await _runCurrentBundle<void>((bundle) async {
      final interactions = bundle.interactions;
      if (interactions == null) {
        return;
      }
      await interactions.respondToPermission(
        AgentPermissionDecision(
          requestId: request.id,
          approved: approved,
          cancelTurn: cancelTurn,
          commandDecision: commandDecision,
          execpolicyAmendment: execpolicyAmendment,
        ),
      );
    });
  }

  /// 回答或跳过独立用户提问。
  ///
  /// UI 先移除卡片，再通过 question 响应方法回写结构化 answers。
  Future<void> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const <String, List<String>>{},
  }) async {
    _timeline.removeQuestionRequest(request.id);
    _resolvePendingAttention(
      kind: AgentAttentionKind.questionRequired,
      sourceId: request.id,
      threadId: request.sessionId,
      turnId: request.turnId,
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    _log.i(
      'Responding to Agent question '
      '(${answers.length} answered questions)',
    );
    await _runCurrentBundle<void>((bundle) async {
      final interactions = bundle.interactions;
      if (interactions == null) {
        return;
      }
      await interactions.respondToQuestion(
        AgentQuestionResponse(requestId: request.id, answers: answers),
      );
    });
  }

  /// 回写 Provider 计划审批结果。
  ///
  /// [reason] 承载用户对计划的修改意见：审批是阻塞请求、回合仍在运行，
  /// 修改意见不能走 `sendMessage`，只能随决定一起回传给 Provider。
  Future<void> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  }) async {
    _timeline.removePlanApprovalRequest(request.id);
    _resolvePendingAttention(
      kind: AgentAttentionKind.planApprovalRequired,
      sourceId: request.id,
      threadId: request.sessionId,
      turnId: request.turnId,
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    await _runCurrentBundle<void>((bundle) async {
      final planApproval = bundle.planApproval;
      if (planApproval == null) {
        return;
      }
      await planApproval.respondToPlanApproval(
        AgentPlanApprovalDecision(
          requestId: request.id,
          kind: kind,
          reason: reason,
        ),
      );
    });
    // provider 驱动的计划审批一旦作出决定，计划即被消费：接受 → grok 自行
    // 进入实施回合；放弃 → grok 退出 plan 模式。必须强制清空 pending turn
    // 模式：Grok 的 markTurnAccepted 在阻塞 session/prompt 返回后才执行，
    // 若不 clear，迟到确认会把 confirmed 写回 plan 并重复触发本地执行交接。
    // 拒绝则留在 plan 模式继续修订。
    if (kind != AgentPlanApprovalDecisionKind.rejected) {
      _conversationModeController.applyServerMode(
        AgentConversationModeId.defaultMode,
        clearPendingTurn: true,
      );
    }
  }

  /// 从上一历史 turn 创建新分支，并用编辑后的文本开启新回合。
  ///
  /// 原 thread 保持不变；分支也不会回滚 Agent 已写入工作区的文件。
  Future<void> editLastUserMessageAndRetry(String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || !canEditLastUserMessage) {
      return;
    }
    final threadId = sessionId;
    if (threadId == null) {
      return;
    }
    final message = _lastEditableUserMessage();
    final boundaryTurnId = message == null
        ? null
        : _timeline.forkBoundaryBeforeMessage(message.id);
    if (boundaryTurnId == null) {
      return;
    }

    final switchToken = _threadSwitchToken;
    _status = const AgentProviderStatus(
      state: AgentProviderConnectionState.running,
      message: 'Creating branch',
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );

    try {
      // fork 属于 thread 管理操作，使用 global runtime；新 Binding 仍保持 dormant，
      // 直到用户真正提交输入。
      final session = await _runGlobalBundle((bundle) {
        final threadBranching = bundle.threadBranching;
        if (threadBranching == null) {
          throw UnsupportedError(
            '${bundle.runtime.config.displayName} '
            'does not support thread branching',
          );
        }
        return threadBranching.forkThread(
          threadId: threadId,
          context: AgentContext(
            projectPath: _projectPath,
            filePath: _contextFilePath,
          ),
          boundary: AgentForkThroughTurn(boundaryTurnId),
          permissionSnapshot: _permissionSelectionController.snapshotForRequest(
            threadId: threadId,
          ),
        );
      });
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      await _openCreatedThread(session, initialMessage: trimmed);
      _restoreSourceAfterBranchCreated();
    } catch (error) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _log.w(
        'Could not create branch and retry thread $threadId '
        '(${error.runtimeType})',
      );
      _markError(
        'Could not create branch and retry message',
        details: error.toString(),
      );
    }
  }

  /// 分叉当前会话为新 thread，并切换到分叉结果。
  Future<AgentSession?> forkCurrentThread() async {
    final threadId = sessionId;
    if (threadId == null || !canForkCurrentThread) {
      return null;
    }
    final switchToken = _threadSwitchToken;
    try {
      final session = await _runGlobalBundle((bundle) {
        final threadBranching = bundle.threadBranching;
        if (threadBranching == null) {
          throw UnsupportedError(
            '${bundle.runtime.config.displayName} '
            'does not support thread branching',
          );
        }
        return threadBranching.forkThread(
          threadId: threadId,
          context: AgentContext(
            projectPath: _projectPath,
            filePath: _contextFilePath,
          ),
          permissionSnapshot: _permissionSelectionController.snapshotForRequest(
            threadId: threadId,
          ),
        );
      });
      if (!_isCurrentSwitch(switchToken)) {
        return session;
      }
      await _openCreatedThread(session);
      return session;
    } catch (error) {
      _log.w('Could not fork thread $threadId (${error.runtimeType})');
      _markError('Could not fork thread', details: error.toString());
      return null;
    }
  }

  Future<void> _openCreatedThread(
    AgentSession session, {
    String? initialMessage,
  }) {
    final sourceThreadId = sessionId;
    if (session.providerId != conversationBinding.providerId) {
      throw StateError(
        'Fork from ${conversationBinding.providerId} returned '
        '${session.providerId}',
      );
    }
    if (sourceThreadId != null && session.id == sourceThreadId) {
      throw StateError('Fork returned the source thread ${session.id}');
    }
    final callback = onCreatedThread;
    if (callback == null) {
      throw StateError(
        'Created thread ${session.id} requires Shell activation',
      );
    }
    return callback(
      session: session,
      context: AgentContext(
        projectPath: _projectPath,
        filePath: _contextFilePath,
      ),
      initialMessage: initialMessage,
    );
  }

  void _restoreSourceAfterBranchCreated() {
    if (_disposed) {
      return;
    }
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.ready,
      message: '$activeProviderName ready',
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  /// 重命名当前 thread；先乐观更新标题，再以 `thread/name/updated` 为准。
  Future<void> renameCurrentThread(String name) async {
    final trimmed = name.trim();
    final threadId = sessionId;
    if (trimmed.isEmpty || threadId == null || !canRenameCurrentThread) {
      return;
    }
    if (trimmed == _currentThreadTitle) {
      return;
    }
    final previousTitle = _currentThreadTitle;
    _applyThreadTitle(trimmed);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.header},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
    try {
      await _runGlobalBundle((bundle) {
        final threadMutations = bundle.threadMutations;
        if (threadMutations == null) {
          throw UnsupportedError(
            '${bundle.runtime.config.displayName} '
            'does not support renaming threads',
          );
        }
        return threadMutations.renameThread(threadId: threadId, name: trimmed);
      });
    } catch (error) {
      if (sessionId == threadId && _currentThreadTitle == trimmed) {
        _applyThreadTitle(previousTitle);
        _publishUiChanges(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.header},
            urgency: AgentUiUpdateUrgency.immediate,
          ),
        );
      }
      _log.w('Could not rename thread $threadId (${error.runtimeType})');
      _markError('Could not rename thread', details: error.toString());
    }
  }

  /// 归档当前 thread；事件订阅会负责同步左侧列表。
  Future<void> archiveCurrentThread() async {
    final threadId = sessionId;
    if (threadId == null || !canArchiveCurrentThread) {
      return;
    }
    try {
      await _runGlobalBundle((bundle) {
        final threadMutations = bundle.threadMutations;
        if (threadMutations == null) {
          throw UnsupportedError(
            '${bundle.runtime.config.displayName} '
            'does not support archiving threads',
          );
        }
        return threadMutations.archiveThread(threadId);
      });
    } catch (error) {
      _log.w('Could not archive thread $threadId (${error.runtimeType})');
      _markError('Could not archive thread', details: error.toString());
    }
  }

  /// 从列表侧同步当前 thread 标题（刷新列表 / 服务端改名后保持详情头栏一致）。
  ///
  /// 仅当 [threadId] 仍是当前会话时生效；标题未变化时不触发刷新。
  void syncThreadTitleIfCurrent(String threadId, String title) {
    if (_disposed) {
      return;
    }
    if (_selectedThreadId != threadId) {
      return;
    }
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _currentThreadTitle) {
      return;
    }
    _applyThreadTitle(trimmed);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.header},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void dispose() {
    _disposed = true;
    // Pane 关闭时兜底释放仍在运行的 Binding 活动令牌。
    _releaseTurnActivity();
    _invalidateProviderEventListener(
      reason: AgentEventPipelineCloseReason.disposed,
    );
    providerController.removeListener(_handleProviderSettingsChanged);
    conversationBinding.removeListener(_handleConversationBindingChanged);
    _modelSelectionController.removeListener(_handleModelSelectionChanged);
    _conversationModeController.removeListener(_handleConversationModeChanged);
    _skillsCatalogController.removeListener(_handleSkillsCatalogChanged);
    _permissionSelectionController.removeListener(
      _handlePermissionStateChanged,
    );
    if (_ownsModelSelectionController) {
      _modelSelectionController.dispose();
    }
    if (_ownsConversationModeController) {
      _conversationModeController.dispose();
    }
    if (_ownsSkillsCatalogController) {
      _skillsCatalogController.dispose();
    }
    _elapsedTicker.dispose();
    _effectRunner.dispose();
    _uiUpdateScheduler.dispose();
    _uiStateStore.dispose();
    _threadSnapshotListenable.dispose();
    contextPanelVisible.dispose();
    _timeline.dispose();
  }

  void _syncElapsedTicker() {
    if (_disposed) {
      return;
    }
    if (isTurnRunning) {
      _elapsedTicker.start();
    } else {
      _elapsedTicker.stop();
    }
  }

  /// 消费活动段脏标记；为 true 时应刷新 header。
  bool _consumeActivityDirty() => _timeline.takeActivityDirty();

  /// 释放会话活动令牌。
  ///
  /// turn 完成、失败、取消和 dispose 共用的收尾入口。
  void _releaseTurnActivity() {
    final activity = _turnActivity;
    _turnActivity = null;
    unawaited(activity?.release());
  }

  void _handleConversationBindingChanged() {
    if (_disposed) {
      return;
    }
    if (conversationBinding.currentRuntime != null) {
      return;
    }
    if (_session != null || _eventPipeline != null) {
      _eventProcessor.settleInterruptedTurn(
        fallbackTurnId: 'provider-disconnected',
      );
      _releaseTurnActivity();
      _session = null;
      _requiresResumedSelectedThread = _selectedThreadId != null;
      _invalidateProviderEventListener();
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
    }
  }

  void _handleProviderSettingsChanged() {
    if (_disposed) {
      return;
    }
    final planExecutionCleared =
        isReadOnly && _planExecutionHandoffController.clear();
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
          if (planExecutionCleared) AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void _handleModelSelectionChanged() {
    if (_disposed) {
      return;
    }
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void _handleConversationModeChanged() {
    if (_disposed) {
      return;
    }
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  /// 应用服务端权威的会话模式（Grok `current_mode_update`）。
  ///
  /// 更新模式控制器的 confirmed/draft，并刷新 header（plan 模式徽标）。
  /// plan 模式状态只以此信号为准，不按 `enter_plan_mode`/`exit_plan_mode`
  /// 工具调用标题推断。
  void _applyServerConversationMode(AgentConversationModeUpdatedEvent event) {
    if (_disposed) {
      return;
    }
    _conversationModeController.applyServerMode(event.modeId);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.header},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void _handleSkillsCatalogChanged() {
    if (_disposed) {
      return;
    }
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  void _handlePermissionStateChanged() {
    if (_disposed) {
      return;
    }
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  // 全局信息与会话运行时严格分流：catalog 只借用 global runtime；session
  // 操作只读取 Binding 当前 runtime。只有 sendMessage 的 beginTurn 可以创建后者。

  /// 在 global runtime 租约作用域内执行会话前操作。
  ///
  /// Provider 实例不会从回调中逸出或缓存在 ViewModel；历史、模型、Skill 与
  /// thread 管理因此都不会创建或占用 session runtime。
  Future<T> _runGlobalBundle<T>(
    Future<T> Function(AgentProviderBundle bundle) operation, {
    String? preferredProviderId,
    bool hydrateCatalogs = false,
  }) async {
    final requestedId = preferredProviderId?.trim();
    final providerId = requestedId == null || requestedId.isEmpty
        ? conversationBinding.providerId
        : requestedId;
    final config = providerController.providerConfigById(providerId);
    if (config == null || !providerController.isProviderEnabled(providerId)) {
      throw StateError('Provider $providerId is not enabled');
    }
    return globalRuntime.run(config, (runtime) async {
      _globalCapabilitiesByProviderId[providerId] = runtime.capabilities;
      final bundle = runtime.bundle;
      if (bundle.runtime.config.id != providerId) {
        throw StateError(
          'Expected provider $providerId but received '
          '${bundle.runtime.config.id}',
        );
      }
      if (hydrateCatalogs) {
        await conversationBinding.bindPermissionCatalog(
          port: bundle.permissionPolicy,
          persistedOptionId: config.resolvedPermissionOptionId,
        );
        await _ensureConversationModeCatalog(bundle);
        await _ensureSkillsCatalog(bundle);
      }
      return operation(bundle);
    });
  }

  Future<T?> _runCurrentBundle<T>(
    Future<T> Function(AgentProviderBundle bundle) operation,
  ) {
    return conversationBinding.runCurrent(
      (runtime) => operation(runtime.bundle),
    );
  }

  /// 绑定当前 session runtime 的事件、模型、权限和能力目录。
  Future<void> _bindLiveRuntime(
    AgentProviderBundle bundle, {
    required AgentProviderRuntimeIdentity runtimeIdentity,
    required String? threadId,
  }) async {
    if (identical(_currentRuntime, bundle.runtime) &&
        _permissionSelectionController.runtimeIdentity == runtimeIdentity &&
        _hasCurrentProviderEventListener(bundle, threadId: threadId)) {
      await _ensureConversationModeCatalog(bundle);
      return;
    }

    _modelSelectionController.bindRuntime(bundle.runtime);
    _permissionSelectionController.bindThread(threadId);
    await _replaceProviderEventSubscription(bundle, threadId: threadId);
    _log.t('Bound conversation runtime: ${bundle.runtime.config.id}');
  }

  Future<void> _ensureSkillsCatalog(AgentProviderBundle bundle) async {
    final runtime = bundle.runtime;
    final supportsSkills = runtime.capabilities.supportsSkillInput;
    final port = supportsSkills ? bundle.skills : null;
    await _skillsCatalogController.bind(
      providerId: runtime.config.id,
      projectPath: _projectPath,
      port: port,
      configFingerprint: runtime.config.id,
    );
  }

  /// 去重键使用 providerId + [_runtimeScopeOf]（协议连接身份）。
  ///
  /// global 与 session 两条路径共享目录缓存，但会话状态只在当前 runtime 上应用。
  Future<void> _ensureConversationModeCatalog(
    AgentProviderBundle bundle,
  ) async {
    final runtime = bundle.runtime;
    final runtimeScope = runtime.runtimeScope;
    if (_conversationModeCatalogProviderId == runtime.config.id &&
        _conversationModeCatalogRuntimeScope == runtimeScope) {
      return;
    }

    final generation = ++_conversationModeCatalogLoadGeneration;
    final preservesCurrentMode =
        _conversationModeCatalogProviderId == runtime.config.id;
    final restoredMode = preservesCurrentMode
        ? _conversationModeController.state.confirmedMode
        : null;
    final restoredDraft = preservesCurrentMode
        ? _conversationModeController.state.draftMode
        : null;
    await _conversationModeController.loadCatalog(
      providerId: runtime.config.id,
      port: bundle.conversationModes,
    );
    if (_disposed || generation != _conversationModeCatalogLoadGeneration) {
      return;
    }

    _conversationModeCatalogProviderId = runtime.config.id;
    _conversationModeCatalogRuntimeScope = runtimeScope;
    if (runtime.config.id == conversationBinding.providerId) {
      _conversationModeController.bindThread(
        threadId: _selectedThreadId,
        historyMode: restoredMode,
      );
      _permissionSelectionController.bindThread(_selectedThreadId);
      if (restoredDraft != null) {
        _conversationModeController.selectMode(restoredDraft);
      }
      _conversationModeController.setTurnRunning(isTurnRunning);
    }
  }

  /// 发送失败时结束本地 pending/running 回合，避免 UI 卡在 running 无法再发。
  void _failPendingLiveTurn() {
    final turnId =
        _timeline.pendingTurnGroupId ?? _timeline.selectedRunningTurnId;
    if (turnId == null) {
      return;
    }
    _timeline.completeLiveTurnGroup(
      turnId,
      status: AgentHistoryTurnStatus.failed,
    );
    _timeline.clearPendingTurnGroupId();
    _consumeActivityDirty();
    _syncElapsedTicker();
    _conversationModeController.setTurnRunning(isTurnRunning);
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  Future<AgentSession> _ensureSession(
    AgentProviderBundle bundle,
    AgentContext context, {
    required int switchToken,
    required String? expectedThreadId,
    required AgentPermissionRequestSnapshot permissionSnapshot,
  }) async {
    final existing = _session;
    if (existing != null) {
      return existing;
    }

    final restoredSessionId = _restoredSessionId;
    if (restoredSessionId != null) {
      try {
        _log.t('Resuming Agent session $restoredSessionId');
        final session = await bundle.conversation.resumeSession(
          restoredSessionId,
          context: context,
          permissionSnapshot: permissionSnapshot,
        );
        if (_isStillSelectedThread(switchToken, expectedThreadId)) {
          await _replaceProviderEventSubscription(bundle, threadId: session.id);
        }
        if (_isStillSelectedThread(switchToken, expectedThreadId)) {
          _session = session;
          _restoredSessionId = session.id;
          _bindConversationModeThreadPreservingDraft(
            threadId: session.id,
            historyMode: _conversationModeController.state.confirmedMode,
          );
          _conversationModeController.setTurnRunning(isTurnRunning);
          _threadOpenPhase = AgentThreadOpenPhase.idle;
          _requiresResumedSelectedThread = false;
          _applySessionTitle(session);
          _publishUiChanges(
            AgentUiUpdateRequest(
              regions: const <AgentUiRegion>{
                AgentUiRegion.header,
                AgentUiRegion.composer,
              },
              urgency: AgentUiUpdateUrgency.immediate,
            ),
          );
        }
        return session;
      } catch (error) {
        _log.w(
          'Could not resume Agent session $restoredSessionId '
          '(${error.runtimeType})',
        );
        if (_requiresResumedSelectedThread) {
          if (_isStillSelectedThread(switchToken, expectedThreadId)) {
            _threadOpenPhase = AgentThreadOpenPhase.openFailed;
          }
          rethrow;
        }
        if (_isStillSelectedThread(switchToken, expectedThreadId) &&
            _restoredSessionId == restoredSessionId) {
          _restoredSessionId = null;
        }
      }
    }

    _log.t(
      'Starting new Agent session with provider ${bundle.runtime.config.id}',
    );
    final session = await bundle.conversation.startSession(
      context: context,
      permissionSnapshot: permissionSnapshot,
    );
    if (_isStillSelectedThread(switchToken, expectedThreadId)) {
      await _replaceProviderEventSubscription(bundle, threadId: session.id);
    }
    if (_isStillSelectedThread(switchToken, expectedThreadId)) {
      _session = session;
      _restoredSessionId = session.id;
      _bindConversationModeThreadPreservingDraft(
        threadId: session.id,
        historyMode: _conversationModeController.state.confirmedMode,
      );
      _conversationModeController.setTurnRunning(isTurnRunning);
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
      _applySessionTitle(session);
      _publishUiChanges(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
    }
    return session;
  }

  void _bindConversationModeThreadPreservingDraft({
    required String threadId,
    required AgentConversationModeId? historyMode,
  }) {
    final draftMode = _conversationModeController.state.draftMode;
    _conversationModeController.bindThread(
      threadId: threadId,
      historyMode: historyMode,
    );
    _permissionSelectionController.bindThread(threadId);
    if (draftMode != null) {
      _conversationModeController.selectMode(draftMode);
    }
  }

  bool _hasCurrentProviderEventListener(
    AgentProviderBundle bundle, {
    required String? threadId,
  }) {
    return _eventPipeline?.matches(
          providerId: bundle.runtime.config.id,
          threadId: threadId,
          runtimeScope:
              conversationBinding.currentRuntime?.runtimeScope ??
              bundle.runtime.runtimeScope,
        ) ??
        false;
  }

  /// 先安装新 Pipeline，再由其异步关闭旧资源；共享 gate 隔离重叠窗口。
  Future<void> _replaceProviderEventSubscription(
    AgentProviderBundle bundle, {
    required String? threadId,
  }) async {
    if (_disposed) {
      return;
    }
    final previous = _eventPipeline;
    final eventSource = conversationBinding.events;
    AgentRuntimeScope? currentRuntimeScope() =>
        conversationBinding.currentRuntime?.runtimeScope ??
        bundle.runtime.runtimeScope;
    late final AgentEventPipeline pipeline;
    pipeline = AgentEventPipeline(
      source: eventSource,
      providerId: bundle.runtime.config.id,
      threadId: threadId,
      runtimeScope: currentRuntimeScope(),
      currentRuntimeScope: currentRuntimeScope,
      allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
      // pipeline 身份是事件 listener generation 的唯一真源。
      processEvent: (event) {
        if (_disposed || !identical(_eventPipeline, pipeline)) {
          return;
        }
        _eventProcessor.process(event);
      },
      onSourceError: (error, _) {
        _log.w('Agent provider event stream failed (${error.runtimeType})');
      },
      onDone: () {
        if (!identical(_eventPipeline, pipeline)) {
          return;
        }
        _eventPipeline = null;
        if (_disposed) {
          return;
        }
        _log.w(
          'Agent provider event stream closed '
          '(provider: ${bundle.runtime.config.id}, '
          'thread: ${threadId ?? 'detached'})',
        );
        _eventProcessor.settleInterruptedTurn(
          fallbackTurnId: 'provider-disconnected',
        );
      },
      replaces: previous,
      onBackpressure: (pendingEventCount) {
        // 诊断仅记录键数量，不泄露对话或工具输出正文。
        _log.w(
          'Flushing Agent event buffer after backpressure '
          '(pending keys: $pendingEventCount)',
        );
      },
    );
    _eventPipeline = pipeline;
  }

  void _invalidateProviderEventListener({
    AgentEventPipelineCloseReason reason =
        AgentEventPipelineCloseReason.threadSwitch,
  }) {
    final pipeline = _eventPipeline;
    if (pipeline == null) {
      return;
    }
    unawaited(pipeline.close(reason: reason));
  }

  Map<String, Object?> _providerRuntimeLogContext(AgentRuntimePort? runtime) {
    final scope = runtime?.runtimeScope;
    return <String, Object?>{
      'providerId': runtime?.config.id ?? _selectedProviderId ?? 'unknown',
      if (runtime != null) 'lifecycleState': runtime.lifecycleState.name,
      if (scope != null) ...<String, Object?>{
        'runtimeId': scope.runtimeId,
        'connectionEpoch': scope.connectionEpoch,
      },
    };
  }

  bool _canResolvePlanExecution(AgentPlanExecutionRequest request) {
    return planExecutionRequest?.id == request.id &&
        sessionId == request.sessionId;
  }

  void _handleAttentionSignal(AgentAttentionSignal signal) {
    final resolvedThreadId = signal.threadId ?? sessionId;
    if (resolvedThreadId == null || resolvedThreadId.trim().isEmpty) {
      return;
    }
    var resolved = signal.withThreadId(resolvedThreadId);
    final handoff = planExecutionRequest;
    if (resolved.kind == AgentAttentionKind.turnCompleted &&
        handoff != null &&
        handoff.turnId == resolved.turnId) {
      resolved = AgentAttentionSignal(
        kind: AgentAttentionKind.planExecutionRequired,
        phase: AgentAttentionPhase.raised,
        sourceId: handoff.id,
        threadId: resolvedThreadId,
        turnId: handoff.turnId,
      );
    }
    onAttention?.call(resolved);
  }

  void _resolvePlanExecutionAttention(AgentPlanExecutionRequest request) {
    _handleAttentionSignal(
      AgentAttentionSignal(
        kind: AgentAttentionKind.planExecutionRequired,
        phase: AgentAttentionPhase.resolved,
        sourceId: request.id,
        threadId: request.sessionId,
        turnId: request.turnId,
      ),
    );
  }

  void _resolvePendingAttention({
    required AgentAttentionKind kind,
    required String sourceId,
    required String? threadId,
    required String? turnId,
  }) {
    _handleAttentionSignal(
      AgentAttentionSignal(
        kind: kind,
        phase: AgentAttentionPhase.resolved,
        sourceId: sourceId,
        threadId: threadId,
        turnId: turnId,
      ),
    );
  }

  /// 在 live turn 被归档前捕获计划正文，生成与 Provider 审批无关的本地交接请求。
  bool _updatePlanExecutionRequestForCompletedTurn(
    AgentTurnCompletedEvent event,
  ) {
    final previousId = planExecutionRequest?.id;
    final liveTurn = _timeline.liveTurnState;
    if (isReadOnly ||
        !activeCapabilities.canPrompt ||
        planApprovalRequests.isNotEmpty ||
        liveTurn == null ||
        liveTurn.id != event.turnId) {
      _planExecutionHandoffController.clear();
      return previousId != null;
    }

    String? planMarkdown;
    String? planMessageId;
    for (final entry in liveTurn.entries.reversed) {
      if (entry case AgentMessageTimelineEntry(:final message)
          when message.role == AgentMessageRole.agent &&
              message.isPlan &&
              message.text.trim().isNotEmpty) {
        planMarkdown = message.text;
        planMessageId = message.id;
        break;
      }
    }
    final modeState = _conversationModeController.state;
    final completedMode =
        modeState.pendingTurnMode?.modeId ?? modeState.confirmedMode;
    final request = _planExecutionHandoffController.offerCompletedPlan(
      sessionId: event.sessionId,
      turnId: event.turnId,
      status: event.status,
      modeId: completedMode,
      planMarkdown: planMarkdown,
      planMessageId: planMessageId,
      planEntries: List<AgentPlanEntry>.of(liveTurn.planEntries),
    );
    return previousId != request?.id;
  }

  /// 时间线中最近一条用户消息（用于编辑重试）。
  AgentConversationMessage? _lastEditableUserMessage() {
    for (final message in _timeline.messages.reversed) {
      if (message.role == AgentMessageRole.user &&
          message.text.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  /// 生成本地时间线条目 id；时间戳 + 单调序号，保证同毫秒内也不碰撞。
  String _nextLocalTimelineId(String prefix) {
    return _localTimelineIds.next(prefix);
  }

  /// 生成 `clientUserMessageId`，用于 turn/start 幂等。
  String _nextClientUserMessageId() {
    return _localTimelineIds.next('msg');
  }

  /// 组装协议输入项：文本（含当前文件上下文）+ skill + mention + 本地图片。
  List<AgentUserInput> _buildUserInputs({
    required String text,
    required List<String> localImagePaths,
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
    List<AgentSkillRef> skills = const <AgentSkillRef>[],
  }) {
    final inputs = <AgentUserInput>[];
    final textElements = <AgentTextElement>[];
    if (text.isNotEmpty && mentions.isNotEmpty) {
      for (final mention in mentions) {
        final needle = '@${mention.name}';
        var searchFrom = 0;
        while (true) {
          final index = text.indexOf(needle, searchFrom);
          if (index < 0) {
            break;
          }
          final start = utf8.encode(text.substring(0, index)).length;
          final end = utf8
              .encode(text.substring(0, index + needle.length))
              .length;
          textElements.add(
            AgentTextElement(start: start, end: end, placeholder: mention.name),
          );
          searchFrom = index + needle.length;
        }
      }
    }
    if (text.isNotEmpty) {
      inputs.add(
        AgentUserInput.text(
          _messageWithContext(text),
          textElements: textElements,
        ),
      );
    } else if (_contextFilePath != null) {
      // 纯图片发送时仍附带当前文件上下文，便于模型定位工作区。
      inputs.add(AgentUserInput.text(_messageWithContext('')));
    }
    final seenSkillPaths = <String>{};
    for (final skill in skills) {
      if (!seenSkillPaths.add(skill.path)) {
        continue;
      }
      inputs.add(AgentUserInput.skill(name: skill.name, path: skill.path));
    }
    for (final mention in mentions) {
      inputs.add(
        AgentUserInput.mention(name: mention.name, path: mention.path),
      );
    }
    for (final path in localImagePaths) {
      inputs.add(AgentUserInput.localImage(path: path));
    }
    return List<AgentUserInput>.unmodifiable(inputs);
  }

  String _messageWithContext(String message) {
    final filePath = _contextFilePath;
    if (filePath == null) {
      return message;
    }
    if (message.isEmpty) {
      return 'Current file context: $filePath';
    }
    return '$message\n\nCurrent file context: $filePath';
  }

  void _markUnavailable(String message, {String? details}) {
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.unavailable,
      message: message,
      details: details,
    );
    final turnId = _timeline.addConversationMessage(
      AgentConversationMessage(
        id: _nextLocalTimelineId('unavailable'),
        role: AgentMessageRole.system,
        text: details == null ? message : '$message: $details',
      ),
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: <AgentUiRegion>{
          if (_timeline.isHistoryTurnId(turnId)) AgentUiRegion.history,
          if (_timeline.isLiveTurnId(turnId)) AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  void _markError(String message, {String? details}) {
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.error,
      message: message,
      details: details,
    );
    final turnId = _timeline.addConversationMessage(
      AgentConversationMessage(
        id: _nextLocalTimelineId('error'),
        role: AgentMessageRole.system,
        text: details == null ? message : '$message: $details',
      ),
    );
    _publishUiChanges(
      AgentUiUpdateRequest(
        regions: <AgentUiRegion>{
          if (_timeline.isHistoryTurnId(turnId)) AgentUiRegion.history,
          if (_timeline.isLiveTurnId(turnId)) AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  bool _isCurrentSwitch(int switchToken) {
    return !_disposed && switchToken == _threadSwitchToken;
  }

  /// 切换会话时 best-effort 取消旧 thread 订阅，失败不影响 UI。
  Future<void> _unsubscribeThreadBestEffort(
    String providerId,
    String threadId,
  ) async {
    try {
      await _runGlobalBundle((bundle) async {
        final threadCatalog = bundle.threadCatalog;
        if (threadCatalog == null) {
          return;
        }
        await threadCatalog.unsubscribeThread(threadId);
      }, preferredProviderId: providerId);
    } catch (error) {
      _log.w(
        'Could not unsubscribe Agent thread $threadId '
        '(${error.runtimeType})',
      );
    }
  }

  String? get _selectedThreadId => _session?.id ?? _restoredSessionId;

  AgentConversationReducerContext _buildEventReducerContext() {
    final effectScope =
        _currentEffectScope() ??
        AgentConversationEffectScope(
          reductionScope: AgentConversationReductionScope.live,
          providerId: activeProviderId,
          listenerGeneration: -1,
          threadId: _selectedThreadId,
        );
    return AgentConversationReducerContext(
      scope: AgentConversationReductionScope.live,
      selectedThreadId: _selectedThreadId,
      requiresResumedSelectedThread: _requiresResumedSelectedThread,
      pendingTurnGroupId: _timeline.pendingTurnGroupId,
      hasTurn: _timeline.hasTurn,
      isHistoryTurnId: _timeline.isHistoryTurnId,
      modelsRefreshing: _modelsRefreshing,
      activeProviderName: activeProviderName,
      activeProviderConfig: _boundProviderConfig,
      effectScope: effectScope,
    );
  }

  AgentConversationEffectScope? _currentEffectScope() {
    final listener = _eventPipeline?.currentListenerScope;
    if (listener == null) {
      return null;
    }
    final runtime = _currentRuntime;
    return AgentConversationEffectScope(
      reductionScope: AgentConversationReductionScope.live,
      providerId: listener.providerId,
      listenerGeneration: listener.listenerGeneration,
      runtimeId: listener.runtimeId,
      connectionEpoch: listener.connectionEpoch,
      providerLifecycleState: runtime?.lifecycleState.name,
      threadId: _selectedThreadId,
    );
  }

  bool _isStillSelectedThread(int switchToken, String? expectedThreadId) {
    if (!_isCurrentSwitch(switchToken)) {
      return false;
    }
    final selectedThreadId = _selectedThreadId;
    return expectedThreadId == null
        ? true
        : selectedThreadId == expectedThreadId;
  }

  /// 优先使用 provider 返回的 thread 标题；空标题时保留当前标题。
  void _applySessionTitle(AgentSession session) {
    final title = session.title?.trim();
    if (title == null || title.isEmpty) {
      return;
    }
    _applyThreadTitle(title);
  }

  /// 更新当前详情标题，并在已绑定 session 时写回其 title 字段。
  void _applyThreadTitle(String title) {
    _currentThreadTitle = title;
    final session = _session;
    if (session != null) {
      _session = AgentSession(
        id: session.id,
        providerId: session.providerId,
        title: title,
        raw: session.raw,
      );
    }
  }

  /// 首条用户输入的临时展示标题（单行、限长，避免头栏被长 prompt 撑爆）。
  static String _provisionalThreadTitle(String text) {
    final singleLine = text
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (singleLine.length <= 48) {
      return singleLine;
    }
    return '${singleLine.substring(0, 47)}…';
  }

  void _applyThreadRuntimeStatus({
    required AgentThreadRuntimeStatus status,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  }) {
    _threadRuntimeStatus = status;
    // 非 active 时清除等待标志，避免 idle/error 残留旧 waiting 态。
    final isActive = status == AgentThreadRuntimeStatus.active;
    _threadWaitingOnApproval = isActive && waitingOnApproval;
    _threadWaitingOnUserInput = isActive && waitingOnUserInput;
  }

  /// 打开历史时丢弃 provider 报告的 active；无 live 绑定不得显示执行中。
  AgentThreadRuntimeStatus _runtimeStatusWithoutExternalBusy(
    AgentThreadRuntimeStatus status,
  ) {
    return status == AgentThreadRuntimeStatus.active
        ? AgentThreadRuntimeStatus.idle
        : status;
  }

  void _clearThreadRuntimeStatus() {
    _threadRuntimeStatus = null;
    _threadWaitingOnApproval = false;
    _threadWaitingOnUserInput = false;
  }

  void _publishUiChanges(AgentUiUpdateRequest request) {
    _debugLastUiUpdateRequest = request;
    // 保持阶段 3 的统一安全发布边界：命令入口与事件 processor 都只标记刷新，
    // 真正的 ValueNotifier 写入由 AgentUiUpdateScheduler 的安全回调执行。
    _threadSnapshotRefreshPending = true;
    _uiUpdates.publish(request);
  }

  AgentHeaderState _buildHeaderState() {
    final activity = currentActivity;
    return AgentHeaderState(
      title: _currentThreadTitle,
      threadOpenPhase: _threadOpenPhase,
      systemNoticeLabel: _modelRerouteNotice,
      statusCapsuleLabel: threadStatusCapsuleLabel,
      waitingOnApproval: _threadWaitingOnApproval,
      waitingOnUserInput: _threadWaitingOnUserInput,
      showRunningIndicator: showRunningIndicator,
      runningActivityLabel: agentActivitySegmentLabel(activity),
      segmentStartedAt: activity.segmentStartedAt,
      turnStartedAt: _timeline.currentTurnStartedAt,
      tokenUsage: _timeline.currentThreadTokenUsage,
      isTurnRunning: isTurnRunning,
      isReadOnly: isReadOnly,
      canFork: canForkCurrentThread,
      canRename: canRenameCurrentThread,
      canArchive: canArchiveCurrentThread,
      isPlanMode: isPlanMode,
    );
  }

  AgentComposerState _buildComposerState() {
    final modeState = _conversationModeController.state;
    return AgentComposerState(
      canSubmitMessage: canSubmitMessage,
      isTurnRunning: isTurnRunning,
      threadOpenPhase: _threadOpenPhase,
      contextUsage: currentThreadLastTokenUsage,
      isReadOnly: isReadOnly,
      unavailableProviderReason: unavailableProviderReason,
      canAttachImages: canAttachImages,
      canMentionResources: canMentionResources,
      canUseSkills: canUseSkills,
      conversationModeStatus: modeState.status,
      conversationModeOptions: modeState.presets,
      selectedConversationMode: modeState.draftMode,
      conversationModeAppliesToNextTurn: modeState.appliesToNextTurn,
      conversationModeStatusMessage: conversationModeStatusMessage,
      conversationModeContextId: conversationModeContextId,
      showModelSelection: showModelSelection,
      modelConfigState: modelConfigUiState,
      showPermissionPolicy: showPermissionPolicy,
      permissionPolicyLabel: permissionPolicyLabel,
      permissionOptions: _permissionSelectionController.options,
      selectedPermissionOptionId:
          _permissionSelectionController.selectedOptionId,
      permissionApplyScopeHint: _permissionSelectionController.applyScopeHint,
      sessionConfigOptions: sessionConfigOptions,
    );
  }

  AgentPendingInteractionState _buildPendingInteractionState() {
    return AgentPendingInteractionState(
      permissions: _timeline.permissionRequests,
      questions: _timeline.questionRequests,
      planApprovals: _timeline.planApprovalRequests,
      planExecutionHandoff: _planExecutionHandoffController.pendingRequest,
      isReadOnly: isReadOnly,
      autoReviewsByTurnId: _autoReviewsByTurnId,
      latestDeniedAutoReview: _latestDeniedAutoReview,
    );
  }

  AgentExpansionState _buildExpansionState() {
    return AgentExpansionState(
      toolCallIds: _timeline.expandedToolCallIds,
      planMessageIds: _timeline.expandedPlanMessageIds,
      activePlanTurnIds: _timeline.expandedActivePlanTurnIds,
      commandGroupIds: _timeline.expandedCommandGroupIds,
      fileEditItemIds: _timeline.expandedFileEditItemIds,
    );
  }

  AgentConversationHistoryState _buildHistoryState() {
    final standby = _timeline.standbyTurnState;
    return AgentConversationHistoryState(
      standbyTurn: standby != null && standby.entries.isNotEmpty
          ? standby.snapshot()
          : null,
      visibleTurns: _timeline.visibleHistoryTurns,
      threadOpenPhase: _threadOpenPhase,
      providerId: threadProviderId,
      providerKind: activeProviderKind,
      providerName: activeProviderName,
    );
  }

  AgentConversationThreadSnapshot _buildThreadSnapshot() {
    return AgentConversationThreadSnapshot(
      sessionId: sessionId,
      providerId: threadProviderId,
      threadTitle: _currentThreadTitle,
      isTurnRunning: isTurnRunning,
      runtimeStatus: _threadRuntimeStatus,
      waitingOnApproval: _threadWaitingOnApproval,
      waitingOnUserInput: _threadWaitingOnUserInput,
    );
  }

  void _flushPendingStreamChangesNow() {
    _uiUpdates.publish(
      AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate),
    );
  }

  void _publishScheduledUiChanges(AgentUiUpdateRequest request) {
    // Thread snapshot 与局部 listenable 共用安全发布边界，避免 immediate 请求
    // 在 Widget build 中先经 Shell 通知形成同步重入。
    if (_threadSnapshotRefreshPending) {
      _threadSnapshotRefreshPending = false;
      _syncThreadSnapshotListenable();
    }
    _uiStateStore.publish(request);
  }

  /// 将当前 isTurnRunning / runtimeStatus 等推到 [threadSnapshotListenable]。
  void _syncThreadSnapshotListenable() {
    _publishThreadSnapshot(_buildThreadSnapshot());
  }

  void _publishThreadSnapshot(AgentConversationThreadSnapshot snapshot) {
    if (!_disposed && snapshot != _threadSnapshotListenable.value) {
      _threadSnapshotListenable.value = snapshot;
    }
  }
}

final class _AgentConversationEventUiUpdatePort implements AgentUiUpdatePort {
  const _AgentConversationEventUiUpdatePort(this._viewModel);

  final AgentConversationViewModel _viewModel;

  @override
  void publish(AgentUiUpdateRequest request) {
    _viewModel._publishUiChanges(request);
  }
}

final class _AgentConversationEventStateTarget
    implements AgentConversationStateMutationTarget {
  const _AgentConversationEventStateTarget(this._viewModel);

  final AgentConversationViewModel _viewModel;

  @override
  AgentConversationStateMutationOutcome apply(
    AgentConversationStateChange change,
  ) {
    switch (change) {
      case AgentSetProviderStatusChange():
        _viewModel._status = change.status;
      case AgentApplySessionStartedChange():
        final session = change.session;
        final wasCurrentSession = _viewModel._session?.id == session.id;
        _viewModel._session = session;
        _viewModel._restoredSessionId = session.id;
        if (!wasCurrentSession) {
          _viewModel._bindConversationModeThreadPreservingDraft(
            threadId: session.id,
            historyMode:
                _viewModel._conversationModeController.state.confirmedMode,
          );
          _viewModel._conversationModeController.setTurnRunning(
            _viewModel.isTurnRunning,
          );
        }
        _viewModel._threadOpenPhase = AgentThreadOpenPhase.idle;
        _viewModel._requiresResumedSelectedThread = false;
        _viewModel._applySessionTitle(session);
      case AgentApplyThreadRuntimeStatusChange():
        _viewModel._applyThreadRuntimeStatus(
          status: change.status,
          waitingOnApproval: change.waitingOnApproval,
          waitingOnUserInput: change.waitingOnUserInput,
        );
      case AgentApplyThreadNameChange():
        final name = change.threadName?.trim();
        if (name != null && name.isNotEmpty) {
          _viewModel._applyThreadTitle(name);
        }
      case AgentApplyThreadPermissionSettingsChange():
        // data mapper 已将 Codex 私有字段原子解码为中立 selection。settings
        // 只回写事件所属 thread effective，不二次 apply、不持久化 provider 默认。
        unawaited(
          _viewModel._permissionSelectionController.applyThreadSettings(
            threadId: change.threadId,
            permissionSelection: change.permissionSelection,
          ),
        );
      case AgentApplyThreadSettingsChange():
        final event = change.event;
        _viewModel._applyThreadSelectionFromThreadSettings(
          modelId: event.model,
        );
        _viewModel._conversationModeController.applyThreadSettings(event);
      case AgentApplySessionConfigChange():
        _viewModel._sessionConfigOptions = change.options;
        _viewModel._applyThreadSelectionFromSessionConfigOptions(
          change.options,
        );
      case AgentApplyConversationModeChange():
        _viewModel._applyServerConversationMode(change.event);
      case AgentApplyAutoApprovalReviewChange():
        final event = change.event;
        _viewModel._autoReviewsByTurnId[event.turnId] = event;
        if (event.status == 'denied') {
          _viewModel._latestDeniedAutoReview = event;
        } else if (event.status == 'approved' &&
            _viewModel._latestDeniedAutoReview?.reviewId == event.reviewId) {
          _viewModel._latestDeniedAutoReview = null;
        }
      case AgentPrepareTurnCompletedChange():
        return AgentConversationStateMutationOutcome(
          pendingInteractionChanged: _viewModel
              ._updatePlanExecutionRequestForCompletedTurn(change.event),
        );
      case AgentFinalizeTurnStartedChange():
        _viewModel._conversationModeController.setTurnRunning(true);
        _viewModel._consumeActivityDirty();
        _viewModel._syncElapsedTicker();
      case AgentFinalizeTurnCompletedChange():
        _viewModel._conversationModeController.setTurnRunning(
          _viewModel.isTurnRunning,
        );
        _viewModel._modelRerouteNotice = null;
        if (!_viewModel.isTurnRunning &&
            _viewModel._status.state == AgentProviderConnectionState.running) {
          _viewModel._status = AgentProviderStatus(
            state: AgentProviderConnectionState.ready,
            message: '${_viewModel.activeProviderName} ready',
          );
        }
        if (!_viewModel.isTurnRunning &&
            _viewModel._threadRuntimeStatus ==
                AgentThreadRuntimeStatus.active) {
          _viewModel._applyThreadRuntimeStatus(
            status: AgentThreadRuntimeStatus.idle,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          );
        }
        // completed/failed 终态后释放 Binding 活动令牌。
        if (!_viewModel.isTurnRunning) {
          _viewModel._releaseTurnActivity();
        }
        _viewModel._consumeActivityDirty();
        _viewModel._syncElapsedTicker();
      case AgentPrepareInterruptedTurnChange():
        _viewModel._clearThreadRuntimeStatus();
        return AgentConversationStateMutationOutcome(
          pendingInteractionChanged: _viewModel._planExecutionHandoffController
              .clear(),
        );
      case AgentFinalizeInterruptedTurnChange():
        _viewModel._conversationModeController.setTurnRunning(
          _viewModel.isTurnRunning,
        );
        // 取消/中断同样结束 Binding 活动状态。
        if (!_viewModel.isTurnRunning) {
          _viewModel._releaseTurnActivity();
        }
        _viewModel._consumeActivityDirty();
        _viewModel._syncElapsedTicker();
      case AgentApplyToolStatusChange():
        final title = change.toolCall.displayTitle.trim();
        if (title.isNotEmpty) {
          _viewModel._status = AgentProviderStatus(
            state: AgentProviderConnectionState.running,
            message: title.length > 80 ? '${title.substring(0, 80)}…' : title,
          );
        }
      case AgentSetModelRerouteNoticeChange():
        _viewModel._modelRerouteNotice = change.notice;
      case AgentHandleModelListChange():
        _viewModel._applyModelList(change.models);
    }
    return AgentConversationStateMutationOutcome.none;
  }

  @override
  void requestThreadSnapshotRefresh() {
    _viewModel._threadSnapshotRefreshPending = true;
  }
}

const Object _threadModelSelectionUnset = Object();

final class _ThreadModelSelectionPatch {
  const _ThreadModelSelectionPatch({
    this.modelId,
    this.reasoningEffort = _threadModelSelectionUnset,
    this.serviceTierId = _threadModelSelectionUnset,
    this.fastEnabled = _threadModelSelectionUnset,
  });

  final String? modelId;
  final Object? reasoningEffort;
  final Object? serviceTierId;
  final Object? fastEnabled;

  bool get hasAny =>
      (modelId != null && modelId!.isNotEmpty) ||
      !identical(reasoningEffort, _threadModelSelectionUnset) ||
      !identical(serviceTierId, _threadModelSelectionUnset) ||
      !identical(fastEnabled, _threadModelSelectionUnset);
}
