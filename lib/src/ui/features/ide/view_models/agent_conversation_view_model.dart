import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logging.dart';
import '../../../../domain/agent/agent_models.dart';
import '../../../../domain/agent/agent_provider.dart';
import 'active_agent_provider_controller.dart';

final _log = loggerFor('zeta.agent.conversation');

/// Agent 面板的状态协调器。
///
/// 它负责把 UI 输入转换成 provider 调用，并把 [AgentEvent] 转换成消息列表、
/// 工具卡片、审批卡片和状态胶囊。Widget 层只监听这个对象，不直接依赖 Codex。
class AgentConversationViewModel extends ChangeNotifier {
  AgentConversationViewModel({required this.providerController});

  static const String defaultThreadTitle = 'New thread';
  static const AgentConversationMessage _welcomeMessage =
      AgentConversationMessage(
        id: 'welcome',
        role: AgentMessageRole.agent,
        text:
            'Ready. Select a file or send a request to start an Agent thread.',
      );

  /// welcome 消息和回合外系统消息所属的 standby 分组 id。
  static const String _standbyTurnId = '__standby__';

  final ActiveAgentProviderController providerController;

  /// 当前已创建的 provider 实例。
  AgentProvider? _provider;
  StreamSubscription<AgentEvent>? _eventSubscription;

  /// 当前会话，对应 provider 里的 thread。
  AgentSession? _session;

  /// 当前正在运行的回合，对应 provider 里的 turn。
  AgentTurn? _activeTurn;
  String? _projectPath;
  String? _contextFilePath;

  /// 从会话恢复出的 thread id；真正发送消息时再尝试 resume。
  String? _restoredSessionId;
  bool _settingsLoaded = false;
  bool _disposed = false;
  int _threadSwitchToken = 0;

  /// 对话流里的消息气泡。
  final List<AgentConversationMessage> _messages = <AgentConversationMessage>[
    _welcomeMessage,
  ];

  /// 工具调用卡片列表。
  final List<AgentToolCall> _toolCalls = <AgentToolCall>[];

  /// 等待用户处理的审批请求。
  final List<AgentPermissionRequest> _permissionRequests =
      <AgentPermissionRequest>[];

  /// 消息、工具调用和审批请求按出现顺序组成的一条时间线。
  final List<AgentTimelineEntry> _timelineEntries = <AgentTimelineEntry>[
    AgentMessageTimelineEntry(message: _welcomeMessage),
  ];

  /// 与 [_timelineEntries] 一一对应的 turn 分组 id；用于按 turn 聚合时间线。
  final List<String> _timelineEntryTurnIds = <String>[_standbyTurnId];

  /// 各 turn 分组的运行时元数据（状态、时间、耗时）。
  final Map<String, _TurnGroupMetadata> _turnMetadata =
      <String, _TurnGroupMetadata>{};

  /// 当前正在追加条目的 turn 分组 id；为 null 时落到 standby 分组。
  String? _currentTurnGroupId;

  /// sendMessage 新建回合时使用的临时分组 id，待 AgentTurnStartedEvent 到达后重命名为真实 turn id。
  String? _pendingTurnGroupId;

  /// provider 消息 id 到 UI 消息位置的索引，用于合并流式 delta。
  final Map<String, int> _messageIndexesByProviderId = <String, int>{};
  final Set<String> _expandedToolCallIds = <String>{};
  final Set<String> _expandedPlanMessageIds = <String>{};
  final Set<String> _expandedCommandGroupIds = <String>{};
  final Set<String> _expandedFileEditItemIds = <String>{};
  int _autoScrollTick = 0;
  String _currentThreadTitle = defaultThreadTitle;
  AgentProviderStatus _status = const AgentProviderStatus.idle();

  /// provider 推送的可用模型列表。
  AgentModelList? _modelList;

  /// 用户当前选择的模型组合，由 config 初始化，随用户操作更新。
  AgentModelSelection _modelSelection = const AgentModelSelection();

  List<AgentConversationMessage> get messages =>
      List<AgentConversationMessage>.unmodifiable(_messages);

  List<AgentToolCall> get toolCalls =>
      List<AgentToolCall>.unmodifiable(_toolCalls);

  List<AgentPermissionRequest> get permissionRequests =>
      List<AgentPermissionRequest>.unmodifiable(_permissionRequests);

  List<AgentTimelineEntry> get timelineEntries =>
      List<AgentTimelineEntry>.unmodifiable(_timelineEntries);

  /// 按出现顺序排列的 turn 分组，每组携带自己的消息体列表。
  ///
  /// 历史恢复和实时事件都会按 turn 聚合，UI 据此分回合渲染。standby 分组
  /// （welcome 消息、回合外的系统提示）排在最前。
  List<AgentConversationTurnGroup> get conversationTurns {
    final groups = <String, List<AgentTimelineEntry>>{};
    final order = <String>[];
    final seen = <String>{};
    for (var index = 0; index < _timelineEntries.length; index += 1) {
      final turnId = _timelineEntryTurnIds[index];
      (groups[turnId] ??= <AgentTimelineEntry>[]).add(_timelineEntries[index]);
      if (seen.add(turnId)) {
        order.add(turnId);
      }
    }
    return <AgentConversationTurnGroup>[
      for (final turnId in order)
        AgentConversationTurnGroup(
          id: turnId,
          entries: List<AgentTimelineEntry>.unmodifiable(groups[turnId]!),
          isStandby: turnId == _standbyTurnId,
          status: _turnMetadata[turnId]?.status,
          startedAt: _turnMetadata[turnId]?.startedAt,
          completedAt: _turnMetadata[turnId]?.completedAt,
          duration: _turnMetadata[turnId]?.duration,
          tokenUsage: _turnMetadata[turnId]?.tokenUsage,
        ),
    ];
  }

