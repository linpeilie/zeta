import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_permission_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.cursor_acp');

/// 为指定工作区创建 Cursor ACP peer。
typedef CursorJsonRpcPeerFactory =
    JsonRpcPeer Function(AgentProviderConfig config, String workspacePath);

/// Cursor 官方 `agent acp` provider。
///
/// 进程严格绑定单个工作区；切换工作区时会关闭旧 peer、取消挂起审批并重新握手。
class CursorAcpAgentProvider implements AgentProvider {
  CursorAcpAgentProvider({
    required this.config,
    JsonRpcPeer? peer,
    CursorJsonRpcPeerFactory? peerFactory,
    AcpSessionUpdateMapper? notificationMapper,
    String? initialWorkspace,
  }) : _injectedPeer = peer,
       _peerFactory = peerFactory ?? createDefaultPeer,
       _notificationMapper =
           notificationMapper ?? const AcpSessionUpdateMapper(),
       _workspacePath = _normalizeWorkspace(initialWorkspace);

  /// 创建生产环境 stdio peer；子进程 cwd 与 ACP session cwd 使用同一路径。
  static JsonRpcPeer createDefaultPeer(
    AgentProviderConfig config,
    String workspacePath,
  ) {
    return JsonRpcStdioTransport(
      command: config.command,
      arguments: config.arguments,
      environment: config.environment,
      workingDirectory: workspacePath,
      processStarter: cursorProcessStarter(config),
    );
  }

  @override
  final AgentProviderConfig config;

