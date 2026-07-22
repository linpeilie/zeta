import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_thread_snapshot.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';
import 'package:zeta/src/features/agent/application/agent_elapsed_ticker.dart';
import 'package:zeta/src/features/agent/application/agent_event_stream_buffer.dart';
import 'package:zeta/src/features/agent/application/agent_provider_event_listener_gate.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/model_config_ui_state.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

export 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';

final _log = loggerFor('zeta.agent.conversation');

/// Agent 面板的状态协调器。
///
/// 当前 ViewModel 只保留 provider/session 协调与事件路由；时间线聚合、
/// 模型选择和局部刷新节流已经下沉到 feature 级应用模块。
class AgentConversationViewModel extends ChangeNotifier {
  AgentConversationViewModel({
    required this.providerController,
    AgentConversationTimelineStore? timelineStore,
    AgentConversationModelSelectionController? modelSelectionController,
    AgentConversationPermissionSelectionController?
    permissionSelectionController,
    this.workspaceFilesProvider,
  }) : _timeline = timelineStore ?? AgentConversationTimelineStore(),
       _ownsModelSelectionController = modelSelectionController == null,
       _modelSelectionController =
           modelSelectionController ??
           AgentConversationModelSelectionController(
             persistSelection: providerController.persistModelSelection,
           ),
       _permissionSelectionController =
           permissionSelectionController ??
           AgentConversationPermissionSelectionController(
             persistSelection: providerController.persistPermissionSelection,
           ) {
    _uiSignals = AgentConversationUiSignals(
      timeline: _timeline,
      onLegacyNotify: _notifyLegacyListeners,
      isDisposed: () => _disposed,
    );
    _modelSelectionController.addListener(_handleModelSelectionChanged);
    providerController.addListener(_handleProviderSettingsChanged);
    _threadSnapshotListenable = ValueNotifier<AgentConversationThreadSnapshot>(
      _buildThreadSnapshot(),
    );
  }

  static const String defaultThreadTitle = 'New thread';

  /// 可选：从 shell 注入工作区文件列表，供 @mention 选择器使用。
  final List<WorkspaceNode> Function()? workspaceFilesProvider;

  final ActiveAgentProviderController providerController;
  final AgentConversationTimelineStore _timeline;
  final bool _ownsModelSelectionController;
  final AgentConversationModelSelectionController _modelSelectionController;
  final AgentConversationPermissionSelectionController
  _permissionSelectionController;
  late final AgentConversationUiSignals _uiSignals;
  final AgentElapsedTicker _elapsedTicker = AgentElapsedTicker();
  late final ValueNotifier<AgentConversationThreadSnapshot>
  _threadSnapshotListenable;

  AgentProvider? _provider;
  StreamSubscription<AgentEvent>? _eventSubscription;
  AgentEventStreamBuffer? _eventBuffer;
  final AgentProviderEventListenerGate _eventListenerGate =
      AgentProviderEventListenerGate();

  AgentSession? _session;
  String? _projectPath;
  String? _contextFilePath;

  String? _restoredSessionId;
  String? _selectedProviderId;
  AgentThreadOpenPhase _threadOpenPhase = AgentThreadOpenPhase.idle;
  bool _requiresResumedSelectedThread = false;
  Future<void>? _settingsLoadFuture;
  bool _disposed = false;
  int _threadSwitchToken = 0;

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

  /// 是否正在执行上下文压缩。
  bool _isCompacting = false;

  /// 上下文详情面板是否展开（头栏「上下文」菜单触发）。
  final ValueNotifier<bool> contextPanelVisible = ValueNotifier<bool>(false);

  /// 当前线程的创建时间；仅从恢复的 thread 摘要填充，新会话为空。
  DateTime? _threadCreatedAt;

  /// 当前线程的最后活跃时间；优先取摘要的 recency，否则 updatedAt。
  DateTime? _threadLastActiveAt;

  /// 本会话已展示过的弃用 summary，避免重复刷屏。
  final Set<String> _shownDeprecationSummaries = <String>{};

  /// 按 turnId 跟踪 Guardian 自动评审状态。
  final Map<String, AgentAutoApprovalReviewEvent> _autoReviewsByTurnId =
      <String, AgentAutoApprovalReviewEvent>{};

  /// 最近一次被拒绝的自动评审（供放行按钮使用）。
  AgentAutoApprovalReviewEvent? _latestDeniedAutoReview;

  /// 上下文占用达到该比例时提示压缩。
  static const double contextCompactThreshold = 0.85;

  /// 本地时间线条目单调序号；避免 Windows 上 DateTime 仅毫秒精度导致 id 碰撞。
  int _localTimelineIdSeq = 0;

  List<AgentConversationMessage> get messages => _timeline.messages;

  List<AgentToolCall> get toolCalls => _timeline.toolCalls;

  List<AgentPermissionRequest> get permissionRequests =>
      _timeline.permissionRequests;

  List<AgentPlanApprovalRequest> get planApprovalRequests =>
      _timeline.planApprovalRequests;

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
      planApprovalRequests.isEmpty &&
      !threadWaitingOnApproval &&
      !threadWaitingOnUserInput;

  bool get hasOlderTurns => _timeline.hasOlderTurns;

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

  int get autoScrollTick => _uiSignals.autoScrollTick;

  int get historyVersion => _uiSignals.historyVersion;

  int get headerVersion => _uiSignals.headerVersion;

  int get composerVersion => _uiSignals.composerVersion;

  /// 待处理权限、提问或计划审批列表的变更版本。
  int get pendingInteractionVersion => _uiSignals.pendingInteractionVersion;

  int get expansionVersion => _uiSignals.expansionVersion;

  ValueListenable<int> get historyVersionListenable =>
      _uiSignals.historyVersionListenable;

  ValueListenable<int> get headerVersionListenable =>
      _uiSignals.headerVersionListenable;

  ValueListenable<int> get composerVersionListenable =>
      _uiSignals.composerVersionListenable;

  /// 供固定交互区监听 pending 列表，避免依赖消息流刷新。
  ValueListenable<int> get pendingInteractionVersionListenable =>
      _uiSignals.pendingInteractionVersionListenable;

  ValueListenable<int> get expansionVersionListenable =>
      _uiSignals.expansionVersionListenable;

  ValueListenable<int> get autoScrollTickListenable =>
      _uiSignals.autoScrollTickListenable;

  ValueListenable<AgentConversationTurnState?> get liveTurnListenable =>
      _timeline.liveTurnListenable;

  String? get projectPath => _projectPath;

  String? get contextFilePath => _contextFilePath;

  String get activeProviderId => providerController.activeProviderId;

  String get activeProviderName => providerController.activeProviderName;

  AgentProviderKind get activeProviderKind =>
      providerController.activeProviderConfig.kind;