  AgentProviderStatus get status => _status;

  int get autoScrollTick => _autoScrollTick;

  String? get projectPath => _projectPath;

  String? get contextFilePath => _contextFilePath;

  String get activeProviderId => providerController.activeProviderId;

  String get activeProviderName => providerController.activeProviderName;

  /// 当前 active provider 的协议类型，UI 据此决定是否显示思考/速率控件。
  AgentProviderKind get activeProviderKind =>
      providerController.activeProviderConfig.kind;

  /// 可用模型列表。
  List<AgentModelInfo> get models =>
      _modelList?.models ?? const <AgentModelInfo>[];

  /// 当前选中的模型信息（从模型列表中查找）。
  AgentModelInfo? get selectedModel {
    final id = _modelSelection.modelId;
    if (id == null) {
      return null;
    }
    final models = _modelList?.models ?? const <AgentModelInfo>[];
    for (final model in models) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }

  /// 当前选中的模型 id。
  String? get selectedModelId => _modelSelection.modelId;

  /// 当前选中的推理深度档位。
  String? get selectedReasoningEffort => _modelSelection.reasoningEffort;

  /// 当前选中的服务档位 id。
  String? get selectedServiceTierId => _modelSelection.serviceTierId;

  /// 是否显示思考按钮：仅 Codex 且当前模型有推理档位时显示。
  bool get showReasoningEffort {
    if (activeProviderKind != AgentProviderKind.codexAppServer) {
      return false;
    }
    return selectedModel?.supportedReasoningEfforts.isNotEmpty ?? false;
  }

  /// 是否显示速率按钮：仅 Codex 且当前模型有服务档位时显示。
  bool get showServiceTier {
    if (activeProviderKind != AgentProviderKind.codexAppServer) {
      return false;
    }
    return selectedModel?.serviceTiers.isNotEmpty ?? false;
  }

  String? get sessionId => _session?.id ?? _restoredSessionId;

  String get currentThreadTitle => _currentThreadTitle;

  bool get showRunningIndicator => isRunning;

  AgentTokenUsage? get currentTurnTokenUsage {
    final activeTurn = _activeTurn;
    if (activeTurn == null) {
      return null;
    }
    return _turnMetadata[activeTurn.id]?.tokenUsage;
  }

  /// 当前 thread 下所有 turn 的累计 token 用量，用于标题栏右侧展示总成本。
  AgentTokenUsage? get currentThreadTokenUsage {
    int? inputTokens;
    int? cachedInputTokens;
    int? outputTokens;
    int? reasoningOutputTokens;
    int? totalTokens;

    for (final metadata in _turnMetadata.values) {
      final usage = metadata.tokenUsage;
      if (usage == null) {
        continue;
      }
      inputTokens = _sumOptionalInt(inputTokens, usage.inputTokens);
      cachedInputTokens = _sumOptionalInt(
        cachedInputTokens,
        usage.cachedInputTokens,
      );
      outputTokens = _sumOptionalInt(outputTokens, usage.outputTokens);
      reasoningOutputTokens = _sumOptionalInt(
        reasoningOutputTokens,
        usage.reasoningOutputTokens,
      );
      totalTokens = _sumOptionalInt(totalTokens, usage.totalTokens);
    }

    if (inputTokens == null &&
        cachedInputTokens == null &&
        outputTokens == null &&
        reasoningOutputTokens == null &&
        totalTokens == null) {
      return null;
    }

    return AgentTokenUsage(
      inputTokens: inputTokens,
      cachedInputTokens: cachedInputTokens,
      outputTokens: outputTokens,
      reasoningOutputTokens: reasoningOutputTokens,
      totalTokens: totalTokens,
    );
  }

  bool get isRunning =>
      _activeTurn != null ||
      _status.state == AgentProviderConnectionState.running ||
      _status.state == AgentProviderConnectionState.connecting;

  bool isToolCallExpanded(String toolCallId) {
    return _expandedToolCallIds.contains(toolCallId);
  }

  /// 计划消息是否处于展开状态。
  bool isPlanMessageExpanded(String messageId) {
    return _expandedPlanMessageIds.contains(messageId);
  }

  /// 命令集是否处于展开状态。
  bool isCommandGroupExpanded(String commandGroupId) {
    return _expandedCommandGroupIds.contains(commandGroupId);
  }

  /// 文件编辑项详情是否处于展开状态。
  bool isFileEditItemExpanded(String fileEditItemId) {
    return _expandedFileEditItemIds.contains(fileEditItemId);
  }

  void toggleToolCall(String toolCallId) {
    if (!_expandedToolCallIds.add(toolCallId)) {
      _expandedToolCallIds.remove(toolCallId);
    }
    _notify();
  }