  final JsonRpcPeer? _injectedPeer;
  final CursorJsonRpcPeerFactory _peerFactory;
  final AcpSessionUpdateMapper _notificationMapper;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final Map<String, _PendingCursorPermission> _pendingPermissions =
      <String, _PendingCursorPermission>{};
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};
  final Set<String> _loggedUnknownNotifications = <String>{};
  final Random _random = Random();

  JsonRpcPeer? _peer;
  AgentSession? _session;
  String? _workspacePath;
  AgentProviderCapabilities _capabilities = AgentProviderCapabilities.cursorAcp;
  Future<void>? _initializationOperation;
  bool _initialized = false;
  bool _disposed = false;
  bool _closingPeer = false;
  bool _usedInjectedPeer = false;

  StreamSubscription<JsonRpcNotification>? _notificationSubscription;
  StreamSubscription<JsonRpcRequest>? _serverRequestSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<JsonRpcProtocolException>? _protocolErrorSubscription;

  @override
  AgentProviderCapabilities get capabilities => _capabilities;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('Cursor provider has been disposed');
    }
    if (_initialized) {
      return;
    }
    final workspace = _workspacePath;
    if (workspace == null || workspace.isEmpty) {
      throw StateError('Cursor ACP 启动前必须先选择项目工作区');
    }
    final inFlight = _initializationOperation;
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _initializeOnce(workspace);
    _initializationOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializationOperation, operation)) {
        _initializationOperation = null;
      }
    }
  }

  Future<void> _initializeOnce(String workspace) async {
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: 'Starting Cursor Agent',
      ),
    );
    try {
      final peer = _peer ??= _createPeer(workspace);
      await peer.start();
      _listenToPeer(peer);
      final result = await peer.sendRequest(
        'initialize',
        params: <String, Object?>{
          'protocolVersion': 1,
          'clientCapabilities': <String, Object?>{
            'fs': <String, Object?>{
              'readTextFile': false,
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
        timeout: _requestTimeout,
      );
      final init = _asMap(result) ?? const <String, Object?>{};
      _validateInitializeResponse(init);
      _applyNegotiatedCapabilities(init['agentCapabilities']);
      await _authenticate(init['authMethods']);
      _initialized = true;
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      _log.info('Cursor ACP initialized for workspace $workspace');
    } on ProcessException catch (error, stackTrace) {
      _log.warning('Could not start Cursor CLI', error, stackTrace);
      await _closeCurrentPeer();
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error, stackTrace) {
      _log.warning('Could not initialize Cursor ACP', error, stackTrace);
      await _closeCurrentPeer();
      _emitFailure('Cursor ACP 初始化失败', error);
      rethrow;
    }
  }

  void _validateInitializeResponse(Map<String, Object?> init) {
    final version = init['protocolVersion'];
    if (version != 1) {
      throw StateError('Cursor ACP 协议版本不兼容：$version（Zeta 需要 v1）');
    }
    final info = _asMap(init['agentInfo']);
    if (info == null || info.isEmpty) {
      return;
    }
    final identity = <Object?>[
      info['name'],
      info['title'],
    ].whereType<Object>().join(' ').toLowerCase();
    if (identity.isNotEmpty && !identity.contains('cursor')) {
      throw StateError('ACP 握手返回了非 Cursor Agent 身份：$identity');
    }
  }

  void _applyNegotiatedCapabilities(Object? value) {
    final agentCapabilities = _asMap(value) ?? const <String, Object?>{};
    final prompt = _asMap(agentCapabilities['promptCapabilities']);
    _capabilities = AgentProviderCapabilities.cursorAcp.copyWith(
      supportsLocalImageInput: prompt?['image'] == true,
      // Phase 2 只在 Agent 明确声明 embeddedContext 时开放 mention 入口。
      supportsResourceInput: prompt?['embeddedContext'] == true,
    );
  }

  Future<void> _authenticate(Object? value) async {
    if (value is! List || value.isEmpty) {
      // 已登录或通过环境变量认证时，Agent 可以返回空 authMethods。
      return;
    }
    String? cursorLogin;
    for (final item in value) {
      final method = _asMap(item);
      if (method?['id']?.toString() == 'cursor_login') {
        cursorLogin = 'cursor_login';
        break;
      }
    }
    if (cursorLogin == null) {
      throw StateError('Cursor Agent 未提供 cursor_login 认证方式，请先在终端登录 Cursor');
    }
    try {
      await _requirePeer().sendRequest(
        'authenticate',
        params: <String, Object?>{'methodId': cursorLogin},
        timeout: _requestTimeout,
      );
    } on JsonRpcException catch (error) {
      throw StateError('Cursor 登录态无效，请先运行 agent login：${error.error.message}');
    }
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    final workspace = _requiredWorkspace(context);
    await _prepareWorkspace(workspace);
    await initialize();
    try {
      final result = await _requirePeer().sendRequest(
        'session/new',
        params: <String, Object?>{
          'cwd': workspace,
          'mcpServers': const <Object?>[],
        },
        timeout: _requestTimeout,
      );
      final payload = _asMap(result) ?? const <String, Object?>{};
      final sessionId = payload['sessionId']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        throw StateError('Cursor ACP session/new 未返回 sessionId');
      }
      final session = AgentSession(
        id: sessionId,
        providerId: config.id,
        raw: payload,
      );
      _session = session;
      _events.add(AgentSessionStartedEvent(session));
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      return session;
    } catch (error, stackTrace) {
      _log.warning('Cursor session/new failed', error, stackTrace);
      _emitFailure('Cursor session 创建失败', error);
      rethrow;
    }
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    throw UnsupportedError('Cursor session 恢复将在 Phase 3 接入');
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    throw UnsupportedError('Cursor session 列表将在 Phase 3 接入');
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    // Cursor 模型来自 session config options；Phase 2 不创建探测 session 污染历史。
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    // Phase 4 通过 session config options 动态实现。
  }

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {
    // Cursor 只使用服务端 request_permission 提供的 option id。
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
    throw UnsupportedError('Cursor ACP 不支持 Codex Guardian 操作');
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    throw UnsupportedError('Cursor session 历史将在 Phase 3 接入');
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    // ACP 没有 Codex thread 通知订阅模型。
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    throw UnsupportedError('Cursor ACP 未声明 thread 重命名能力');
  }

  @override
  Future<void> archiveThread(String threadId) async {
    throw UnsupportedError('Cursor ACP 未声明归档能力');
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    throw UnsupportedError('Cursor ACP 未声明取消归档能力');
  }

  @override
  Future<void> deleteThread(String threadId) async {
    throw UnsupportedError('Cursor ACP 未声明 session 删除能力');
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
  }) async {
    throw UnsupportedError('Cursor ACP 未声明 session 分叉能力');
  }

  @override
  Future<AgentThreadHistorySnapshot> rollbackThread({
    required String threadId,
    required int numTurns,
  }) async {
    throw UnsupportedError('Cursor ACP 未声明回滚能力');
  }

  @override
  Future<void> compactThread(String threadId) async {
    throw UnsupportedError('Cursor ACP 未声明压缩能力');
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    final workspace = _requiredWorkspace(context);
    if (!_sameWorkspace(_workspacePath, workspace) ||
        _session?.id != session.id) {
      throw StateError('Cursor session 不属于当前工作区，请创建新的 Cursor thread');
    }
    await initialize();
    final prompt = await _buildPrompt(
      context: context,
      message: message,
      inputs: inputs,
    );
    final turnId = _newTurnId();
    _runningTurnIdsBySessionId[session.id] = turnId;
    final turn = AgentTurn(id: turnId, sessionId: session.id);
    _events.add(AgentTurnStartedEvent(turn));
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Cursor Agent is working',
      ),
    );
    try {
      final result = await _requirePeer().sendRequest(
        'session/prompt',
        params: <String, Object?>{'sessionId': session.id, 'prompt': prompt},
        timeout: const Duration(hours: 2),
      );
      if (_runningTurnIdsBySessionId[session.id] == turnId) {
        _runningTurnIdsBySessionId.remove(session.id);
        final payload = _asMap(result) ?? const <String, Object?>{};
        final reason =
            payload['stopReason']?.toString() ??
            payload['stop_reason']?.toString() ??
            'end_turn';
        final status = _statusForStopReason(reason);
        _events.add(
          AgentTurnCompletedEvent(
            sessionId: session.id,
            turnId: turnId,
            status: status,
            errorMessage: status == AgentHistoryTurnStatus.failed
                ? reason
                : null,
            raw: payload,
          ),
        );
      }
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      return turn;
    } catch (error, stackTrace) {
      _log.warning('Cursor session/prompt failed', error, stackTrace);
      if (_runningTurnIdsBySessionId.remove(session.id) == turnId) {
        _events.add(
          AgentTurnCompletedEvent(
            sessionId: session.id,
            turnId: turnId,
            status: AgentHistoryTurnStatus.failed,
            errorMessage: error.toString(),
          ),
        );
      }
      _emitFailure('Cursor prompt 失败', error);
      rethrow;
    }
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    throw UnsupportedError('Cursor ACP 未声明 steer 能力');
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    final peer = _requirePeer();
    peer.sendNotification(
      'session/cancel',
      params: <String, Object?>{'sessionId': turn.sessionId},
    );
    await _cancelPendingPermissions(peer);
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    final pending = _pendingPermissions.remove(decision.requestId);
    if (pending == null) {
      _log.warning('Ignoring unknown Cursor permission ${decision.requestId}');
      return;
    }
    if (decision.cancelTurn) {
      await _respondPermissionCancelled(_requirePeer(), pending);
      return;
    }
    final optionId = pending.mapping.preferredOptionId(
      approved: decision.approved,
    );
    if (optionId == null) {
      await _respondPermissionCancelled(_requirePeer(), pending);
      return;
    }
    await _requirePeer().sendResponse(
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
    await _closeCurrentPeer();
    await _events.close();
  }

  Future<void> _prepareWorkspace(String workspace) async {
    if (_sameWorkspace(_workspacePath, workspace)) {
      return;
    }
    await _closeCurrentPeer();
    _workspacePath = workspace;
    _session = null;
    _capabilities = AgentProviderCapabilities.cursorAcp;
  }

  JsonRpcPeer _createPeer(String workspace) {
    if (!_usedInjectedPeer && _injectedPeer != null) {
      _usedInjectedPeer = true;
      return _injectedPeer;
    }
    return _peerFactory(config, workspace);
  }

  void _listenToPeer(JsonRpcPeer peer) {
    _notificationSubscription = peer.notifications.listen(
      _handleNotification,
      onDone: _handlePeerClosed,
    );
    _serverRequestSubscription = peer.serverRequests.listen(
      _handleServerRequest,
    );
    _stderrSubscription = peer.stderrLines.listen((line) {
      if (line.trim().isNotEmpty) {
        // 不写入 stderr 原文，避免登录态或路径信息进入应用日志。
        _log.fine('Cursor stderr (${line.length} chars)');
      }
    });
    _protocolErrorSubscription = peer.protocolErrors.listen((error) {
      _log.warning(
        'Cursor ACP protocol warning: ${error.message}',
        error.cause,
      );
      _events.add(
        AgentErrorEvent(message: 'Cursor ACP 协议警告', details: error.toString()),
      );
    });
  }

  void _handleNotification(JsonRpcNotification notification) {
    if (notification.method != 'session/update') {
      if (_loggedUnknownNotifications.add(notification.method)) {
        _log.fine(
          'Ignoring unknown Cursor notification ${notification.method}',
        );
      }
      return;
    }
    final sessionId = notification.params['sessionId']?.toString();
    final mapped = _notificationMapper.mapSessionUpdate(
      params: notification.params,
      runningTurnId: sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId],
    );
    for (final event in mapped.events) {
      if (event is AgentTurnCompletedEvent && sessionId != null) {
        _runningTurnIdsBySessionId.remove(sessionId);
      }
      _events.add(event);
    }
    final unmatched = mapped.unmatchedKind;
    if (mapped.events.isEmpty &&
        unmatched != null &&
        _loggedUnknownNotifications.add('session/update:$unmatched')) {
      _log.fine('Ignoring unknown Cursor update $unmatched');
    }
  }

  Future<void> _handleServerRequest(JsonRpcRequest request) async {
    try {
      if (request.method == 'session/request_permission') {
        await _handlePermissionRequest(request);
        return;
      }
      await _requirePeer().sendResponse(
        request.id,
        error: JsonRpcError(
          code: -32601,
          message: 'Method not supported: ${request.method}',
        ),
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Cursor server request ${request.method} failed',
        error,
        stackTrace,
      );
      try {
        await _requirePeer().sendResponse(
          request.id,
          error: JsonRpcError(code: -32000, message: error.toString()),
        );
      } catch (_) {
        // 进程已经退出时无法再回写错误。
      }
    }
  }

  Future<void> _handlePermissionRequest(JsonRpcRequest request) async {
    final sessionId = request.params['sessionId']?.toString();
    final mapping = AcpPermissionMapper.mapRequest(
      requestId: request.id,
      params: request.params,
      runningTurnId: sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId],
    );
    final pending = _PendingCursorPermission(
      requestId: request.id,
      requestKey: mapping.request.id,
      mapping: mapping,
    );
    _pendingPermissions[pending.requestKey] = pending;
    if (mapping.options.isEmpty) {
      await _respondPermissionCancelled(_requirePeer(), pending);
      return;
    }
    _events.add(AgentPermissionRequestedEvent(mapping.request));
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for approval: ${mapping.request.title}',
      ),
    );
  }

  Future<List<Map<String, Object?>>> _buildPrompt({
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
  }) async {
    final resolved = <AgentUserInput>[
      if (inputs != null && inputs.isNotEmpty)
        ...inputs
      else if (message?.trim().isNotEmpty ?? false)
        AgentUserInput.text(message!.trim()),
    ];
    if (resolved.isEmpty) {
      throw ArgumentError('prompt requires message or inputs');
    }
    final blocks = <Map<String, Object?>>[];
    for (final input in resolved) {
      switch (input) {
        case AgentTextUserInput(:final text):
          blocks.add(<String, Object?>{'type': 'text', 'text': text});
        case AgentLocalImageUserInput(:final path):
          if (!capabilities.supportsLocalImageInput) {
            throw UnsupportedError('当前 Cursor ACP 未声明图片输入能力');
          }
          final file = File(path);
          final bytes = await file.readAsBytes();
          blocks.add(<String, Object?>{
            'type': 'image',
            'mimeType': _imageMimeType(path),
            'data': base64Encode(bytes),
          });
        case AgentMentionUserInput(:final name, :final path):
          if (!capabilities.supportsResourceInput) {
            throw UnsupportedError('当前 Cursor ACP 未声明 mention/resource 能力');
          }
          blocks.add(_resourceLink(name: name, path: path));
      }
    }
    final contextFile = context.filePath?.trim();
    if (contextFile != null &&
        contextFile.isNotEmpty &&
        capabilities.supportsResourceInput) {
      blocks.add(
        _resourceLink(
          name: contextFile.split(RegExp(r'[\\/]')).last,
          path: contextFile,
        ),
      );
    }
    return blocks;
  }

  Future<void> _cancelPendingPermissions(JsonRpcPeer peer) async {
    for (final pending in _pendingPermissions.values.toList()) {
      try {
        await _respondPermissionCancelled(peer, pending);
      } catch (_) {
        _pendingPermissions.remove(pending.requestKey);
      }
    }
  }

  Future<void> _respondPermissionCancelled(
    JsonRpcPeer peer,
    _PendingCursorPermission pending,
  ) async {
    _pendingPermissions.remove(pending.requestKey);
    await peer.sendResponse(
      pending.requestId,
      result: <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
    );
  }

  Future<void> _closeCurrentPeer() async {
    final peer = _peer;
    _peer = null;
    _initialized = false;
    _initializationOperation = null;
    _runningTurnIdsBySessionId.clear();
    if (peer == null) {
      return;
    }
    _closingPeer = true;
    try {
      await _cancelPendingPermissions(peer);
      await _notificationSubscription?.cancel();
      await _serverRequestSubscription?.cancel();
      await _stderrSubscription?.cancel();
      await _protocolErrorSubscription?.cancel();
      _notificationSubscription = null;
      _serverRequestSubscription = null;
      _stderrSubscription = null;
      _protocolErrorSubscription = null;
      await peer.close();
    } finally {
      _closingPeer = false;
    }
  }

  void _handlePeerClosed() {
    if (_disposed || _closingPeer) {
      return;
    }
    _initialized = false;
    _peer = null;
    _session = null;
    _pendingPermissions.clear();
    _runningTurnIdsBySessionId.clear();
    _emitUnavailable('Cursor Agent 进程已意外退出');
  }

  JsonRpcPeer _requirePeer() {
    final peer = _peer;
    if (peer == null) {
      throw StateError('Cursor ACP peer 尚未启动');
    }
    return peer;
  }

  String _requiredWorkspace(AgentContext context) {
    final workspace = _normalizeWorkspace(context.projectPath);
    if (workspace == null || workspace.isEmpty) {
      throw StateError('Cursor ACP session 需要项目工作区');
    }
    return workspace;
  }

  Duration get _requestTimeout {
    final value = config.extra['timeoutSeconds'];
    if (value is int && value >= 5 && value <= 600) {
      return Duration(seconds: value);
    }
    return const Duration(seconds: 60);
  }

  String _newTurnId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return 'cursor-turn-$millis-$suffix';
  }

  AgentHistoryTurnStatus _statusForStopReason(String reason) {
    final normalized = reason.toLowerCase();
    if (normalized.contains('cancel')) {
      return AgentHistoryTurnStatus.interrupted;
    }
    if (normalized.contains('error') ||
        normalized.contains('fail') ||
        normalized.contains('refus')) {
      return AgentHistoryTurnStatus.failed;
    }
    return AgentHistoryTurnStatus.completed;
  }

  void _emitStatus(AgentProviderStatus status) {
    if (!_events.isClosed) {
      _events.add(AgentStatusEvent(status));
    }
  }

  void _emitUnavailable(String message, {String? details}) {
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.unavailable,
        message: message,
        details: details,
      ),
    );
    if (!_events.isClosed) {
      _events.add(AgentErrorEvent(message: message, details: details));
    }
  }

  void _emitFailure(String message, Object error) {
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.error,
        message: message,
        details: error.toString(),
      ),
    );
    if (!_events.isClosed) {
      _events.add(AgentErrorEvent(message: message, details: error.toString()));
    }
  }
}

class _PendingCursorPermission {
  const _PendingCursorPermission({
    required this.requestId,
    required this.requestKey,
    required this.mapping,
  });

  final Object requestId;
  final String requestKey;
  final AcpPermissionMapping mapping;
}

String? _normalizeWorkspace(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  var normalized = Directory(trimmed).absolute.path;
  while (normalized.length > 1 &&
      (normalized.endsWith('/') || normalized.endsWith('\\'))) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _sameWorkspace(String? left, String? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return Platform.isWindows
      ? left.toLowerCase() == right.toLowerCase()
      : left == right;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

Map<String, Object?> _resourceLink({
  required String name,
  required String path,
}) {
  final uri = path.startsWith('file:') ? path : Uri.file(path).toString();
  return <String, Object?>{'type': 'resource_link', 'uri': uri, 'name': name};
}

String _imageMimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
