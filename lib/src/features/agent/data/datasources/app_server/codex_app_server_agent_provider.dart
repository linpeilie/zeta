import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
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
class CodexAppServerAgentProvider implements AgentProvider {
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

  /// 缓存的模型列表，initialize 握手后自动拉取。
  AgentModelList? _modelList;

  /// 是否已完成 initialize 握手。
  bool _initialized = false;

  /// 正在执行的初始化操作，用于去重并发初始化调用。
  Future<void>? _initializationOperation;

  /// 是否已调用 dispose，防止重复释放资源。
  bool _disposed = false;

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

    final session = await _client.startSession(
      context: context,
      previousSessionId: _session?.id,
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

    final session = await _client.resumeSession(
      sessionId,
      context: context,
      previousSessionId: _session?.id,
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
  }) async {
    await initialize();
    _log.fine('Reading Codex thread history $threadId');
    return _client.readThreadHistory(
      threadId: threadId,
      sessionPath: sessionPath,
    );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    await initialize();
    _log.info('Starting Codex turn for thread ${session.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Agent is working',
      ),
    );

    final turn = await _client.sendMessage(
      session: session,
      message: message,
      context: context,
      selection: _modelSelection,
    );
    _markRunningTurn(session.id, turn.id);
    _events.add(AgentTurnStartedEvent(turn));
    _log.fine('Started Codex turn ${turn.id}');
    return turn;
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    await initialize();
    _log.info('Steering Codex turn for thread ${session.id}');
    await _client.steerTurn(
      session: session,
      message: message,
      context: context,
    );
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
      if (_isIgnorableMcpTransportStderr(line)) {
        _log.fine(
          'Ignoring local MCP transport stderr (${line.length} characters)',
        );
        return;
      }

      _log.warning('Codex stderr line received (${line.length} characters)');
      _events.add(AgentErrorEvent(message: 'Codex stderr', details: line));
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
    if (_isErrorNotification(notification.method)) {
      _log.warning(
        'Codex ${notification.method}: '
        '${_string(notification.params['message']) ?? 'No message'}',
      );
    }

    final mapping = _notificationMapper.map(
      notification,
      runningTurnIdForSession: (threadId) =>
          _runningTurnIdsBySessionId[threadId],
    );

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

    for (final event in mapping.events) {
      _events.add(event);
    }
  }

  /// 将服务端审批请求委托给审批映射器，再由 provider 保存待处理状态。
  void _handleServerRequest(JsonRpcRequest request) {
    _log.fine('Received Codex server request ${request.method}');
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
}

/// 默认通过 stdio 启动 Codex app-server 子进程。
JsonRpcPeer _defaultPeerFactory(AgentProviderConfig config) {
  return JsonRpcStdioTransport(
    command: config.command,
    arguments: config.arguments,
    environment: config.environment,
  );
}
