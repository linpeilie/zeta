import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_models_cli.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_operation_scheduler.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_runtime_json_rpc_peer.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_permission_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_acp_notification_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.grok_acp');

/// 根据 provider 配置创建 JSON-RPC 端点。
typedef JsonRpcPeerFactory = JsonRpcPeer Function(AgentProviderConfig config);

/// Grok CLI ACP stdio provider。
///
/// 启动 `grok agent stdio`，通过标准 ACP JSON-RPC 完成会话、流式回复与审批。
/// 不支持的 Codex 专有能力通过 [capabilities] 关闭，并在误调用时明确失败。
class GrokAcpAgentProvider
    implements
        AgentProvider,
        AgentRuntimeLifecycleProvider,
        AgentRuntimeScopeProvider {
  GrokAcpAgentProvider({
    required this.config,
    JsonRpcPeer? peer,
    JsonRpcPeerFactory? peerFactory,
    GrokSessionHistoryReader? sessionHistoryReader,
    GrokModelsCli? modelsCli,
    GrokAcpNotificationMapper? notificationMapper,
    List<Duration>? generatedTitlePollDelays,
  }) : _modelSelection = AgentModelSelection(
         modelId: config.selectedModel ?? config.defaultModel,
         reasoningEffort: config.selectedReasoningEffort,
         serviceTierId: config.selectedServiceTier,
       ),
       _sessionHistoryReader =
           sessionHistoryReader ?? GrokSessionHistoryReader(),
       _modelsCli = modelsCli ?? const GrokModelsCli(),
       _notificationMapper = notificationMapper ?? GrokAcpNotificationMapper(),
       _generatedTitlePollDelays =
           generatedTitlePollDelays ?? _defaultGeneratedTitlePollDelays {
    // 在构造体中创建 peer，以便闭包捕获运行时模型选择。
    final delegate =
        peer ??
        (peerFactory ??
            ((cfg) => createDefaultPeer(
              cfg,
              modelIdResolver: () => _modelSelection.modelId,
              reasoningEffortResolver: () => _modelSelection.reasoningEffort,
            )))(config);
    _peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: config.id);
  }

  /// 首轮结束后轮询本地 `summary.json` 的间隔（Grok 异步写 generated_title）。
  static const List<Duration> _defaultGeneratedTitlePollDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 21),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
  ];

  /// 测试友好的 peer 工厂：可注入 [modelIdResolver]。
  static JsonRpcPeer createDefaultPeer(
    AgentProviderConfig config, {
    String? Function()? modelIdResolver,
    String? Function()? reasoningEffortResolver,
  }) {
    return JsonRpcStdioTransport(
      command: config.command,
      arguments: config.arguments,
      environment: config.environment,
      processStarter: grokProcessStarter(
        config,
        modelIdResolver: modelIdResolver,
        reasoningEffortResolver: reasoningEffortResolver,
      ),
    );
  }

  late final ProviderRuntimeJsonRpcPeer _peer;
  final GrokSessionHistoryReader _sessionHistoryReader;
  final GrokModelsCli _modelsCli;
  final GrokAcpNotificationMapper _notificationMapper;
  final List<Duration> _generatedTitlePollDelays;

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final ProviderOperationScheduler _operationScheduler =
      ProviderOperationScheduler();

  final Map<String, _PendingAcpPermission> _pendingPermissions =
      <String, _PendingAcpPermission>{};

  AgentSession? _session;
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};

  /// sessionId → 工作目录，便于定位 `~/.grok/sessions/.../summary.json`。
  final Map<String, String> _projectPathBySessionId = <String, String>{};

  /// sessionId → 已解析的本地 session 目录，避免重复扫描。
  final Map<String, String> _sessionPathBySessionId = <String, String>{};

  /// 已向 UI 推送过的正式 generated_title，避免重复事件。
  final Map<String, String> _emittedTitlesBySessionId = <String, String>{};

  /// 标题轮询代数；切换会话或重新调度时递增以取消旧轮询。
  final Map<String, int> _titlePollTokensBySessionId = <String, int>{};

  AgentModelSelection _modelSelection;
  AgentModelList? _modelList;
  bool _initialized = false;
  Future<void>? _initializationOperation;
  bool _disposed = false;
  Future<void>? _disposeOperation;
  bool _loadSessionSupported = true;

  /// session/load 期间为 true：抑制回放通知进入直播时间线。
  bool _suppressingSessionLoadReplay = false;

  /// 本地读到的历史快照缓存（按 session id），避免重复解析大文件。
  final Map<String, AgentThreadHistorySnapshot> _historyCache =
      <String, AgentThreadHistorySnapshot>{};

  final Set<String> _loggedUnmatched = <String>{};
  final _random = Random();

  StreamSubscription<JsonRpcNotification>? _notificationSubscription;
  StreamSubscription<JsonRpcRequest>? _serverRequestSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<JsonRpcProtocolException>? _protocolErrorSubscription;

  @override
  final AgentProviderConfig config;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentProviderCapabilities get capabilities => AgentProviderCapabilities
      .grokAcp
      .copyWith(canResumeSession: _loadSessionSupported);

  @override
  AgentProviderLifecycleState get lifecycleState => _peer.lifecycleState;

  @override
  AgentRuntimeScope? get runtimeScope => _peer.runtimeScope;

  /// Grok identity reducer 的脱敏累计诊断。
  GrokStreamIdentityDiagnostics get streamIdentityDiagnostics =>
      _notificationMapper.diagnostics;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw const ProviderConnectionClosedException(
        'Grok Provider has been disposed',
      );
    }
    if (_initialized) {
      return;
    }
    final inFlight = _initializationOperation;
    if (inFlight != null) {
      await inFlight;
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

  Future<void> _initializeOnce() async {
    _log.info('Initializing Grok ACP provider ${config.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: 'Starting Grok CLI',
      ),
    );

    try {
      await _peer.start();
      _listenToPeer();

      final initResult = await _peer.sendRequest(
        'initialize',
        params: <String, Object?>{
          'protocolVersion': 1,
          'clientCapabilities': <String, Object?>{
            'fs': <String, Object?>{
              'readTextFile': true,
              'writeTextFile': false,
            },
            'terminal': false,
          },
          'clientInfo': <String, Object?>{
            'name': 'zeta',
            'title': 'Zeta IDE',
            'version': '0.1.0',
          },
        },
      );
      final initMap =
          _asStringKeyedMap(initResult) ?? const <String, Object?>{};
      final caps = _asStringKeyedMap(initMap['agentCapabilities']);
      _loadSessionSupported = caps?['loadSession'] != false;
      _log.info(
        'Grok initialize completed for ${config.id}; '
        'loadSession=$_loadSessionSupported',
      );

      // Grok 0.2.101 把完整模型列表放在 initialize._meta.modelState，
      // session/new 并不是唯一来源。这里必须在鉴权前接入，保证旧会话也能显示选择器。
      final initMeta = _asStringKeyedMap(initMap['_meta']);
      _applyModelsPayload(
        initMeta?['modelState'] ?? initMap['modelState'] ?? initMap['models'],
      );

      // 优先使用缓存 token；失败不阻断后续（某些环境可能已隐式鉴权）。
      await _authenticateBestEffort(initMap['authMethods']);

      _peer.markReady();
      _initialized = true;
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      _log.info('Grok ACP provider ${config.id} initialized');

      // 模型列表在 session/new 时更完整；此处先 CLI 降级预填。
      unawaited(_prefetchModelsFromCli());
    } on ProcessException catch (error, stackTrace) {
      _peer.markFailed();
      _log.warning('Could not start Grok CLI', error, stackTrace);
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error, stackTrace) {
      _peer.markFailed();
      _log.warning('Could not initialize Grok ACP provider', error, stackTrace);
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.error,
          message: 'Could not start ${config.displayName}',
          details: error.toString(),
        ),
      );
      _addEvent(
        AgentErrorEvent(
          message: 'Could not start ${config.displayName}',
          details: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> _authenticateBestEffort(Object? authMethods) async {
    String? methodId;
    if (authMethods is List) {
      for (final item in authMethods) {
        if (item is! Map) {
          continue;
        }
        final id = item['id']?.toString();
        if (id == 'cached_token') {
          methodId = id;
          break;
        }
        methodId ??= id;
      }
    }
    if (methodId == null) {
      return;
    }
    try {
      await _peer.sendRequest(
        'authenticate',
        params: <String, Object?>{'methodId': methodId},
        timeout: const Duration(seconds: 20),
      );
      _log.fine('Grok ACP authenticated via $methodId');
    } catch (error, stackTrace) {
      _log.warning(
        'Grok ACP authenticate($methodId) failed; continuing',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _prefetchModelsFromCli() async {
    if (_modelList != null && _modelList!.models.isNotEmpty) {
      return;
    }
    try {
      final list = await _modelsCli.listModels(config);
      if (_disposed || list.models.isEmpty) {
        return;
      }
      _setModelList(list);
    } catch (error, stackTrace) {
      _log.fine('CLI model prefetch failed', error, stackTrace);
    }
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    await initialize();
    final cwd = context.projectPath?.trim();
    if (cwd == null || cwd.isEmpty) {
      throw StateError('Grok ACP session/new requires projectPath as cwd');
    }

    final result = await _peer.sendRequest(
      'session/new',
      params: <String, Object?>{'cwd': cwd, 'mcpServers': <Object?>[]},
      timeout: const Duration(seconds: 60),
    );
    final map = _asStringKeyedMap(result) ?? const <String, Object?>{};
    final sessionId = map['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Grok ACP session/new returned no sessionId');
    }

    _applyModelsFromSessionPayload(map);
    await _applyModelSelectionIfNeeded(sessionId);

    final session = AgentSession(
      id: sessionId,
      providerId: config.id,
      raw: map,
    );
    _activateSession(session);
    _rememberProjectPath(sessionId, cwd);
    _addEvent(AgentSessionStartedEvent(session));
    _log.info('Started Grok ACP session $sessionId');
    return session;
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) => _scheduleThreadOperation(
    sessionId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      final cwd = context.projectPath?.trim();

      if (_loadSessionSupported) {
        // 历史预热属于本次独占恢复操作，避免后台读取越过后续同 Thread 变更。
        try {
          await _readThreadHistory(threadId: sessionId);
        } catch (_) {
          // 历史元数据不可用不应阻止协议恢复。
        }
        _suppressingSessionLoadReplay = true;
        try {
          final result = await _peer.sendRequest(
            'session/load',
            params: <String, Object?>{
              'sessionId': sessionId,
              if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
              'mcpServers': <Object?>[],
            },
            timeout: const Duration(seconds: 120),
          );
          final map = _asStringKeyedMap(result) ?? const <String, Object?>{};
          _applyModelsFromSessionPayload(map);
          await _applyModelSelectionIfNeeded(sessionId);
          final session = AgentSession(
            id: sessionId,
            providerId: config.id,
            raw: map,
          );
          _activateSession(session);
          if (cwd != null && cwd.isNotEmpty) {
            _rememberProjectPath(sessionId, cwd);
          }
          // 恢复已有会话时也可能已有 generated_title，主动同步一次。
          _scheduleGeneratedTitlePoll(sessionId);
          _addEvent(AgentSessionStartedEvent(session));
          _log.info('Loaded Grok ACP session $sessionId (replay suppressed)');
          return session;
        } catch (error, stackTrace) {
          _log.warning('session/load failed for $sessionId', error, stackTrace);
          rethrow;
        } finally {
          _suppressingSessionLoadReplay = false;
        }
      }

      throw UnsupportedError(
        '${config.displayName} does not support resuming existing sessions',
      );
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
          // 归档视图：Grok 本地存储暂无归档语义，返回空页。
          if (query.archived) {
            return const AgentThreadPage(
              threads: <AgentThreadSummary>[],
              nextCursor: null,
            );
          }
          return _sessionHistoryReader.listThreads(
            query: query,
            providerId: config.id,
            environment: <String, String>{
              ...Platform.environment,
              ...config.environment,
            },
          );
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

  Future<AgentThreadHistorySnapshot> _readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    // 历史 JSONL 只有用量和 modelId，上下文上限来自 initialize.modelState。
    // 初始化失败不应阻断离线历史，因此仅做 best-effort。
    if (_modelList == null || _modelList!.models.isEmpty) {
      try {
        await initialize();
      } catch (error, stackTrace) {
        _log.fine(
          'Could not load Grok model metadata before reading history',
          error,
          stackTrace,
        );
      }
    }
    final cached = _historyCache[threadId];
    if (cached != null &&
        cached.turns.isNotEmpty &&
        (sessionPath == null ||
            sessionPath.isEmpty ||
            cached.raw['sessionPath'] == sessionPath)) {
      return _enrichHistorySnapshot(cached);
    }

    final snapshot = await _sessionHistoryReader.readThreadHistory(
      threadId: threadId,
      providerId: config.id,
      projectPath: projectPath,
      sessionPath: sessionPath,
      environment: <String, String>{
        ...Platform.environment,
        ...config.environment,
      },
    );
    final enriched = _enrichHistorySnapshot(snapshot);
    if (enriched.turns.isNotEmpty) {
      _historyCache[threadId] = enriched;
    }
    return enriched;
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    final cached = _modelList;
    if (cached != null && cached.models.isNotEmpty) {
      return cached;
    }
    await initialize();
    if (_modelList != null && _modelList!.models.isNotEmpty) {
      return _modelList!;
    }
    final fromCli = await _modelsCli.listModels(config);
    if (!_disposed && fromCli.models.isNotEmpty) {
      _setModelList(fromCli);
    }
    return fromCli;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    _modelSelection = selection;
    final sessionId = _session?.id;
    if (sessionId != null) {
      unawaited(_applyModelSelectionIfNeeded(sessionId));
    }
  }

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {
    // Grok ACP 使用 session/request_permission 交互审批，无 Codex 策略模型。
    _log.fine(
      'Ignoring permission selection for Grok ACP '
      '(approval=${selection.approvalPolicy})',
    );
  }

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    return const <AgentPermissionProfileSummary>[];
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {
    _log.fine('Grok ACP has no Guardian; ignore approveGuardianDeniedAction');
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.sharedRead,
    () => _readThreadHistory(
      threadId: threadId,
      sessionPath: sessionPath,
      projectPath: projectPath,
    ),
  );

  @override
  Future<void> unsubscribeThread(String threadId) async {
    // ACP 无 thread 订阅模型。
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    throw UnsupportedError('Grok ACP does not support renaming threads');
  }

  @override
  Future<void> archiveThread(String threadId) async {
    throw UnsupportedError('Grok ACP does not support archiving threads');
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    throw UnsupportedError('Grok ACP does not support unarchiving threads');
  }

  @override
  Future<void> deleteThread(String threadId) async {
    throw UnsupportedError('Grok ACP does not support deleting threads');
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
  }) async {
    throw UnsupportedError('Grok ACP does not support forking threads');
  }

  @override
  Future<void> compactThread(String threadId) async {
    throw UnsupportedError('Grok ACP does not support compacting threads');
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    await initialize();
    final cwd = context.projectPath?.trim();
    if (cwd != null && cwd.isNotEmpty) {
      _rememberProjectPath(session.id, cwd);
    }
    final prompt = AcpContentCodec.buildPromptBlocks(
      message: message,
      inputs: inputs,
      context: context,
      encodeLocalImagesAsPathText: true,
    );
    final turnId = _newTurnId();
    _runningTurnIdsBySessionId[session.id] = turnId;
    final currentRuntimeScope = _peer.runtimeScope;
    if (currentRuntimeScope == null) {
      _runningTurnIdsBySessionId.remove(session.id);
      throw const ProviderConnectionClosedException(
        'Grok Provider has no active runtime scope',
      );
    }
    _notificationMapper.beginTurn(
      runtimeScope: currentRuntimeScope,
      sessionId: session.id,
      turnId: turnId,
    );
    final turn = AgentTurn(id: turnId, sessionId: session.id);
    _addEvent(AgentTurnStartedEvent(turn));
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Agent is working',
      ),
    );

    try {
      final result = await _peer.sendRequest(
        'session/prompt',
        params: <String, Object?>{'sessionId': session.id, 'prompt': prompt},
        // 单次 turn 可能很长；由用户取消或进程退出打断。
        timeout: const Duration(hours: 2),
      );
      final map = _asStringKeyedMap(result) ?? const <String, Object?>{};
      final stopReason =
          map['stopReason']?.toString() ??
          map['stop_reason']?.toString() ??
          'end_turn';
      final mapped = _notificationMapper.mapPromptTerminal(
        runtimeScope: currentRuntimeScope,
        sessionId: session.id,
        turnId: turnId,
        stopReason: stopReason,
        source: GrokTerminalSource.promptRpc,
        raw: map,
      );
      _noteTurnCompletedFromMapped(sessionId: session.id, mapped: mapped);
      _emitMapped(mapped);
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
    } catch (error, stackTrace) {
      _log.warning('session/prompt failed', error, stackTrace);
      _notificationMapper.noteBoundary(
        runtimeScope: currentRuntimeScope,
        sessionId: session.id,
        runningTurnId: turnId,
        kind: GrokNarrativeBoundaryKind.warningOrSystem,
      );
      final mapped = _notificationMapper.mapPromptTerminal(
        runtimeScope: currentRuntimeScope,
        sessionId: session.id,
        turnId: turnId,
        stopReason: 'prompt_error',
        source: GrokTerminalSource.promptError,
      );
      _noteTurnCompletedFromMapped(sessionId: session.id, mapped: mapped);
      _emitMapped(mapped);
      _notificationMapper.invalidateTurn(
        runtimeScope: currentRuntimeScope,
        sessionId: session.id,
        runningTurnId: turnId,
        promptId: null,
        reason: GrokIdentityInvalidationReason.promptError,
      );
      _addEvent(
        AgentErrorEvent(
          message: 'Grok prompt failed',
          details: error.toString(),
        ),
      );
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.error,
          message: 'Prompt failed',
          details: error.toString(),
        ),
      );
      rethrow;
    }

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
    throw UnsupportedError('Grok ACP does not support steering active turns');
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    _log.info('Cancelling Grok ACP turn ${turn.id}');
    final currentRuntimeScope = _peer.runtimeScope;
    _peer.sendNotification(
      'session/cancel',
      params: <String, Object?>{'sessionId': turn.sessionId},
    );
    if (currentRuntimeScope != null) {
      final mapped = _notificationMapper.mapPromptTerminal(
        runtimeScope: currentRuntimeScope,
        sessionId: turn.sessionId,
        turnId: turn.id,
        stopReason: 'cancelled',
        source: GrokTerminalSource.cancel,
      );
      _noteTurnCompletedFromMapped(sessionId: turn.sessionId, mapped: mapped);
      _emitMapped(mapped);
      _notificationMapper.invalidateTurn(
        runtimeScope: currentRuntimeScope,
        sessionId: turn.sessionId,
        runningTurnId: turn.id,
        promptId: null,
        reason: GrokIdentityInvalidationReason.cancel,
      );
    }
    // 取消时关闭所有挂起的审批。
    for (final entry in List<_PendingAcpPermission>.from(
      _pendingPermissions.values,
    )) {
      await _respondPermissionCancelled(entry);
    }
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    final pending = _pendingPermissions.remove(decision.requestId);
    if (pending == null) {
      _log.warning(
        'Ignoring response for unknown Grok permission ${decision.requestId}',
      );
      return;
    }

    if (decision.cancelTurn) {
      await _respondPermissionCancelled(pending);
      return;
    }

    final optionId = pending.mapping.preferredOptionId(
      approved: decision.approved,
    );
    if (optionId == null) {
      await _respondPermissionCancelled(pending);
      return;
    }

    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{
        'outcome': <String, Object?>{
          'outcome': 'selected',
          'optionId': optionId,
        },
      },
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
    _disposed = true;
    _operationScheduler.beginClosing();
    _peer.beginClosing();
    final currentRuntimeScope = _peer.runtimeScope;
    if (currentRuntimeScope != null) {
      _notificationMapper.invalidateRuntime(
        runtimeScope: currentRuntimeScope,
        reason: GrokIdentityInvalidationReason.dispose,
      );
    }
    // 递增所有 token 以停止进行中的标题轮询。
    for (final sessionId in _titlePollTokensBySessionId.keys.toList()) {
      _titlePollTokensBySessionId[sessionId] =
          (_titlePollTokensBySessionId[sessionId] ?? 0) + 1;
    }
    for (final pending in _pendingPermissions.values.toList()) {
      try {
        await _respondPermissionCancelled(pending);
      } catch (_) {
        _pendingPermissions.remove(pending.requestKey);
      }
    }
    await _notificationSubscription?.cancel();
    await _serverRequestSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    await _peer.close();
    await _operationScheduler.close();
    _notificationMapper.dispose();
    await _events.close();
  }

  void _listenToPeer() {
    _notificationSubscription ??= _peer.notifications.listen(
      _handleNotification,
      onDone: _handlePeerClosed,
    );
    _serverRequestSubscription ??= _peer.serverRequests.listen((request) {
      unawaited(
        _peer.handleServerRequest(request, _handleServerRequest).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          _log.warning(
            'Grok server request ${request.method} did not complete',
            error,
            stackTrace,
          );
        }),
      );
    });
    _stderrSubscription ??= _peer.stderrLines.listen((line) {
      if (line.trim().isEmpty) {
        return;
      }
      _log.fine('Grok stderr (${line.length} chars)');
    });
    _protocolErrorSubscription ??= _peer.protocolErrors.listen((error) {
      _log.warning(
        'Grok protocol warning (${error.message.length} characters)',
        error.cause,
      );
      _addEvent(
        AgentErrorEvent(
          message: 'Grok protocol warning',
          details: error.toString(),
        ),
      );
    });
  }

  void _handleNotification(JsonRpcNotification notification) {
    final method = notification.method;
    final params = notification.params;
    final notificationRuntimeScope = notification.runtimeScope;
    if (notificationRuntimeScope == null) {
      return;
    }

    // session/load 回放或带 isReplay 的更新：不进入直播时间线，避免与
    // readThreadHistory → applyHistorySnapshot 重复渲染。
    if (_shouldSuppressTimelineNotification(method: method, params: params)) {
      return;
    }

    if (method == 'session/update') {
      final sessionId = params['sessionId']?.toString();
      final turnId = sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId];
      final mapped = _notificationMapper.mapSessionUpdate(
        params: params,
        runningTurnId: turnId,
        runtimeScope: notificationRuntimeScope,
      );
      _noteTurnCompletedFromMapped(sessionId: sessionId, mapped: mapped);
      _emitMapped(mapped);
      return;
    }

    if (method == '_x.ai/session/update' || method == 'x.ai/session/update') {
      final sessionId = params['sessionId']?.toString();
      final turnId = sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId];
      final mapped = _notificationMapper.mapXaiSessionUpdate(
        params: params,
        runningTurnId: turnId,
        runtimeScope: notificationRuntimeScope,
      );
      _noteTurnCompletedFromMapped(sessionId: sessionId, mapped: mapped);
      _emitMapped(mapped);
      return;
    }

    // 其它 x.ai 扩展通知：诊断即可，避免刷屏。
    if (method.startsWith('_x.ai/') || method.startsWith('x.ai/')) {
      if (_loggedUnmatched.add(method)) {
        _log.fine('Ignoring Grok extension notification: $method');
      }
      return;
    }

    if (_loggedUnmatched.add(method)) {
      _log.fine('Unmatched Grok notification: $method');
    }
  }

  void _emitMapped(GrokAcpMappedUpdate mapped) {
    for (final event in mapped.events) {
      _addEvent(_enrichUsageEvent(event));
    }
    final unmatched = mapped.unmatchedKind;
    if (unmatched != null &&
        mapped.events.isEmpty &&
        _loggedUnmatched.add(unmatched)) {
      _log.fine('Unmatched Grok update kind: $unmatched');
    }
  }

  /// 通知路径已完成回合时，清除 running 标记，避免 RPC 返回再 complete 一次。
  void _noteTurnCompletedFromMapped({
    required String? sessionId,
    required GrokAcpMappedUpdate mapped,
  }) {
    if (sessionId == null) {
      return;
    }
    for (final event in mapped.events) {
      if (event is AgentTurnCompletedEvent) {
        if (_runningTurnIdsBySessionId[sessionId] == event.turnId) {
          _runningTurnIdsBySessionId.remove(sessionId);
        }
        // Grok 在 turn 后异步写 summary.generated_title，无 live 通知。
        _scheduleGeneratedTitlePoll(sessionId);
        return;
      }
    }
  }

  void _activateSession(AgentSession session) {
    final previousSessionId = _session?.id;
    final currentRuntimeScope = _peer.runtimeScope;
    if (previousSessionId != null &&
        previousSessionId != session.id &&
        currentRuntimeScope != null) {
      _notificationMapper.invalidateSession(
        runtimeScope: currentRuntimeScope,
        sessionId: previousSessionId,
        reason: GrokIdentityInvalidationReason.sessionSwitched,
      );
      _runningTurnIdsBySessionId.remove(previousSessionId);
    }
    _session = session;
  }

  void _rememberProjectPath(String sessionId, String projectPath) {
    final trimmed = projectPath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _projectPathBySessionId[sessionId] = trimmed;
  }

  /// 调度对 `summary.json` 的轮询；新调度会使旧轮询失效。
  void _scheduleGeneratedTitlePoll(String sessionId) {
    if (_disposed || sessionId.isEmpty) {
      return;
    }
    final token = (_titlePollTokensBySessionId[sessionId] ?? 0) + 1;
    _titlePollTokensBySessionId[sessionId] = token;
    unawaited(_pollGeneratedTitle(sessionId: sessionId, token: token));
  }

  Future<void> _pollGeneratedTitle({
    required String sessionId,
    required int token,
  }) async {
    final delays = _generatedTitlePollDelays;
    for (var index = 0; index < delays.length; index++) {
      final delay = delays[index];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (_disposed || _titlePollTokensBySessionId[sessionId] != token) {
        return;
      }

      final snapshot = await _sessionHistoryReader.readSessionTitleSnapshot(
        threadId: sessionId,
        projectPath: _projectPathBySessionId[sessionId],
        sessionPath: _sessionPathBySessionId[sessionId],
        environment: <String, String>{
          ...Platform.environment,
          ...config.environment,
        },
      );
      if (_disposed || _titlePollTokensBySessionId[sessionId] != token) {
        return;
      }
      final sessionPath = snapshot?.sessionPath?.trim();
      if (sessionPath != null && sessionPath.isNotEmpty) {
        _sessionPathBySessionId[sessionId] = sessionPath;
      }

      // 只认 generated_title 为自动改名终态，避免 session_summary / 临时文案抢先结束轮询。
      final authoritative = snapshot?.authoritativeTitle?.trim();
      if (authoritative != null && authoritative.isNotEmpty) {
        if (_emittedTitlesBySessionId[sessionId] == authoritative) {
          return;
        }
        _emittedTitlesBySessionId[sessionId] = authoritative;
        _log.info(
          'Grok session $sessionId generated_title ready '
          '(${authoritative.length} characters)',
        );
        _addEvent(
          AgentThreadNameUpdatedEvent(
            threadId: sessionId,
            threadName: authoritative,
          ),
        );
        return;
      }

      // 最后一轮仍无 generated_title 时，才回退 session_summary（总好过一直停在临时标题）。
      final isLastAttempt = index == delays.length - 1;
      if (!isLastAttempt) {
        continue;
      }
      final fallback = snapshot?.sessionSummary?.trim();
      if (fallback == null || fallback.isEmpty) {
        _log.fine(
          'Grok session $sessionId title poll finished without generated_title',
        );
        return;
      }
      if (_emittedTitlesBySessionId[sessionId] == fallback) {
        return;
      }
      _emittedTitlesBySessionId[sessionId] = fallback;
      _log.fine(
        'Grok session $sessionId falling back to session_summary '
        '(${fallback.length} characters)',
      );
      _addEvent(
        AgentThreadNameUpdatedEvent(threadId: sessionId, threadName: fallback),
      );
    }
  }

  /// 是否应抑制通知进入直播时间线。
  bool _shouldSuppressTimelineNotification({
    required String method,
    required Map<String, Object?> params,
  }) {
    if (_suppressingSessionLoadReplay &&
        (method == 'session/update' ||
            method == '_x.ai/session/update' ||
            method == 'x.ai/session/update' ||
            method.startsWith('_x.ai/') ||
            method.startsWith('x.ai/'))) {
      return true;
    }
    final meta = _asStringKeyedMap(params['_meta']);
    if (meta?['isReplay'] == true) {
      return true;
    }
    final update = _asStringKeyedMap(params['update']);
    final updateMeta = _asStringKeyedMap(update?['_meta']);
    if (updateMeta?['isReplay'] == true) {
      return true;
    }
    return false;
  }

  Future<void> _handleServerRequest(JsonRpcRequest request) async {
    try {
      switch (request.method) {
        case 'session/request_permission':
          await _handlePermissionRequest(request);
        case 'fs/read_text_file':
          await _handleReadTextFile(request);
        case 'fs/write_text_file':
          await _peer.sendScopedResponse(
            request.id,
            runtimeScope: request.runtimeScope,
            error: const JsonRpcError(
              code: -32601,
              message: 'fs/write_text_file is not supported by Zeta client',
            ),
          );
        default:
          _log.fine(
            'Rejecting unsupported Grok server request ${request.method}',
          );
          await _peer.sendScopedResponse(
            request.id,
            runtimeScope: request.runtimeScope,
            error: JsonRpcError(
              code: -32601,
              message: 'Method not supported: ${request.method}',
            ),
          );
      }
    } catch (error, stackTrace) {
      // 服务端请求必须始终应答，否则 session/prompt 会一直挂起。
      _log.warning(
        'Grok server request ${request.method} failed',
        error,
        stackTrace,
      );
      try {
        await _peer.sendScopedResponse(
          request.id,
          runtimeScope: request.runtimeScope,
          error: JsonRpcError(code: -32000, message: error.toString()),
        );
      } catch (_) {
        // 连接已断开时忽略二次失败。
      }
    }
  }

  void _handlePeerClosed() {
    if (_disposed ||
        _peer.lifecycleState == AgentProviderLifecycleState.closing ||
        _peer.lifecycleState == AgentProviderLifecycleState.closed) {
      return;
    }
    final closedRuntimeScope = _peer.runtimeScope;
    if (closedRuntimeScope != null) {
      _notificationMapper.invalidateRuntime(
        runtimeScope: closedRuntimeScope,
        reason: GrokIdentityInvalidationReason.peerClosed,
      );
    }
    _initialized = false;
    _runningTurnIdsBySessionId.clear();
    for (final pending in _pendingPermissions.values) {
      _addEvent(
        AgentPermissionResolvedEvent(
          requestId: pending.requestKey,
          threadId: pending.mapping.request.sessionId ?? '',
          raw: const <String, Object?>{'reason': 'connectionClosed'},
        ),
      );
    }
    _pendingPermissions.clear();
    _emitUnavailable('Grok ACP 连接已关闭');
  }

  Future<void> _handlePermissionRequest(JsonRpcRequest request) async {
    final params = request.params;
    final sessionId = params['sessionId']?.toString();
    final requestRuntimeScope = request.runtimeScope;
    if (sessionId != null && requestRuntimeScope != null) {
      _notificationMapper.noteBoundary(
        runtimeScope: requestRuntimeScope,
        sessionId: sessionId,
        runningTurnId: _runningTurnIdsBySessionId[sessionId],
        kind: GrokNarrativeBoundaryKind.permission,
      );
    }
    final mapping = AcpPermissionMapper.mapRequest(
      requestId: request.id,
      params: params,
      runningTurnId: sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId],
    );
    final requestKey = mapping.request.id;
    final pending = _PendingAcpPermission(
      requestId: request.id,
      requestKey: requestKey,
      runtimeScope: request.runtimeScope,
      mapping: mapping,
    );
    _pendingPermissions[requestKey] = pending;

    _log.info('Grok permission requested; options=${mapping.options.length}');

    // 无选项时无法交互批准，立即 cancelled，避免 prompt 永久挂起。
    if (mapping.options.isEmpty) {
      _log.warning(
        'Grok permission $requestKey has no options; cancelling to unblock',
      );
      await _respondPermissionCancelled(pending);
      return;
    }

    _addEvent(AgentPermissionRequestedEvent(mapping.request));

    // 更新状态文案，避免 UI 看起来像「无响应卡住」。
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for approval: ${mapping.request.title}',
      ),
    );
  }

  Future<void> _handleReadTextFile(JsonRpcRequest request) async {
    final rawPath = request.params['path']?.toString();
    final path = _normalizeClientFsPath(rawPath);
    if (path == null || path.isEmpty) {
      await _peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        error: const JsonRpcError(code: -32602, message: 'path is required'),
      );
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        await _peer.sendScopedResponse(
          request.id,
          runtimeScope: request.runtimeScope,
          error: JsonRpcError(code: -32000, message: 'File not found: $path'),
        );
        return;
      }
      var text = await file.readAsString();
      final line = request.params['line'];
      final limit = request.params['limit'];
      final lineNum = line is int ? line : int.tryParse(line?.toString() ?? '');
      final limitNum = limit is int
          ? limit
          : int.tryParse(limit?.toString() ?? '');
      if (lineNum != null || limitNum != null) {
        final lines = const LineSplitter().convert(text);
        final start = lineNum != null && lineNum > 0 ? lineNum - 1 : 0;
        final end = limitNum != null && limitNum > 0
            ? (start + limitNum).clamp(0, lines.length)
            : lines.length;
        text = lines.sublist(start.clamp(0, lines.length), end).join('\n');
      }
      await _peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        result: <String, Object?>{'content': text},
      );
    } catch (error) {
      await _peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        error: JsonRpcError(code: -32000, message: error.toString()),
      );
    }
  }

  /// 规范化 ACP `fs/read_text_file` 路径（支持 `file:///` 与 Windows 盘符）。
  String? _normalizeClientFsPath(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    var path = trimmed;
    if (path.startsWith('file:')) {
      final uri = Uri.tryParse(path);
      if (uri != null && uri.scheme == 'file') {
        // Windows: file:///D:/a/b → /D:/a/b → D:/a/b
        path = uri.toFilePath(windows: Platform.isWindows);
      } else {
        path = path.replaceFirst(RegExp(r'^file:///?'), '');
        if (Platform.isWindows && path.startsWith('/')) {
          path = path.substring(1);
        }
      }
    }
    try {
      path = Uri.decodeFull(path);
    } catch (_) {
      // 非百分号编码路径保持原样。
    }
    return path;
  }

  Future<void> _respondPermissionCancelled(
    _PendingAcpPermission pending,
  ) async {
    _pendingPermissions.remove(pending.requestKey);
    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
    );
  }

  void _applyModelsFromSessionPayload(Map<String, Object?> map) {
    _applyModelsPayload(map['models']);
  }

  /// 应用 initialize / session 返回的模型状态，并保留更完整的旧元数据。
  void _applyModelsPayload(Object? payload) {
    final list = parseAcpModelsPayload(payload);
    if (list == null || list.models.isEmpty) {
      return;
    }
    final modelsMap = _asStringKeyedMap(payload);
    _setModelList(
      list,
      currentModelId: modelsMap?['currentModelId']?.toString(),
    );
  }

  void _setModelList(AgentModelList incoming, {String? currentModelId}) {
    if (_disposed) {
      return;
    }
    final previousById = <String, AgentModelInfo>{
      for (final model in _modelList?.models ?? const <AgentModelInfo>[])
        model.id: model,
    };
    final incomingIds = incoming.models.map((model) => model.id).toSet();
    final merged = AgentModelList(
      models: List<AgentModelInfo>.unmodifiable(<AgentModelInfo>[
        ...incoming.models.map((model) {
          final previous = previousById[model.id];
          if (previous == null || model.contextWindowTokens != null) {
            return model;
          }
          return AgentModelInfo(
            id: model.id,
            model: model.model,
            displayName: model.displayName,
            description: model.description ?? previous.description,
            hidden: model.hidden,
            supportedReasoningEfforts: model.supportedReasoningEfforts.isEmpty
                ? previous.supportedReasoningEfforts
                : model.supportedReasoningEfforts,
            defaultReasoningEffort:
                model.defaultReasoningEffort ?? previous.defaultReasoningEffort,
            serviceTiers: model.serviceTiers.isEmpty
                ? previous.serviceTiers
                : model.serviceTiers,
            defaultServiceTier:
                model.defaultServiceTier ?? previous.defaultServiceTier,
            isDefault: model.isDefault,
            contextWindowTokens: previous.contextWindowTokens,
            raw: model.raw,
          );
        }),
        for (final previous in previousById.values)
          if (!incomingIds.contains(previous.id)) previous,
      ]),
      nextCursor: incoming.nextCursor,
    );
    _modelList = merged;
    _addEvent(AgentModelListEvent(merged));

    // 同步当前模型选择
    final current = currentModelId?.trim();
    if (current != null &&
        current.isNotEmpty &&
        (_modelSelection.modelId == null || _modelSelection.modelId!.isEmpty)) {
      _modelSelection = AgentModelSelection(
        modelId: current,
        reasoningEffort: _modelSelection.reasoningEffort,
        serviceTierId: _modelSelection.serviceTierId,
      );
    }
  }

  AgentEvent _enrichUsageEvent(AgentEvent event) {
    if (event is! AgentTokenUsageEvent ||
        event.tokenUsage.modelContextWindow != null) {
      return event;
    }
    final window = _contextWindowForModel();
    if (window == null) {
      return event;
    }
    return AgentTokenUsageEvent(
      sessionId: event.sessionId,
      turnId: event.turnId,
      isSessionCumulative: event.isSessionCumulative,
      tokenUsage: _withContextWindow(event.tokenUsage, window),
      raw: event.raw,
    );
  }

  AgentThreadHistorySnapshot _enrichHistorySnapshot(
    AgentThreadHistorySnapshot snapshot,
  ) {
    final turns = <AgentHistoryTurn>[];
    for (final turn in snapshot.turns) {
      final usage = turn.tokenUsage;
      final window =
          turn.modelContextWindow ??
          usage?.modelContextWindow ??
          _contextWindowForModel(turn.model);
      if (window == null) {
        turns.add(turn);
        continue;
      }
      turns.add(
        AgentHistoryTurn(
          id: turn.id,
          entries: turn.entries,
          status: turn.status,
          startedAt: turn.startedAt,
          completedAt: turn.completedAt,
          duration: turn.duration,
          timeToFirstToken: turn.timeToFirstToken,
          cwd: turn.cwd,
          model: turn.model,
          modelContextWindow: window,
          collaborationMode: turn.collaborationMode,
          tokenUsage: usage == null ? null : _withContextWindow(usage, window),
          tokenUsageIsSessionCumulative: turn.tokenUsageIsSessionCumulative,
          errorMessage: turn.errorMessage,
          errorCode: turn.errorCode,
          raw: turn.raw,
        ),
      );
    }
    final currentTurnId = snapshot.currentTurn?.id;
    AgentHistoryTurn? currentTurn;
    if (currentTurnId != null) {
      for (final turn in turns) {
        if (turn.id == currentTurnId) {
          currentTurn = turn;
          break;
        }
      }
    }
    return AgentThreadHistorySnapshot(
      threadId: snapshot.threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: currentTurn,
      raw: snapshot.raw,
    );
  }

  int? _contextWindowForModel([String? modelId]) {
    final models = _modelList?.models ?? const <AgentModelInfo>[];
    if (models.isEmpty) {
      return null;
    }
    final target = modelId?.trim().isNotEmpty == true
        ? modelId!.trim()
        : _modelSelection.modelId?.trim();
    if (target != null && target.isNotEmpty) {
      for (final model in models) {
        if (model.id == target || model.model == target) {
          return model.contextWindowTokens;
        }
      }
    }
    for (final model in models) {
      if (model.isDefault && model.contextWindowTokens != null) {
        return model.contextWindowTokens;
      }
    }
    return null;
  }

  AgentTokenUsage _withContextWindow(AgentTokenUsage usage, int window) {
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
      modelContextWindow: usage.modelContextWindow ?? window,
    );
  }

  Future<void> _applyModelSelectionIfNeeded(String sessionId) async {
    final modelId = _modelSelection.modelId?.trim();
    if (modelId == null || modelId.isEmpty) {
      return;
    }
    try {
      await _peer.sendRequest(
        'session/set_model',
        params: <String, Object?>{'sessionId': sessionId, 'modelId': modelId},
        timeout: const Duration(seconds: 15),
      );
    } catch (error, stackTrace) {
      _log.fine('session/set_model failed for $modelId', error, stackTrace);
    }
  }

  String _newTurnId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return 'grok-turn-$millis-$suffix';
  }

  void _emitStatus(AgentProviderStatus status) {
    _addEvent(AgentStatusEvent(status));
  }

  void _emitUnavailable(String message, {String? details}) {
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.unavailable,
        message: message,
        details: details,
      ),
    );
    _addEvent(AgentErrorEvent(message: message, details: details));
  }

  /// provider 切换时异步任务可能晚于 dispose 返回；关闭后禁止再写事件流。
  void _addEvent(AgentEvent event) {
    if (_disposed || _events.isClosed) {
      return;
    }
    _events.add(event);
  }

  Map<String, Object?>? _asStringKeyedMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, item) => MapEntry(key.toString(), item as Object?));
  }
}

class _PendingAcpPermission {
  _PendingAcpPermission({
    required this.requestId,
    required this.requestKey,
    required this.runtimeScope,
    required this.mapping,
  });

  final Object requestId;
  final String requestKey;
  final AgentRuntimeScope? runtimeScope;
  final AcpPermissionMapping mapping;
}