  /// 切换计划消息折叠状态。
  void togglePlanMessage(String messageId) {
    if (!_expandedPlanMessageIds.add(messageId)) {
      _expandedPlanMessageIds.remove(messageId);
    }
    _notify();
  }

  /// 切换命令集折叠状态。
  void toggleCommandGroup(String commandGroupId) {
    if (!_expandedCommandGroupIds.add(commandGroupId)) {
      _expandedCommandGroupIds.remove(commandGroupId);
    }
    _notify();
  }

  /// 切换文件编辑项详情展开状态。
  void toggleFileEditItem(String fileEditItemId) {
    if (!_expandedFileEditItemIds.add(fileEditItemId)) {
      _expandedFileEditItemIds.remove(fileEditItemId);
    }
    _notify();
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
    _notify();
  }

  /// 预加载模型列表。
  ///
  /// 在 IDE 启动时调用，触发 provider initialize 握手并拉取 `model/list`，
  /// 使输入框下方的模型/思考/速率控件在用户发送消息前就可用。
  Future<void> loadModels() async {
    await loadSettings();
    final config = providerController.activeProviderConfig;
    _modelSelection = AgentModelSelection(
      modelId: config.selectedModel,
      reasoningEffort: config.selectedReasoningEffort,
      serviceTierId: config.selectedServiceTier,
    );
    try {
      final provider = await _ensureProvider();
      await provider.initialize();
      // initialize 会自动拉取 model list 并发出 AgentModelListEvent。
      // 如果事件未到达（如 provider 已初始化过），再主动拉取一次缓存。
      if (_modelList == null) {
        final models = await provider.listModels();
        _handleModelList(models);
      }
    } catch (error, stackTrace) {
      _log.warning('Could not preload Agent models', error, stackTrace);
    }
    _notify();
  }

  /// 选择模型，同步到 provider 并持久化。
  Future<void> selectModel(String modelId) async {
    final model = _findModel(modelId);
    if (model == null) {
      return;
    }
    // 切换模型时回退到该模型的默认推理档位和服务档位。
    _modelSelection = AgentModelSelection(
      modelId: modelId,
      reasoningEffort: model.defaultReasoningEffort,
      serviceTierId: model.defaultServiceTier,
    );
    await _syncSelection();
  }

  /// 选择推理深度档位。
  Future<void> selectReasoningEffort(String? effort) async {
    _modelSelection = AgentModelSelection(
      modelId: _modelSelection.modelId,
      reasoningEffort: effort,
      serviceTierId: _modelSelection.serviceTierId,
    );
    await _syncSelection();
  }

  /// 选择服务档位。
  Future<void> selectServiceTier(String? tierId) async {
    _modelSelection = AgentModelSelection(
      modelId: _modelSelection.modelId,
      reasoningEffort: _modelSelection.reasoningEffort,
      serviceTierId: tierId,
    );
    await _syncSelection();
  }

  /// 从模型列表中按 id 查找模型信息。
  AgentModelInfo? _findModel(String modelId) {
    final models = _modelList?.models ?? const <AgentModelInfo>[];
    for (final model in models) {
      if (model.id == modelId) {
        return model;
      }
    }
    return null;
  }

  /// 将当前选择同步到 provider 运行时状态并持久化到配置。
  Future<void> _syncSelection() async {
    final provider = _provider;
    if (provider != null) {
      provider.updateModelSelection(_modelSelection);
    }
    await providerController.persistModelSelection(_modelSelection);
    _notify();
  }

  /// 处理 provider 推送的模型列表。
  ///
  /// 首次到达时根据 config 选择和模型默认值初始化有效选择；
  /// 后续更新只刷新列表，保留用户已选模型（若仍存在）。
  void _handleModelList(AgentModelList modelList) {
    _modelList = modelList;
    _reconcileSelection();
    _notify();
  }

