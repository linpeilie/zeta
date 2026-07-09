import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

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
  }

  static const String defaultThreadTitle = 'New thread';

  /// 可选：从 shell 注入工作区文件列表，供 @mention 选择器使用。
  final List<WorkspaceNode> Function()? workspaceFilesProvider;

  final ActiveAgentProviderController providerController;
  final AgentConversationTimelineStore _timeline;
  final AgentConversationModelSelectionController _modelSelectionController;
  final AgentConversationPermissionSelectionController
  _permissionSelectionController;
  late final AgentConversationUiSignals _uiSignals;

  AgentProvider? _provider;
  StreamSubscription<AgentEvent>? _eventSubscription;

  AgentSession? _session;
  String? _projectPath;
  String? _contextFilePath;

  String? _restoredSessionId;
  AgentThreadOpenPhase _threadOpenPhase = AgentThreadOpenPhase.idle;
  bool _requiresResumedSelectedThread = false;
  bool _settingsLoaded = false;
  bool _disposed = false;
  int _threadSwitchToken = 0;

  String _currentThreadTitle = defaultThreadTitle;
  AgentProviderStatus _status = const AgentProviderStatus.idle();
  AgentThreadRuntimeStatus? _threadRuntimeStatus;
  bool _threadWaitingOnApproval = false;
  bool _threadWaitingOnUserInput = false;

  /// 最近一次模型改道的目标模型；用于头栏短暂提示。
  String? _modelRerouteNotice;

  /// 是否正在执行上下文压缩。
  bool _isCompacting = false;

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

  bool get hasOlderTurns => _timeline.hasOlderTurns;

  AgentProviderStatus get status => _status;

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

  int get expansionVersion => _uiSignals.expansionVersion;

  ValueListenable<int> get historyVersionListenable =>
      _uiSignals.historyVersionListenable;

  ValueListenable<int> get headerVersionListenable =>
      _uiSignals.headerVersionListenable;

  ValueListenable<int> get composerVersionListenable =>
      _uiSignals.composerVersionListenable;

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

  List<AgentModelInfo> get models => _modelSelectionController.models;

  AgentModelInfo? get selectedModel => _modelSelectionController.selectedModel;

  String? get selectedModelId => _modelSelectionController.selectedModelId;

  String? get selectedReasoningEffort =>
      _modelSelectionController.selectedReasoningEffort;

  String? get selectedServiceTierId =>
      _modelSelectionController.selectedServiceTierId;

  bool get showReasoningEffort {
    if (activeProviderKind != AgentProviderKind.codexAppServer) {
      return false;
    }
    return selectedModel?.supportedReasoningEfforts.isNotEmpty ?? false;
  }

  bool get showServiceTier {
    if (activeProviderKind != AgentProviderKind.codexAppServer) {
      return false;
    }
    return selectedModel?.serviceTiers.isNotEmpty ?? false;
  }

  /// Codex 会话显示审批/沙箱策略选择器。
  bool get showPermissionPolicy =>
      activeProviderKind == AgentProviderKind.codexAppServer;

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

  String get currentThreadTitle => _currentThreadTitle;

  bool get showRunningIndicator =>
      isTurnRunning && threadStatusCapsuleLabel == null;

  AgentThreadOpenPhase get threadOpenPhase => _threadOpenPhase;

  bool get requiresResumedSelectedThread => _requiresResumedSelectedThread;

  AgentTokenUsage? get currentTurnTokenUsage => _timeline.currentTurnTokenUsage;

  AgentTokenUsage? get currentThreadTokenUsage =>
      _timeline.currentThreadTokenUsage;

  /// 当前上下文窗口占用比例（0~1）；缺少窗口大小时为空。
  double? get contextWindowUsageRatio {
    final usage = currentThreadTokenUsage;
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
    return ratio != null && ratio >= contextCompactThreshold;
  }

  /// 是否正在压缩上下文。
  bool get isCompacting => _isCompacting;

  /// 空闲且末尾存在用户消息时可编辑重试。
  bool get canEditLastUserMessage {
    if (!canSubmitMessage || isTurnRunning || _isCompacting) {
      return false;
    }
    return _lastEditableUserMessage() != null;
  }

  /// 最近一条可编辑的用户消息文本；无可编辑消息时为空。
  String? get lastEditableUserMessageText => _lastEditableUserMessage()?.text;

  /// 最近一条可编辑用户消息的 id。
  String? get lastEditableUserMessageId => _lastEditableUserMessage()?.id;

  bool get isTurnRunning => _timeline.isTurnRunning;

  bool get isRunning => isTurnRunning;

  bool get canSubmitMessage => _threadOpenPhase == AgentThreadOpenPhase.idle;

  bool isToolCallExpanded(String toolCallId) {
    return _timeline.isToolCallExpanded(toolCallId);
  }

  bool isPlanMessageExpanded(String messageId) {
    return _timeline.isPlanMessageExpanded(messageId);
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
  Future<void> loadSettings() async {
    if (_settingsLoaded) {
      return;
    }
    _settingsLoaded = true;
    try {
      await providerController.loadSettings();
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.idle,
        message: '$activeProviderName ready',
      );
      _log.fine('Loaded Agent provider settings: $activeProviderId');
    } catch (error, stackTrace) {
      _log.warning('Could not load Agent provider settings', error, stackTrace);
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
    final config = providerController.activeProviderConfig;
    _modelSelectionController.seedFromConfig(config);
    _permissionSelectionController.seedFromConfig(config);
    try {
      final provider = await _ensureProvider();
      await provider.initialize();
      if (_modelSelectionController.modelList == null) {
        final models = await provider.listModels();
        _handleModelList(models);
      }
      await _permissionSelectionController.refreshProfiles();
    } catch (error, stackTrace) {
      _log.warning('Could not preload Agent models', error, stackTrace);
    }
    _publishUiChanges(composer: true);
  }

  Future<void> selectModel(String modelId) async {
    await _modelSelectionController.selectModel(modelId);
    _publishUiChanges(composer: true);
  }

  Future<void> selectReasoningEffort(String? effort) async {
    await _modelSelectionController.selectReasoningEffort(effort);
    _publishUiChanges(composer: true);
  }

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
      await provider.approveGuardianDeniedAction(
        threadId: threadId,
        event: review.raw,
      );
      _latestDeniedAutoReview = null;
      _publishUiChanges(header: true, liveTurn: true);
    } catch (error, stackTrace) {
      _log.warning(
        'Could not approve guardian-denied action',
        error,
        stackTrace,
      );
    }
  }

  Future<void> selectServiceTier(String? tierId) async {
    await _modelSelectionController.selectServiceTier(tierId);
    _publishUiChanges(composer: true);
  }

  void _handleModelList(AgentModelList modelList) {
    _modelSelectionController.handleModelList(modelList);
    _publishUiChanges(composer: true);
  }

  /// 更新当前项目和文件上下文。
  ///
  /// 项目变更时清空内存中的 session/turn；如果恢复状态里带了 thread id，则保留到
  /// 第一次发送消息时再调用 provider resume。
  void updateWorkspace({
    required String? projectPath,
    required String? contextFilePath,
    String? restoredSessionId,
    bool resetConversation = false,
  }) {
    final projectChanged = projectPath != _projectPath;
    _projectPath = projectPath;
    _contextFilePath = contextFilePath;
    if (projectChanged || resetConversation) {
      // 离开当前会话时取消订阅；恢复到另一 thread 时也退订旧 id。
      final previousThreadId = _selectedThreadId;
      _flushPendingStreamChangesNow();
      _threadSwitchToken += 1;
      _session = null;
      _restoredSessionId = restoredSessionId;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
      _currentThreadTitle = defaultThreadTitle;
      _status = const AgentProviderStatus.idle();
      _clearThreadRuntimeStatus();
      _modelRerouteNotice = null;
      _timeline.resetToWelcomeState();
      if (previousThreadId != null && previousThreadId != restoredSessionId) {
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
    if (restoredSessionId != null) {
      _restoredSessionId = restoredSessionId;
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
      localImagePaths.where((path) => path.trim().isNotEmpty),
    );
    if ((trimmed.isEmpty && imagePaths.isEmpty && mentions.isEmpty) ||
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
      mentions: mentions,
    );
    final clientUserMessageId = _nextClientUserMessageId();

    final isNewTurn = runningTurnId == null;
    if (isNewTurn) {
      _timeline.startPendingLiveTurn();
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
    _publishUiChanges(
      syncLiveTurn: true,
      liveTurn: true,
      header: true,
      composer: true,
      autoScroll: true,
    );

    try {
      await loadSettings();
      final provider = await _ensureProvider();
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
      _log.info('Sending Agent request with provider ${provider.config.id}');
      if (isNewTurn) {
        final turn = await provider.sendMessage(
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
        await provider.steerTurn(
          session: session,
          inputs: inputs,
          context: context,
          clientUserMessageId: clientUserMessageId,
        );
      }
    } on ProcessException catch (error, stackTrace) {
      _log.warning(
        'Agent provider process failed: ${error.message}',
        error,
        stackTrace,
      );
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _markUnavailable(error.message, details: error.toString());
    } on UnsupportedError catch (error, stackTrace) {
      _log.warning('Unsupported Agent provider', error, stackTrace);
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
      _markError(error.message ?? 'Provider is not supported');
    } catch (error, stackTrace) {
      _log.warning('Agent request failed', error, stackTrace);
      if (!_isStillSelectedThread(switchToken, selectedThreadId)) {
        return;
      }
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
    await provider.cancelTurn(AgentTurn(id: turnId, sessionId: sessionId));
  }

  /// 切换到项目列表中选中的 thread。
  Future<void> switchThread(AgentThreadSummary thread) async {
    final switchToken = ++_threadSwitchToken;
    // 离开旧会话时先记下 id，切走后取消服务端订阅，减少无关通知。
    final previousThreadId = _selectedThreadId;
    _flushPendingStreamChangesNow();
    _session = null;
    _restoredSessionId = thread.id;
    _requiresResumedSelectedThread = true;
    _threadOpenPhase = AgentThreadOpenPhase.loadingHistory;
    _currentThreadTitle = thread.displayName;
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
      final provider = await _ensureProvider();
      if (previousThreadId != null && previousThreadId != thread.id) {
        // 不阻塞历史加载：退订失败只记日志。
        unawaited(_unsubscribeThreadBestEffort(provider, previousThreadId));
      }
      final history = await provider.readThreadHistory(
        threadId: thread.id,
        sessionPath: thread.sessionPath,
      );
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _timeline.applyHistorySnapshot(history, thread);
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
    } catch (error, stackTrace) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _threadOpenPhase = AgentThreadOpenPhase.openFailed;
      _log.warning(
        'Could not load Agent thread history ${thread.id}',
        error,
        stackTrace,
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
    _publishUiChanges(history: true, liveTurn: true);
    _log.info(
      'Responding to Agent permission ${request.kind.name}: approved=$approved',
    );
    await _provider?.respondToPermission(
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

  /// 回滚末尾一回合并用新文本重发（编辑上一条用户消息）。
  ///
  /// 协议明确：rollback **不**还原 agent 已写入的本地文件。
  Future<void> editLastUserMessageAndRetry(String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || !canEditLastUserMessage) {
      return;
    }
    final threadId = sessionId;
    if (threadId == null) {
      return;
    }

    final switchToken = _threadSwitchToken;
    _status = const AgentProviderStatus(
      state: AgentProviderConnectionState.running,
      message: 'Rolling back turn',
    );
    _publishUiChanges(header: true, composer: true);

    try {
      final provider = await _ensureProvider();
      final history = await provider.rollbackThread(
        threadId: threadId,
        numTurns: 1,
      );
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      final summary = AgentThreadSummary(
        id: threadId,
        providerId: provider.config.id,
        projectPath: _projectPath ?? '',
        title: _currentThreadTitle == defaultThreadTitle
            ? null
            : _currentThreadTitle,
        preview: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: AgentThreadRuntimeStatus.idle,
      );
      _timeline.applyHistorySnapshot(history, summary);
      _session = AgentSession(
        id: threadId,
        providerId: provider.config.id,
        title: summary.title,
      );
      _restoredSessionId = threadId;
      _requiresResumedSelectedThread = false;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _publishUiChanges(
        history: true,
        syncLiveTurn: true,
        header: true,
        composer: true,
      );
      await sendMessage(trimmed);
    } catch (error, stackTrace) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _log.warning(
        'Could not rollback and retry thread $threadId',
        error,
        stackTrace,
      );
      _markError('Could not edit and retry message', details: error.toString());
    }
  }

  /// 分叉当前会话为新 thread，并切换到分叉结果。
  Future<AgentSession?> forkCurrentThread() async {
    final threadId = sessionId;
    if (threadId == null || !canSubmitMessage || isTurnRunning) {
      return null;
    }
    final switchToken = _threadSwitchToken;
    try {
      final provider = await _ensureProvider();
      final session = await provider.forkThread(
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
    } catch (error, stackTrace) {
      _log.warning('Could not fork thread $threadId', error, stackTrace);
      _markError('Could not fork thread', details: error.toString());
      return null;
    }
  }

  /// 启动上下文压缩。
  Future<void> compactCurrentThread() async {
    final threadId = sessionId;
    if (threadId == null || _isCompacting || isTurnRunning) {
      return;
    }
    _isCompacting = true;
    _publishUiChanges(header: true, composer: true);
    try {
      final provider = await _ensureProvider();
      await provider.compactThread(threadId);
    } catch (error, stackTrace) {
      _isCompacting = false;
      _log.warning('Could not compact thread $threadId', error, stackTrace);
      _markError('Could not compact context', details: error.toString());
      _publishUiChanges(header: true, composer: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _uiSignals.dispose();
    unawaited(_eventSubscription?.cancel());
    _timeline.dispose();
    super.dispose();
  }

  Future<AgentProvider> _ensureProvider() async {
    final provider = await providerController.activeProvider();
    if (identical(_provider, provider)) {
      return provider;
    }

    await _eventSubscription?.cancel();
    _log.fine('Using shared Agent provider: ${provider.config.id}');
    _provider = provider;
    _modelSelectionController.bindProvider(provider);
    _permissionSelectionController.bindProvider(provider);
    _eventSubscription = provider.events.listen(_handleEvent);
    return provider;
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
        final session = await provider.resumeSession(
          restoredSessionId,
          context: context,
        );
        if (_isStillSelectedThread(switchToken, expectedThreadId)) {
          _session = session;
          _restoredSessionId = session.id;
          _threadOpenPhase = AgentThreadOpenPhase.idle;
          _requiresResumedSelectedThread = false;
          _applySessionTitle(session);
        }
        return session;
      } catch (error, stackTrace) {
        _log.warning(
          'Could not resume Agent session $restoredSessionId',
          error,
          stackTrace,
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
    final session = await provider.startSession(context: context);
    if (_isStillSelectedThread(switchToken, expectedThreadId)) {
      _session = session;
      _restoredSessionId = session.id;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
      _applySessionTitle(session);
    }
    return session;
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
          _currentThreadTitle = name;
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
        final model = event.model?.trim();
        if (model != null && model.isNotEmpty) {
          unawaited(selectModel(model));
        }
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
        _scheduleStreamFlush(header: true);
      case AgentMessageDeltaEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        final isPlanDelta = _rawLooksLikePlan(event.raw);
        _timeline.appendMessageDelta(event);
        _scheduleStreamFlush(autoScroll: true, expansion: isPlanDelta);
      case AgentReasoningDeltaEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.appendReasoningDelta(event);
        _scheduleStreamFlush(autoScroll: true, expansion: true);
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
        _timeline.upsertPlanMessage(event);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
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
        if (event.toolCall.status == AgentToolStatus.inProgress) {
          _scheduleStreamFlush(autoScroll: true);
          break;
        }
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentPermissionRequestedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.request.sessionId,
          turnId: event.request.turnId,
        )) {
          break;
        }
        _timeline.addPermissionRequest(event.request);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentPermissionResolvedEvent():
        // 他端已应答：按 threadId 路由，移除本端仍展示的审批卡。
        if (!_shouldHandleEventForCurrentThread(sessionId: event.threadId)) {
          break;
        }
        _timeline.removePermissionRequest(event.requestId);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
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
      await provider.unsubscribeThread(threadId);
    } catch (error, stackTrace) {
      _log.warning(
        'Could not unsubscribe Agent thread $threadId',
        error,
        stackTrace,
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

  /// 粗判 raw 是否来自 plan 流，用于决定是否刷新展开态。
  bool _rawLooksLikePlan(Map<String, Object?> raw) {
    final type = raw['type'];
    if (type is String && type.toLowerCase().contains('plan')) {
      return true;
    }
    final item = raw['item'];
    if (item is Map) {
      final itemType = item['type'];
      if (itemType is String && itemType.toLowerCase().contains('plan')) {
        return true;
      }
    }
    return false;
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
    _currentThreadTitle = title;
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
    bool expansion = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    _uiSignals.publish(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header,
      composer: composer,
      expansion: expansion,
      liveTurn: liveTurn,
      autoScroll: autoScroll,
    );
  }

  void _notifyLegacyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _scheduleStreamFlush({
    bool header = false,
    bool autoScroll = false,
    bool expansion = false,
  }) {
    _uiSignals.scheduleStreamFlush(
      header: header,
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
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    _uiSignals.flushStreamChangesNow(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header,
      composer: composer,
      liveTurn: liveTurn,
      autoScroll: autoScroll,
    );
  }
}