  /// 当前 thread 所属 provider 的能力；未绑定实例时回退到 kind 的保守静态能力。
  AgentProviderCapabilities get activeCapabilities {
    final providerId =
        _session?.providerId ?? _selectedProviderId ?? activeProviderId;
    final provider = _provider;
    if (provider != null && provider.config.id == providerId) {
      return provider.capabilities;
    }
    return providerController.capabilitiesForProviderId(providerId);
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

  /// Provider 支持会话级审批/沙箱策略时显示选择器。
  bool get showPermissionPolicy =>
      activeCapabilities.supportsPermissionPolicySelection;

  /// Provider 支持模型切换时显示模型选择器。
  bool get showModelSelection => activeCapabilities.supportsModelSelection;

  bool get canAttachImages => activeCapabilities.supportsLocalImageInput;

  bool get canMentionResources => activeCapabilities.supportsResourceInput;

  bool get canRenameCurrentThread =>
      sessionId != null && !isReadOnly && activeCapabilities.canRenameThread;

  bool get canArchiveCurrentThread =>
      sessionId != null && !isReadOnly && activeCapabilities.canArchiveThread;

  bool get canForkCurrentThread =>
      sessionId != null &&
      canSubmitMessage &&
      !isTurnRunning &&
      activeCapabilities.canForkThread;

  bool get canCompactCurrentThread =>
      sessionId != null &&
      !_isCompacting &&
      !isTurnRunning &&
      !isReadOnly &&
      activeCapabilities.canCompactThread;

  /// 可切换的全局 provider 列表（已启用）。
  List<AgentProviderConfig> get availableProviders =>
      providerController.enabledProviders;

  /// 切换 active provider（双后端共存）。
  Future<void> switchActiveProvider(String providerId) async {
    if (providerId == activeProviderId) {
      return;
    }
    _flushPendingStreamChangesNow();
    _invalidateProviderEventListener();
    await providerController.setActiveProvider(providerId);
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _provider = null;
    final config = providerController.activeProviderConfig;
    _modelSelectionController.resetForProvider(config);
    _permissionSelectionController.resetForProvider(config);
    // 切换后清空当前会话草稿，避免跨协议 thread id 混用。
    _session = null;
    _sessionConfigOptions = const <AgentSessionConfigOption>[];
    _restoredSessionId = null;
    _selectedProviderId = providerId;
    _requiresResumedSelectedThread = false;
    _timeline.clearConversation();
    _modelRerouteNotice = null;
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.connecting,
      message: 'Loading $activeProviderName',
    );
    _publishUiChanges(
      history: true,
      syncLiveTurn: true,
      header: true,
      composer: true,
    );
    await loadModels();
  }

  AgentPermissionSelection get permissionSelection =>
      _permissionSelectionController.selection;

  String get permissionPolicyLabel =>
      _permissionSelectionController.displayLabel;

  AgentAutoApprovalReviewEvent? get latestDeniedAutoReview =>
      _latestDeniedAutoReview;

  /// 当前回合的自动评审状态（若有）。
  AgentAutoApprovalReviewEvent? autoReviewForTurn(String? turnId) {
    if (turnId == null) {
      return null;
    }
    return _autoReviewsByTurnId[turnId];
  }

  /// 供 @mention 选择器使用的工作区文件（已扁平化）。
  List<WorkspaceNode> mentionCandidateFiles({String query = ''}) {
    final roots = workspaceFilesProvider?.call() ?? const <WorkspaceNode>[];
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

    for (final root in roots) {
      walk(root);
    }
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return List<WorkspaceNode>.unmodifiable(files.take(40));
    }
    return List<WorkspaceNode>.unmodifiable(
      files
          .where(
            (file) =>
                file.name.toLowerCase().contains(trimmed) ||
                file.path.toLowerCase().contains(trimmed),
          )
          .take(40),
    );
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

  /// 共享 1 秒时钟；header/卡片用其计算 live elapsed。
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

  AgentTokenUsage? get currentTurnTokenUsage => _timeline.currentTurnTokenUsage;

  AgentTokenUsage? get currentThreadTokenUsage =>
      _timeline.currentThreadTokenUsage;

  /// 当前 thread 最近一次请求的 token 用量。
  AgentTokenUsage? get currentThreadLastTokenUsage =>
      _timeline.currentThreadLastTokenUsage;

  /// 当前上下文窗口占用比例（0~1）；基于最近一次请求的 token 用量计算。
  double? get contextWindowUsageRatio {
    final usage = currentThreadLastTokenUsage;
    final total = usage?.totalTokens;
    final window = usage?.modelContextWindow;
    if (total == null || window == null || window <= 0) {
      return null;
    }
    return (total / window).clamp(0.0, 1.0);
  }

  /// 是否应展示「压缩上下文」入口。
  bool get shouldOfferContextCompact {
    final ratio = contextWindowUsageRatio;
    return activeCapabilities.canCompactThread &&
        ratio != null &&
        ratio >= contextCompactThreshold;
  }