  /// 根据模型列表校正当前选择，确保 modelId/effort/tier 都有效。
  void _reconcileSelection() {
    final models = _modelList?.models ?? const <AgentModelInfo>[];
    if (models.isEmpty) {
      return;
    }

    // 确定有效 modelId：当前选择 → isDefault 模型 → 第一个模型。
    var modelId = _modelSelection.modelId;
    AgentModelInfo? selected = _findModel(modelId ?? '');
    if (selected == null) {
      final defaultModel = models.firstWhere(
        (model) => model.isDefault,
        orElse: () => models.first,
      );
      modelId = defaultModel.id;
      selected = defaultModel;
    }

    // 确定有效推理档位：当前选择（若模型支持）→ 模型默认 → null。
    var effort = _modelSelection.reasoningEffort;
    if (effort == null ||
        !selected.supportedReasoningEfforts.any((e) => e.effort == effort)) {
      effort = selected.defaultReasoningEffort;
    }

    // 确定有效服务档位：当前选择（若模型有）→ 模型默认 → null。
    var tierId = _modelSelection.serviceTierId;
    if (tierId == null || !selected.serviceTiers.any((t) => t.id == tierId)) {
      tierId = selected.defaultServiceTier;
    }

    final newSelection = AgentModelSelection(
      modelId: modelId,
      reasoningEffort: effort,
      serviceTierId: tierId,
    );
    if (newSelection.modelId != _modelSelection.modelId ||
        newSelection.reasoningEffort != _modelSelection.reasoningEffort ||
        newSelection.serviceTierId != _modelSelection.serviceTierId) {
      _modelSelection = newSelection;
      final provider = _provider;
      if (provider != null) {
        provider.updateModelSelection(_modelSelection);
      }
      // 首次校正出的默认选择也持久化，保证重启后一致。
      unawaited(providerController.persistModelSelection(_modelSelection));
    }
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
      _session = null;
      _activeTurn = null;
      _restoredSessionId = restoredSessionId;
      _currentThreadTitle = defaultThreadTitle;
    } else if (restoredSessionId != null) {
      _restoredSessionId = restoredSessionId;
    }
    _notify();
  }

  /// 发送用户消息。
  ///
  /// 没有 active turn 时创建新回合；已有 active turn 时发送 steer，保持完整工具循环。
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    // 新回合：先开一个临时 turn 分组承载用户消息，待 turn 真正启动后重命名为真实 turn id。
    // steer：追加到当前回合的分组里。
    final isNewTurn = _activeTurn == null;
    if (isNewTurn) {
      _pendingTurnGroupId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
      _currentTurnGroupId = _pendingTurnGroupId;
    }
    _addConversationMessage(
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
    _notify();

    try {
      await loadSettings();
      final provider = await _ensureProvider();
      final context = AgentContext(
        projectPath: _projectPath,
        filePath: _contextFilePath,
      );
      final session = await _ensureSession(provider, context);
      _log.info('Sending Agent request with provider ${provider.config.id}');
      // 同一个输入框承担“新请求”和“追加 steer”两种行为。
      if (isNewTurn) {
        _activeTurn = await provider.sendMessage(
          session: session,
          message: _messageWithContext(trimmed),
          context: context,
        );
        // 兜底：若 provider 未推送 AgentTurnStartedEvent（或事件尚未重命名临时分组），
        // 用返回的 turn id 把临时分组改成真实回合。
        final pendingId = _pendingTurnGroupId;
        if (pendingId != null && _activeTurn != null) {
          _beginLiveTurnGroup(_activeTurn!);
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
      _markUnavailable(error.message, details: error.toString());
    } on UnsupportedError catch (error, stackTrace) {
      _log.warning('Unsupported Agent provider', error, stackTrace);
      _markError(error.message ?? 'Provider is not supported');
    } catch (error, stackTrace) {
      _log.warning('Agent request failed', error, stackTrace);
      _markError('Agent request failed', details: error.toString());
    } finally {
      // 未能启动 turn 时清理临时分组标记；成功时由 AgentTurnStartedEvent 处理已清空。
      _pendingTurnGroupId = null;
    }
  }

  /// 取消正在运行的回合。
  Future<void> cancelActiveTurn() async {
    final turn = _activeTurn;
    final provider = _provider;
    if (turn == null || provider == null) {
      return;
    }
    _log.info('Cancelling Agent turn ${turn.id}');
    await provider.cancelTurn(turn);
  }

  /// 切换到项目列表中选中的 thread。
  ///
  /// 运行中的回合不能切换，调用方会先检查 [isRunning] 并给用户提示。
  Future<void> switchThread(AgentThreadSummary thread) async {
    if (isRunning) {
      return;
    }

    final switchToken = ++_threadSwitchToken;
    _session = null;
    _activeTurn = null;
    _restoredSessionId = thread.id;
    _currentThreadTitle = thread.displayName;
    _clearConversation();
    _status = const AgentProviderStatus(
      state: AgentProviderConnectionState.connecting,
      message: 'Loading history',
    );
    _notify();

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
      _applyHistorySnapshot(history, thread);
      _status = const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: 'Opening thread',
      );
      _notify();
    } catch (error, stackTrace) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _log.warning(
        'Could not load Agent thread history ${thread.id}',
        error,
        stackTrace,
      );
      _markError('Could not load thread history', details: error.toString());
      return;
    }

    try {
      final provider = await _ensureProvider();
      final session = await provider.resumeSession(
        thread.id,
        context: AgentContext(
          projectPath: _projectPath ?? thread.projectPath,
          filePath: _contextFilePath,
        ),
      );
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _session = session;
      _restoredSessionId = session.id;
      _applySessionTitle(session);
      _status = AgentProviderStatus(
        state: AgentProviderConnectionState.ready,
        message: '$activeProviderName ready',
      );
      _notify();
    } catch (error, stackTrace) {
      if (!_isCurrentSwitch(switchToken)) {
        return;
      }
      _log.warning(
        'Could not resume Agent thread ${thread.id}',
        error,
        stackTrace,
      );
      _markError('Could not open Agent thread', details: error.toString());
    }
  }

  /// 处理审批卡片的 approve/deny。
  ///
  /// UI 先移除卡片，再异步回写 provider，避免按钮点击后卡片停留造成重复提交。
  Future<void> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
  }) async {
    _removePermissionRequest(request.id);
    _notify();
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
    unawaited(_eventSubscription?.cancel());
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
    _eventSubscription = provider.events.listen(_handleEvent);
    return provider;
  }

  Future<AgentSession> _ensureSession(
    AgentProvider provider,
    AgentContext context,
  ) async {
    final existing = _session;
    if (existing != null) {
      return existing;
    }

    final restoredSessionId = _restoredSessionId;
    if (restoredSessionId != null) {
      try {
        _log.fine('Resuming Agent session $restoredSessionId');
        // 先尝试恢复上次 thread；失败时回退到新建 thread。
        _session = await provider.resumeSession(
          restoredSessionId,
          context: context,
        );
        _applySessionTitle(_session!);
        return _session!;
      } catch (error, stackTrace) {
        _log.warning(
          'Could not resume Agent session $restoredSessionId',
          error,
          stackTrace,
        );
        _restoredSessionId = null;
      }
    }

    _log.fine('Starting new Agent session with provider ${provider.config.id}');
    _session = await provider.startSession(context: context);
    _restoredSessionId = _session!.id;
    _applySessionTitle(_session!);
    return _session!;
  }

  /// 将 provider 事件规约成面板状态。
  void _handleEvent(AgentEvent event) {
    switch (event) {
      case AgentStatusEvent():
        _status = event.status;
      case AgentSessionStartedEvent():
        _session = event.session;
        _restoredSessionId = event.session.id;
        _applySessionTitle(event.session);
      case AgentTurnStartedEvent():
        _activeTurn = event.turn;
        _beginLiveTurnGroup(event.turn);
      case AgentTurnCompletedEvent():
        _activeTurn = null;
        _completeLiveTurnGroup(event.turnId);
        if (_status.state == AgentProviderConnectionState.running) {
          _status = AgentProviderStatus(
            state: AgentProviderConnectionState.ready,
            message: '$activeProviderName ready',
          );
        }
      case AgentTokenUsageEvent():
        _updateTurnTokenUsage(event);
      case AgentMessageDeltaEvent():
        _appendMessageDelta(event);
      case AgentMessageUpdatedEvent():
        _updateMessage(event);
      case AgentPlanUpdatedEvent():
        _upsertPlanMessage(event);
      case AgentToolCallEvent():
        _upsertToolCall(event.toolCall);
      case AgentPermissionRequestedEvent():
        _addPermissionRequest(event.request);
      case AgentModelListEvent():
        _handleModelList(event.models);
      case AgentErrorEvent():
        _addConversationMessage(
          AgentConversationMessage(
            id: 'error-${DateTime.now().microsecondsSinceEpoch}',
            role: AgentMessageRole.system,
            text: event.details == null
                ? event.message
                : '${event.message}: ${event.details}',
          ),
        );
    }
    _notify();
  }

  /// 合并流式消息增量。
  ///
  /// 同一个 provider messageId 首次出现时创建气泡，后续 delta 追加到同一条消息。
  void _appendMessageDelta(AgentMessageDeltaEvent event) {
    final existingIndex = _messageIndexesByProviderId[event.messageId];
    final kind = _messageKindFromRaw(role: event.role, raw: event.raw);
    if (existingIndex == null) {
      _messageIndexesByProviderId[event.messageId] = _messages.length;
      _addConversationMessage(
        AgentConversationMessage(
          id: event.messageId,
          role: event.role,
          text: event.delta,
          kind: kind,
          phase: event.phase,
          status: event.status,
          duration: event.duration,
          raw: event.raw,
        ),
      );
      return;
    }
    final existing = _messages[existingIndex];
    final updated = existing.copyWith(
      text: '${existing.text}${event.delta}',
      kind: kind == AgentConversationMessageKind.plan ? kind : existing.kind,
      phase: event.phase,
      status: event.status,
      duration: event.duration,
      raw: event.raw.isEmpty ? null : event.raw,
    );
    _messages[existingIndex] = updated;
    _replaceTimelineMessage(updated);
  }

  /// 用 completed item 通知更新已有消息 metadata。
  void _updateMessage(AgentMessageUpdatedEvent event) {
    final existingIndex = _messageIndexesByProviderId[event.messageId];
    final role = event.role ?? AgentMessageRole.agent;
    final kind = _messageKindFromRaw(role: role, raw: event.raw);
    if (existingIndex == null) {
      final text = event.text?.trim();
      if (text == null || text.isEmpty) {
        return;
      }
      _messageIndexesByProviderId[event.messageId] = _messages.length;
      _addConversationMessage(
        AgentConversationMessage(
          id: event.messageId,
          role: role,
          text: text,
          kind: kind,
          phase: event.phase,
          status: event.status,
          duration: event.duration,
          raw: event.raw,
        ),
      );
      return;
    }

    final existing = _messages[existingIndex];
    final updated = existing.copyWith(
      role: event.role,
      text: event.text,
      kind: kind == AgentConversationMessageKind.plan ? kind : existing.kind,
      phase: event.phase,
      status: event.status,
      duration: event.duration,
      raw: event.raw.isEmpty ? null : event.raw,
    );
    _messages[existingIndex] = updated;
    _replaceTimelineMessage(updated);
  }

  /// 将 Agent 计划更新渲染为可折叠的 markdown 消息。
  void _upsertPlanMessage(AgentPlanUpdatedEvent event) {
    final messageId = '${event.turnId ?? 'current'}-plan';
    final message = AgentConversationMessage(
      id: messageId,
      role: AgentMessageRole.agent,
      text: _planMarkdownFromEntries(event.entries),
      kind: AgentConversationMessageKind.plan,
      raw: <String, Object?>{
        'type': 'plan',
        'entries': <Map<String, String?>>[
          for (final entry in event.entries)
            <String, String?>{
              'content': entry.content,
              'status': entry.status,
              'priority': entry.priority,
            },
        ],
      },
    );
    final existingIndex = _messageIndexesByProviderId[messageId];
    if (existingIndex == null) {
      _messageIndexesByProviderId[messageId] = _messages.length;
      _addConversationMessage(message);
      return;
    }
    _messages[existingIndex] = message;
    _replaceTimelineMessage(message);
  }

  /// 插入或更新工具卡片。
  void _upsertToolCall(AgentToolCall toolCall) {
    final index = _toolCalls.indexWhere((item) => item.id == toolCall.id);
    if (index == -1) {
      _toolCalls.add(toolCall);
      _appendTimelineEntry(AgentToolTimelineEntry(toolCall: toolCall));
      return;
    }
    _toolCalls[index] = toolCall;
    _replaceTimelineTool(toolCall);
  }

  /// 把当前文件路径作为文本上下文附加给 provider。
  ///
  /// V1 不读取文件内容，只让 agent 知道用户当前选中的文件路径。
  String _messageWithContext(String message) {
    final filePath = _contextFilePath;
    if (filePath == null) {
      return message;
    }
    return '$message\n\nCurrent file context: $filePath';
  }

  /// 标记 provider 不可用，例如本机没有安装 Codex CLI。
  void _markUnavailable(String message, {String? details}) {
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.unavailable,
      message: message,
      details: details,
    );
    _addConversationMessage(
      AgentConversationMessage(
        id: 'unavailable-${DateTime.now().microsecondsSinceEpoch}',
        role: AgentMessageRole.system,
        text: details == null ? message : '$message: $details',
      ),
    );
    _notify();
  }

  /// 标记通用错误。
  void _markError(String message, {String? details}) {
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.error,
      message: message,
      details: details,
    );
    _addConversationMessage(
      AgentConversationMessage(
        id: 'error-${DateTime.now().microsecondsSinceEpoch}',
        role: AgentMessageRole.system,
        text: details == null ? message : '$message: $details',
      ),
    );
    _notify();
  }

  bool _isCurrentSwitch(int switchToken) {
    return !_disposed && switchToken == _threadSwitchToken;
  }

  int? _sumOptionalInt(int? left, int? right) {
    if (right == null) {
      return left;
    }
    return (left ?? 0) + right;
  }

  /// 优先使用 provider 返回的 thread 标题；空标题时保留当前标题。
  void _applySessionTitle(AgentSession session) {
    final title = session.title?.trim();
    if (title == null || title.isEmpty) {
      return;
    }
    _currentThreadTitle = title;
  }

  void _clearConversation() {
    _messages.clear();
    _toolCalls.clear();
    _permissionRequests.clear();
    _timelineEntries.clear();
    _timelineEntryTurnIds.clear();
    _turnMetadata.clear();
    _messageIndexesByProviderId.clear();
    _expandedToolCallIds.clear();
    _expandedPlanMessageIds.clear();
    _expandedCommandGroupIds.clear();
    _expandedFileEditItemIds.clear();
    _currentTurnGroupId = null;
    _pendingTurnGroupId = null;
  }

  void _applyHistorySnapshot(
    AgentThreadHistorySnapshot history,
    AgentThreadSummary thread,
  ) {
    _clearConversation();
    if (history.turns.isEmpty) {
      _addConversationMessage(
        AgentConversationMessage(
          id: 'selected-${DateTime.now().microsecondsSinceEpoch}',
          role: AgentMessageRole.system,
          text: 'Selected thread: ${thread.displayName}',
        ),
      );
      return;
    }

    // 按返回的 turn 集合逐回合重建时间线，每个 turn 自带消息体列表。
    for (final turn in history.turns) {
      _currentTurnGroupId = turn.id;
      _turnMetadata[turn.id] = _TurnGroupMetadata(
        status: turn.status,
        startedAt: turn.startedAt,
        completedAt: turn.completedAt,
        duration: turn.duration,
        tokenUsage: turn.tokenUsage,
      );
      for (final entry in turn.entries) {
        switch (entry) {
          case AgentHistoryMessageEntry():
            _messageIndexesByProviderId[entry.id] = _messages.length;
            _addConversationMessage(
              AgentConversationMessage(
                id: entry.id,
                role: entry.role,
                text: entry.text,
                kind: _messageKindFromRaw(role: entry.role, raw: entry.raw),
                phase: entry.phase,
                status: entry.status,
                duration: entry.duration,
                raw: entry.raw,
              ),
            );
          case AgentHistoryToolEntry():
            _upsertToolCall(entry.toolCall);
          case AgentHistoryEventEntry():
            _appendTimelineEntry(AgentHistoryEventTimelineEntry(event: entry));
        }
      }
    }
    _currentTurnGroupId = null;
  }

  void _addConversationMessage(AgentConversationMessage message) {
    _messages.add(message);
    _appendTimelineEntry(AgentMessageTimelineEntry(message: message));
  }

  /// 追加时间线条目，并打上当前 turn 分组 id。
  void _appendTimelineEntry(AgentTimelineEntry entry) {
    _timelineEntries.add(entry);
    _timelineEntryTurnIds.add(_currentTurnGroupId ?? _standbyTurnId);
    _markTimelineChanged();
  }

  void _replaceTimelineMessage(AgentConversationMessage message) {
    final index = _timelineEntries.indexWhere(
      (entry) =>
          entry is AgentMessageTimelineEntry && entry.message.id == message.id,
    );
    if (index == -1) {
      return;
    }
    _timelineEntries[index] = AgentMessageTimelineEntry(message: message);
    _markTimelineChanged();
  }

  void _replaceTimelineTool(AgentToolCall toolCall) {
    final index = _timelineEntries.indexWhere(
      (entry) =>
          entry is AgentToolTimelineEntry && entry.toolCall.id == toolCall.id,
    );
    if (index == -1) {
      return;
    }
    _timelineEntries[index] = AgentToolTimelineEntry(toolCall: toolCall);
    _markTimelineChanged();
  }

  void _addPermissionRequest(AgentPermissionRequest request) {
    _permissionRequests.add(request);
    _appendTimelineEntry(AgentPermissionTimelineEntry(request: request));
  }

  void _removePermissionRequest(String requestId) {
    _permissionRequests.removeWhere((item) => item.id == requestId);
    var index = 0;
    while (index < _timelineEntries.length) {
      final entry = _timelineEntries[index];
      if (entry is AgentPermissionTimelineEntry &&
          entry.request.id == requestId) {
        _timelineEntries.removeAt(index);
        _timelineEntryTurnIds.removeAt(index);
      } else {
        index += 1;
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _markTimelineChanged() {
    _autoScrollTick += 1;
  }

  /// turn 真正启动时，把 sendMessage 建立的临时分组重命名为真实 turn id，
  /// 并记录运行状态与起始时间。后续条目都会归到该分组。
  void _beginLiveTurnGroup(AgentTurn turn) {
    final pendingId = _pendingTurnGroupId;
    if (pendingId != null && pendingId != turn.id) {
      _renameTurnGroup(pendingId, turn.id);
    }
    _currentTurnGroupId = turn.id;
    _pendingTurnGroupId = null;
    final existing = _turnMetadata[turn.id];
    _turnMetadata[turn.id] = _TurnGroupMetadata(
      status: AgentHistoryTurnStatus.running,
      startedAt: existing?.startedAt ?? DateTime.now(),
      completedAt: existing?.completedAt,
      duration: existing?.duration,
      tokenUsage: existing?.tokenUsage,
    );
  }

  /// turn 完成时更新分组元数据；后续条目回到 standby 分组。
  void _completeLiveTurnGroup(String turnId) {
    final meta = _turnMetadata[turnId];
    final completedAt = DateTime.now();
    _turnMetadata[turnId] = _TurnGroupMetadata(
      status: AgentHistoryTurnStatus.completed,
      startedAt: meta?.startedAt,
      completedAt: completedAt,
      duration: meta?.startedAt == null
          ? null
          : completedAt.difference(meta!.startedAt!),
      tokenUsage: meta?.tokenUsage,
    );
    _currentTurnGroupId = null;
  }

  /// 用 provider 上报的 token 用量更新对应回合分组的元数据。
  ///
  /// 优先按事件中的 turnId 定位分组；缺失时回退到当前活跃回合或 standby。
  void _updateTurnTokenUsage(AgentTokenUsageEvent event) {
    final turnId = event.turnId ?? _activeTurn?.id ?? _currentTurnGroupId;
    if (turnId == null) {
      return;
    }
    final meta = _turnMetadata[turnId];
    _turnMetadata[turnId] = _TurnGroupMetadata(
      status: meta?.status,
      startedAt: meta?.startedAt,
      completedAt: meta?.completedAt,
      duration: meta?.duration,
      tokenUsage: event.tokenUsage,
    );
  }

  /// 把某个 turn 分组的 id 改名，同步更新条目侧的归属索引。
  void _renameTurnGroup(String oldId, String newId) {
    for (var index = 0; index < _timelineEntryTurnIds.length; index += 1) {
      if (_timelineEntryTurnIds[index] == oldId) {
        _timelineEntryTurnIds[index] = newId;
      }
    }
    final meta = _turnMetadata.remove(oldId);
    if (meta != null) {
      _turnMetadata[newId] = meta;
    }
  }
}

AgentConversationMessageKind _messageKindFromRaw({
  required AgentMessageRole role,
  required Map<String, Object?> raw,
}) {
  if (role != AgentMessageRole.agent) {
    return AgentConversationMessageKind.regular;
  }
  return _rawContainsPlanType(raw)
      ? AgentConversationMessageKind.plan
      : AgentConversationMessageKind.regular;
}

bool _rawContainsPlanType(Map<String, Object?> raw) {
  return _normalizedMessageType(_stringFromObject(raw['type'])) == 'plan' ||
      _normalizedMessageType(
            _stringFromObject(_mapFromObject(raw['item'])['type']),
          ) ==
          'plan' ||
      _normalizedMessageType(
            _stringFromObject(_mapFromObject(raw['payload'])['type']),
          ) ==
          'plan' ||
      _normalizedMessageType(
            _stringFromObject(
              _mapFromObject(_mapFromObject(raw['payload'])['item'])['type'],
            ),
          ) ==
          'plan';
}

String _planMarkdownFromEntries(List<AgentPlanEntry> entries) {
  if (entries.isEmpty) {
    return 'Plan';
  }
  return entries
      .map((entry) {
        final marker = switch (_normalizedMessageType(entry.status)) {
          'completed' || 'complete' || 'done' => '- [x]',
          'pending' || 'inprogress' || 'running' || 'started' => '- [ ]',
          _ => '-',
        };
        return '$marker ${entry.content}';
      })
      .join('\n');
}

String? _normalizedMessageType(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
}

String? _stringFromObject(Object? value) {
  return value is String ? value : null;
}

Map<String, Object?> _mapFromObject(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final map = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      map[key] = entry.value;
    }
  }
  return map;
}

