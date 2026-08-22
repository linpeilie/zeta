import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:zeta_agent_providers/src/agent_ignored_message_logger.dart';
import 'package:zeta_agent_providers/src/datasources/app_server/codex_permission_policy_adapter.dart';
import 'package:zeta_agent_providers/src/datasources/app_server/codex_process_starter.dart';
import 'package:zeta_agent_providers/src/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta_agent_providers/src/datasources/transport/provider_operation_scheduler.dart';
import 'package:zeta_agent_providers/src/datasources/transport/provider_runtime_json_rpc_peer.dart';
import 'package:zeta_agent_providers/src/agent_provider_static_capabilities.dart';
import 'package:zeta_agent_providers/src/mappers/codex_permission_policy_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

part 'codex_app_server_client.dart';
part 'codex_collaboration_mode_catalog_failure.dart';
part 'codex_app_server_runtime_info.dart';
part '../../mappers/codex_app_server_helpers.dart';
part '../../mappers/codex_approval_mapper.dart';
part '../../mappers/codex_collaboration_mode_mapper.dart';
part '../../mappers/codex_conversation_mode_codec.dart';
part '../../mappers/codex_file_change_tracker.dart';
part '../../mappers/codex_model_list_mapper.dart';
part '../../mappers/codex_notification_mapper.dart';
part '../../mappers/codex_question_mapper.dart';
part '../../mappers/codex_skills_mapper.dart';
part '../../mappers/codex_turn_start_params_encoder.dart';
part '../local_history/codex_jsonl_history_parser.dart';
part '../local_history/codex_thread_history_reader.dart';

final _log = zetaLoggerFor('zeta.agent.codex_app_server');

/// 根据 provider 配置创建 JSON-RPC 端点。
typedef JsonRpcPeerFactory = JsonRpcPeer Function(AgentProviderConfig config);

