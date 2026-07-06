import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

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
  }) : _timeline = timelineStore ?? AgentConversationTimelineStore(),
       _modelSelectionController =
           modelSelectionController ??
           AgentConversationModelSelectionController(
             persistSelection: providerController.persistModelSelection,
           ) {
    _uiSignals = AgentConversationUiSignals(
      timeline: _timeline,
      onLegacyNotify: _notifyLegacyListeners,
      isDisposed: () => _disposed,
    );
  }

  static const String defaultThreadTitle = 'New thread';

  final ActiveAgentProviderController providerController;
  final AgentConversationTimelineStore _timeline;
  final AgentConversationModelSelectionController _modelSelectionController;
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

  String? get sessionId => _session?.id ?? _restoredSessionId;

  String get currentThreadTitle => _currentThreadTitle;

  bool get showRunningIndicator => isTurnRunning;

  AgentThreadOpenPhase get threadOpenPhase => _threadOpenPhase;

  bool get requiresResumedSelectedThread => _requiresResumedSelectedThread;

  AgentTokenUsage? get currentTurnTokenUsage => _timeline.currentTurnTokenUsage;

  AgentTokenUsage? get currentThreadTokenUsage =>
      _timeline.currentThreadTokenUsage;

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
    _modelSelectionController.seedFromConfig(
      providerController.activeProviderConfig,
    );
    try {
      final provider = await _ensureProvider();
      await provider.initialize();
      if (_modelSelectionController.modelList == null) {
        final models = await provider.listModels();
        _handleModelList(models);
      }
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
  }) {
    final projectChanged = projectPath != _projectPath;
    _projectPath = projectPath;
    _contextFilePath = contextFilePath;
    if (projectChanged) {
      _threadSwitchToken += 1;
      _session = null;
      _restoredSessionId = restoredSessionId;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
      _currentThreadTitle = defaultThreadTitle;
    } else if (restoredSessionId != null) {
      _restoredSessionId = restoredSessionId;
      _threadOpenPhase = AgentThreadOpenPhase.idle;
      _requiresResumedSelectedThread = false;
    }
    _publishUiChanges(header: true, composer: true);
  }

  /// 发送用户消息。
  ///
  /// 没有 active turn 时创建新回合；已有 active turn 时发送 steer，保持完整工具循环。
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !canSubmitMessage) {
      return;
    }

    if (_requiresResumedSelectedThread && _selectedThreadId == null) {
      return;
    }

    final switchToken = _threadSwitchToken;
    final selectedThreadId = _selectedThreadId;
    final runningTurnId = _timeline.selectedRunningTurnId;

    final isNewTurn = runningTurnId == null;
    if (isNewTurn) {
      _timeline.startPendingLiveTurn();
    } else {
      _timeline.currentTurnGroupId = runningTurnId;
    }
    _timeline.addConversationMessage(
      AgentConversationMessage(
        id: 'user-${DateTime.now().microsecondsSinceEpoch}',
        role: AgentMessageRole.user,
        text: trimmed,
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
          message: _messageWithContext(trimmed),
          context: context,
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
          message: _messageWithContext(trimmed),
          context: context,
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
    _flushPendingStreamChangesNow();
    _session = null;
    _restoredSessionId = thread.id;
    _requiresResumedSelectedThread = true;
    _threadOpenPhase = AgentThreadOpenPhase.loadingHistory;
    _currentThreadTitle = thread.displayName;
    _timeline.clearConversation();
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

  /// 处理审批卡片的 approve/deny。
  ///
  /// UI 先移除卡片，再异步回写 provider，避免按钮点击后卡片停留造成重复提交。
  Future<void> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
  }) async {
    _timeline.removePermissionRequest(request.id);
    _publishUiChanges(history: true, liveTurn: true);
    _log.info(
      'Responding to Agent permission ${request.kind.name}: approved=$approved',
    );
    await _provider?.respondToPermission(
      AgentPermissionDecision(requestId: request.id, approved: approved),
    );
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
      case AgentTurnStartedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.turn.sessionId,
          turnId: event.turn.id,
        )) {
          break;
        }
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
        _timeline.completeLiveTurnGroup(event.turnId);
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
        _timeline.appendMessageDelta(event);
        _scheduleStreamFlush(autoScroll: true);
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
      case AgentToolCallEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.toolCall.sessionId,
          turnId: event.toolCall.turnId,
        )) {
          break;
        }
        _timeline.upsertToolCall(event.toolCall);
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
      case AgentModelListEvent():
        _handleModelList(event.models);
      case AgentErrorEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _timeline.addConversationMessage(
          AgentConversationMessage(
            id: 'error-${DateTime.now().microsecondsSinceEpoch}',
            role: AgentMessageRole.system,
            text: event.details == null
                ? event.message
                : '${event.message}: ${event.details}',
          ),
        );
        _flushStreamChangesNow(history: true, liveTurn: true, autoScroll: true);
    }
  }

  String _messageWithContext(String message) {
    final filePath = _contextFilePath;
    if (filePath == null) {
      return message;
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
        id: 'unavailable-${DateTime.now().microsecondsSinceEpoch}',
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
        id: 'error-${DateTime.now().microsecondsSinceEpoch}',
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
    _currentThreadTitle = title;
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

  void _scheduleStreamFlush({bool header = false, bool autoScroll = false}) {
    _uiSignals.scheduleStreamFlush(header: header, autoScroll: autoScroll);
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