/// Agent 消息在 UI 中的展示类型。
enum AgentConversationMessageKind { regular, plan }

/// Agent 面板中的单条对话消息。
class AgentConversationMessage {
  const AgentConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    this.kind = AgentConversationMessageKind.regular,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
  });

  final String id;
  final AgentMessageRole role;
  final String text;
  final AgentConversationMessageKind kind;
  final AgentMessagePhase? phase;
  final AgentMessageStatus? status;
  final Duration? duration;
  final Map<String, Object?> raw;

  bool get isPlan => kind == AgentConversationMessageKind.plan;

  bool get isCompletedCommentary {
    return role == AgentMessageRole.agent &&
        phase == AgentMessagePhase.commentary &&
        status == AgentMessageStatus.completed;
  }

  AgentConversationMessage copyWith({
    AgentMessageRole? role,
    String? text,
    AgentConversationMessageKind? kind,
    AgentMessagePhase? phase,
    AgentMessageStatus? status,
    Duration? duration,
    Map<String, Object?>? raw,
  }) {
    return AgentConversationMessage(
      id: id,
      role: role ?? this.role,
      text: text ?? this.text,
      kind: kind ?? this.kind,
      phase: phase ?? this.phase,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      raw: raw ?? this.raw,
    );
  }
}

/// Agent 面板的统一时间线条目。
///
/// 历史记录和实时 provider 事件都会转换成这些条目，避免 UI 按类型分段后打乱顺序。
sealed class AgentTimelineEntry {
  const AgentTimelineEntry({required this.id});