  /// 是否正在压缩上下文。
  bool get isCompacting => _isCompacting;

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
    if (!activeCapabilities.canForkThreadAtTurn ||
        !canSubmitMessage ||
        isTurnRunning ||
        _isCompacting) {
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

  bool loadOlderTurns() {
    final changed = _timeline.loadOlderTurns();
    if (changed) {
      _publishUiChanges(history: true);
    }
    return changed;
  }

  void toggleToolCall(String toolCallId) {
    _timeline.toggleToolCall(toolCallId);
    _publishUiChanges(expansion: true);
  }

  void togglePlanMessage(String messageId) {
    _timeline.togglePlanMessage(messageId);
    _publishUiChanges(expansion: true);
  }

  void toggleActivePlan(String turnId) {
    _timeline.toggleActivePlan(turnId);
    _publishUiChanges(expansion: true);
  }

  void toggleCommandGroup(String commandGroupId) {
    _timeline.toggleCommandGroup(commandGroupId);
    _publishUiChanges(expansion: true);
  }

  void toggleFileEditItem(String fileEditItemId) {
    _timeline.toggleFileEditItem(fileEditItemId);
    _publishUiChanges(expansion: true);
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
      _log.fine('Loaded Agent provider settings: $activeProviderId');
    } catch (error) {
      _log.warning(
        'Could not load Agent provider settings (${error.runtimeType})',
      );
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.error,
        message: 'Could not load Agent providers',
        details: error.toString(),
      );
    }
    _publishUiChanges();
  }

  /// 预加载模型列表。
  ///
  /// 在 IDE 启动时调用，触发 provider initialize 握手并拉取 `model/list`，
  /// 使输入框下方的模型/思考/速率控件在用户发送消息前就可用。
  Future<void> loadModels() async {
    await loadSettings();
    if (!providerController.hasRuntimeProvider) {
      _modelsRefreshing = false;
      _modelRefreshError = null;
      _publishUiChanges(composer: true);
      return;
    }
    final config = providerController.activeProviderConfig;
    _modelSelectionController.seedFromConfig(config);
    _permissionSelectionController.seedFromConfig(config);
    final capabilities = providerController.capabilitiesForProviderId(
      config.id,
    );
    final bootstrapPolicy = capabilities.bootstrapPolicy;
    if (!bootstrapPolicy.allowsEagerModelPreload) {
      _log.fine(
        'Deferring ${config.displayName} preload until session bootstrap',
      );
      _publishUiChanges(composer: true);
      return;
    }
    final hasWorkspace = _projectPath?.trim().isNotEmpty ?? false;
    if (bootstrapPolicy.requiresWorkspace && !hasWorkspace) {
      _log.fine(
        'Deferring ${config.displayName} preload until a workspace is ready',
      );
      _publishUiChanges(composer: true);
      return;
    }
    _modelsRefreshing = true;
    _modelRefreshError = null;
    _publishUiChanges(composer: true);
    try {
      final provider = await _ensureProvider();
      await provider.initialize();
      await _replaceProviderEventSubscription(
        provider,
        threadId: _selectedThreadId,
      );
      final modelCatalog = provider.bundle.modelCatalog;
      if (_modelSelectionController.modelList == null && modelCatalog != null) {
        final models = await modelCatalog.listModels();
        _handleModelList(models);
      }
      await _permissionSelectionController.refreshProfiles();
    } catch (error) {
      _log.warning('Could not preload Agent models (${error.runtimeType})');
      _modelRefreshError = '模型列表刷新失败，已保留现有配置。';
    } finally {
      _modelsRefreshing = false;
      _publishUiChanges(composer: true);
    }
  }

  Future<bool> selectModel(String modelId) =>
      _modelSelectionController.selectModel(modelId);

  Future<bool> selectReasoningEffort(String? effort) =>
      _modelSelectionController.selectReasoningEffort(effort);

  Future<void> selectPermissionPreset(AgentPermissionPreset preset) async {
    await _permissionSelectionController.selectPreset(preset);
    _publishUiChanges(composer: true);
  }

  /// Guardian 拒绝后的人工放行。
  Future<void> approveGuardianDeniedAction() async {
    final review = _latestDeniedAutoReview;
    final threadId = review?.threadId ?? sessionId;
    if (review == null || threadId == null) {
      return;
    }
    try {
      final provider = await _ensureProvider();
      final interactions = provider.bundle.interactions;
      if (interactions == null) {
        return;
      }
      await interactions.approveGuardianDeniedAction(
        threadId: threadId,
        event: review.raw,
      );
      _latestDeniedAutoReview = null;
      _publishUiChanges(header: true, liveTurn: true);
    } catch (error) {
      _log.warning(
        'Could not approve guardian-denied action (${error.runtimeType})',
      );
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
    final provider = _provider;
    final sessionConfiguration = provider?.bundle.sessionConfiguration;
    if (sessionId == null || sessionConfiguration == null) {
      return;
    }
    try {
      await sessionConfiguration.setSessionConfigOption(
        sessionId: sessionId,
        configId: configId,
        value: value,
      );
    } catch (error) {
      _log.warning(
        'Could not update Agent session config $configId '
        '(${error.runtimeType})',
      );
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.error,
        message: 'Could not update session option',
        details: error.toString(),
      );
      _publishUiChanges(header: true, composer: true);
    }
  }

  void _handleModelList(AgentModelList modelList) {
    _modelRefreshError = null;
    _modelSelectionController.handleModelList(modelList);
    _publishUiChanges(composer: true);
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

  /// 更新当前项目和文件上下文。
  ///
  /// 项目变更时清空内存中的 session/turn；如果恢复状态里带了 thread id，则保留到
  /// 第一次发送消息时再调用 provider resume。恢复 thread 时必须同时提供
  /// [restoredProviderId]，禁止回退到当前 active provider 猜测归属。
  ///
  /// 仅更新当前文件路径时，不得清掉「已选中 thread 必须 resume」约束，
  /// 否则 Grok 等会话在 `session/load` 失败时会误走 `startSession` 开新会话。
  void updateWorkspace({
    required String? projectPath,
    required String? contextFilePath,
    String? restoredSessionId,
    String? restoredProviderId,
    bool resetConversation = false,
  }) {
    final projectChanged = projectPath != _projectPath;
    final normalizedProviderId = restoredProviderId?.trim();
    final hasRestoredProvider =
        normalizedProviderId != null && normalizedProviderId.isNotEmpty;
    final canRestoreSession = restoredSessionId == null || hasRestoredProvider;
    final effectiveRestoredSessionId = canRestoreSession
        ? restoredSessionId
        : null;
    if (!canRestoreSession) {
      _log.warning(
        'Ignoring restored Agent session $restoredSessionId without provider ownership',
      );
    }
    _projectPath = projectPath;
    _contextFilePath = contextFilePath;
    if (projectChanged || resetConversation) {
      // 离开当前会话时取消订阅；恢复到另一 thread 时也退订旧 id。
      final previousThreadId = _selectedThreadId;
      _flushPendingStreamChangesNow();
      _invalidateProviderEventListener();
      _threadSwitchToken += 1;
      _session = null;
      _sessionConfigOptions = const <AgentSessionConfigOption>[];
      _restoredSessionId = effectiveRestoredSessionId;
      _selectedProviderId = effectiveRestoredSessionId == null
          ? null
          : normalizedProviderId;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
      _currentThreadTitle = defaultThreadTitle;
      _status = const AgentProviderStatus.idle();
      _clearThreadRuntimeStatus();
      _modelRerouteNotice = null;
      _threadCreatedAt = null;
      _threadLastActiveAt = null;
      contextPanelVisible.value = false;
      _timeline.resetToWelcomeState();
      _consumeActivityDirty();
      _syncElapsedTicker();
      if (previousThreadId != null &&
          previousThreadId != effectiveRestoredSessionId) {
        final provider = _provider;
        if (provider != null) {
          unawaited(_unsubscribeThreadBestEffort(provider, previousThreadId));
        }
      }
      _publishUiChanges(
        history: true,
        syncLiveTurn: true,
        header: true,
        composer: true,
      );
      return;
    }
    // 同项目下仅同步文件上下文：若 shell 带了 restoredSessionId，只在本地
    // 尚无选中 thread 时写入，避免覆盖 switchThread 已锁定的 resume 目标。
    if (effectiveRestoredSessionId != null && _selectedThreadId == null) {
      _invalidateProviderEventListener();
      _restoredSessionId = effectiveRestoredSessionId;
      _selectedProviderId = normalizedProviderId;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
    }
    _publishUiChanges(header: true, composer: true);
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
    if ((trimmed.isEmpty && imagePaths.isEmpty && resolvedMentions.isEmpty) ||
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
    );
    final clientUserMessageId = _nextClientUserMessageId();

    final isNewTurn = runningTurnId == null;
    if (isNewTurn) {
      // 在发送瞬间冻结本回合模型配置，避免 footer 被后续改配置污染。
      _timeline.startPendingLiveTurn(modelConfig: _currentTurnModelConfig());
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
      syncLiveTurn: true,
      liveTurn: true,
      header: true,
      composer: true,
      autoScroll: true,
    );

    try {
      await loadSettings();
      // 已选中 thread 时必须落到该 thread 所属 provider，避免用 Codex 去 resume Grok id。
      final provider = await _ensureProvider(
        preferredProviderId: _selectedProviderId,
      );
      final context = AgentContext(
        projectPath: _projectPath,
        filePath: _contextFilePath,
      );
      final session = await _ensureSession(
        provider,
        context,
        switchToken: switchToken,
        expectedThreadId: selectedThreadId,
      );
      final conversation = provider.bundle.conversation;
      // 新会话在 Grok 异步 generated_title 出现前，先用首条用户消息作临时标题。
      if (_isStillSelectedThread(switchToken, session.id) &&
          _currentThreadTitle == defaultThreadTitle &&
          trimmed.isNotEmpty) {
        _applyThreadTitle(_provisionalThreadTitle(trimmed));
        _publishUiChanges(header: true);
      }
      _log.info('Sending Agent request with provider ${provider.config.id}');
      if (isNewTurn) {
        final turn = await conversation.sendMessage(
          session: session,
          inputs: inputs,
          context: context,
          clientUserMessageId: clientUserMessageId,
        );
        final pendingId = _timeline.pendingTurnGroupId;
        if (pendingId != null &&
            _isStillSelectedThread(switchToken, session.id)) {
          _timeline.beginLiveTurnGroup(turn);
          _publishUiChanges(
            syncLiveTurn: true,
            liveTurn: true,
            header: true,
            composer: true,
          );
        }
      } else {
        final turnSteering = provider.bundle.turnSteering;
        if (turnSteering == null) {
          throw UnsupportedError(
            '${provider.config.displayName} does not support steering turns',
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
    } on ProcessException catch (error) {
      _log.warning(
        'Agent provider process failed (errorCode=${error.errorCode})',
      );
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _failPendingLiveTurn();
      _markUnavailable(error.message, details: error.toString());
    } on UnsupportedError catch (error) {
      _log.warning('Unsupported Agent provider (${error.runtimeType})');
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _failPendingLiveTurn();
      _markError(error.message ?? 'Provider is not supported');
    } catch (error) {
      _log.warning('Agent request failed (${error.runtimeType})');
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _failPendingLiveTurn();
      _markError('Agent request failed', details: error.toString());
    } finally {
      _timeline.clearPendingTurnGroupId();
    }
  }

  /// 取消正在运行的回合。
  Future<void> cancelActiveTurn() async {
    final provider = _provider;
    final turnId = _timeline.selectedCancelableTurnId();
    final sessionId = _selectedThreadId;
    if (turnId == null || sessionId == null || provider == null) {
      return;
    }
    _log.info('Cancelling Agent turn $turnId');
    await provider.bundle.conversation.cancelTurn(
      AgentTurn(id: turnId, sessionId: sessionId),
    );
  }

  /// 切换到项目列表中选中的 thread。
  Future<void> switchThread(AgentThreadSummary thread) async {
    final switchToken = ++_threadSwitchToken;
    // 在第一个 await 前让旧 thread listener 失效，避免其微任务事件污染新时间线。
    _invalidateProviderEventListener();
    // Provider 配置可能仍在应用启动阶段读取；必须等待其完成后再判断 thread 归属，
    // 否则会先看到内置 Codex、随后却从磁盘加载出 Grok，并用错误后端读取历史。
    await loadSettings();
    if (!_isCurrentSwitch(switchToken)) {
      return;
    }
    // 跨 provider thread：先切 active backend，再加载历史。
    // 失败必须 fail-closed，禁止用错误 provider 读历史 / 后续 resume。
    if (thread.providerId != activeProviderId) {
      final canSwitch = availableProviders.any(
        (provider) => provider.id == thread.providerId,
      );
      if (!canSwitch) {
        _session = null;
        _sessionConfigOptions = const <AgentSessionConfigOption>[];
        _restoredSessionId = thread.id;
        _selectedProviderId = thread.providerId;
        _requiresResumedSelectedThread = true;
        _threadOpenPhase = AgentThreadOpenPhase.openFailed;
        _currentThreadTitle = thread.displayName;
        _timeline.clearConversation();
        final unavailable = providerController.unavailableReasonForProviderId(
          thread.providerId,
        );
        if (unavailable != null) {
          _markUnavailable('Cursor Agent unavailable', details: unavailable);
        } else {
          _markError(
            'Could not open thread',
            details:
                'Provider ${thread.providerId} is not enabled; history is read-only or unavailable.',
          );
        }
        return;
      }
      try {
        await switchActiveProvider(thread.providerId);
      } catch (error) {
        if (!_isCurrentSwitch(switchToken)) {
          return;
        }
        _log.warning(
          'Could not switch provider to ${thread.providerId} for thread '
          '${thread.id} (${error.runtimeType})',
        );
        _session = null;
        _sessionConfigOptions = const <AgentSessionConfigOption>[];
        _restoredSessionId = thread.id;
        _selectedProviderId = thread.providerId;
        _requiresResumedSelectedThread = true;
        _threadOpenPhase = AgentThreadOpenPhase.openFailed;
        _currentThreadTitle = thread.displayName;
        _timeline.clearConversation();
        _markError(
          'Could not switch Agent provider',
          details: error.toString(),
        );
        return;
      }
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
    }
    // 离开旧会话时先记下 id，切走后取消服务端订阅，减少无关通知。
    final previousThreadId = _selectedThreadId;
    _flushPendingStreamChangesNow();
    _session = null;
    _sessionConfigOptions = const <AgentSessionConfigOption>[];
    _restoredSessionId = thread.id;
    _selectedProviderId = thread.providerId;
    _requiresResumedSelectedThread = true;
    _threadOpenPhase = AgentThreadOpenPhase.loadingHistory;
    _currentThreadTitle = thread.displayName;
    _threadCreatedAt = thread.createdAt;
    _threadLastActiveAt = thread.lastActiveAt;
    _applyThreadRuntimeStatus(
      status: thread.status,
      waitingOnApproval: thread.waitingOnApproval,
      waitingOnUserInput: thread.waitingOnUserInput,
    );
    _timeline.clearConversation();
    _modelRerouteNotice = null;
    _status = const AgentProviderStatus(
      state: AgentProviderConnectionState.connecting,
      message: 'Loading history',
    );
    _publishUiChanges(
      history: true,
      syncLiveTurn: true,
      header: true,
      composer: true,
    );

    try {
      await loadSettings();
      final provider = await _ensureProvider(
        preferredProviderId: thread.providerId,
      );
      if (previousThreadId != null && previousThreadId != thread.id) {
        // 不阻塞历史加载：退订失败只记日志。
        unawaited(_unsubscribeThreadBestEffort(provider, previousThreadId));
      }
      final threadCatalog = provider.bundle.threadCatalog;
      if (threadCatalog == null) {
        throw UnsupportedError(
          '${provider.config.displayName} does not support thread history',
        );
      }
      final history = await threadCatalog.readThreadHistory(
        threadId: thread.id,
        sessionPath: thread.sessionPath,
        projectPath: thread.projectPath,
      );
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      await _replaceProviderEventSubscription(provider, threadId: thread.id);
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _timeline.applyHistorySnapshot(history, thread);
      _applyThreadSelectionFromHistory(history);
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
        history: true,
        syncLiveTurn: true,
        header: true,
        composer: true,
        autoScroll: true,
      );
    } catch (error) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _threadOpenPhase = AgentThreadOpenPhase.openFailed;
      _log.warning(
        'Could not load Agent thread history ${thread.id} '
        '(${error.runtimeType})',
      );
      _markError('Could not load thread history', details: error.toString());
    }
  }

  /// 处理审批卡片的 approve/deny / 结构化答案。
  ///
  /// UI 先移除卡片，再异步回写 provider，避免按钮点击后卡片停留造成重复提交。
  Future<void> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    Map<String, List<String>> answers = const <String, List<String>>{},
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const <String>[],
  }) async {
    _timeline.removePermissionRequest(request.id);
    _publishUiChanges(history: true, liveTurn: true, pendingInteraction: true);
    _log.info(
      'Responding to Agent permission ${request.kind.name}: approved=$approved',
    );
    final interactions = _provider?.bundle.interactions;
    if (interactions == null) {
      return;
    }
    await interactions.respondToPermission(
      AgentPermissionDecision(
        requestId: request.id,
        approved: approved,
        cancelTurn: cancelTurn,
        answers: answers,
        commandDecision: commandDecision,
        execpolicyAmendment: execpolicyAmendment,
      ),
    );
  }

  Future<void> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind,
  ) async {
    _timeline.removePlanApprovalRequest(request.id);
    _publishUiChanges(history: true, liveTurn: true, pendingInteraction: true);
    final planApproval = _provider?.bundle.planApproval;
    if (planApproval == null) {
      return;
    }
    await planApproval.respondToPlanApproval(
      AgentPlanApprovalDecision(requestId: request.id, kind: kind),
    );
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
    _publishUiChanges(header: true, composer: true);

    try {
      final provider = await _ensureProvider();
      final threadBranching = provider.bundle.threadBranching;
      if (threadBranching == null) {
        throw UnsupportedError(
          '${provider.config.displayName} does not support thread branching',
        );
      }
      final session = await threadBranching.forkThread(
        threadId: threadId,
        context: AgentContext(
          projectPath: _projectPath,
          filePath: _contextFilePath,
        ),
        boundary: AgentForkThroughTurn(boundaryTurnId),
      );
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      final summary = AgentThreadSummary(
        id: session.id,
        providerId: session.providerId,
        projectPath: _projectPath ?? '',
        title: session.title,
        preview: session.title ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: AgentThreadRuntimeStatus.idle,
      );
      await switchThread(summary);
      if (sessionId != session.id ||
          _threadOpenPhase != AgentThreadOpenPhase.idle) {
        return;
      }
      await sendMessage(trimmed);
    } catch (error) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _log.warning(
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
      final provider = await _ensureProvider();
      final threadBranching = provider.bundle.threadBranching;
      if (threadBranching == null) {
        throw UnsupportedError(
          '${provider.config.displayName} does not support thread branching',
        );
      }
      final session = await threadBranching.forkThread(
        threadId: threadId,
        context: AgentContext(
          projectPath: _projectPath,
          filePath: _contextFilePath,
        ),
      );
      if (!_isCurrentSwitch(switchToken)) {
        return session;
      }
      await switchThread(
        AgentThreadSummary(
          id: session.id,
          providerId: session.providerId,
          projectPath: _projectPath ?? '',
          title: session.title,
          preview: session.title ?? '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      return session;
    } catch (error) {
      _log.warning('Could not fork thread $threadId (${error.runtimeType})');
      _markError('Could not fork thread', details: error.toString());
      return null;
    }
  }

  /// 启动上下文压缩。
  Future<void> compactCurrentThread() async {
    final threadId = sessionId;
    if (threadId == null || !canCompactCurrentThread) {
      return;
    }
    _isCompacting = true;
    _publishUiChanges(header: true, composer: true);
    try {
      final provider = await _ensureProvider();
      final threadMutations = provider.bundle.threadMutations;
      if (threadMutations == null) {
        throw UnsupportedError(
          '${provider.config.displayName} does not support compacting threads',
        );
      }
      await threadMutations.compactThread(threadId);
    } catch (error) {
      _isCompacting = false;
      _log.warning('Could not compact thread $threadId (${error.runtimeType})');
      _markError('Could not compact context', details: error.toString());
      _publishUiChanges(header: true, composer: true);
    }
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
    _publishUiChanges(header: true);
    try {
      final provider = await _ensureProvider();
      final threadMutations = provider.bundle.threadMutations;
      if (threadMutations == null) {
        throw UnsupportedError(
          '${provider.config.displayName} does not support renaming threads',
        );
      }
      await threadMutations.renameThread(threadId: threadId, name: trimmed);
    } catch (error) {
      if (sessionId == threadId && _currentThreadTitle == trimmed) {
        _applyThreadTitle(previousTitle);
        _publishUiChanges(header: true);
      }
      _log.warning('Could not rename thread $threadId (${error.runtimeType})');
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
      final provider = await _ensureProvider();
      final threadMutations = provider.bundle.threadMutations;
      if (threadMutations == null) {
        throw UnsupportedError(
          '${provider.config.displayName} does not support archiving threads',
        );
      }
      await threadMutations.archiveThread(threadId);
    } catch (error) {
      _log.warning('Could not archive thread $threadId (${error.runtimeType})');
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
    _publishUiChanges(header: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateProviderEventListener();
    providerController.removeListener(_handleProviderSettingsChanged);
    _modelSelectionController.removeListener(_handleModelSelectionChanged);
    if (_ownsModelSelectionController) {
      _modelSelectionController.dispose();
    }
    _elapsedTicker.dispose();
    _uiSignals.dispose();
    _threadSnapshotListenable.dispose();
    contextPanelVisible.dispose();
    unawaited(_eventSubscription?.cancel());
    _timeline.dispose();
    super.dispose();
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

  void _handleProviderSettingsChanged() {
    if (_disposed) {
      return;
    }
    _publishUiChanges(header: true, composer: true);
  }

  void _handleModelSelectionChanged() {
    if (_disposed) {
      return;
    }
    _publishUiChanges(composer: true);
  }

  /// 确保拿到正确的共享 provider 实例。
  ///
  /// [preferredProviderId] 非空且与当前 active 不同时，会先切换 active（不清理
  /// 时间线），再绑定事件流。用于「已打开 Grok thread 却仍挂在 Codex」等错位场景。
  Future<AgentProvider> _ensureProvider({String? preferredProviderId}) async {
    final targetId = preferredProviderId?.trim();
    if (targetId != null &&
        targetId.isNotEmpty &&
        targetId != activeProviderId) {
      await _bindActiveProviderWithoutClearingConversation(targetId);
    }

    final provider = await providerController.activeProvider();
    if (targetId != null &&
        targetId.isNotEmpty &&
        provider.config.id != targetId) {
      // 配置在异步获取 provider 期间发生变化时 fail-closed，禁止把 thread id
      // 和 sessionPath 交给错误协议的历史读取器。
      throw StateError(
        'Expected provider $targetId but received ${provider.config.id}',
      );
    }
    if (identical(_provider, provider) &&
        _hasCurrentProviderEventListener(
          provider,
          threadId: _selectedThreadId,
        )) {
      return provider;
    }

    if (!identical(_provider, provider)) {
      _log.fine('Using shared Agent provider: ${provider.config.id}');
      _provider = provider;
      _modelSelectionController.bindProvider(provider);
      _permissionSelectionController.bindProvider(provider);
    }
    await _replaceProviderEventSubscription(
      provider,
      threadId: _selectedThreadId,
    );
    return provider;
  }

  /// 切换 active provider，但保留当前时间线与待 resume 的 thread id。
  ///
  /// 与 [switchActiveProvider] 不同：后者面向「用户主动换后端」会清空对话；
  /// 本方法面向「已打开 thread 后纠偏到正确 backend」。
  Future<void> _bindActiveProviderWithoutClearingConversation(
    String providerId,
  ) async {
    if (providerId == activeProviderId) {
      return;
    }
    final enabled = availableProviders.any(
      (provider) => provider.id == providerId,
    );
    if (!enabled) {
      throw StateError('Provider $providerId is not enabled');
    }
    _log.info(
      'Rebinding active provider to $providerId without clearing conversation',
    );
    _invalidateProviderEventListener();
    await providerController.setActiveProvider(providerId);
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _provider = null;
    // 旧 backend 上的 live session 不可复用。
    _session = null;
    _sessionConfigOptions = const <AgentSessionConfigOption>[];
    final config = providerController.activeProviderConfig;
    _modelSelectionController.resetForProvider(config);
    _permissionSelectionController.resetForProvider(config);
    _selectedProviderId ??= providerId;
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
    _publishUiChanges(
      history: true,
      syncLiveTurn: true,
      header: true,
      composer: true,
    );
  }

  Future<AgentSession> _ensureSession(
    AgentProvider provider,
    AgentContext context, {
    required int switchToken,
    required String? expectedThreadId,
  }) async {
    final existing = _session;
    if (existing != null) {
      return existing;
    }

    final restoredSessionId = _restoredSessionId;
    if (restoredSessionId != null) {
      try {
        _log.fine('Resuming Agent session $restoredSessionId');
        final session = await provider.bundle.conversation.resumeSession(
          restoredSessionId,
          context: context,
        );
        if (_isStillSelectedThread(switchToken, expectedThreadId)) {
          await _replaceProviderEventSubscription(
            provider,
            threadId: session.id,
          );
        }
        if (_isStillSelectedThread(switchToken, expectedThreadId)) {
          _session = session;
          _restoredSessionId = session.id;
          _threadOpenPhase = AgentThreadOpenPhase.idle;
          _requiresResumedSelectedThread = false;
          _applySessionTitle(session);
          _publishUiChanges(header: true, composer: true);
        }
        return session;
      } catch (error) {
        _log.warning(
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

    _log.fine('Starting new Agent session with provider ${provider.config.id}');
    final session = await provider.bundle.conversation.startSession(
      context: context,
    );
    if (_isStillSelectedThread(switchToken, expectedThreadId)) {
      await _replaceProviderEventSubscription(provider, threadId: session.id);
    }
    if (_isStillSelectedThread(switchToken, expectedThreadId)) {
      _session = session;
      _restoredSessionId = session.id;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
      _applySessionTitle(session);
      _publishUiChanges(header: true, composer: true);
    }
    return session;
  }

  AgentRuntimeScope? _runtimeScopeOf(AgentProvider provider) {
    return provider.bundle.runtime.runtimeScope;
  }

  bool _hasCurrentProviderEventListener(
    AgentProvider provider, {
    required String? threadId,
  }) {
    final scope = _eventListenerGate.current;
    if (scope == null ||
        scope.providerId != provider.config.id ||
        scope.threadId != threadId) {
      return false;
    }
    final expectedRuntime = scope.runtimeScope;
    final currentRuntime = _runtimeScopeOf(provider);
    if (expectedRuntime == null) {
      // Provider 尚未创建 runtime；首个事件会把 scope 绑定到实际连接。
      return true;
    }
    return expectedRuntime == currentRuntime;
  }

  /// 先安装新 listener，再异步取消旧 listener；代次门保证重叠窗口内只消费新事件。
  Future<void> _replaceProviderEventSubscription(
    AgentProvider provider, {
    required String? threadId,
  }) async {
    if (_disposed) {
      return;
    }
    final previousSubscription = _eventSubscription;
    final previousBuffer = _eventBuffer;
    final scope = _eventListenerGate.activate(
      providerId: provider.config.id,
      threadId: threadId,
      runtimeScope: _runtimeScopeOf(provider),
    );
    final buffer = AgentEventStreamBuffer(
      onEvent: (event) {
        if (_disposed || !identical(_provider, provider)) {
          return;
        }
        if (!_eventListenerGate.accepts(
          scope,
          currentRuntimeScope: _runtimeScopeOf(provider),
          allowDetachedRuntime: _isCriticalDetachedEvent(event),
        )) {
          return;
        }
        _handleEvent(event);
      },
      onBackpressure: (pendingEventCount) {
        // 诊断仅记录键数量，不泄露对话或工具输出正文。
        _log.warning(
          'Flushing Agent event buffer after backpressure '
          '(pending keys: $pendingEventCount)',
        );
      },
    );
    StreamSubscription<AgentEvent>? subscription;
    subscription = provider.events.listen(
      buffer.add,
      onError: (Object error, StackTrace _) {
        if (!_eventListenerGate.accepts(
          scope,
          currentRuntimeScope: _runtimeScopeOf(provider),
          allowDetachedRuntime: true,
        )) {
          return;
        }
        _log.warning(
          'Agent provider event stream failed (${error.runtimeType})',
        );
      },
      onDone: () {
        buffer.dispose();
        if (!_eventListenerGate.release(scope)) {
          return;
        }
        if (identical(_eventBuffer, buffer)) {
          _eventBuffer = null;
        }
        if (identical(_eventSubscription, subscription)) {
          _eventSubscription = null;
        }
      },
    );
    _eventSubscription = subscription;
    _eventBuffer = buffer;

    // 旧代数未发布的 delta/progress 属于旧 thread 或旧连接，必须直接丢弃。
    previousBuffer?.dispose();
    if (previousSubscription != null &&
        !identical(previousSubscription, subscription)) {
      // 代次门已经屏蔽旧流；取消过程不得阻塞新 thread 的历史发布。
      unawaited(previousSubscription.cancel());
    }
  }

  void _invalidateProviderEventListener() {
    _eventListenerGate.invalidate();
    _eventBuffer?.dispose();
    _eventBuffer = null;
  }

  bool _isCriticalDetachedEvent(AgentEvent event) {
    return event is AgentStatusEvent ||
        event is AgentErrorEvent ||
        event is AgentTurnCompletedEvent ||
        event is AgentThreadClosedEvent ||
        event is AgentPermissionRequestedEvent ||
        event is AgentPermissionResolvedEvent ||
        event is AgentPlanApprovalRequestedEvent ||
        event is AgentPlanApprovalResolvedEvent;
  }

  /// 最近一次已展示的错误概要。
  ///
  /// Codex 在失败时会同时发送 `error` 通知和带 `turn.error` 的
  /// `turn/completed`，两者携带相同的错误文本；记录该值用于去重，
  /// 避免同一条错误在时间线上出现两次。
  String? _lastShownErrorMessage;

  /// 将 provider 事件规约成面板状态。
  void _handleEvent(AgentEvent event) {
    switch (event) {
      case AgentStatusEvent():
        _status = event.status;
        _publishUiChanges();
      case AgentSessionStartedEvent():
        if (!_shouldAcceptSessionStarted(event.session.id)) {
          break;
        }
        _session = event.session;
        _restoredSessionId = event.session.id;
        _threadOpenPhase = AgentThreadOpenPhase.idle;
        _requiresResumedSelectedThread = false;
        _applySessionTitle(event.session);
        _publishUiChanges(header: true, composer: true);
      case AgentThreadStatusChangedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        _applyThreadRuntimeStatus(
          status: event.status,
          waitingOnApproval: event.waitingOnApproval,
          waitingOnUserInput: event.waitingOnUserInput,
        );
        _publishUiChanges(header: true);
      case AgentThreadNameUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        final name = event.threadName?.trim();
        if (name != null && name.isNotEmpty) {
          // 服务端自动/手动改名后同步详情头栏与 session 缓存。
          _applyThreadTitle(name);
        }
        _publishUiChanges(header: true);
      case AgentThreadArchivedEvent():
      case AgentThreadUnarchivedEvent():
      case AgentThreadDeletedEvent():
        // 列表侧负责移除；若当前会话被删/归档，由 shell onActiveThreadCleared 重置。
        break;
      case AgentThreadClosedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        _clearThreadRuntimeStatus();
        if (isTurnRunning) {
          // 服务端关闭线程时清本地运行态，避免卡在 running。
          _timeline.completeLiveTurnGroup(
            _timeline.selectedRunningTurnId ?? 'closed',
            status: AgentHistoryTurnStatus.interrupted,
          );
        }
        _consumeActivityDirty();
        _syncElapsedTicker();
        _publishUiChanges(
          history: true,
          syncLiveTurn: true,
          header: true,
          composer: true,
        );
      case AgentThreadCompactedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        _isCompacting = false;
        _publishUiChanges(header: true, composer: true);
      case AgentThreadSettingsUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        _applyThreadSelectionFromThreadSettings(modelId: event.model);
        _permissionSelectionController.applyThreadSettings(
          approvalPolicy: event.approvalPolicy,
          sandboxPolicy: event.sandboxPolicy,
          permissionProfileId: event.activePermissionProfileId,
        );
        _publishUiChanges(composer: true);
      case AgentAutoApprovalReviewEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.threadId,
          turnId: event.turnId,
        )) {
          break;
        }
        _autoReviewsByTurnId[event.turnId] = event;
        if (event.status == 'denied') {
          _latestDeniedAutoReview = event;
        } else if (event.status == 'approved') {
          if (_latestDeniedAutoReview?.reviewId == event.reviewId) {
            _latestDeniedAutoReview = null;
          }
        }
        _publishUiChanges(header: true, liveTurn: true, history: true);
      case AgentTurnStartedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.turn.sessionId,
          turnId: event.turn.id,
        )) {
          break;
        }
        _lastShownErrorMessage = null;
        _timeline.beginLiveTurnGroup(event.turn);
        _consumeActivityDirty();
        _syncElapsedTicker();
        _flushStreamChangesNow(
          syncLiveTurn: true,
          liveTurn: true,
          header: true,
          composer: true,
        );
      case AgentTurnCompletedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        // 先插失败原因，让消息归入该回合分组，再收尾分组。
        _addTurnFailureMessage(event);
        _timeline.completeLiveTurnGroup(
          event.turnId,
          status: event.status,
          duration: event.duration,
        );
        // 回合结束后清除改道头栏提示，避免残留到下一回合。
        _modelRerouteNotice = null;
        if (!isTurnRunning &&
            _status.state == AgentProviderConnectionState.running) {
          _status = AgentProviderStatus(
            state: AgentProviderConnectionState.ready,
            message: '$activeProviderName ready',
          );
        }
        // turn 已结束后若仍残留 active，会让侧栏 isBusy 一直转圈；
        // status/changed→idle 可能迟到或缺失，这里与 isTurnRunning 对齐。
        if (!isTurnRunning &&
            _threadRuntimeStatus == AgentThreadRuntimeStatus.active) {
          _applyThreadRuntimeStatus(
            status: AgentThreadRuntimeStatus.idle,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          );
        }
        _consumeActivityDirty();
        _syncElapsedTicker();
        _flushStreamChangesNow(
          history: true,
          syncLiveTurn: true,
          header: true,
          composer: true,
          autoScroll: true,
        );
      case AgentTokenUsageEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.updateTurnTokenUsage(event);
        // header：会话总 token；composer：上下文窗口；history/live：turn footer。
        // Grok 的 usage 常在 turn 完成后才到，必须刷新历史区分隔线。
        final usageTurnId = event.turnId;
        final usageOnHistory =
            usageTurnId != null && _timeline.isHistoryTurnId(usageTurnId);
        _flushStreamChangesNow(
          header: true,
          composer: true,
          history: usageOnHistory,
          // 无 turnId 或仍在 live 区时刷新 live footer。
          liveTurn: !usageOnHistory,
        );
      case AgentMessageDeltaEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        final isPlanDelta = event.kind == AgentMessageKind.plan;
        _timeline.appendMessageDelta(event);
        _scheduleStreamFlush(
          header: _consumeActivityDirty(),
          autoScroll: true,
          expansion: isPlanDelta,
        );
      case AgentReasoningDeltaEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.appendReasoningDelta(event);
        _scheduleStreamFlush(
          header: _consumeActivityDirty(),
          autoScroll: true,
          expansion: true,
        );
      case AgentMessageUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.updateMessage(event);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentPlanUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.replaceActivePlan(event);
        _flushStreamChangesNow(liveTurn: true);
      case AgentSessionConfigUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.sessionId)) {
          break;
        }
        _sessionConfigOptions = event.options;
        _applyThreadSelectionFromSessionConfigOptions(event.options);
        _publishUiChanges(composer: true);
      case AgentTurnDiffEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.upsertTurnDiff(event);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentToolCallEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.toolCall.sessionId,
          turnId: event.toolCall.turnId,
        )) {
          break;
        }
        _timeline.upsertToolCall(event.toolCall);
        final activityChanged = _consumeActivityDirty();
        // 工具进行中时更新状态文案；相位变化时刷新 header。
        if (event.toolCall.status == AgentToolStatus.inProgress ||
            event.toolCall.status == AgentToolStatus.pending) {
          final title = event.toolCall.displayTitle.trim();
          if (title.isNotEmpty) {
            _status = AgentProviderStatus(
              state: AgentProviderConnectionState.running,
              message: title.length > 80 ? '${title.substring(0, 80)}…' : title,
            );
          }
          _scheduleStreamFlush(header: activityChanged, autoScroll: true);
          break;
        }
        _flushStreamChangesNow(
          liveTurn: true,
          header: activityChanged,
          autoScroll: true,
        );
      case AgentPermissionRequestedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.request.sessionId,
          turnId: event.request.turnId,
        )) {
          break;
        }
        _timeline.addPermissionRequest(event.request);
        _flushStreamChangesNow(liveTurn: true, pendingInteraction: true);
      case AgentPermissionResolvedEvent():
        // 他端已应答：按 threadId 路由，移除本端仍展示的审批卡。
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        _timeline.removePermissionRequest(event.requestId);
        _flushStreamChangesNow(liveTurn: true, pendingInteraction: true);
      case AgentPlanApprovalRequestedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.request.sessionId,
          turnId: event.request.turnId,
        )) {
          break;
        }
        _timeline.addPlanApprovalRequest(event.request);
        _flushStreamChangesNow(liveTurn: true, pendingInteraction: true);
      case AgentPlanApprovalResolvedEvent():
        if (!_shouldHandleEventForCurrentThread(sessionId: event.sessionId)) {
          break;
        }
        _timeline.removePlanApprovalRequest(event.requestId);
        _flushStreamChangesNow(liveTurn: true, pendingInteraction: true);
      case AgentModelReroutedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.threadId,
          turnId: event.turnId,
        )) {
          break;
        }
        _modelRerouteNotice = '已改道至 ${event.toModel}';
        _timeline.addHistoryEvent(
          AgentHistoryEventEntry(
            id: _nextLocalTimelineId('model-reroute'),
            kind: AgentHistoryEventKind.system,
            title: '模型已改道',
            description: '${event.fromModel} → ${event.toModel}',
            content: _modelRerouteReasonLabel(event.reason),
            raw: event.raw,
          ),
        );
        _flushStreamChangesNow(liveTurn: true, header: true, autoScroll: true);
      case AgentDeprecationNoticeEvent():
        // 按 summary 去重：同一弃用提示在本 ViewModel 生命周期内只展示一次。
        if (!_shownDeprecationSummaries.add(event.summary)) {
          break;
        }
        _timeline.addHistoryEvent(
          AgentHistoryEventEntry(
            id: _nextLocalTimelineId('deprecation'),
            kind: AgentHistoryEventKind.warning,
            title: '适配层弃用提示',
            description: event.summary,
            content: event.details == null
                ? '请升级 Codex 适配层以继续兼容协议变更。'
                : '${event.details}\n请升级 Codex 适配层以继续兼容协议变更。',
            raw: event.raw,
          ),
        );
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentSystemItemEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        // contextCompaction item 到达时也结束 compact 进行中标志。
        if (event.entry.title.contains('压缩') ||
            event.entry.kind == AgentHistoryEventKind.system) {
          final rawType = event.entry.raw['type']?.toString();
          if (rawType == 'contextCompaction' ||
              event.entry.title.contains('上下文已压缩')) {
            _isCompacting = false;
          }
        }
        _timeline.addHistoryEvent(event.entry);
        _flushStreamChangesNow(
          liveTurn: true,
          header: true,
          composer: true,
          autoScroll: true,
        );
      case AgentModelListEvent():
        _handleModelList(event.models);
      case AgentErrorEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _lastShownErrorMessage = event.message;
        _timeline.addConversationMessage(
          AgentConversationMessage(
            id: _nextLocalTimelineId('error'),
            role: AgentMessageRole.system,
            text: _errorMessageText(event),
          ),
        );
        _flushStreamChangesNow(
          history: true,
          liveTurn: true,
          header: true,
          autoScroll: true,
        );
    }
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

  /// 将协议改道原因枚举转为可读说明。
  String _modelRerouteReasonLabel(String reason) {
    return switch (reason) {
      'highRiskCyberActivity' => '原因：高风险网络活动策略',
      _ => '原因：$reason',
    };
  }

  /// 回合以失败终态结束时，把 `turn.error` 的原因插入时间线。
  ///
  /// 若同样的错误文本刚通过 `error` 通知展示过则跳过，避免重复。
  void _addTurnFailureMessage(AgentTurnCompletedEvent event) {
    final errorMessage = event.errorMessage;
    if (event.status != AgentHistoryTurnStatus.failed ||
        errorMessage == null ||
        errorMessage == _lastShownErrorMessage) {
      return;
    }
    _lastShownErrorMessage = errorMessage;
    _timeline.addConversationMessage(
      AgentConversationMessage(
        id: _nextLocalTimelineId('turn-failed'),
        role: AgentMessageRole.system,
        text: 'Turn failed: $errorMessage',
      ),
    );
  }

  /// 生成本地时间线条目 id；时间戳 + 单调序号，保证同毫秒内也不碰撞。
  String _nextLocalTimelineId(String prefix) {
    _localTimelineIdSeq += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localTimelineIdSeq';
  }

  /// 生成 `clientUserMessageId`，用于 turn/start 幂等。
  String _nextClientUserMessageId() {
    _localTimelineIdSeq += 1;
    return 'msg-${DateTime.now().microsecondsSinceEpoch}-$_localTimelineIdSeq';
  }

  /// 组装错误事件的展示文本；服务端声明会自动重试时附加提示。
  String _errorMessageText(AgentErrorEvent event) {
    final buffer = StringBuffer(event.message);
    final details = event.details;
    if (details != null && details.isNotEmpty) {
      buffer.write(': $details');
    }
    if (event.willRetry ?? false) {
      buffer.write(' (Codex will retry automatically)');
    }
    if (event.code == 'contextWindowExceeded') {
      buffer.write('。上下文已超限，可点击头栏「压缩上下文」后继续。');
    }
    return buffer.toString();
  }

  /// 组装协议输入项：文本（含当前文件上下文）+ mention + 本地图片。
  List<AgentUserInput> _buildUserInputs({
    required String text,
    required List<String> localImagePaths,
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
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
      history: _timeline.isHistoryTurnId(turnId),
      liveTurn: _timeline.isLiveTurnId(turnId),
      header: true,
      composer: true,
      autoScroll: true,
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
      history: _timeline.isHistoryTurnId(turnId),
      liveTurn: _timeline.isLiveTurnId(turnId),
      header: true,
      composer: true,
      autoScroll: true,
    );
  }

  bool _isCurrentSwitch(int switchToken) {
    return !_disposed && switchToken == _threadSwitchToken;
  }

  /// 切换会话时 best-effort 取消旧 thread 订阅，失败不影响 UI。
  Future<void> _unsubscribeThreadBestEffort(
    AgentProvider provider,
    String threadId,
  ) async {
    try {
      final threadCatalog = provider.bundle.threadCatalog;
      if (threadCatalog == null) {
        return;
      }
      await threadCatalog.unsubscribeThread(threadId);
    } catch (error) {
      _log.warning(
        'Could not unsubscribe Agent thread $threadId '
        '(${error.runtimeType})',
      );
    }
  }

  String? get _selectedThreadId => _session?.id ?? _restoredSessionId;

  bool _shouldAcceptSessionStarted(String sessionId) {
    final selectedThreadId = _selectedThreadId;
    if (selectedThreadId != null) {
      return selectedThreadId == sessionId;
    }
    return !_requiresResumedSelectedThread;
  }

  bool _shouldHandleEventForCurrentThread({String? sessionId, String? turnId}) {
    final selectedThreadId = _selectedThreadId;
    if (sessionId != null) {
      return selectedThreadId == sessionId;
    }
    if (turnId != null) {
      return _timeline.hasTurn(turnId) ||
          turnId == _timeline.pendingTurnGroupId;
    }
    return true;
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

  void _clearThreadRuntimeStatus() {
    _threadRuntimeStatus = null;
    _threadWaitingOnApproval = false;
    _threadWaitingOnUserInput = false;
  }

  void _publishUiChanges({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool pendingInteraction = false,
    bool expansion = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    _syncThreadSnapshotListenable();
    _uiSignals.publish(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header,
      composer: composer,
      pendingInteraction: pendingInteraction,
      expansion: expansion,
      liveTurn: liveTurn,
      autoScroll: autoScroll,
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

  void _notifyLegacyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _scheduleStreamFlush({
    bool header = false,
    bool composer = false,
    bool autoScroll = false,
    bool expansion = false,
  }) {
    _uiSignals.scheduleStreamFlush(
      header: header,
      composer: composer,
      autoScroll: autoScroll,
      expansion: expansion,
    );
  }

  void _flushPendingStreamChangesNow() {
    _uiSignals.flushPendingStreamChangesNow();
  }

  void _flushStreamChangesNow({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool pendingInteraction = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    // 流式 flush 也必须刷新 thread snapshot，否则 turn/completed 等路径
    // 只更新分区信号、不推 isTurnRunning，侧栏会一直卡在执行中。
    _syncThreadSnapshotListenable();
    _uiSignals.flushStreamChangesNow(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header,
      composer: composer,
      pendingInteraction: pendingInteraction,
      liveTurn: liveTurn,
      autoScroll: autoScroll,
    );
  }

  /// 将当前 isTurnRunning / runtimeStatus 等推到 [threadSnapshotListenable]。
  void _syncThreadSnapshotListenable() {
    final nextThreadSnapshot = _buildThreadSnapshot();
    if (nextThreadSnapshot != _threadSnapshotListenable.value) {
      _threadSnapshotListenable.value = nextThreadSnapshot;
    }
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
