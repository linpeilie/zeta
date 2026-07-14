import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

part 'codex_app_server_client.dart';
part '../../mappers/codex_app_server_helpers.dart';
part '../../mappers/codex_approval_mapper.dart';
part '../../mappers/codex_model_list_mapper.dart';
part '../../mappers/codex_notification_mapper.dart';
part '../local_history/codex_jsonl_history_parser.dart';
part '../local_history/codex_thread_history_reader.dart';

final _log = loggerFor('zeta.agent.codex_app_server');

/// 根据 provider 配置创建 JSON-RPC 端点。
typedef JsonRpcPeerFactory = JsonRpcPeer Function(AgentProviderConfig config);

/// Codex app-server 的 Agent provider 实现。
///
/// 该类现在只负责生命周期、状态协同与事件分发，具体的 JSON-RPC 请求、
/// 通知映射、审批映射与历史解析已经拆分到独立模块。
class CodexAppServerAgentProvider
    implements AgentProvider, AgentUsageQuotaProvider {
  /// 创建 Codex app-server provider 实例。
  ///
  /// [config] 包含命令、参数、环境变量等 provider 配置。
  /// [peer] 允许外部注入已创建的 JSON-RPC 对等体，用于测试。
  /// [peerFactory] 用于在未提供 [peer] 时按 [config] 创建默认对等体。
  CodexAppServerAgentProvider({
    required this.config,
    JsonRpcPeer? peer,
    JsonRpcPeerFactory? peerFactory,
  }) : _modelSelection = AgentModelSelection(
         modelId: config.selectedModel,
         reasoningEffort: config.selectedReasoningEffort,
         serviceTierId: config.selectedServiceTier,
       ),
       _permissionSelection = AgentPermissionSelection(
         approvalPolicy:
             config.selectedApprovalPolicy ??
             AgentPermissionSelection.defaultApprovalPolicy,
         sandboxPolicy:
             config.selectedSandboxPolicy ??
             AgentPermissionSelection.defaultSandboxPolicy,
         permissionProfileId: config.selectedPermissionProfileId,
       ),
       _peer = peer ?? (peerFactory ?? _defaultPeerFactory)(config) {
    final threadHistoryReader = _CodexThreadHistoryReader();
    final modelListMapper = _CodexModelListMapper();
    _client = _CodexAppServerClient(
      peer: _peer,
      config: config,
      modelListMapper: modelListMapper,
      threadHistoryReader: threadHistoryReader,
    );
    _notificationMapper = _CodexNotificationMapper(providerId: config.id);
    _approvalMapper = _CodexApprovalMapper();
  }

  /// JSON-RPC 通信对等体，负责与 Codex app-server 进程交换消息。
  final JsonRpcPeer _peer;

  late final _CodexAppServerClient _client;
  late final _CodexNotificationMapper _notificationMapper;
  late final _CodexApprovalMapper _approvalMapper;

  /// 广播事件流控制器，所有 Agent 事件通过此流发出。
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  /// 等待用户审批的服务端 JSON-RPC 请求。
  final Map<String, _PendingApproval> _pendingApprovals =
      <String, _PendingApproval>{};

  /// 当前活跃的 Agent 会话，由 thread/start 或 thread/resume 设置。
  AgentSession? _session;

  /// 各 thread 当前运行中的 turn id。
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};

  /// 用户在输入框选择的模型组合。
  AgentModelSelection _modelSelection;

  /// 用户选择的审批/沙箱策略。
  AgentPermissionSelection _permissionSelection;

  /// 缓存的模型列表，initialize 握手后自动拉取。
  AgentModelList? _modelList;

  /// 是否已完成 initialize 握手。
  bool _initialized = false;

  /// 正在执行的初始化操作，用于去重并发初始化调用。
  Future<void>? _initializationOperation;

  /// 是否已调用 dispose，防止重复释放资源。
  bool _disposed = false;

  /// 已记过 fine 日志的未匹配通知 method（按 method 去重，避免刷屏）。
  final Set<String> _loggedUnmatchedNotificationMethods = <String>{};

  /// 未匹配通知按 method 的累计次数（开发期诊断用，每次到达都递增）。
  final Map<String, int> _unmatchedNotificationCounts = <String, int>{};

  StreamSubscription<JsonRpcNotification>? _notificationSubscription;
  StreamSubscription<JsonRpcRequest>? _serverRequestSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<JsonRpcProtocolException>? _protocolErrorSubscription;

  @override
  final AgentProviderConfig config;

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

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderCapabilities.codexAppServer;

  /// 开发诊断：未匹配服务端通知按 method 的累计次数。
  ///
  /// 首次见到某 method 会记一条 fine 日志；后续同名通知只递增计数。
  @visibleForTesting
  Map<String, int> get unmatchedNotificationCountsForTesting =>
      Map<String, int>.unmodifiable(_unmatchedNotificationCounts);

  @override
  Future<void> initialize() async {
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
    _log.info('Initializing Agent provider ${config.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: 'Starting Codex CLI',
      ),
    );

    try {
      await _peer.start();
      _listenToPeer();

      await _peer.sendRequest(
        'initialize',
        params: <String, Object?>{
          'clientInfo': <String, Object?>{
            'name': 'zeta',
            'title': 'Zeta IDE',
            'version': '0.1.0',
          },
          // 显式声明协商能力，避免依赖服务端默认值的隐式行为。
          'capabilities': <String, Object?>{
            // 不接收实验性 API 方法与字段；动态工具等能力落地时再开启。
            'experimentalApi': false,
            // 不参与 attestation/generate 流程（A5 已对误发请求兜底拒绝）。
            'requestAttestation': false,
            // 表单式 elicitation 尚无渲染能力（见计划 3.8），暂不允许。
            'mcpServerOpenaiFormElicitation': false,
            'optOutNotificationMethods': _optedOutNotificationMethods,
          },
        },
      );

      _peer.sendNotification('initialized');
      _initialized = true;
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      _log.info('Agent provider ${config.id} initialized');

      await _fetchModelList();
    } on ProcessException catch (error, stackTrace) {
      _log.warning(
        'Could not start Agent provider process ${config.id}',
        error,
        stackTrace,
      );
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error, stackTrace) {
      _log.warning(
        'Could not initialize Agent provider ${config.id}',
        error,
        stackTrace,
      );
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

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    await initialize();
    _log.fine('Starting Codex thread for provider ${config.id}');

    final previousSessionId = _session?.id;
    final session = await _client.startSession(
      context: context,
      permissionSelection: _permissionSelection,
      previousSessionId: previousSessionId,
    );
    // 新建会话后取消旧 thread 订阅，避免后台通知继续到达。
    await _unsubscribePreviousThreadIfNeeded(
      previousSessionId: previousSessionId,
      nextSessionId: session.id,
    );
    _session = session;
    _events.add(AgentSessionStartedEvent(session));
    _log.info('Started Codex thread ${session.id}');
    return session;
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    await initialize();
    _log.fine('Resuming Codex thread $sessionId');

    final previousSessionId = _session?.id;
    final session = await _client.resumeSession(
      sessionId,
      context: context,
      permissionSelection: _permissionSelection,
      previousSessionId: previousSessionId,
    );
    // resume 成功后再退订旧 thread，保证新会话已接管订阅。
    await _unsubscribePreviousThreadIfNeeded(
      previousSessionId: previousSessionId,
      nextSessionId: session.id,
    );
    _session = session;
    _events.add(AgentSessionStartedEvent(session));
    _log.info('Resumed Codex thread ${session.id}');
    return session;
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    await initialize();
    _log.fine(
      'Listing Codex threads for ${query.projectPath} '
      'limit=${query.limit} cursor=${query.cursor}',
    );
    return _client.listThreads(query: query);
  }

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    await initialize();
    return _client.readUsageQuota();
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    final cached = _modelList;
    if (cached != null) {
      return cached;
    }
    await initialize();
    return _modelList ?? const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    _modelSelection = selection;
    _log.fine(
      'Updated model selection: model=${selection.modelId} '
      'effort=${selection.reasoningEffort} tier=${selection.serviceTierId}',
    );
  }

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {
    _permissionSelection = selection;
    _log.fine(
      'Updated permission selection: approval=${selection.approvalPolicy} '
      'sandbox=${selection.sandboxPolicy}',
    );
  }

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    await initialize();
    return _client.listPermissionProfiles();
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {
    await initialize();
    _log.info('Approving guardian-denied action for thread $threadId');
    await _client.approveGuardianDeniedAction(threadId: threadId, event: event);
  }

  /// 向 Codex app-server 发送 `model/list` 请求并缓存结果。
  Future<void> _fetchModelList() async {
    try {
      final list = await _client.fetchModelList();
      _modelList = list;
      _events.add(AgentModelListEvent(list));
      _log.fine('Fetched ${list.models.length} models from Codex');
    } catch (error, stackTrace) {
      _log.warning('Could not fetch Codex model list', error, stackTrace);
    }
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    await initialize();
    _log.fine('Reading Codex thread history $threadId');
    return _client.readThreadHistory(
      threadId: threadId,
      sessionPath: sessionPath,
    );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    if (threadId.isEmpty) {
      return;
    }
    await initialize();
    await _unsubscribeThreadBestEffort(threadId);
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    await initialize();
    await _client.renameThread(threadId: threadId, name: name);
  }

  @override
  Future<void> archiveThread(String threadId) async {
    await initialize();
    await _client.archiveThread(threadId);
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    await initialize();
    await _client.unarchiveThread(threadId);
  }

  @override
  Future<void> deleteThread(String threadId) async {
    await initialize();
    await _client.deleteThread(threadId);
    if (_session?.id == threadId) {
      await _unsubscribeThreadBestEffort(threadId);
      _session = null;
    }
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
  }) async {
    await initialize();
    final previousSessionId = _session?.id;
    final session = await _client.forkThread(
      threadId: threadId,
      context: context,
      permissionSelection: _permissionSelection,
      previousSessionId: previousSessionId,
    );
    await _unsubscribePreviousThreadIfNeeded(
      previousSessionId: previousSessionId,
      nextSessionId: session.id,
    );
    _session = session;
    _events.add(AgentSessionStartedEvent(session));
    _log.info('Forked Codex thread $threadId -> ${session.id}');
    return session;
  }

  @override
  Future<AgentThreadHistorySnapshot> rollbackThread({
    required String threadId,
    required int numTurns,
  }) async {
    await initialize();
    _log.info('Rolling back Codex thread $threadId by $numTurns turn(s)');
    return _client.rollbackThread(threadId: threadId, numTurns: numTurns);
  }

  @override
  Future<void> compactThread(String threadId) async {
    await initialize();
    _log.info('Starting compact for Codex thread $threadId');
    await _client.compactThread(threadId);
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
    final resolvedInputs = _resolveUserInputs(message: message, inputs: inputs);
    _log.info('Starting Codex turn for thread ${session.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Agent is working',
      ),
    );

    final turn = await _client.sendMessage(
      session: session,
      inputs: resolvedInputs,
      context: context,
      selection: _modelSelection,
      permissionSelection: _permissionSelection,
      clientUserMessageId: clientUserMessageId,
    );
    _markRunningTurn(session.id, turn.id);
    _events.add(AgentTurnStartedEvent(turn));
    _log.fine('Started Codex turn ${turn.id}');
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
    await initialize();
    final resolvedInputs = _resolveUserInputs(message: message, inputs: inputs);
    _log.info('Steering Codex turn for thread ${session.id}');
    await _client.steerTurn(
      session: session,
      inputs: resolvedInputs,
      context: context,
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
    _log.info('Interrupting Codex turn ${turn.id}');
    await _client.cancelTurn(turn);
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    final pending = _pendingApprovals.remove(decision.requestId);
    if (pending == null) {
      _log.warning(
        'Ignoring response for unknown Codex permission ${decision.requestId}',
      );
      return;
    }

    _log.info(
      'Responding to Codex permission ${pending.method}: '
      'approved=${decision.approved}',
    );
    await _peer.sendResponse(
      pending.requestId,
      result: _approvalMapper.approvalResponse(pending, decision),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _log.fine('Disposing Agent provider ${config.id}');
    _disposed = true;

    await _notificationSubscription?.cancel();
    await _serverRequestSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    await _peer.close();
    await _events.close();
  }

  /// 订阅 JSON-RPC 对等体的各事件流。
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
      // stderr 是 app-server 的 tracing/诊断通道，其中也包含回合内工具失败的
      // 日志。用户可见错误必须以 JSON-RPC `error`、`turn/completed` 或 item
      // 事件为准，不能把每一行 stderr 拆成对话消息。
      _log.fine('Codex stderr line received (${line.length} characters)');
    });
    _protocolErrorSubscription ??= _peer.protocolErrors.listen((error) {
      _log.warning('Codex protocol warning: ${error.message}', error.cause);
      _events.add(
        AgentErrorEvent(
          message: 'Codex protocol warning',
          details: error.toString(),
        ),
      );
    });
  }

  /// 将服务端通知委托给通知映射器，再由 provider 协调状态变更。
  void _handleNotification(JsonRpcNotification notification) {
    if (_shouldIgnoreNotification(notification.method)) {
      return;
    }
    if (_isErrorNotification(notification.method)) {
      // `error` 通知的消息在嵌套的 TurnError 里，`configWarning` 用 summary。
      final message =
          _string(notification.params['message']) ??
          _string(_map(notification.params['error'])['message']) ??
          _string(notification.params['summary']) ??
          'No message';
      _log.warning('Codex ${notification.method}: $message');
    } else if (notification.method == 'deprecationNotice') {
      // 弃用提示需可观测，便于升级适配层；UI 侧再做一次性展示。
      final summary = _string(notification.params['summary']) ?? 'No summary';
      final details = _string(notification.params['details']);
      _log.warning(
        'Codex deprecationNotice: $summary'
        '${details == null ? '' : ' ($details)'}',
      );
    } else if (notification.method == 'model/rerouted') {
      final fromModel = _string(notification.params['fromModel']);
      final toModel = _string(notification.params['toModel']);
      final reason = _string(notification.params['reason']);
      _log.info(
        'Codex model/rerouted: $fromModel → $toModel'
        '${reason == null ? '' : ' ($reason)'}',
      );
    }

    final mapping = _notificationMapper.map(
      notification,
      runningTurnIdForSession: (threadId) =>
          _runningTurnIdsBySessionId[threadId],
    );

    // 协议演进时未适配的通知：按 method 去重记 fine，并累计诊断计数。
    final unmatchedMethod = mapping.unmatchedMethod;
    if (unmatchedMethod != null) {
      _recordUnmatchedNotification(unmatchedMethod);
      return;
    }

    final session = mapping.session;
    if (session != null) {
      _session = session;
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
            message: '${config.displayName} ready',
          ),
        );
      }
    }

    // 他端已解决审批：只清本地 pending，不再向服务端回写响应。
    for (final event in mapping.events) {
      if (event is AgentPermissionResolvedEvent) {
        final pending = _pendingApprovals.remove(event.requestId);
        if (pending != null) {
          _log.info(
            'Codex server request ${event.requestId} resolved externally '
            '(${pending.method}); dismissing local approval',
          );
        } else {
          _log.fine(
            'Codex server request ${event.requestId} resolved externally '
            'with no local pending approval',
          );
        }
      } else if (event is AgentThreadDeletedEvent ||
          event is AgentThreadClosedEvent) {
        // 线程关闭/删除：清本地会话与运行态，避免继续向已失效 thread 发请求。
        final threadId = event is AgentThreadDeletedEvent
            ? event.threadId
            : (event as AgentThreadClosedEvent).threadId;
        _runningTurnIdsBySessionId.remove(threadId);
        if (_session?.id == threadId) {
          _session = null;
        }
        unawaited(_unsubscribeThreadBestEffort(threadId));
      }
      _events.add(event);
    }
  }

  /// 记录未匹配通知：首次 method 打 fine 日志，之后只递增计数。
  void _recordUnmatchedNotification(String method) {
    _unmatchedNotificationCounts[method] =
        (_unmatchedNotificationCounts[method] ?? 0) + 1;
    if (_loggedUnmatchedNotificationMethods.add(method)) {
      _log.fine(
        'Ignoring unmatched Codex notification: $method '
        '(further occurrences counted silently)',
      );
    }
  }

  /// 将服务端审批请求委托给审批映射器，再由 provider 保存待处理状态。
  void _handleServerRequest(JsonRpcRequest request) {
    // 未知或不支持的请求立即回 JSON-RPC error，不进 UI；伪造 `{}`/null
    // 成功应答会违反响应 schema，可能让服务端 turn 永久卡住。
    final rejection = _approvalMapper.rejectionFor(request);
    if (rejection != null) {
      _log.warning(
        'Declining unsupported Codex server request ${request.method}: '
        '${rejection.message}',
      );
      unawaited(
        _peer.sendResponse(request.id, error: rejection).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          _log.warning(
            'Failed to reject Codex server request ${request.method}',
            error,
            stackTrace,
          );
        }),
      );
      return;
    }

    final mapped = _approvalMapper.mapRequest(request);
    _pendingApprovals[mapped.pendingApproval.id] = mapped.pendingApproval;
    _events.add(mapped.event);
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

  /// 切换到不同 thread 时取消旧订阅；同 id 或空 id 跳过。
  Future<void> _unsubscribePreviousThreadIfNeeded({
    required String? previousSessionId,
    required String nextSessionId,
  }) async {
    if (previousSessionId == null || previousSessionId == nextSessionId) {
      return;
    }
    await _unsubscribeThreadBestEffort(previousSessionId);
  }

  /// best-effort 退订：失败只记日志，不阻断会话切换。
  Future<void> _unsubscribeThreadBestEffort(String threadId) async {
    try {
      final status = await _client.unsubscribeThread(threadId);
      _log.fine(
        'Unsubscribed Codex thread $threadId'
        '${status == null ? '' : ' (status=$status)'}',
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Could not unsubscribe Codex thread $threadId',
        error,
        stackTrace,
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