/// Codex app-server 的 Agent provider 实现。
///
/// 该类现在只负责生命周期、状态协同与事件分发，具体的 JSON-RPC 请求、
/// 通知映射、审批映射与历史解析已经拆分到独立模块。
class CodexAppServerAgentProvider
    implements
        AgentRuntimePort,
        AgentConversationPort,
        AgentThreadCatalogPort,
        AgentThreadSubscriptionPort,
        AgentThreadNamingPort,
        AgentThreadArchivalPort,
        AgentThreadDeletionPort,
        AgentThreadCompactionPort,
        AgentThreadBranchingPort,
        AgentTurnSteeringPort,
        AgentPermissionResponsePort,
        AgentQuestionResponsePort,
        AgentDeniedActionOverridePort,
        AgentModelCatalogPort,
        AgentConversationModeCatalogPort,
        AgentSkillsPort,
        AgentUsageQuotaProvider {
  /// 创建 Codex app-server provider 实例。
  ///
  /// [config] 包含命令、参数、环境变量等 provider 配置。
  /// [peer] 允许外部注入已创建的 JSON-RPC 对等体，用于测试。
  /// [peerFactory] 用于在未提供 [peer] 时按 [config] 创建默认对等体。
  CodexAppServerAgentProvider({
    required this.config,
    this.textCatalog = const FallbackAgentUiTextCatalog(),
    JsonRpcPeer? peer,
    JsonRpcPeerFactory? peerFactory,
  }) : _modelSelection = AgentModelSelection(
         modelId: config.selectedModel,
         reasoningEffort: config.selectedReasoningEffort,
         serviceTierId: config.selectedServiceTier,
       ) {
    _peer = ProviderRuntimeJsonRpcPeer(
      peer ?? (peerFactory ?? _defaultPeerFactory)(config),
      providerId: config.id,
    );
    final threadHistoryReader = _CodexThreadHistoryReader(
      textCatalog: textCatalog,
    );
    final modelListMapper = _CodexModelListMapper();
    final collaborationModeMapper = _CodexCollaborationModeMapper();
    final skillsMapper = _CodexSkillsMapper();
    final turnStartParamsEncoder = _CodexTurnStartParamsEncoder(
      defaultModelId: config.defaultModel,
    );
    final configPermissionFallback =
        CodexPermissionPolicyCodec.snapshotFromConfig(config);
    _client = _CodexAppServerClient(
      peer: _peer,
      config: config,
      modelListMapper: modelListMapper,
      collaborationModeMapper: collaborationModeMapper,
      skillsMapper: skillsMapper,
      turnStartParamsEncoder: turnStartParamsEncoder,
      threadHistoryReader: threadHistoryReader,
      configPermissionFallback: configPermissionFallback,
      textCatalog: textCatalog,
    );
    _notificationMapper = _CodexNotificationMapper(
      providerId: config.id,
      textCatalog: textCatalog,
    );
    _approvalMapper = _CodexApprovalMapper();
    _questionMapper = _CodexQuestionMapper(textCatalog);
    _permissionPolicyAdapter = CodexPermissionPolicyAdapter(
      ensureInitialized: initialize,
      sendRequest: (method, {Map<String, Object?> params = const {}}) async {
        return _peer.sendRequest(method, params: params);
      },
    );
  }

  /// JSON-RPC 通信对等体，负责与 Codex app-server 进程交换消息。
  late final ProviderRuntimeJsonRpcPeer _peer;

  late final _CodexAppServerClient _client;
  late final _CodexNotificationMapper _notificationMapper;
  late final _CodexApprovalMapper _approvalMapper;
  late final _CodexQuestionMapper _questionMapper;
  late final CodexPermissionPolicyAdapter _permissionPolicyAdapter;

  /// 广播事件流控制器，所有 Agent 事件通过此流发出。
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  /// 以 Thread/Project 资源键协调历史读取与变更请求。
  final ProviderOperationScheduler _operationScheduler =
      ProviderOperationScheduler();

  /// 等待用户审批的服务端 JSON-RPC 请求。
  final Map<String, _PendingApproval> _pendingApprovals =
      <String, _PendingApproval>{};

  /// 等待用户回答的服务端 JSON-RPC 请求。
  final Map<String, _PendingQuestion> _pendingQuestions =
      <String, _PendingQuestion>{};

  /// 被拒操作人工放行所需的协议 event，按 reviewId 持有。
  final Map<String, Map<String, Object?>> _deniedActionEventsByRequestId =
      <String, Map<String, Object?>>{};

  /// 各 thread 当前运行中的 turn id。
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};

  /// 用户在输入框选择的模型组合。
  AgentModelSelection _modelSelection;

  AgentProviderCapabilities _capabilities =
      AgentProviderStaticCapabilities.codexAppServer;

  AgentRuntimeInfo? _runtimeInfo;

  /// 按是否包含隐藏项区分的实例内模型目录缓存。
  final Map<bool, AgentModelList> _modelLists = <bool, AgentModelList>{};

  /// 当前连接 epoch 已成功读取的对话模式目录。
  AgentConversationModeCatalog? _conversationModeCatalog;
  AgentRuntimeScope? _conversationModeCatalogScope;

  /// 同一连接 epoch 内的目录请求只允许一个在途操作。
  Future<AgentConversationModeCatalog>? _conversationModeCatalogOperation;
  AgentRuntimeScope? _conversationModeCatalogOperationScope;

  /// 服务端明确不支持实验方法后，同一 epoch 不再自动重试。
  AgentRuntimeScope? _unsupportedConversationModeCatalogScope;

  /// Skill 文件变更失效广播（供 application 层 stale 刷新）。
  final StreamController<void> _skillsChanged =
      StreamController<void>.broadcast();

  /// 是否已完成 initialize 握手。
  bool _initialized = false;

  /// 正在执行的初始化操作，用于去重并发初始化调用。
  Future<void>? _initializationOperation;

  /// 是否已调用 dispose，防止重复释放资源。
  bool _disposed = false;

  Future<void>? _disposeOperation;

  final AgentIgnoredMessageLogger _ignoredMessageLogger =
      AgentIgnoredMessageLogger(
        providerLabel: 'Codex',
        loggerName: 'zeta.agent.codex_app_server',
      );

  StreamSubscription<JsonRpcNotification>? _notificationSubscription;
  StreamSubscription<JsonRpcRequest>? _serverRequestSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<JsonRpcProtocolException>? _protocolErrorSubscription;

  @override
  final AgentProviderConfig config;

  /// 当前进程的 Zeta 自有文案目录。
  final AgentUiTextCatalog textCatalog;

  /// initialize 时请求服务端屏蔽的通知(协议要求精确 method 名)。
  ///
  /// 只列近期路线图之外(P4~P5)且不消费的通知,减少 stdio 流量与解析开销：
  /// 实时语音、远程控制、插件生态、Windows 沙箱与安全审计元数据。
  /// Phase 1~3 计划消费的通知(reasoning/plan/diff、account、mcp、skills 等)
  /// 不在此列;适配对应功能时若列表有交集需同步移除。
  static const List<String> _optedOutNotificationMethods = <String>[
    'thread/realtime/closed',
    'thread/realtime/error',
    'thread/realtime/itemAdded',
    'thread/realtime/outputAudio/delta',
    'thread/realtime/sdp',
    'thread/realtime/started',
    'thread/realtime/transcript/delta',
    'thread/realtime/transcript/done',
    'remoteControl/status/changed',
    'app/list/updated',
    'windows/worldWritableWarning',
    'windowsSandbox/setupCompleted',
    'model/safetyBuffering/updated',
    'model/verification',
    'turn/moderationMetadata',
  ];

  static const bool _experimentalApiEnabled = true;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentProviderCapabilities get capabilities => _capabilities;

  @override
  AgentRuntimeInfo? get runtimeInfo => _runtimeInfo;

  @override
  AgentProviderLifecycleState get lifecycleState => _peer.lifecycleState;

  @override
  AgentRuntimeScope? get runtimeScope => _peer.runtimeScope;

  /// 开发诊断：被忽略服务端通知按 method + reason 的累计次数。
  @visibleForTesting
  Map<String, int> get ignoredNotificationCountsForTesting =>
      _ignoredMessageLogger.ignoredCounts;

  /// 开发诊断：未匹配服务端通知按 method 的累计次数。
  @visibleForTesting
  Map<String, int> get unmatchedNotificationCountsForTesting =>
      _ignoredMessageLogger.unmatchedCounts;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw const ProviderConnectionClosedException(
        'Codex Provider has been disposed',
      );
    }
    if (_initialized) {
      return;
    }
    final inFlightInitialization = _initializationOperation;
    if (inFlightInitialization != null) {
      await inFlightInitialization;
      return;
    }

    final operation = _initializeOnce();
    _initializationOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializationOperation, operation)) {
        _initializationOperation = null;
      }
    }
  }

  /// 执行一次完整的初始化流程：启动 JSON-RPC 对等体、订阅流、
  /// 发送 LSP 风格的 initialize 请求与 initialized 通知。
  Future<void> _initializeOnce() async {
    _log.i('Initializing Agent provider ${config.id}');
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: textCatalog.startingProvider(config.displayName),
      ),
    );

    try {
      await _peer.start();
      _listenToPeer();

      final initializeResult = await _peer.sendRequest(
        'initialize',
        params: <String, Object?>{
          'clientInfo': <String, Object?>{
            'name': 'zeta',
            'title': 'Zeta',
            'version': '0.1.0',
          },
          // 显式声明协商能力，避免依赖服务端默认值的隐式行为。
          'capabilities': <String, Object?>{
            // permission profile 选择依赖 experimental 字段；其余未消费字段保持
            // 宽容忽略，未知请求仍走 fail-closed 拒绝。
            'experimentalApi': _experimentalApiEnabled,
            // 不参与 attestation/generate 流程（A5 已对误发请求兜底拒绝）。
            'requestAttestation': false,
            // 表单式 elicitation 尚无渲染能力（见计划 3.8），暂不允许。
            'mcpServerOpenaiFormElicitation': false,
            'optOutNotificationMethods': _optedOutNotificationMethods,
          },
        },
      );
      _log.i('Codex initialize completed for ${config.id}');

      _runtimeInfo = _codexRuntimeInfoFromInitialize(
        initializeResult,
        runtimeScope: _peer.runtimeScope!,
        configuredVersion: config.extra['detectedCurrentVersion']?.toString(),
        experimentalApiEnabled: _experimentalApiEnabled,
      );
      _capabilities = _codexCapabilitiesForRuntime(_runtimeInfo!);

      _peer.sendNotification('initialized');
      _peer.markReady();
      _initialized = true;
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: textCatalog.providerReady(config.displayName),
        ),
      );
      _log.i('Agent provider ${config.id} initialized');
    } on ProcessException catch (error) {
      _peer.markFailed();
      _log.w(
        'Could not start Agent provider process ${config.id} '
        '(errorCode=${error.errorCode})',
      );
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error) {
      _peer.markFailed();
      _log.w(
        'Could not initialize Agent provider ${config.id} '
        '(${error.runtimeType})',
      );
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.error,
          message: textCatalog.couldNotStart(config.displayName),
          details: error.toString(),
        ),
      );
      _events.add(
        AgentErrorEvent(
          message: textCatalog.couldNotStart(config.displayName),
          details: error.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    await initialize();
    _log.t('Starting Codex thread for provider ${config.id}');

    final session = await _client.startSession(
      context: context,
      permissionSnapshot: permissionSnapshot,
      previousSessionId: null,
    );
    _events.add(AgentSessionStartedEvent(session));
    _log.i('Started Codex thread ${session.id}');
    return session;
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) => _scheduleThreadOperation(
    sessionId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      _log.t('Resuming Codex thread $sessionId');

      final session = await _client.resumeSession(
        sessionId,
        context: context,
        permissionSnapshot: permissionSnapshot,
        previousSessionId: null,
      );
      _events.add(AgentSessionStartedEvent(session));
      _log.i('Resumed Codex thread ${session.id}');
      return session;
    },
  );

  @override
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query}) =>
      _operationScheduler.schedule<AgentThreadPage>(
        key: ProjectOperationKey(
          providerId: config.id,
          projectPath: query.projectPath,
        ),
        access: ProviderOperationAccess.sharedRead,
        operation: () async {
          await initialize();
          _log.t(
            'Listing Codex threads for ${query.projectPath} '
            'limit=${query.limit} cursor=${query.cursor}',
          );
          return _client.listThreads(query: query);
        },
      );

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    await initialize();
    return _client.readUsageQuota();
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      return refreshModels(limit: limit, includeHidden: includeHidden);
    }
    final cached = _modelLists[includeHidden];
    if (cached != null) {
      return cached;
    }
    await initialize();
    final initializedCache = _modelLists[includeHidden];
    if (initializedCache != null) {
      return initializedCache;
    }
    return _fetchModelList(limit: limit, includeHidden: includeHidden);
  }

  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    await initialize();
    return _fetchModelList(limit: limit, includeHidden: includeHidden);
  }

  @override
  Stream<void> get skillsChanged => _skillsChanged.stream;

  @override
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  }) async {
    await initialize();
    final normalizedCwds = <String>[
      for (final cwd in cwds)
        if (cwd.trim().isNotEmpty) cwd.trim(),
    ];
    final projectPath = normalizedCwds.isEmpty
        ? '__default__'
        : normalizedCwds.join('\u0001');
    return _operationScheduler.schedule<AgentSkillsCatalog>(
      key: ProjectOperationKey(providerId: config.id, projectPath: projectPath),
      access: ProviderOperationAccess.sharedRead,
      operation: () => _client.fetchSkillsCatalog(
        cwds: normalizedCwds,
        forceReload: forceReload,
      ),
    );
  }

  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
    await initialize();
    final scope = _peer.runtimeScope;
    if (scope == null) {
      throw const ProviderConnectionClosedException(
        'Codex Provider has no active runtime scope',
      );
    }

    if (_conversationModeCatalogScope == scope) {
      final cached = _conversationModeCatalog;
      if (cached != null) {
        return cached;
      }
    }
    if (_unsupportedConversationModeCatalogScope == scope) {
      throw UnsupportedError('${config.displayName} 当前运行时不支持对话模式目录');
    }
    if (_conversationModeCatalogOperationScope == scope) {
      final inFlight = _conversationModeCatalogOperation;
      if (inFlight != null) {
        return inFlight;
      }
    }

    final operation = _fetchConversationModeCatalog(scope);
    _conversationModeCatalogOperation = operation;
    _conversationModeCatalogOperationScope = scope;
    try {
      return await operation;
    } finally {
      if (identical(_conversationModeCatalogOperation, operation)) {
        _conversationModeCatalogOperation = null;
        _conversationModeCatalogOperationScope = null;
      }
    }
  }

  Future<AgentConversationModeCatalog> _fetchConversationModeCatalog(
    AgentRuntimeScope scope,
  ) async {
    try {
      final catalog = await _client.fetchCollaborationModeCatalog();
      if (!_canCommitConversationModeCatalog(scope)) {
        return catalog;
      }

      _conversationModeCatalog = catalog;
      _conversationModeCatalogScope = scope;
      final supportsModeSelection = _hasRequiredConversationModes(catalog);
      _capabilities = _capabilities.copyWith(
        supportsModeSelection: supportsModeSelection,
      );
      _log.t(
        'Loaded ${catalog.presets.length} Codex collaboration modes '
        '(selectable=$supportsModeSelection)',
      );
      return catalog;
    } catch (error) {
      final failure = _classifyConversationModeCatalogFailure(error);
      if (_canCommitConversationModeCatalog(scope) &&
          failure ==
              _CodexConversationModeCatalogFailureKind.unsupportedRuntime) {
        _unsupportedConversationModeCatalogScope = scope;
        _capabilities = _capabilities.copyWith(supportsModeSelection: false);
      }
      _log.w(
        'Could not load Codex collaboration modes '
        '(failure=${failure.name}, error=${error.runtimeType})',
      );
      if (failure ==
          _CodexConversationModeCatalogFailureKind.unsupportedRuntime) {
        throw UnsupportedError('${config.displayName} 当前运行时不支持对话模式目录');
      }
      rethrow;
    }
  }

  bool _canCommitConversationModeCatalog(AgentRuntimeScope scope) {
    return !_disposed && _peer.runtimeScope == scope;
  }

  bool _hasRequiredConversationModes(AgentConversationModeCatalog catalog) {
    var hasDefault = false;
    var hasPlan = false;
    for (final preset in catalog.presets) {
      switch (preset.id.kind) {
        case AgentConversationModeKind.defaultMode:
          hasDefault = true;
        case AgentConversationModeKind.plan:
          hasPlan = true;
        case AgentConversationModeKind.unknown:
          break;
      }
    }
    return hasDefault && hasPlan;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    _modelSelection = selection;
    _log.t(
      'Updated model selection: model=${selection.modelId} '
      'effort=${selection.reasoningEffort} tier=${selection.serviceTierId}',
    );
  }

  AgentPermissionPolicyPort get permissionPolicy => _permissionPolicyAdapter;

  @override
  Future<void> approveDeniedAction(
    AgentDeniedActionOverrideRequest request,
  ) async {
    final event = _deniedActionEventsByRequestId.remove(request.requestId);
    if (event == null) {
      throw StateError(
        'No pending denied action override for ${request.requestId}',
      );
    }
    await initialize();
    _log.i('Approving guardian-denied action for thread ${request.threadId}');
    await _client.approveGuardianDeniedAction(
      threadId: request.threadId,
      event: event,
    );
  }

  /// 向 Codex app-server 分页读取完整 `model/list` 并缓存结果。
  Future<AgentModelList> _fetchModelList({
    required int limit,
    required bool includeHidden,
  }) async {
    final list = await _client.fetchModelList(
      limit: limit,
      includeHidden: includeHidden,
    );
    _modelLists[includeHidden] = list;
    _events.add(AgentModelListEvent(list));
    _log.i(
      'Fetched Codex model list '
      '(includeHidden=$includeHidden, limit=$limit): '
      '${list.describeForLog()}',
    );
    return list;
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.sharedRead,
    () async {
      await initialize();
      _log.t('Reading Codex thread history $threadId');
      return _client.readThreadHistory(
        threadId: threadId,
        sessionPath: sessionPath,
      );
    },
  );

  @override
  Future<void> unsubscribeThread(String threadId) async {
    if (threadId.isEmpty) {
      return;
    }
    await initialize();
    await _unsubscribeThreadBestEffort(threadId);
  }

  @override
  Future<void> renameThread({required String threadId, required String name}) =>
      _scheduleThreadOperation(
        threadId,
        ProviderOperationAccess.exclusive,
        () async {
          await initialize();
          await _client.renameThread(threadId: threadId, name: name);
        },
      );

  @override
  Future<void> archiveThread(String threadId) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      await _client.archiveThread(threadId);
    },
  );

  @override
  Future<void> unarchiveThread(String threadId) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      await _client.unarchiveThread(threadId);
    },
  );

  @override
  Future<void> deleteThread(String threadId) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      await _client.deleteThread(threadId);
      await _unsubscribeThreadBestEffort(threadId);
    },
  );

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      if (boundary is AgentForkThroughTurn &&
          !_capabilities.canForkThreadAtTurn) {
        throw UnsupportedError('当前 Codex 版本不支持稳定的指定 turn 分支能力');
      }
      final session = await _client.forkThread(
        threadId: threadId,
        context: context,
        boundary: boundary,
        permissionSnapshot: permissionSnapshot,
        previousSessionId: null,
      );
      _events.add(AgentSessionStartedEvent(session));
      _log.i('Forked Codex thread $threadId -> ${session.id}');
      return session;
    },
  );

  @override
  Future<void> compactThread(String threadId) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      _log.i('Starting compact for Codex thread $threadId');
      await _client.compactThread(threadId);
    },
  );

  Future<T> _scheduleThreadOperation<T>(
    String threadId,
    ProviderOperationAccess access,
    FutureOr<T> Function() operation,
  ) {
    return _operationScheduler.schedule<T>(
      key: ThreadOperationKey(providerId: config.id, threadId: threadId),
      access: access,
      operation: operation,
    );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    // 编码前置校验必须发生在 initialize 之前，非法模式不得触发任何 RPC。
    _client.validateTurnConfiguration(configuration);
    await initialize();
    final resolvedInputs = _resolveUserInputs(message: message, inputs: inputs);
    _log.i('Starting Codex turn for thread ${session.id}');
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: textCatalog.agentIsWorking,
      ),
    );

    final turn = await _client.sendMessage(
      session: session,
      inputs: resolvedInputs,
      context: context,
      selection: _modelSelection,
      permissionSnapshot: configuration.permissionSnapshot,
      turnConfiguration: configuration,
      clientUserMessageId: clientUserMessageId,
    );
    _markRunningTurn(session.id, turn.id);
    _events.add(
      AgentTurnStartedEvent.fromModelSelection(
        turn: turn,
        selection: _modelSelection,
      ),
    );
    _log.t('Started Codex turn ${turn.id}');
    return turn;
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    await initialize();
    final activeTurnId = _runningTurnIdsBySessionId[session.id];
    if (activeTurnId == null) {
      throw StateError('当前会话没有可追加指令的活动 turn');
    }
    if (activeTurnId != expectedTurnId) {
      throw StateError(
        '活动 turn 已变化：expected=$expectedTurnId, actual=$activeTurnId',
      );
    }
    final resolvedInputs = _resolveUserInputs(message: message, inputs: inputs);
    _log.i('Steering Codex turn for thread ${session.id}');
    await _client.steerTurn(
      session: session,
      inputs: resolvedInputs,
      expectedTurnId: activeTurnId,
      clientUserMessageId: clientUserMessageId,
    );
  }

  /// 归一化发送载荷：优先 [inputs]，否则把 [message] 包成单条文本输入。
  List<AgentUserInput> _resolveUserInputs({
    String? message,
    List<AgentUserInput>? inputs,
  }) {
    if (inputs != null && inputs.isNotEmpty) {
      return List<AgentUserInput>.unmodifiable(inputs);
    }
    final text = message?.trim() ?? '';
    if (text.isEmpty) {
      throw ArgumentError('sendMessage/steerTurn requires message or inputs');
    }
    return List<AgentUserInput>.unmodifiable(<AgentUserInput>[
      AgentUserInput.text(text),
    ]);
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    _log.i('Interrupting Codex turn ${turn.id}');
    await _client.cancelTurn(turn);
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    final pending = _pendingApprovals.remove(decision.requestId);
    if (pending == null) {
      _log.w(
        'Ignoring response for unknown Codex permission ${decision.requestId}',
      );
      return;
    }

    _log.i(
      'Responding to Codex permission ${pending.method}: '
      'approved=${decision.approved}',
    );
    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: _approvalMapper.approvalResponse(pending, decision),
    );
  }

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) async {
    final pending = _pendingQuestions.remove(response.requestId);
    if (pending == null) {
      _log.w(
        'Ignoring response for unknown Codex question ${response.requestId}',
      );
      return;
    }

    _log.i(
      'Responding to Codex user question '
      '(${response.answers.length} answered questions)',
    );
    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: _questionMapper.response(response),
    );
  }

  @override
  Future<void> dispose() {
    final existing = _disposeOperation;
    if (existing != null) {
      return existing;
    }
    final operation = _disposeOnce();
    _disposeOperation = operation;
    return operation;
  }

  Future<void> _disposeOnce() async {
    _log.t('Disposing Agent provider ${config.id}');
    _disposed = true;
    _clearConversationModeCatalogState();
    _operationScheduler.beginClosing();
    _peer.beginClosing();

    _resolvePendingInteractionsOnConnectionClosed();
    _deniedActionEventsByRequestId.clear();

    await _notificationSubscription?.cancel();
    await _serverRequestSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    _notificationMapper.dispose();
    await _peer.close();
    await _operationScheduler.close();
    await _events.close();
    await _skillsChanged.close();
  }

  void _clearConversationModeCatalogState() {
    _conversationModeCatalog = null;
    _conversationModeCatalogScope = null;
    _conversationModeCatalogOperation = null;
    _conversationModeCatalogOperationScope = null;
    _unsupportedConversationModeCatalogScope = null;
    _capabilities = _capabilities.copyWith(supportsModeSelection: false);
  }

  /// 订阅 JSON-RPC 对等体的各事件流。
  void _listenToPeer() {
    _notificationSubscription ??= _peer.notifications.listen(
      _handleNotification,
      onDone: _handlePeerClosed,
    );
    _serverRequestSubscription ??= _peer.serverRequests.listen((request) {
      unawaited(
        _peer.handleServerRequest(request, _handleServerRequest).catchError((
          Object error,
          StackTrace _,
        ) {
          _log.w(
            'Codex server request ${request.method} did not complete '
            '(${error.runtimeType})',
          );
        }),
      );
    });
    _stderrSubscription ??= _peer.stderrLines.listen((line) {
      if (line.trim().isEmpty) {
        return;
      }
      // stderr 是 app-server 的 tracing/诊断通道，其中也包含回合内工具失败的
      // 日志。用户可见错误必须以 JSON-RPC `error`、`turn/completed` 或 item
      // 事件为准，不能把每一行 stderr 拆成对话消息。
      _log.t('Codex stderr line received (${line.length} characters)');
    });
    _protocolErrorSubscription ??= _peer.protocolErrors.listen((error) {
      _log.w(
        'Codex protocol warning (${error.message.length} characters; '
        'cause=${error.causeType ?? 'unknown'})',
      );
      _events.add(
        AgentErrorEvent(
          message: textCatalog.protocolWarning(config.displayName),
          details: error.toString(),
        ),
      );
    });
  }

  /// 将服务端通知委托给通知映射器，再由 provider 协调状态变更。
  void _handleNotification(JsonRpcNotification notification) {
    if (_shouldIgnoreNotification(notification.method)) {
      _ignoredMessageLogger.record(
        method: notification.method,
        reason: 'filtered by provider policy',
        payload: notification.params,
        rawPayload: notification.raw,
      );
      return;
    }
    if (_isErrorNotification(notification.method)) {
      // `error` 通知的消息在嵌套的 TurnError 里，`configWarning` 用 summary。
      final message =
          _string(notification.params['message']) ??
          _string(_map(notification.params['error'])['message']) ??
          _string(notification.params['summary']) ??
          'No message';
      _log.w(
        'Codex ${notification.method} '
        '(${message.length} message characters)',
      );
    } else if (notification.method == 'deprecationNotice') {
      // 弃用提示需可观测，便于升级适配层；UI 侧再做一次性展示。
      final summary = _string(notification.params['summary']) ?? 'No summary';
      final details = _string(notification.params['details']);
      _log.w(
        'Codex deprecationNotice '
        '(${summary.length} summary characters, '
        '${details?.length ?? 0} detail characters)',
      );
    } else if (notification.method == 'model/rerouted') {
      final fromModel = _string(notification.params['fromModel']);
      final toModel = _string(notification.params['toModel']);
      final reason = _string(notification.params['reason']);
      _log.i(
        'Codex model/rerouted: $fromModel → $toModel '
        '(${reason?.length ?? 0} reason characters)',
      );
    } else if (notification.method == 'skills/changed') {
      if (!_skillsChanged.isClosed) {
        _skillsChanged.add(null);
      }
      _log.t('Codex skills/changed received');
      return;
    }

    final mapping = _notificationMapper.map(
      notification,
      runningTurnIdForSession: (threadId) =>
          _runningTurnIdsBySessionId[threadId],
    );

    final ignoredReason = mapping.ignoredReason;
    if (ignoredReason != null) {
      _ignoredMessageLogger.record(
        method: notification.method,
        reason: ignoredReason,
        payload: notification.params,
        rawPayload: notification.raw,
        unmatched: mapping.unmatchedMethod != null,
      );
      return;
    }

    final startedTurn = mapping.startedTurn;
    if (startedTurn != null) {
      _markRunningTurn(startedTurn.sessionId, startedTurn.id);
    }

    final completedTurn = mapping.completedTurn;
    if (completedTurn != null) {
      _completeRunningTurn(completedTurn.sessionId, completedTurn.turnId);
      if (_runningTurnIdsBySessionId.isEmpty) {
        _emitStatus(
          AgentProviderStatus(
            state: AgentProviderConnectionState.ready,
            message: textCatalog.providerReady(config.displayName),
          ),
        );
      }
    }

    // 他端已解决交互：只清本地 pending，不再向服务端回写响应。
    for (final event in mapping.events) {
      if (event is AgentPermissionResolvedEvent) {
        final pendingQuestion = _pendingQuestions.remove(event.requestId);
        if (pendingQuestion != null) {
          _log.i(
            'Codex user question ${event.requestId} resolved externally; '
            'dismissing local question',
          );
          _events.add(
            AgentQuestionResolvedEvent(
              requestId: event.requestId,
              threadId: event.threadId,
              raw: event.raw,
            ),
          );
          continue;
        }
        final pending = _pendingApprovals.remove(event.requestId);
        if (pending != null) {
          _log.i(
            'Codex server request ${event.requestId} resolved externally '
            '(${pending.method}); dismissing local approval',
          );
        } else {
          _log.t(
            'Codex server request ${event.requestId} resolved externally '
            'with no local pending approval',
          );
        }
      } else if (event is AgentAutoApprovalReviewEvent) {
        _trackDeniedActionOverride(event);
      } else if (event is AgentThreadDeletedEvent ||
          event is AgentThreadClosedEvent) {
        // 线程关闭/删除：清理该 thread 的运行态与服务端订阅。
        final threadId = event is AgentThreadDeletedEvent
            ? event.threadId
            : (event as AgentThreadClosedEvent).threadId;
        _runningTurnIdsBySessionId.remove(threadId);
        _clearDeniedActionOverridesForThread(threadId);
        _notificationMapper.invalidateSession(
          runtimeScope: notification.runtimeScope,
          sessionId: threadId,
        );
        unawaited(_unsubscribeThreadBestEffort(threadId));
      }
      _events.add(event);
    }
  }

  /// 将服务端审批请求委托给审批映射器，再由 provider 保存待处理状态。
  Future<void> _handleServerRequest(JsonRpcRequest request) async {
    if (request.method == 'item/tool/requestUserInput') {
      final mapped = _questionMapper.mapRequest(request);
      _pendingQuestions[mapped.pendingQuestion.id] = mapped.pendingQuestion;
      _events.add(mapped.event);
      return;
    }

    // 未知或不支持的请求立即回 JSON-RPC error，不进 UI；伪造 `{}`/null
    // 成功应答会违反响应 schema，可能让服务端 turn 永久卡住。
    final rejection = _approvalMapper.rejectionFor(request);
    if (rejection != null) {
      _log.w(
        'Declining unsupported Codex server request ${request.method}: '
        '${rejection.message}',
      );
      await _peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        error: rejection,
      );
      return;
    }

    final mapped = _approvalMapper.mapRequest(request);
    _pendingApprovals[mapped.pendingApproval.id] = mapped.pendingApproval;
    _events.add(mapped.event);
  }

  void _handlePeerClosed() {
    if (_disposed ||
        _peer.lifecycleState == AgentProviderLifecycleState.closing ||
        _peer.lifecycleState == AgentProviderLifecycleState.closed) {
      return;
    }
    _notificationMapper.invalidateRuntime(_peer.runtimeScope);
    _initialized = false;
    _runningTurnIdsBySessionId.clear();
    _resolvePendingInteractionsOnConnectionClosed();
    _emitUnavailable(textCatalog.appServerConnectionClosed(config.displayName));
  }

  void _resolvePendingInteractionsOnConnectionClosed() {
    for (final pending in _pendingApprovals.values) {
      _events.add(
        AgentPermissionResolvedEvent(
          requestId: pending.id,
          threadId: _string(pending.params['threadId']) ?? '',
          raw: const <String, Object?>{'reason': 'connectionClosed'},
        ),
      );
    }
    _pendingApprovals.clear();
    _deniedActionEventsByRequestId.clear();
    for (final pending in _pendingQuestions.values) {
      _events.add(
        AgentQuestionResolvedEvent(
          requestId: pending.id,
          threadId: _string(pending.params['threadId']) ?? '',
          raw: const <String, Object?>{'reason': 'connectionClosed'},
        ),
      );
    }
    _pendingQuestions.clear();
  }

  void _trackDeniedActionOverride(AgentAutoApprovalReviewEvent event) {
    switch (event.status) {
      case 'denied':
        _deniedActionEventsByRequestId[event.reviewId] = event.raw;
      case 'approved' || 'timedOut' || 'aborted':
        _deniedActionEventsByRequestId.remove(event.reviewId);
    }
  }

  void _clearDeniedActionOverridesForThread(String threadId) {
    _deniedActionEventsByRequestId.removeWhere(
      (requestId, raw) => raw['threadId'] == threadId,
    );
  }

  /// 发出 provider 连接状态事件。
  void _emitStatus(AgentProviderStatus status) {
    _events.add(AgentStatusEvent(status));
  }

  /// 发出 unavailable 状态事件和错误事件。
  void _emitUnavailable(String message, {String? details}) {
    final status = AgentProviderStatus(
      state: AgentProviderConnectionState.unavailable,
      message: message,
      details: details,
    );
    _events
      ..add(AgentStatusEvent(status))
      ..add(AgentErrorEvent(message: message, details: details));
  }

  void _markRunningTurn(String sessionId, String turnId) {
    _runningTurnIdsBySessionId[sessionId] = turnId;
  }

  void _completeRunningTurn(String sessionId, String turnId) {
    if (_runningTurnIdsBySessionId[sessionId] == turnId) {
      _runningTurnIdsBySessionId.remove(sessionId);
    }
  }

  /// best-effort 退订：失败只记日志，不阻断显式会话关闭。
  Future<void> _unsubscribeThreadBestEffort(String threadId) async {
    try {
      final status = await _client.unsubscribeThread(threadId);
      _log.t(
        'Unsubscribed Codex thread $threadId'
        '${status == null ? '' : ' (status=$status)'}',
      );
    } catch (error) {
      _log.w(
        'Could not unsubscribe Codex thread $threadId '
        '(${error.runtimeType})',
      );
    }
  }

  bool _shouldIgnoreNotification(String method) {
    return switch (method) {
      'mcpServer/startupStatus/updated' => true,
      _ => false,
    };
  }
}

/// 默认通过 stdio 启动 Codex app-server 子进程。
JsonRpcPeer _defaultPeerFactory(AgentProviderConfig config) {
  return JsonRpcStdioTransport(
    command: config.command,
    arguments: config.arguments,
    environment: config.environment,
    processStarter: codexProcessStarter(config),
  );
}
