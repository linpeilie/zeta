import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_models_cli.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_acp_notification_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.grok_acp');

/// 根据 provider 配置创建 JSON-RPC 端点。
typedef JsonRpcPeerFactory = JsonRpcPeer Function(AgentProviderConfig config);

/// Grok CLI ACP stdio provider。
///
/// 启动 `grok agent stdio`，通过标准 ACP JSON-RPC 完成会话、流式回复与审批。
/// 不支持的 Codex 专有能力（Guardian、permission profile 等）安全 no-op。
class GrokAcpAgentProvider implements AgentProvider {
  GrokAcpAgentProvider({
    required this.config,
    JsonRpcPeer? peer,
    JsonRpcPeerFactory? peerFactory,
    GrokSessionHistoryReader? sessionHistoryReader,
    GrokModelsCli? modelsCli,
    GrokAcpNotificationMapper? notificationMapper,
  }) : _modelSelection = AgentModelSelection(
         modelId: config.selectedModel ?? config.defaultModel,
         reasoningEffort: config.selectedReasoningEffort,
         serviceTierId: config.selectedServiceTier,
       ),
       _sessionHistoryReader =
           sessionHistoryReader ?? GrokSessionHistoryReader(),
       _modelsCli = modelsCli ?? const GrokModelsCli(),
       _notificationMapper =
           notificationMapper ?? const GrokAcpNotificationMapper() {
    // 在构造体中创建 peer，以便闭包捕获运行时模型选择。
    _peer =
        peer ??
        (peerFactory ??
            ((cfg) => createDefaultPeer(
              cfg,
              modelIdResolver: () => _modelSelection.modelId,
              reasoningEffortResolver: () => _modelSelection.reasoningEffort,
            )))(config);
  }

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

  late final JsonRpcPeer _peer;
  final GrokSessionHistoryReader _sessionHistoryReader;
  final GrokModelsCli _modelsCli;
  final GrokAcpNotificationMapper _notificationMapper;

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  final Map<String, _PendingAcpPermission> _pendingPermissions =
      <String, _PendingAcpPermission>{};

