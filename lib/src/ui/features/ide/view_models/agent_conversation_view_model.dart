import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

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
  AgentConversationViewModel({required this.providerController}) {
    _seedInitialStandbyTimeline();
  }

  static const String defaultThreadTitle = 'New thread';
  static const int _historyPageSize = 3;
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
  String? _projectPath;
  String? _contextFilePath;

  /// 从会话恢复出的 thread id；真正发送消息时再尝试 resume。
  String? _restoredSessionId;
  AgentThreadOpenPhase _threadOpenPhase = AgentThreadOpenPhase.idle;
  bool _requiresResumedSelectedThread = false;
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

  /// 时间线条目所属的 turn id，用于增量更新 turn store。
  final Map<String, String> _turnIdsByTimelineEntryId = <String, String>{};

  /// 已加载历史 turn 的顺序；只对线程历史分页窗口生效。
  final List<String> _historicalTurnOrder = <String>[];

  /// 当前会话新增的 live turn 顺序；不参与“加载更早”窗口裁剪。
  final List<String> _liveTurnOrder = <String>[];

  /// turn 分组的增量缓存，避免每次从扁平 timeline 全量 regroup。
  final Map<String, AgentConversationTurnState> _turnGroups =
      <String, AgentConversationTurnState>{};

  /// 历史区版本；仅在可见历史/standby 区发生变化时递增。
  final ValueNotifier<int> _historyVersionNotifier = ValueNotifier<int>(0);

  /// 标题区版本；thread 标题、运行状态、token 汇总变化时递增。
  final ValueNotifier<int> _headerVersionNotifier = ValueNotifier<int>(0);

  /// 输入区版本；模型列表、发送/取消按钮状态变化时递增。
  final ValueNotifier<int> _composerVersionNotifier = ValueNotifier<int>(0);

  /// 自动滚动信号；仅在需要“可能滚到底部”时递增。
  final ValueNotifier<int> _autoScrollTickNotifier = ValueNotifier<int>(0);

  /// 当前 live turn 引用；仅在 live turn 绑定切换时通知。
  final ValueNotifier<AgentConversationTurnState?> _liveTurnNotifier =
      ValueNotifier<AgentConversationTurnState?>(null);

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
  int _visibleHistoryStartIndex = 0;
  String _currentThreadTitle = defaultThreadTitle;
  AgentProviderStatus _status = const AgentProviderStatus.idle();
  Timer? _streamFlushTimer;
  bool _streamNeedsLiveFlush = false;
  bool _streamNeedsHeaderFlush = false;
  bool _streamNeedsAutoScroll = false;

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
  /// 历史只显示当前可见窗口内的 turn；live turn 和 standby 分组始终可见。
  List<AgentConversationTurnGroup> get conversationTurns {
    final visibleTurnIds = <String>[
      if (standbyTurnState case final standby? when standby.entries.isNotEmpty)
        standby.id,
      for (final turn in visibleHistoryTurnStates) turn.id,
      if (liveTurnState case final live?) live.id,
    ];
    return List<AgentConversationTurnGroup>.unmodifiable(
      <AgentConversationTurnGroup>[
        for (final turnId in visibleTurnIds) _turnGroupSnapshot(turnId),
      ],
    );
  }

  /// 当前分页窗口内的历史 turn 集合，不包含 standby/live turn。
  List<AgentConversationTurnGroup> get visibleHistoryTurns =>
      List<AgentConversationTurnGroup>.unmodifiable(
        <AgentConversationTurnGroup>[
          for (final turn in visibleHistoryTurnStates) turn.snapshot(),
        ],
      );

  AgentConversationTurnState? get standbyTurnState =>
      _turnGroups[_standbyTurnId];

  List<AgentConversationTurnState> get visibleHistoryTurnStates =>
      List<AgentConversationTurnState>.unmodifiable(
        _historicalTurnOrder
            .skip(_visibleHistoryStartIndex)
            .map((turnId) => _turnGroups[turnId])
            .whereType<AgentConversationTurnState>(),
      );

  AgentConversationTurnState? get liveTurnState => _liveTurnNotifier.value;

  /// 历史窗口前面是否还有更早的 turn 未展开。
  bool get hasOlderTurns => _visibleHistoryStartIndex > 0;

  AgentProviderStatus get status => _status;

  int get autoScrollTick => _autoScrollTickNotifier.value;

  int get historyVersion => _historyVersionNotifier.value;

  int get headerVersion => _headerVersionNotifier.value;

  int get composerVersion => _composerVersionNotifier.value;

  ValueListenable<int> get historyVersionListenable => _historyVersionNotifier;

  ValueListenable<int> get headerVersionListenable => _headerVersionNotifier;

  ValueListenable<int> get composerVersionListenable =>
      _composerVersionNotifier;

  ValueListenable<int> get autoScrollTickListenable => _autoScrollTickNotifier;

  ValueListenable<AgentConversationTurnState?> get liveTurnListenable =>
      _liveTurnNotifier;

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

  bool get showRunningIndicator => isTurnRunning;

  AgentThreadOpenPhase get threadOpenPhase => _threadOpenPhase;

  bool get requiresResumedSelectedThread => _requiresResumedSelectedThread;

  AgentTokenUsage? get currentTurnTokenUsage {
    final runningTurnId = _selectedRunningTurnId();
    if (runningTurnId == null) {
      return null;
    }
    return _turnGroups[runningTurnId]?.tokenUsage;
  }

  /// 当前 thread 下所有 turn 的累计 token 用量，用于标题栏右侧展示总成本。
  AgentTokenUsage? get currentThreadTokenUsage {
    int? inputTokens;
    int? cachedInputTokens;
    int? outputTokens;
    int? reasoningOutputTokens;
    int? totalTokens;

    for (final turn in _turnGroups.values) {
      if (turn.isStandby) {
        continue;
      }
      final usage = turn.tokenUsage;
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

  bool get isTurnRunning => _selectedRunningTurnId() != null;

  bool get isRunning => isTurnRunning;

  bool get canSubmitMessage => _threadOpenPhase == AgentThreadOpenPhase.idle;

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

  /// 扩大历史窗口，一次多显示固定页数的更早 turn。
  bool loadOlderTurns() {
    final nextStartIndex = math.max(
      0,
      _visibleHistoryStartIndex - _historyPageSize,
    );
    if (nextStartIndex == _visibleHistoryStartIndex) {
      return false;
    }
    _visibleHistoryStartIndex = nextStartIndex;
    _publishUiChanges(history: true);
    return true;
  }

  void toggleToolCall(String toolCallId) {
    if (!_expandedToolCallIds.add(toolCallId)) {
      _expandedToolCallIds.remove(toolCallId);
    }
    _publishUiChanges(history: true, liveTurn: true);
  }

  /// 切换计划消息折叠状态。
  void togglePlanMessage(String messageId) {
    if (!_expandedPlanMessageIds.add(messageId)) {
      _expandedPlanMessageIds.remove(messageId);
    }
    _publishUiChanges(history: true, liveTurn: true);
  }

  /// 切换命令集折叠状态。
  void toggleCommandGroup(String commandGroupId) {
    if (!_expandedCommandGroupIds.add(commandGroupId)) {
      _expandedCommandGroupIds.remove(commandGroupId);
    }
    _publishUiChanges(history: true, liveTurn: true);
  }

  /// 切换文件编辑项详情展开状态。
  void toggleFileEditItem(String fileEditItemId) {
    if (!_expandedFileEditItemIds.add(fileEditItemId)) {
      _expandedFileEditItemIds.remove(fileEditItemId);
    }
    _publishUiChanges(history: true, liveTurn: true);
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
    _publishUiChanges(composer: true);
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
    _publishUiChanges(composer: true);
  }

  /// 处理 provider 推送的模型列表。
  ///
  /// 首次到达时根据 config 选择和模型默认值初始化有效选择；
  /// 后续更新只刷新列表，保留用户已选模型（若仍存在）。
  void _handleModelList(AgentModelList modelList) {
    _modelList = modelList;
    _reconcileSelection();
    _publishUiChanges(composer: true);
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
    final runningTurnId = _selectedRunningTurnId();

    // 新回合：先开一个临时 turn 分组承载用户消息，待 turn 真正启动后重命名为真实 turn id。
    // steer：追加到当前回合的分组里。
    final isNewTurn = runningTurnId == null;
    if (isNewTurn) {
      _pendingTurnGroupId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
      _currentTurnGroupId = _pendingTurnGroupId;
      _turnStateFor(
        _pendingTurnGroupId!,
        isStandby: false,
        isHistorical: false,
      ).updateMetadata(
        status: AgentHistoryTurnStatus.running,
        startedAt: DateTime.now(),
      );
    } else {
      _currentTurnGroupId = runningTurnId;
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
      // 同一个输入框承担“新请求”和“追加 steer”两种行为。
      if (isNewTurn) {
        final turn = await provider.sendMessage(
          session: session,
          message: _messageWithContext(trimmed),
          context: context,
        );
        // 兜底：若 provider 未推送 AgentTurnStartedEvent（或事件尚未重命名临时分组），
        // 用返回的 turn id 把临时分组改成真实回合。
        final pendingId = _pendingTurnGroupId;
        if (pendingId != null &&
            _isStillSelectedThread(switchToken, session.id)) {
          _beginLiveTurnGroup(turn);
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
      // 未能启动 turn 时清理临时分组标记；成功时由 AgentTurnStartedEvent 处理已清空。
      _pendingTurnGroupId = null;
    }
  }

  /// 取消正在运行的回合。
  Future<void> cancelActiveTurn() async {
    final provider = _provider;
    final turnId = _selectedCancelableTurnId();
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
    _clearConversation();
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
      _applyHistorySnapshot(history, thread);
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
    _removePermissionRequest(request.id);
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
    _streamFlushTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    for (final turn in _turnGroups.values) {
      turn.dispose();
    }
    _historyVersionNotifier.dispose();
    _headerVersionNotifier.dispose();
    _composerVersionNotifier.dispose();
    _autoScrollTickNotifier.dispose();
    _liveTurnNotifier.dispose();
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
        // 先尝试恢复上次 thread；普通工作区恢复失败时才回退到新建 thread。
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
        _beginLiveTurnGroup(event.turn);
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
        _completeLiveTurnGroup(event.turnId);
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
        _updateTurnTokenUsage(event);
        _scheduleStreamFlush(header: true);
      case AgentMessageDeltaEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _appendMessageDelta(event);
        _scheduleStreamFlush(autoScroll: true);
      case AgentMessageUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _updateMessage(event);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentPlanUpdatedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.sessionId,
          turnId: event.turnId,
        )) {
          break;
        }
        _upsertPlanMessage(event);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentToolCallEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.toolCall.sessionId,
          turnId: event.toolCall.turnId,
        )) {
          break;
        }
        _upsertToolCall(event.toolCall);
        _flushStreamChangesNow(liveTurn: true, autoScroll: true);
      case AgentPermissionRequestedEvent():
        if (!_shouldHandleEventForCurrentThread(
          sessionId: event.request.sessionId,
          turnId: event.request.turnId,
        )) {
          break;
        }
        _addPermissionRequest(event.request);
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
        _addConversationMessage(
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
    final turnId = _addConversationMessage(
      AgentConversationMessage(
        id: 'unavailable-${DateTime.now().microsecondsSinceEpoch}',
        role: AgentMessageRole.system,
        text: details == null ? message : '$message: $details',
      ),
    );
    _publishUiChanges(
      history: _isHistoryTurnId(turnId),
      liveTurn: _isLiveTurnId(turnId),
      header: true,
      composer: true,
      autoScroll: true,
    );
  }

  /// 标记通用错误。
  void _markError(String message, {String? details}) {
    _status = AgentProviderStatus(
      state: AgentProviderConnectionState.error,
      message: message,
      details: details,
    );
    final turnId = _addConversationMessage(
      AgentConversationMessage(
        id: 'error-${DateTime.now().microsecondsSinceEpoch}',
        role: AgentMessageRole.system,
        text: details == null ? message : '$message: $details',
      ),
    );
    _publishUiChanges(
      history: _isHistoryTurnId(turnId),
      liveTurn: _isLiveTurnId(turnId),
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
      return _turnGroups.containsKey(turnId) || turnId == _pendingTurnGroupId;
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

  String? _selectedRunningTurnId() {
    final currentTurnGroupId = _currentTurnGroupId;
    if (_turnGroups[currentTurnGroupId]?.status ==
        AgentHistoryTurnStatus.running) {
      return currentTurnGroupId;
    }

    for (var index = _liveTurnOrder.length - 1; index >= 0; index -= 1) {
      final turnId = _liveTurnOrder[index];
      if (_turnGroups[turnId]?.status == AgentHistoryTurnStatus.running) {
        return turnId;
      }
    }

    for (var index = _historicalTurnOrder.length - 1; index >= 0; index -= 1) {
      final turnId = _historicalTurnOrder[index];
      if (_turnGroups[turnId]?.status == AgentHistoryTurnStatus.running) {
        return turnId;
      }
    }

    for (final entry in _turnGroups.entries) {
      if (entry.value.status == AgentHistoryTurnStatus.running) {
        return entry.key;
      }
    }
    return null;
  }

  String? _selectedCancelableTurnId() {
    final turnId = _selectedRunningTurnId();
    if (turnId == null || turnId == _pendingTurnGroupId) {
      return null;
    }
    return turnId;
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

  void _seedInitialStandbyTimeline() {
    final standbyGroup = _turnStateFor(
      _standbyTurnId,
      isStandby: true,
      isHistorical: false,
    );
    standbyGroup.appendEntry(_timelineEntries.single);
    _turnIdsByTimelineEntryId[_timelineEntries.single.id] = _standbyTurnId;
  }

  void _clearConversation() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _streamNeedsLiveFlush = false;
    _streamNeedsHeaderFlush = false;
    _streamNeedsAutoScroll = false;
    _messages.clear();
    _toolCalls.clear();
    _permissionRequests.clear();
    _timelineEntries.clear();
    _timelineEntryTurnIds.clear();
    _turnIdsByTimelineEntryId.clear();
    _historicalTurnOrder.clear();
    _liveTurnOrder.clear();
    _turnGroups.clear();
    _liveTurnNotifier.value = null;
    _messageIndexesByProviderId.clear();
    _expandedToolCallIds.clear();
    _expandedPlanMessageIds.clear();
    _expandedCommandGroupIds.clear();
    _expandedFileEditItemIds.clear();
    _currentTurnGroupId = null;
    _pendingTurnGroupId = null;
    _visibleHistoryStartIndex = 0;
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
    String? runningTurnId;
    for (final turn in history.turns) {
      final isRunningTurn = turn.status == AgentHistoryTurnStatus.running;
      _registerHistoryTurn(turn, asLive: isRunningTurn);
      _currentTurnGroupId = turn.id;
      if (isRunningTurn) {
        runningTurnId = turn.id;
      }
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
    _visibleHistoryStartIndex = _defaultVisibleHistoryStartIndexForLength(
      _historicalTurnOrder.length,
    );
    _currentTurnGroupId = runningTurnId;
    _syncLiveTurnBinding();
  }

  String _addConversationMessage(AgentConversationMessage message) {
    _messages.add(message);
    return _appendTimelineEntry(AgentMessageTimelineEntry(message: message));
  }

  /// 追加时间线条目，并打上当前 turn 分组 id。
  String _appendTimelineEntry(AgentTimelineEntry entry) {
    final turnId = _currentTurnGroupId ?? _standbyTurnId;
    _timelineEntries.add(entry);
    _timelineEntryTurnIds.add(turnId);
    _turnIdsByTimelineEntryId[entry.id] = turnId;
    _turnStateFor(
      turnId,
      isStandby: turnId == _standbyTurnId,
      isHistorical:
          _currentTurnGroupId != null &&
          _historicalTurnOrder.contains(turnId) &&
          !_liveTurnOrder.contains(turnId),
    ).appendEntry(entry);
    return turnId;
  }

  String? _replaceTimelineMessage(AgentConversationMessage message) {
    final index = _timelineEntries.indexWhere(
      (entry) =>
          entry is AgentMessageTimelineEntry && entry.message.id == message.id,
    );
    if (index == -1) {
      return null;
    }
    final updatedEntry = AgentMessageTimelineEntry(message: message);
    _timelineEntries[index] = updatedEntry;
    final turnId = _timelineEntryTurnIds[index];
    _turnGroups[turnId]?.replaceEntry(updatedEntry);
    return turnId;
  }

  String? _replaceTimelineTool(AgentToolCall toolCall) {
    final index = _timelineEntries.indexWhere(
      (entry) =>
          entry is AgentToolTimelineEntry && entry.toolCall.id == toolCall.id,
    );
    if (index == -1) {
      return null;
    }
    final updatedEntry = AgentToolTimelineEntry(toolCall: toolCall);
    _timelineEntries[index] = updatedEntry;
    final turnId = _timelineEntryTurnIds[index];
    _turnGroups[turnId]?.replaceEntry(updatedEntry);
    return turnId;
  }

  String _addPermissionRequest(AgentPermissionRequest request) {
    _permissionRequests.add(request);
    return _appendTimelineEntry(AgentPermissionTimelineEntry(request: request));
  }

  void _removePermissionRequest(String requestId) {
    _permissionRequests.removeWhere((item) => item.id == requestId);
    var index = 0;
    while (index < _timelineEntries.length) {
      final entry = _timelineEntries[index];
      if (entry is AgentPermissionTimelineEntry &&
          entry.request.id == requestId) {
        final turnId = _timelineEntryTurnIds[index];
        _timelineEntries.removeAt(index);
        _timelineEntryTurnIds.removeAt(index);
        _turnIdsByTimelineEntryId.remove(entry.id);
        _turnGroups[turnId]?.removeEntry(entry.id);
      } else {
        index += 1;
      }
    }
  }

  void _publishUiChanges({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    if (_disposed) {
      return;
    }
    if (syncLiveTurn) {
      _syncLiveTurnBinding();
    }
    if (history) {
      _historyVersionNotifier.value += 1;
    }
    if (header) {
      _headerVersionNotifier.value += 1;
    }
    if (composer) {
      _composerVersionNotifier.value += 1;
    }
    if (liveTurn) {
      liveTurnState?.markDirty();
      liveTurnState?.flushNow();
    }
    if (autoScroll) {
      _autoScrollTickNotifier.value += 1;
    }
    _notifyLegacyListeners();
  }

  void _notifyLegacyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _scheduleStreamFlush({bool header = false, bool autoScroll = false}) {
    if (_disposed) {
      return;
    }
    _streamNeedsLiveFlush = true;
    _streamNeedsHeaderFlush = _streamNeedsHeaderFlush || header;
    _streamNeedsAutoScroll = _streamNeedsAutoScroll || autoScroll;
    _streamFlushTimer ??= Timer(
      const Duration(milliseconds: 16),
      _flushPendingStreamChangesNow,
    );
  }

  void _flushPendingStreamChangesNow() {
    _flushStreamChangesNow();
  }

  void _flushStreamChangesNow({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    if (_disposed) {
      return;
    }
    final scheduledLiveFlush = _streamNeedsLiveFlush;
    final scheduledHeaderFlush = _streamNeedsHeaderFlush;
    final scheduledAutoScroll = _streamNeedsAutoScroll;
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _streamNeedsLiveFlush = false;
    _streamNeedsHeaderFlush = false;
    _streamNeedsAutoScroll = false;
    _publishUiChanges(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header || scheduledHeaderFlush,
      composer: composer,
      liveTurn: liveTurn || scheduledLiveFlush,
      autoScroll: autoScroll || scheduledAutoScroll,
    );
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
    final turnState = _turnStateFor(
      turn.id,
      isStandby: false,
      isHistorical: false,
    );
    turnState.updateMetadata(
      status: AgentHistoryTurnStatus.running,
      startedAt: turnState.startedAt ?? DateTime.now(),
      completedAt: turnState.completedAt,
      duration: turnState.duration,
      tokenUsage: turnState.tokenUsage,
    );
  }

  /// turn 完成时更新分组元数据；后续条目回到 standby 分组。
  void _completeLiveTurnGroup(String turnId) {
    final turnState = _turnGroups[turnId];
    if (turnState == null) {
      _currentTurnGroupId = null;
      _pendingTurnGroupId = null;
      return;
    }
    final oldHistoryLength = _historicalTurnOrder.length;
    final oldDefaultStartIndex = _defaultVisibleHistoryStartIndexForLength(
      oldHistoryLength,
    );
    final historyExpanded = _visibleHistoryStartIndex < oldDefaultStartIndex;
    final previousVisibleCount = oldHistoryLength - _visibleHistoryStartIndex;
    final completedAt = DateTime.now();
    turnState.updateMetadata(
      status: AgentHistoryTurnStatus.completed,
      startedAt: turnState.startedAt,
      completedAt: completedAt,
      duration: turnState.startedAt == null
          ? null
          : completedAt.difference(turnState.startedAt!),
      tokenUsage: turnState.tokenUsage,
    );
    _promoteTurnToHistorical(turnId);
    if (historyExpanded) {
      _visibleHistoryStartIndex = math.max(
        0,
        _historicalTurnOrder.length - previousVisibleCount,
      );
    } else {
      _visibleHistoryStartIndex = _defaultVisibleHistoryStartIndexForLength(
        _historicalTurnOrder.length,
      );
    }
    _currentTurnGroupId = null;
  }

  /// 用 provider 上报的 token 用量更新对应回合分组的元数据。
  ///
  /// 优先按事件中的 turnId 定位分组；缺失时回退到当前运行回合。
  void _updateTurnTokenUsage(AgentTokenUsageEvent event) {
    final pendingId = _pendingTurnGroupId;
    if (event.turnId != null &&
        pendingId != null &&
        !_turnGroups.containsKey(event.turnId) &&
        _turnGroups.containsKey(pendingId)) {
      _renameTurnGroup(pendingId, event.turnId!);
      _pendingTurnGroupId = null;
    }
    final turnId =
        event.turnId ?? _selectedRunningTurnId() ?? _currentTurnGroupId;
    if (turnId == null) {
      return;
    }
    final turnState = _turnStateFor(
      turnId,
      isStandby: false,
      isHistorical: false,
    );
    turnState.updateMetadata(
      status: turnState.status,
      startedAt: turnState.startedAt,
      completedAt: turnState.completedAt,
      duration: turnState.duration,
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
    final historicalIndex = _historicalTurnOrder.indexOf(oldId);
    if (historicalIndex != -1) {
      _historicalTurnOrder[historicalIndex] = newId;
    }
    final liveIndex = _liveTurnOrder.indexOf(oldId);
    if (liveIndex != -1) {
      _liveTurnOrder[liveIndex] = newId;
    }
    final group = _turnGroups.remove(oldId);
    if (group != null) {
      group.rename(newId);
      _turnGroups[newId] = group;
      for (final entry in group.entries) {
        _turnIdsByTimelineEntryId[entry.id] = newId;
      }
    }
    if (_currentTurnGroupId == oldId) {
      _currentTurnGroupId = newId;
    }
    if (_pendingTurnGroupId == oldId) {
      _pendingTurnGroupId = newId;
    }
  }

  void _registerHistoryTurn(AgentHistoryTurn turn, {required bool asLive}) {
    _turnStateFor(
      turn.id,
      isStandby: false,
      isHistorical: !asLive,
    ).updateMetadata(
      status: turn.status,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      duration: turn.duration,
      tokenUsage: turn.tokenUsage,
    );
  }

  AgentConversationTurnState _turnStateFor(
    String turnId, {
    required bool isStandby,
    required bool isHistorical,
  }) {
    final existing = _turnGroups[turnId];
    if (existing != null) {
      if (!isStandby) {
        if (isHistorical) {
          _promoteTurnToHistorical(turnId);
        } else {
          _promoteTurnToLive(turnId);
        }
      }
      return existing;
    }
    if (!isStandby) {
      if (isHistorical) {
        _promoteTurnToHistorical(turnId);
      } else {
        _promoteTurnToLive(turnId);
      }
    }
    final created = AgentConversationTurnState(
      id: turnId,
      isStandby: isStandby,
    );
    _turnGroups[turnId] = created;
    return created;
  }

  AgentConversationTurnGroup _turnGroupSnapshot(String turnId) {
    final group = _turnGroups[turnId];
    if (group == null) {
      return AgentConversationTurnGroup(
        id: turnId,
        entries: const <AgentTimelineEntry>[],
        isStandby: turnId == _standbyTurnId,
      );
    }
    return group.snapshot();
  }

  void _syncLiveTurnBinding() {
    final nextLiveTurn = _currentLiveTurnState();
    if (identical(_liveTurnNotifier.value, nextLiveTurn)) {
      return;
    }
    _liveTurnNotifier.value = nextLiveTurn;
  }

  AgentConversationTurnState? _currentLiveTurnState() {
    final currentTurnGroupId = _currentTurnGroupId;
    if (currentTurnGroupId != null) {
      final current = _turnGroups[currentTurnGroupId];
      if (current != null && current.isRunning) {
        return current;
      }
    }
    final runningTurnId = _selectedRunningTurnId();
    if (runningTurnId == null) {
      return null;
    }
    return _turnGroups[runningTurnId];
  }

  void _promoteTurnToLive(String turnId) {
    _historicalTurnOrder.remove(turnId);
    if (!_liveTurnOrder.contains(turnId)) {
      _liveTurnOrder.add(turnId);
    }
  }

  void _promoteTurnToHistorical(String turnId) {
    _liveTurnOrder.remove(turnId);
    if (!_historicalTurnOrder.contains(turnId)) {
      _historicalTurnOrder.add(turnId);
    }
  }

  int _defaultVisibleHistoryStartIndexForLength(int historyLength) {
    return math.max(0, historyLength - _historyPageSize);
  }

  bool _isHistoryTurnId(String turnId) {
    return turnId == _standbyTurnId || _historicalTurnOrder.contains(turnId);
  }

  bool _isLiveTurnId(String turnId) {
    return _liveTurnOrder.contains(turnId) || _currentTurnGroupId == turnId;
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

/// thread 打开阶段。
enum AgentThreadOpenPhase { idle, loadingHistory, openFailed }

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

/// 单个 turn 的运行时状态。
///
/// 历史区使用快照渲染；live 区直接监听这个对象，避免流式增量时整页重建。
class AgentConversationTurnState extends ChangeNotifier {
  AgentConversationTurnState({required this.id, required this.isStandby});

  String id;
  final bool isStandby;
  final List<AgentTimelineEntry> _entries = <AgentTimelineEntry>[];
  AgentHistoryTurnStatus? _status;
  DateTime? _startedAt;
  DateTime? _completedAt;
  Duration? _duration;
  AgentTokenUsage? _tokenUsage;
  bool _dirty = false;

  List<AgentTimelineEntry> get entries => UnmodifiableListView(_entries);

  AgentHistoryTurnStatus? get status => _status;

  DateTime? get startedAt => _startedAt;

  DateTime? get completedAt => _completedAt;

  Duration? get duration => _duration;

  AgentTokenUsage? get tokenUsage => _tokenUsage;

  bool get isRunning => _status == AgentHistoryTurnStatus.running;

  void appendEntry(AgentTimelineEntry entry) {
    _entries.add(entry);
    _dirty = true;
  }

  void replaceEntry(AgentTimelineEntry entry) {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      return;
    }
    _entries[index] = entry;
    _dirty = true;
  }

  void removeEntry(String entryId) {
    final removedCount = _entries.length;
    _entries.removeWhere((entry) => entry.id == entryId);
    if (_entries.length != removedCount) {
      _dirty = true;
    }
  }

  void rename(String nextId) {
    if (id == nextId) {
      return;
    }
    id = nextId;
    _dirty = true;
  }

  void updateMetadata({
    AgentHistoryTurnStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    Duration? duration,
    AgentTokenUsage? tokenUsage,
  }) {
    _status = status;
    _startedAt = startedAt;
    _completedAt = completedAt;
    _duration = duration;
    _tokenUsage = tokenUsage;
    _dirty = true;
  }

  void markDirty() {
    _dirty = true;
  }

  void flushNow() {
    if (!_dirty) {
      return;
    }
    _dirty = false;
    notifyListeners();
  }

  AgentConversationTurnGroup snapshot() {
    return AgentConversationTurnGroup(
      id: id,
      entries: List<AgentTimelineEntry>.unmodifiable(_entries),
      isStandby: isStandby,
      status: _status,
      startedAt: _startedAt,
      completedAt: _completedAt,
      duration: _duration,
      tokenUsage: _tokenUsage,
    );
  }
}