  /// UI 时间线中的稳定 id。
  final String id;
}

/// 时间线消息条目。
class AgentMessageTimelineEntry extends AgentTimelineEntry {
  AgentMessageTimelineEntry({required this.message})
    : super(id: 'message-${message.id}');

  final AgentConversationMessage message;
}

/// 时间线工具调用条目。
class AgentToolTimelineEntry extends AgentTimelineEntry {
  AgentToolTimelineEntry({required this.toolCall})
    : super(id: 'tool-${toolCall.id}');

  final AgentToolCall toolCall;
}

/// 时间线审批请求条目。
class AgentPermissionTimelineEntry extends AgentTimelineEntry {
  AgentPermissionTimelineEntry({required this.request})
    : super(id: 'permission-${request.id}');

  final AgentPermissionRequest request;
}

/// 时间线历史事件条目。
class AgentHistoryEventTimelineEntry extends AgentTimelineEntry {
  AgentHistoryEventTimelineEntry({required this.event})
    : super(id: 'history-event-${event.id}');

  final AgentHistoryEventEntry event;
}

/// Agent 面板按 turn 聚合后的分组，供 UI 分回合渲染。
///
/// 每个 [AgentConversationTurnGroup] 携带该回合内的消息体列表 [entries]，
/// 以及可选的运行状态、起止时间、耗时和 token 用量。standby 分组
/// （welcome、回合外系统提示）的 [isStandby] 为 true，UI 可以选择不渲染分组标题。
class AgentConversationTurnGroup {
  const AgentConversationTurnGroup({
    required this.id,
    required this.entries,
    required this.isStandby,
    this.status,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.tokenUsage,
  });

  /// 分组 id；真实回合为 turn id，standby 为 `__standby__`。
  final String id;

  /// 该回合内按顺序排列的时间线条目（消息、工具卡、审批、历史事件）。
  final List<AgentTimelineEntry> entries;

  /// 是否为回合外的 standby 分组。
  final bool isStandby;

  /// 回合运行状态；standby 分组为 null。
  final AgentHistoryTurnStatus? status;

  /// 回合开始时间。
  final DateTime? startedAt;

  /// 回合完成时间。
  final DateTime? completedAt;

  /// 回合耗时。
  final Duration? duration;

  /// 回合 token 消耗统计；standby 分组为 null。
  final AgentTokenUsage? tokenUsage;
}

/// turn 分组的运行时元数据（内部使用）。
class _TurnGroupMetadata {
  const _TurnGroupMetadata({
    this.status,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.tokenUsage,
  });

  final AgentHistoryTurnStatus? status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final AgentTokenUsage? tokenUsage;
}