  AgentSession? _session;
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};

  /// 最近一次 turn id（含已完成），供 `session/prompt` 返回后迟到的
  /// `turn_completed` 通知仍能对齐本地 turn 分组。
  final Map<String, String> _lastTurnIdsBySessionId = <String, String>{};
  AgentModelSelection _modelSelection;
  AgentModelList? _modelList;
  bool _initialized = false;
  Future<void>? _initializationOperation;
  bool _disposed = false;
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
  Future<void> initialize() async {
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

      // 优先使用缓存 token；失败不阻断后续（某些环境可能已隐式鉴权）。
      await _authenticateBestEffort(initMap['authMethods']);

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
      _log.warning('Could not start Grok CLI', error, stackTrace);
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error, stackTrace) {
      _log.warning('Could not initialize Grok ACP provider', error, stackTrace);
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.error,
          message: 'Could not start ${config.displayName}',
          details: error.toString(),
        ),
      );
      _events.add(
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
      if (list.models.isEmpty) {
        return;
      }
      _modelList = list;
      _events.add(AgentModelListEvent(list));
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
    _session = session;
    _events.add(AgentSessionStartedEvent(session));
    _log.info('Started Grok ACP session $sessionId');
    return session;
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    await initialize();
    final cwd = context.projectPath?.trim();

    if (_loadSessionSupported) {
      // 预热本地历史缓存：UI 已在 switchThread 应用过；此处保证后续读一致。
      unawaited(
        readThreadHistory(threadId: sessionId).then((_) {}, onError: (_) {}),
      );
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
        _session = session;
        _events.add(AgentSessionStartedEvent(session));
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
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
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
    _modelList = fromCli;
    if (fromCli.models.isNotEmpty) {
      _events.add(AgentModelListEvent(fromCli));
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
  }) async {
    final cached = _historyCache[threadId];
    if (cached != null &&
        cached.turns.isNotEmpty &&
        (sessionPath == null ||
            sessionPath.isEmpty ||
            cached.raw['sessionPath'] == sessionPath)) {
      return cached;
    }

    final snapshot = await _sessionHistoryReader.readThreadHistory(
      threadId: threadId,
      providerId: config.id,
      projectPath: null,
      sessionPath: sessionPath,
      environment: <String, String>{
        ...Platform.environment,
        ...config.environment,
      },
    );
    if (snapshot.turns.isNotEmpty) {
      _historyCache[threadId] = snapshot;
    }
    return snapshot;
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    // ACP 无 thread 订阅模型。
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    _log.fine('Grok ACP renameThread is not supported; no-op ($threadId)');
  }

  @override
  Future<void> archiveThread(String threadId) async {
    _log.fine('Grok ACP archiveThread is not supported; no-op ($threadId)');
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    _log.fine('Grok ACP unarchiveThread is not supported; no-op ($threadId)');
  }

  @override
  Future<void> deleteThread(String threadId) async {
    // 尝试标准/扩展删除；失败则 no-op。
    try {
      await _peer.sendRequest(
        'session/delete',
        params: <String, Object?>{'sessionId': threadId},
        timeout: const Duration(seconds: 15),
      );
      if (_session?.id == threadId) {
        _session = null;
      }
      _events.add(AgentThreadDeletedEvent(threadId: threadId));
    } catch (error, stackTrace) {
      _log.fine(
        'session/delete unsupported or failed for $threadId',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
  }) async {
    try {
      final result = await _peer.sendRequest(
        'session/fork',
        params: <String, Object?>{
          'sessionId': threadId,
          if (context.projectPath case final cwd?
              when cwd.trim().isNotEmpty) ...{
            'cwd': cwd,
          },
          'mcpServers': <Object?>[],
        },
        timeout: const Duration(seconds: 60),
      );
      final map = _asStringKeyedMap(result) ?? const <String, Object?>{};
      final newId =
          map['sessionId']?.toString() ?? map['newSessionId']?.toString();
      if (newId != null && newId.isNotEmpty) {
        final session = AgentSession(
          id: newId,
          providerId: config.id,
          raw: map,
        );
        _session = session;
        _events.add(AgentSessionStartedEvent(session));
        return session;
      }
    } catch (error, stackTrace) {
      _log.fine('session/fork failed; creating new session', error, stackTrace);
    }
    return startSession(context: context);
  }

  @override
  Future<AgentThreadHistorySnapshot> rollbackThread({
    required String threadId,
    required int numTurns,
  }) async {
    try {
      await _peer.sendRequest(
        'x.ai/rewind',
        params: <String, Object?>{'sessionId': threadId, 'numTurns': numTurns},
        timeout: const Duration(seconds: 30),
      );
    } catch (error, stackTrace) {
      _log.fine('x.ai/rewind unsupported', error, stackTrace);
    }
    return readThreadHistory(threadId: threadId);
  }

  @override
  Future<void> compactThread(String threadId) async {
    // 通过 slash 命令 compact 触发（若 agent 支持 available command）。
    try {
      await _peer.sendRequest(
        'session/prompt',
        params: <String, Object?>{
          'sessionId': threadId,
          'prompt': <Object?>[
            <String, Object?>{'type': 'text', 'text': '/compact'},
          ],
        },
        timeout: const Duration(minutes: 5),
      );
    } catch (error, stackTrace) {
      _log.fine('compact via /compact failed', error, stackTrace);
    }
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
    final prompt = _buildPromptBlocks(
      message: message,
      inputs: inputs,
      context: context,
    );
    final turnId = _newTurnId();
    _runningTurnIdsBySessionId[session.id] = turnId;
    _lastTurnIdsBySessionId[session.id] = turnId;
    final turn = AgentTurn(id: turnId, sessionId: session.id);
    _events.add(AgentTurnStartedEvent(turn));
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
      // 若 `_x.ai/session/update` turn_completed 已先完成，不再二次 complete
      //（避免冲掉 usage/duration，也避免与迟到通知竞态）。
      if (_runningTurnIdsBySessionId[session.id] == turnId) {
        final stopReason =
            map['stopReason']?.toString() ??
            map['stop_reason']?.toString() ??
            'end_turn';
        final status = _stopReasonToStatus(stopReason);
        _runningTurnIdsBySessionId.remove(session.id);
        _events.add(
          AgentTurnCompletedEvent(
            sessionId: session.id,
            turnId: turnId,
            status: status,
            errorMessage: status == AgentHistoryTurnStatus.failed
                ? stopReason
                : null,
            raw: map,
          ),
        );
      }
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
    } catch (error, stackTrace) {
      final stillRunning = _runningTurnIdsBySessionId[session.id] == turnId;
      if (stillRunning) {
        _runningTurnIdsBySessionId.remove(session.id);
      }
      _log.warning('session/prompt failed', error, stackTrace);
      if (stillRunning) {
        _events.add(
          AgentTurnCompletedEvent(
            sessionId: session.id,
            turnId: turnId,
            status: AgentHistoryTurnStatus.failed,
            errorMessage: error.toString(),
          ),
        );
      }
      _events.add(
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
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    // ACP 无 steer；降级为新的 prompt（可能打断当前回合语义，仅作尽力）。
    _log.fine('Grok ACP steerTurn falls back to session/prompt');
    await sendMessage(
      session: session,
      context: context,
      message: message,
      inputs: inputs,
      clientUserMessageId: clientUserMessageId,
    );
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    _log.info('Cancelling Grok ACP turn ${turn.id}');
    _peer.sendNotification(
      'session/cancel',
      params: <String, Object?>{'sessionId': turn.sessionId},
    );
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

    final optionId = decision.approved
        ? pending.preferAllowOptionId()
        : pending.preferRejectOptionId();
    if (optionId == null) {
      await _respondPermissionCancelled(pending);
      return;
    }

    await _peer.sendResponse(
      pending.requestId,
      result: <String, Object?>{
        'outcome': <String, Object?>{
          'outcome': 'selected',
          'optionId': optionId,
        },
      },
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _notificationSubscription?.cancel();
    await _serverRequestSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    await _peer.close();
    await _events.close();
  }

  void _listenToPeer() {
    _notificationSubscription ??= _peer.notifications.listen(
      _handleNotification,
    );
    _serverRequestSubscription ??= _peer.serverRequests.listen(
      _handleServerRequest,
    );
    _stderrSubscription ??= _peer.stderrLines.listen((line) {
      if (line.trim().isEmpty) {
        return;
      }
      _log.fine('Grok stderr (${line.length} chars)');
    });
    _protocolErrorSubscription ??= _peer.protocolErrors.listen((error) {
      _log.warning('Grok protocol warning: ${error.message}', error.cause);
      _events.add(
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

    // session/load 回放或带 isReplay 的更新：不进入直播时间线，避免与
    // readThreadHistory → applyHistorySnapshot 重复渲染。
    if (_shouldSuppressTimelineNotification(method: method, params: params)) {
      return;
    }

    if (method == 'session/update') {
      final sessionId = params['sessionId']?.toString();
      final turnId = sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId] ??
                _lastTurnIdsBySessionId[sessionId];
      final mapped = _notificationMapper.mapSessionUpdate(
        params: params,
        runningTurnId: turnId,
      );
      _noteTurnCompletedFromMapped(sessionId: sessionId, mapped: mapped);
      _emitMapped(mapped);
      return;
    }

    if (method == '_x.ai/session/update' || method == 'x.ai/session/update') {
      final sessionId = params['sessionId']?.toString();
      // turn_completed 常在 session/prompt 返回后才到；用 lastTurnId 兜底对齐。
      final turnId = sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId] ??
                _lastTurnIdsBySessionId[sessionId];
      final mapped = _notificationMapper.mapXaiSessionUpdate(
        params: params,
        runningTurnId: turnId,
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
      _events.add(event);
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
        _lastTurnIdsBySessionId[sessionId] = event.turnId;
        if (_runningTurnIdsBySessionId[sessionId] == event.turnId) {
          _runningTurnIdsBySessionId.remove(sessionId);
        }
        return;
      }
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
          await _peer.sendResponse(
            request.id,
            error: const JsonRpcError(
              code: -32601,
              message: 'fs/write_text_file is not supported by Zeta client',
            ),
          );
        default:
          _log.fine(
            'Rejecting unsupported Grok server request ${request.method}',
          );
          await _peer.sendResponse(
            request.id,
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
        await _peer.sendResponse(
          request.id,
          error: JsonRpcError(code: -32000, message: error.toString()),
        );
      } catch (_) {
        // 连接已断开时忽略二次失败。
      }
    }
  }

  Future<void> _handlePermissionRequest(JsonRpcRequest request) async {
    final params = request.params;
    final sessionId = params['sessionId']?.toString();
    final options = <_AcpPermissionOption>[];
    final rawOptions = params['options'];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        if (item is! Map) {
          continue;
        }
        final map = item.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final optionId = map['optionId']?.toString();
        if (optionId == null || optionId.isEmpty) {
          continue;
        }
        options.add(
          _AcpPermissionOption(
            optionId: optionId,
            name: map['name']?.toString() ?? optionId,
            kind: map['kind']?.toString() ?? '',
          ),
        );
      }
    }

    final requestKey = request.id.toString();
    final toolCall = params['toolCall'];
    String title = 'Approve tool execution';
    String? description;
    if (toolCall is Map) {
      title = toolCall['title']?.toString() ?? title;
      description = toolCall['kind']?.toString();
    }

    final pending = _PendingAcpPermission(
      requestId: request.id,
      requestKey: requestKey,
      options: options,
    );
    _pendingPermissions[requestKey] = pending;

    _log.info(
      'Grok permission requested: $title '
      '(options: ${options.map((o) => o.optionId).join(', ')})',
    );

    // 无选项时无法交互批准，立即 cancelled，避免 prompt 永久挂起。
    if (options.isEmpty) {
      _log.warning(
        'Grok permission $requestKey has no options; cancelling to unblock',
      );
      await _respondPermissionCancelled(pending);
      return;
    }

    _events.add(
      AgentPermissionRequestedEvent(
        AgentPermissionRequest(
          id: requestKey,
          title: title,
          kind: AgentPermissionKind.other,
          description: description,
          sessionId: sessionId,
          turnId: sessionId == null
              ? null
              : _runningTurnIdsBySessionId[sessionId],
          raw: params,
        ),
      ),
    );

    // 更新状态文案，避免 UI 看起来像「无响应卡住」。
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for approval: $title',
      ),
    );
  }

  Future<void> _handleReadTextFile(JsonRpcRequest request) async {
    final rawPath = request.params['path']?.toString();
    final path = _normalizeClientFsPath(rawPath);
    if (path == null || path.isEmpty) {
      await _peer.sendResponse(
        request.id,
        error: const JsonRpcError(code: -32602, message: 'path is required'),
      );
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        await _peer.sendResponse(
          request.id,
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
      await _peer.sendResponse(
        request.id,
        result: <String, Object?>{'content': text},
      );
    } catch (error) {
      await _peer.sendResponse(
        request.id,
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
    await _peer.sendResponse(
      pending.requestId,
      result: <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
    );
  }

  void _applyModelsFromSessionPayload(Map<String, Object?> map) {
    final list = parseAcpModelsPayload(map['models']);
    if (list == null || list.models.isEmpty) {
      return;
    }
    _modelList = list;
    _events.add(AgentModelListEvent(list));

    // 同步当前模型选择
    final modelsMap = _asStringKeyedMap(map['models']);
    final current = modelsMap?['currentModelId']?.toString();
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

  List<Map<String, Object?>> _buildPromptBlocks({
    String? message,
    List<AgentUserInput>? inputs,
    required AgentContext context,
  }) {
    final blocks = <Map<String, Object?>>[];
    final resolved = <AgentUserInput>[
      if (inputs != null && inputs.isNotEmpty)
        ...inputs
      else if ((message?.trim().isNotEmpty ?? false))
        AgentUserInput.text(message!.trim()),
    ];
    if (resolved.isEmpty) {
      throw ArgumentError('sendMessage requires message or inputs');
    }

    for (final input in resolved) {
      switch (input) {
        case AgentTextUserInput(:final text):
          blocks.add(<String, Object?>{'type': 'text', 'text': text});
        case AgentLocalImageUserInput(:final path):
          // 当前 Grok promptCapabilities.image=false；附带路径提示。
          blocks.add(<String, Object?>{
            'type': 'text',
            'text': '[local image: $path]',
          });
        case AgentMentionUserInput(:final name, :final path):
          blocks.add(<String, Object?>{
            'type': 'resource_link',
            'uri': path.startsWith('file:') ? path : 'file:///$path',
            'name': name,
          });
      }
    }

    // 附加当前文件上下文（embeddedContext 能力为 true）。
    final filePath = context.filePath?.trim();
    if (filePath != null && filePath.isNotEmpty) {
      blocks.add(<String, Object?>{
        'type': 'resource_link',
        'uri': filePath.startsWith('file:') ? filePath : 'file:///$filePath',
        'name': filePath.split(RegExp(r'[\\/]')).last,
      });
    }
    return blocks;
  }

  AgentHistoryTurnStatus _stopReasonToStatus(String stopReason) {
    final normalized = stopReason.toLowerCase();
    if (normalized.contains('cancel')) {
      return AgentHistoryTurnStatus.interrupted;
    }
    if (normalized.contains('refus') ||
        normalized.contains('error') ||
        normalized.contains('fail') ||
        normalized.contains('max_token') ||
        normalized.contains('max_turn')) {
      return AgentHistoryTurnStatus.failed;
    }
    return AgentHistoryTurnStatus.completed;
  }

  String _newTurnId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return 'grok-turn-$millis-$suffix';
  }

  void _emitStatus(AgentProviderStatus status) {
    _events.add(AgentStatusEvent(status));
  }

  void _emitUnavailable(String message, {String? details}) {
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.unavailable,
        message: message,
        details: details,
      ),
    );
    _events.add(AgentErrorEvent(message: message, details: details));
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
    required this.options,
  });

  final Object requestId;
  final String requestKey;
  final List<_AcpPermissionOption> options;

  String? preferAllowOptionId() {
    for (final option in options) {
      if (option.kind.contains('allow_once') || option.kind == 'allow_once') {
        return option.optionId;
      }
    }
    for (final option in options) {
      if (option.kind.contains('allow')) {
        return option.optionId;
      }
    }
    return options.isEmpty ? null : options.first.optionId;
  }

  String? preferRejectOptionId() {
    for (final option in options) {
      if (option.kind.contains('reject')) {
        return option.optionId;
      }
    }
    return options.isEmpty ? null : options.last.optionId;
  }
}

class _AcpPermissionOption {
  const _AcpPermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  final String optionId;
  final String name;
  final String kind;
}
