import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/acp_session_replay_collector.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_diagnostics_store.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_session_index_store.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_runtime_json_rpc_peer.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_permission_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_config_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/cursor_acp_extension_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.cursor_acp');

/// 为指定工作区创建 Cursor ACP peer。
typedef CursorJsonRpcPeerFactory =
    JsonRpcPeer Function(AgentProviderConfig config, String workspacePath);

/// Cursor 官方 `agent acp` provider。
///
/// 进程严格绑定单个工作区；切换工作区时会关闭旧 peer、取消挂起审批并重新握手。
class CursorAcpAgentProvider
    implements
        AgentProvider,
        AgentLocalThreadListProvider,
        AgentSessionConfigProvider,
        AgentPlanApprovalProvider,
        AgentRuntimeLifecycleProvider {
  CursorAcpAgentProvider({
    required this.config,
    JsonRpcPeer? peer,
    CursorJsonRpcPeerFactory? peerFactory,
    AcpSessionUpdateMapper? notificationMapper,
    AcpSessionConfigMapper? sessionConfigMapper,
    CursorAcpExtensionMapper? extensionMapper,
    CursorSessionIndexStore? sessionIndexStore,
    CursorDiagnosticsStore? diagnosticsStore,
    DateTime Function()? clock,
    String? initialWorkspace,
    this.blockingRequestTimeout = const Duration(minutes: 5),
  }) : _injectedPeer = peer,
       _peerFactory = peerFactory ?? createDefaultPeer,
       _notificationMapper =
           notificationMapper ?? const AcpSessionUpdateMapper(),
       _sessionConfigMapper =
           sessionConfigMapper ?? const AcpSessionConfigMapper(),
       _extensionMapper = extensionMapper ?? CursorAcpExtensionMapper(),
       _sessionIndexStore =
           sessionIndexStore ?? MemoryCursorSessionIndexStore(),
       _diagnostics = diagnosticsStore ?? CursorDiagnosticsStore.shared,
       _clock = clock ?? DateTime.now,
       _workspacePath = normalizeCursorWorkspacePath(initialWorkspace);

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
  final AcpSessionConfigMapper _sessionConfigMapper;
  final CursorAcpExtensionMapper _extensionMapper;
  final CursorSessionIndexStore _sessionIndexStore;
  final CursorDiagnosticsStore _diagnostics;
  final DateTime Function() _clock;
  final Duration blockingRequestTimeout;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final Map<String, _PendingCursorPermission> _pendingPermissions =
      <String, _PendingCursorPermission>{};
  final Map<String, _PendingCursorQuestion> _pendingQuestions =
      <String, _PendingCursorQuestion>{};
  final Map<String, _PendingCursorPlan> _pendingPlans =
      <String, _PendingCursorPlan>{};
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};
  final Set<String> _loggedUnknownNotifications = <String>{};
  final Map<String, AcpSessionReplayCollector> _replayCollectors =
      <String, AcpSessionReplayCollector>{};
  final Map<String, Future<_LoadedCursorSession>> _sessionLoadOperations =
      <String, Future<_LoadedCursorSession>>{};
  final Map<String, _LoadedCursorSession> _loadedSessions =
      <String, _LoadedCursorSession>{};
  final Map<String, String?> _sessionTitles = <String, String?>{};
  final Map<String, List<AgentSessionConfigOption>> _sessionConfigOptions =
      <String, List<AgentSessionConfigOption>>{};
  final Set<String> _legacyModeSessions = <String>{};
  final Random _random = Random();

  ProviderRuntimeJsonRpcPeer? _peer;
  AgentSession? _session;
  String? _workspacePath;
  AgentProviderCapabilities _capabilities = AgentProviderCapabilities.cursorAcp;
  Future<void>? _initializationOperation;
  Future<void>? _disposeOperation;
  bool _initialized = false;
  bool _disposed = false;
  bool _closingPeer = false;
  bool _usedInjectedPeer = false;
  bool _supportsRemoteSessionList = false;
  int _peerGeneration = 0;
  AgentProviderLifecycleState _detachedLifecycleState =
      AgentProviderLifecycleState.stopped;

  StreamSubscription<JsonRpcNotification>? _notificationSubscription;
  StreamSubscription<JsonRpcRequest>? _serverRequestSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<JsonRpcProtocolException>? _protocolErrorSubscription;

  @override
  AgentProviderCapabilities get capabilities => _capabilities;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentProviderLifecycleState get lifecycleState =>
      _peer?.lifecycleState ?? _detachedLifecycleState;

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
    _diagnostics.record(
      source: CursorDiagnosticsStore.runtimeSource,
      message: 'startup; stage=cli; workspace=selected',
    );
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
            'session': <String, Object?>{
              'configOptions': <String, Object?>{
                'boolean': <String, Object?>{},
              },
            },
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
      _diagnostics.recordHandshake(
        protocolVersion: init['protocolVersion'],
        agentInfo: init['agentInfo'],
        capabilities: init['agentCapabilities'],
        cliVersion: config.extra['detectedCurrentVersion']?.toString(),
      );
      final previousFingerprint = config.extra['cursorCapabilityFingerprint']
          ?.toString();
      final currentFingerprint =
          _diagnostics.snapshot.handshake?.capabilityFingerprint;
      if (previousFingerprint != null &&
          currentFingerprint != null &&
          previousFingerprint != currentFingerprint) {
        _diagnostics.record(
          source: CursorDiagnosticsStore.runtimeSource,
          message:
              'compatibility warning; negotiated capabilities changed; '
              'run Cursor detection again',
          level: CursorDiagnosticLevel.warning,
        );
      }
      await _authenticate(init['authMethods']);
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'authentication ready; stage=auth',
      );
      peer.markReady();
      _initialized = true;
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      _log.info('Cursor ACP initialized for workspace $workspace');
    } on ProcessException catch (error, stackTrace) {
      _peer?.markFailed();
      _log.warning('Could not start Cursor CLI', error, stackTrace);
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'startup failed; stage=cli; error=$error',
        level: CursorDiagnosticLevel.error,
      );
      await _closeCurrentPeer();
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error, stackTrace) {
      _peer?.markFailed();
      _log.warning('Could not initialize Cursor ACP', error, stackTrace);
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'initialize failed; stage=handshake/auth; error=$error',
        level: CursorDiagnosticLevel.error,
      );
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
    final sessionCapabilities = _asMap(
      agentCapabilities['sessionCapabilities'],
    );
    final canLoadSession = agentCapabilities['loadSession'] == true;
    _supportsRemoteSessionList =
        sessionCapabilities?.containsKey('list') == true;
    _capabilities = AgentProviderCapabilities.cursorAcp.copyWith(
      canResumeSession: canLoadSession,
      canReadHistory: canLoadSession,
      canDeleteThread: sessionCapabilities?.containsKey('delete') == true,
      supportsLocalImageInput: prompt?['image'] == true,
      // 只在 Agent 明确声明 embeddedContext 时开放 mention 入口。
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
      final title = _optionalString(payload['title']);
      final session = AgentSession(
        id: sessionId,
        providerId: config.id,
        title: title,
        raw: payload,
      );
      _session = session;
      if (payload.containsKey('title')) {
        _sessionTitles[sessionId] = title;
      }
      await _rememberSessionBestEffort(
        sessionId: sessionId,
        workspacePath: workspace,
        title: title,
        updateTitle: payload.containsKey('title'),
        status: AgentThreadRuntimeStatus.idle,
        metadata: _asMap(payload['_meta']),
        createdAt: _clock(),
      );
      _events.add(AgentSessionStartedEvent(session));
      _applySessionSetup(sessionId: sessionId, payload: payload);
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      return session;
    } catch (error, stackTrace) {
      _log.warning('Cursor session/new failed', error, stackTrace);
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'session/new failed; stage=session; error=$error',
        level: CursorDiagnosticLevel.error,
      );
      _emitFailure('Cursor session 创建失败', error);
      rethrow;
    }
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    final workspace = _requiredWorkspace(context);
    final indexed = await _sessionIndexStore.load();
    final indexedSession = indexed.find(sessionId);
    if (indexedSession != null &&
        !cursorWorkspacePathsEqual(indexedSession.workspacePath, workspace)) {
      throw StateError('Cursor session 不属于当前工作区，已拒绝跨项目恢复');
    }
    final loaded = await _ensureSessionLoaded(
      sessionId: sessionId,
      workspace: workspace,
    );
    _session = loaded.session;
    _events.add(AgentSessionStartedEvent(loaded.session));
    return loaded.session;
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    if (query.archived) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }
    final workspace = normalizeCursorWorkspacePath(query.projectPath);
    if (workspace == null) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }

    final localIndex = await _sessionIndexStore.load();
    final merged = <String, AgentThreadSummary>{
      for (final entry in localIndex.sessions)
        if (cursorWorkspacePathsEqual(entry.workspacePath, workspace))
          entry.sessionId: entry.toThreadSummary(),
    };
    final localCount = merged.length;
    var remoteCount = 0;
    var remoteSucceeded = false;

    // 远端列表是可选增强；定位、认证或 session/list 失败都不能遮蔽本地索引。
    try {
      await _prepareWorkspace(workspace);
      await initialize();
      if (_supportsRemoteSessionList) {
        final remote = await _listRemoteSessions(workspace);
        remoteCount = remote.length;
        remoteSucceeded = true;
        await _rememberRemoteSessionsBestEffort(
          workspacePath: workspace,
          sessions: remote,
        );
        for (final summary in remote) {
          final local = merged[summary.id];
          merged[summary.id] = local == null
              ? summary
              : summary.copyWith(createdAt: local.createdAt);
        }
      }
    } catch (error, stackTrace) {
      _log.fine(
        'Cursor remote session list unavailable; using local index',
        error,
        stackTrace,
      );
    }

    final searchTerm = query.searchTerm?.trim().toLowerCase();
    final sessions = merged.values.where((thread) {
      if (searchTerm == null || searchTerm.isEmpty) {
        return true;
      }
      return thread.id.toLowerCase().contains(searchTerm) ||
          thread.displayName.toLowerCase().contains(searchTerm);
    }).toList()..sort(_compareThreadRecency);
    final offset = _cursorOffset(query.cursor);
    final limit = query.limit <= 0 ? 50 : query.limit;
    final page = sessions.skip(offset).take(limit).toList(growable: false);
    final nextOffset = offset + page.length;
    final nextCursor = nextOffset < sessions.length
        ? '$_localListCursorPrefix$nextOffset'
        : null;
    _log.info(
      'Listed Cursor sessions for $workspace '
      'local=$localCount remote=$remoteCount '
      'remoteSupported=$_supportsRemoteSessionList '
      'remoteSucceeded=$remoteSucceeded merged=${merged.length} '
      'matched=${sessions.length} offset=$offset page=${page.length} '
      'next=${nextCursor != null}',
    );
    return AgentThreadPage(
      threads: List<AgentThreadSummary>.unmodifiable(page),
      nextCursor: nextCursor,
    );
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
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId) {
    return _sessionConfigOptions[sessionId] ??
        const <AgentSessionConfigOption>[];
  }

  @override
  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  }) async {
    final options = sessionConfigOptions(sessionId);
    AgentSessionConfigOption? option;
    for (final candidate in options) {
      if (candidate.id == configId) {
        option = candidate;
        break;
      }
    }
    if (option == null) {
      throw StateError('Cursor session 不存在配置项：$configId');
    }
    if (option.kind == AgentSessionConfigOptionKind.select &&
        !option.values.any((item) => item.id == value)) {
      throw ArgumentError.value(value, 'value', '不是服务端提供的配置值');
    }
    if (option.kind == AgentSessionConfigOptionKind.boolean && value is! bool) {
      throw ArgumentError.value(value, 'value', '布尔配置必须使用 bool');
    }
    if (_session?.id != sessionId && !_loadedSessions.containsKey(sessionId)) {
      throw StateError('Cursor session 尚未在当前工作区加载');
    }
    await initialize();

    if (_legacyModeSessions.contains(sessionId) &&
        (option.category == 'mode' || option.id == 'mode')) {
      await _requirePeer().sendRequest(
        'session/set_mode',
        params: <String, Object?>{'sessionId': sessionId, 'modeId': value},
        timeout: _requestTimeout,
      );
      _applyConfigOptions(
        sessionId: sessionId,
        options: _sessionConfigMapper.applyCurrentMode(options, value),
        usesLegacyModes: true,
      );
      return;
    }

    final result = await _requirePeer().sendRequest(
      'session/set_config_option',
      params: <String, Object?>{
        'sessionId': sessionId,
        'configId': configId,
        if (option.kind == AgentSessionConfigOptionKind.boolean)
          'type': 'boolean',
        'value': value,
      },
      timeout: _requestTimeout,
    );
    final payload = _asMap(result);
    final updated = _sessionConfigMapper.tryMapConfigOptions(
      payload?['configOptions'],
    );
    if (updated == null) {
      throw StateError('Cursor ACP set_config_option 未返回完整 configOptions');
    }
    _applyConfigOptions(
      sessionId: sessionId,
      options: updated,
      usesLegacyModes: false,
    );
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
    String? projectPath,
  }) async {
    final index = await _sessionIndexStore.load();
    final indexed = index.find(threadId);
    final hintedWorkspace = normalizeCursorWorkspacePath(
      projectPath ?? sessionPath,
    );
    if (indexed != null &&
        hintedWorkspace != null &&
        !cursorWorkspacePathsEqual(indexed.workspacePath, hintedWorkspace)) {
      throw StateError('Cursor thread locator 与本地索引工作区不一致');
    }
    final workspace = indexed?.workspacePath ?? hintedWorkspace;
    if (workspace == null) {
      throw StateError('Cursor session 缺少工作区信息，无法安全加载历史');
    }
    final loaded = await _ensureSessionLoaded(
      sessionId: threadId,
      workspace: workspace,
    );
    return loaded.history;
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
    final index = await _sessionIndexStore.load();
    final workspace = index.find(threadId)?.workspacePath ?? _workspacePath;
    if (workspace == null) {
      throw StateError('Cursor session 缺少工作区信息，无法校验删除能力');
    }
    await _prepareWorkspace(workspace);
    await initialize();
    if (!capabilities.canDeleteThread) {
      throw UnsupportedError('Cursor ACP 未声明 session/delete 能力');
    }
    await _requirePeer().sendRequest(
      'session/delete',
      params: <String, Object?>{'sessionId': threadId},
      timeout: _requestTimeout,
    );
    await _removeIndexedSession(threadId, localOnly: false);
  }

  @override
  Future<void> removeThreadFromList(String threadId) async {
    await _removeIndexedSession(threadId, localOnly: true);
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
  }) async {
    throw UnsupportedError('Cursor ACP 未声明 session 分叉能力');
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
    if (!cursorWorkspacePathsEqual(_workspacePath, workspace) ||
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
    await _rememberSessionBestEffort(
      sessionId: session.id,
      workspacePath: workspace,
      status: AgentThreadRuntimeStatus.active,
    );
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
      await _rememberSessionBestEffort(
        sessionId: session.id,
        workspacePath: workspace,
        status: AgentThreadRuntimeStatus.idle,
      );
      return turn;
    } catch (error, stackTrace) {
      _log.warning('Cursor session/prompt failed', error, stackTrace);
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message:
            'session/prompt failed; stage=turn; errorType=${error.runtimeType}',
        level: CursorDiagnosticLevel.error,
      );
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
      await _rememberSessionBestEffort(
        sessionId: session.id,
        workspacePath: workspace,
        status: AgentThreadRuntimeStatus.systemError,
      );
      _emitFailure('Cursor prompt 失败', error);
      rethrow;
    }
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
    throw UnsupportedError('Cursor ACP 未声明 steer 能力');
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    final peer = _requirePeer();
    peer.sendNotification(
      'session/cancel',
      params: <String, Object?>{'sessionId': turn.sessionId},
    );
    await _cancelPendingInteractions(peer);
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    final pending = _pendingPermissions.remove(decision.requestId);
    if (pending != null) {
      pending.timer.cancel();
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
      await _requirePeer().sendScopedResponse(
        pending.requestId,
        runtimeScope: pending.runtimeScope,
        result: <String, Object?>{
          'outcome': <String, Object?>{
            'outcome': 'selected',
            'optionId': optionId,
          },
        },
      );
      return;
    }

    final question = _pendingQuestions.remove(decision.requestId);
    if (question == null) {
      _log.warning('Ignoring unknown Cursor interaction ${decision.requestId}');
      return;
    }
    question.timer.cancel();
    final outcome = decision.cancelTurn
        ? <String, Object?>{'outcome': 'cancelled'}
        : !decision.approved
        ? <String, Object?>{
            'outcome': 'skipped',
            if (decision.message?.trim().isNotEmpty ?? false)
              'reason': decision.message!.trim(),
          }
        : <String, Object?>{
            'outcome': 'answered',
            'answers': <Map<String, Object?>>[
              for (final item in question.request.questions)
                <String, Object?>{
                  'questionId': item.questionId,
                  'selectedOptionIds':
                      decision.answers[item.questionId] ?? const <String>[],
                },
            ],
          };
    await _requirePeer().sendScopedResponse(
      question.requestId,
      runtimeScope: question.runtimeScope,
      result: <String, Object?>{'outcome': outcome},
    );
  }

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) async {
    final pending = _pendingPlans.remove(decision.requestId);
    if (pending == null) {
      _log.warning('Ignoring unknown Cursor plan ${decision.requestId}');
      return;
    }
    pending.timer.cancel();
    final outcome = switch (decision.kind) {
      AgentPlanApprovalDecisionKind.accepted => <String, Object?>{
        'outcome': 'accepted',
      },
      AgentPlanApprovalDecisionKind.rejected => <String, Object?>{
        'outcome': 'rejected',
        if (decision.reason?.trim().isNotEmpty ?? false)
          'reason': decision.reason!.trim(),
      },
      AgentPlanApprovalDecisionKind.cancelled => <String, Object?>{
        'outcome': 'cancelled',
      },
    };
    await _requirePeer().sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{'outcome': outcome},
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
    await _closeCurrentPeer();
    _diagnostics.recordExit('provider disposed', expected: true);
    await _events.close();
  }

  Future<void> _prepareWorkspace(String workspace) async {
    if (cursorWorkspacePathsEqual(_workspacePath, workspace)) {
      return;
    }
    if (_peer != null) {
      _diagnostics.recordExit('workspace changed', expected: true);
    }
    await _closeCurrentPeer();
    _workspacePath = workspace;
    _session = null;
    _capabilities = AgentProviderCapabilities.cursorAcp;
    _supportsRemoteSessionList = false;
  }

  Future<List<AgentThreadSummary>> _listRemoteSessions(String workspace) async {
    final sessions = <String, AgentThreadSummary>{};
    final seenCursors = <String>{};
    var rawCount = 0;
    var ignoredCount = 0;
    var pageCount = 0;
    var reachedLimit = false;
    String? cursor;
    remotePages:
    for (var page = 0; page < _maxRemoteListPages; page += 1) {
      final result = await _requirePeer().sendRequest(
        'session/list',
        params: <String, Object?>{'cwd': workspace, 'cursor': ?cursor},
        timeout: _requestTimeout,
      );
      pageCount = page + 1;
      final payload = _asMap(result) ?? const <String, Object?>{};
      final rawSessions = payload['sessions'];
      if (rawSessions is List) {
        for (final rawSession in rawSessions) {
          rawCount += 1;
          final summary = _remoteThreadSummary(
            value: rawSession,
            expectedWorkspace: workspace,
          );
          if (summary != null) {
            sessions[summary.id] = summary;
          } else {
            ignoredCount += 1;
          }
          if (sessions.length >= _maxRemoteSessions) {
            reachedLimit = true;
            break remotePages;
          }
        }
      }
      final nextCursor = _optionalString(payload['nextCursor']);
      if (nextCursor == null ||
          nextCursor.isEmpty ||
          !seenCursors.add(nextCursor)) {
        break;
      }
      cursor = nextCursor;
    }
    _log.info(
      'Cursor session/list for $workspace pages=$pageCount '
      'received=$rawCount accepted=${sessions.length} ignored=$ignoredCount '
      'capped=$reachedLimit',
    );
    return sessions.values.toList(growable: false);
  }

  AgentThreadSummary? _remoteThreadSummary({
    required Object? value,
    required String expectedWorkspace,
  }) {
    final session = _asMap(value);
    if (session == null) {
      return null;
    }
    final sessionId = _optionalString(session['sessionId']);
    final workspace = normalizeCursorWorkspacePath(session['cwd']?.toString());
    if (sessionId == null ||
        sessionId.isEmpty ||
        workspace == null ||
        !cursorWorkspacePathsEqual(workspace, expectedWorkspace)) {
      return null;
    }
    final updatedAt = _decodeDateTime(session['updatedAt']) ?? _clock();
    final metadata = sanitizeCursorSessionMetadata(
      _asMap(session['_meta']) ?? const <String, Object?>{},
    );
    return AgentThreadSummary(
      id: sessionId,
      providerId: config.id,
      projectPath: workspace,
      title: _optionalString(session['title']),
      sessionPath: workspace,
      preview: '',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      recencyAt: updatedAt,
      status: AgentThreadRuntimeStatus.idle,
      raw: <String, Object?>{
        'source': 'cursor-session-list',
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    );
  }

  Future<_LoadedCursorSession> _ensureSessionLoaded({
    required String sessionId,
    required String workspace,
  }) async {
    await _prepareWorkspace(workspace);
    await initialize();
    if (!capabilities.canResumeSession || !capabilities.canReadHistory) {
      throw UnsupportedError('当前 Cursor Agent 未声明 loadSession，无法恢复已有 session');
    }
    final cached = _loadedSessions[sessionId];
    if (cached != null) {
      _session = cached.session;
      return cached;
    }
    final inFlight = _sessionLoadOperations[sessionId];
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _loadSession(sessionId: sessionId, workspace: workspace);
    _sessionLoadOperations[sessionId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_sessionLoadOperations[sessionId], operation)) {
        _sessionLoadOperations.remove(sessionId);
      }
    }
  }

  Future<_LoadedCursorSession> _loadSession({
    required String sessionId,
    required String workspace,
  }) async {
    final peer = _requirePeer();
    final generation = _peerGeneration;
    final collector = AcpSessionReplayCollector(
      threadId: sessionId,
      mapper: _notificationMapper,
    );
    _replayCollectors[sessionId] = collector;
    Object? result;
    try {
      result = await peer.sendRequest(
        'session/load',
        params: <String, Object?>{
          'sessionId': sessionId,
          'cwd': workspace,
          'mcpServers': const <Object?>[],
        },
        timeout: const Duration(minutes: 2),
      );
    } finally {
      if (identical(_replayCollectors[sessionId], collector)) {
        _replayCollectors.remove(sessionId);
      }
    }
    if (generation != _peerGeneration ||
        !identical(peer, _peer) ||
        !cursorWorkspacePathsEqual(workspace, _workspacePath)) {
      throw StateError('Cursor workspace 已切换，本次 session/load 结果已失效');
    }

    final payload = _asMap(result) ?? const <String, Object?>{};
    _applySessionSetup(sessionId: sessionId, payload: payload);
    final index = await _sessionIndexStore.load();
    final indexed = index.find(sessionId);
    final payloadTitle = _optionalString(payload['title']);
    final title = payload.containsKey('title')
        ? payloadTitle
        : _sessionTitles.containsKey(sessionId)
        ? _sessionTitles[sessionId]
        : indexed?.title;
    final history = collector.build(
      raw: <String, Object?>{
        'source': 'cursor-session-load',
        if (payload.isNotEmpty) 'response': payload,
      },
    );
    final session = AgentSession(
      id: sessionId,
      providerId: config.id,
      title: title,
      raw: payload,
    );
    final loaded = _LoadedCursorSession(session: session, history: history);
    _loadedSessions[sessionId] = loaded;
    _session = session;
    await _rememberSessionBestEffort(
      sessionId: sessionId,
      workspacePath: workspace,
      title: title,
      updateTitle:
          payload.containsKey('title') ||
          _sessionTitles.containsKey(sessionId) ||
          indexed != null,
      status: AgentThreadRuntimeStatus.idle,
      metadata: _asMap(payload['_meta']),
      createdAt: indexed?.createdAt,
    );
    _log.info('Loaded Cursor ACP session $sessionId with replay capture');
    return loaded;
  }

  void _handleSessionInfoUpdate({
    required String sessionId,
    required Map<String, Object?> update,
  }) {
    final hasTitle = update.containsKey('title');
    final title = _optionalString(update['title']);
    if (hasTitle) {
      _sessionTitles[sessionId] = title;
      final loaded = _loadedSessions[sessionId];
      if (loaded != null) {
        _loadedSessions[sessionId] = _LoadedCursorSession(
          session: AgentSession(
            id: loaded.session.id,
            providerId: loaded.session.providerId,
            title: title,
            raw: loaded.session.raw,
          ),
          history: loaded.history,
        );
      }
      final current = _session;
      if (current?.id == sessionId) {
        _session = AgentSession(
          id: current!.id,
          providerId: current.providerId,
          title: title,
          raw: current.raw,
        );
      }
      if (!_events.isClosed) {
        _events.add(
          AgentThreadNameUpdatedEvent(
            threadId: sessionId,
            threadName: title,
            raw: update,
          ),
        );
      }
    }
    final workspace = _workspacePath;
    if (workspace == null) {
      return;
    }
    unawaited(
      _rememberSessionBestEffort(
        sessionId: sessionId,
        workspacePath: workspace,
        title: title,
        updateTitle: hasTitle,
        updatedAt: _decodeDateTime(update['updatedAt']),
        metadata: _asMap(update['_meta']),
      ),
    );
  }

  void _applySessionSetup({
    required String sessionId,
    required Map<String, Object?> payload,
  }) {
    final snapshot = _sessionConfigMapper.mapSessionSetup(payload);
    _applyConfigOptions(
      sessionId: sessionId,
      options: snapshot.options,
      usesLegacyModes: snapshot.usesLegacyModes,
    );
  }

  void _applyConfigOptions({
    required String sessionId,
    required List<AgentSessionConfigOption> options,
    required bool usesLegacyModes,
  }) {
    final snapshot = List<AgentSessionConfigOption>.unmodifiable(options);
    _sessionConfigOptions[sessionId] = snapshot;
    if (usesLegacyModes) {
      _legacyModeSessions.add(sessionId);
    } else {
      _legacyModeSessions.remove(sessionId);
    }
    _capabilities = _capabilities.copyWith(
      supportsModelSelection: snapshot.any(
        (option) => option.category == 'model',
      ),
      supportsModeSelection: snapshot.any(
        (option) => option.category == 'mode',
      ),
      supportsReasoningOptions: snapshot.any(
        (option) => option.category == 'thought_level',
      ),
      supportsServiceTierSelection: snapshot.any(
        (option) => option.category == 'model_config',
      ),
    );
    if (!_events.isClosed) {
      _events.add(
        AgentSessionConfigUpdatedEvent(sessionId: sessionId, options: snapshot),
      );
    }
  }

  Future<void> _rememberSessionBestEffort({
    required String sessionId,
    required String workspacePath,
    String? title,
    bool updateTitle = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    AgentThreadRuntimeStatus? status,
    Map<String, Object?>? metadata,
  }) async {
    try {
      final now = (updatedAt ?? _clock()).toUtc();
      await _sessionIndexStore.update((current) {
        final existing = current.find(sessionId);
        final mergedMetadata = <String, Object?>{
          ...?existing?.metadata,
          ...sanitizeCursorSessionMetadata(
            metadata ?? const <String, Object?>{},
          ),
        };
        final next = CursorSessionIndexEntry(
          sessionId: sessionId,
          providerId: config.id,
          workspacePath: workspacePath,
          title: updateTitle ? title : existing?.title,
          createdAt: (existing?.createdAt ?? createdAt ?? now).toUtc(),
          updatedAt: now,
          status: status ?? existing?.status ?? AgentThreadRuntimeStatus.idle,
          metadata: mergedMetadata,
        );
        return current.upsert(next);
      });
    } catch (error, stackTrace) {
      _log.warning(
        'Could not persist Cursor session index entry $sessionId',
        error,
        stackTrace,
      );
    }
  }

  /// 把远端可见会话批量回填到最小索引，供 CLI 不可用或不再支持 list 时兜底。
  Future<void> _rememberRemoteSessionsBestEffort({
    required String workspacePath,
    required List<AgentThreadSummary> sessions,
  }) async {
    if (sessions.isEmpty) {
      return;
    }
    try {
      await _sessionIndexStore.update((current) {
        var next = current;
        for (final session in sessions) {
          final existing = next.find(session.id);
          final remoteMetadata = _asMap(_asMap(session.raw)?['metadata']);
          final updatedAt =
              existing != null && existing.updatedAt.isAfter(session.updatedAt)
              ? existing.updatedAt
              : session.updatedAt;
          final title =
              existing == null ||
                  !session.updatedAt.isBefore(existing.updatedAt)
              ? session.title ?? existing?.title
              : existing.title ?? session.title;
          next = next.upsert(
            CursorSessionIndexEntry(
              sessionId: session.id,
              providerId: config.id,
              workspacePath: session.projectPath,
              title: title,
              createdAt: existing?.createdAt ?? session.createdAt,
              updatedAt: updatedAt,
              status: existing?.status ?? AgentThreadRuntimeStatus.idle,
              metadata: <String, Object?>{
                ...?existing?.metadata,
                ...sanitizeCursorSessionMetadata(
                  remoteMetadata ?? const <String, Object?>{},
                ),
              },
            ),
          );
        }
        return next;
      });
      _log.info(
        'Backfilled ${sessions.length} Cursor sessions for $workspacePath',
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Could not backfill Cursor session index for $workspacePath',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _removeIndexedSession(
    String sessionId, {
    required bool localOnly,
  }) async {
    await _sessionIndexStore.update((current) => current.remove(sessionId));
    _loadedSessions.remove(sessionId);
    _sessionTitles.remove(sessionId);
    _sessionConfigOptions.remove(sessionId);
    _legacyModeSessions.remove(sessionId);
    _extensionMapper.clearSession(sessionId);
    if (_session?.id == sessionId) {
      _session = null;
    }
    if (!_events.isClosed) {
      _events.add(
        AgentThreadDeletedEvent(
          threadId: sessionId,
          raw: <String, Object?>{'localOnly': localOnly},
        ),
      );
    }
  }

  ProviderRuntimeJsonRpcPeer _createPeer(String workspace) {
    final JsonRpcPeer delegate;
    if (!_usedInjectedPeer && _injectedPeer != null) {
      _usedInjectedPeer = true;
      delegate = _injectedPeer;
    } else {
      delegate = _peerFactory(config, workspace);
    }
    return ProviderRuntimeJsonRpcPeer(delegate, providerId: config.id);
  }

  void _listenToPeer(ProviderRuntimeJsonRpcPeer peer) {
    _notificationSubscription = peer.notifications.listen(
      _handleNotification,
      onDone: _handlePeerClosed,
    );
    _serverRequestSubscription = peer.serverRequests.listen((request) {
      unawaited(
        peer.handleServerRequest(request, _handleServerRequest).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          _log.warning(
            'Cursor server request ${request.method} did not complete',
            error,
            stackTrace,
          );
        }),
      );
    });
    _stderrSubscription = peer.stderrLines.listen((line) {
      if (line.trim().isNotEmpty) {
        _diagnostics.recordStderr(line);
        // 不写入 stderr 原文，避免登录态或路径信息进入应用日志。
        _log.fine('Cursor stderr (${line.length} chars)');
      }
    });
    _protocolErrorSubscription = peer.protocolErrors.listen((error) {
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'protocol warning; stage=mapping; error=${error.message}',
        level: CursorDiagnosticLevel.warning,
      );
      _log.warning(
        'Cursor ACP protocol warning (${error.message.length} characters)',
        error.cause,
      );
      _events.add(
        AgentErrorEvent(message: 'Cursor ACP 协议警告', details: error.toString()),
      );
    });
  }

  void _handleNotification(JsonRpcNotification notification) {
    if (notification.method != 'session/update') {
      if (notification.method.startsWith('cursor/')) {
        final sessionId =
            _optionalString(notification.params['sessionId']) ?? _session?.id;
        final mapped = _extensionMapper.mapNotification(
          method: notification.method,
          params: notification.params,
          sessionId: sessionId,
          turnId: _runningTurnId(sessionId),
        );
        for (final event in mapped.events) {
          _events.add(event);
        }
        if (mapped.events.isNotEmpty) {
          return;
        }
      }
      if (_loggedUnknownNotifications.add(notification.method)) {
        _diagnostics.record(
          source: CursorDiagnosticsStore.runtimeSource,
          message:
              'compatibility warning; unknown notification=${notification.method}',
          level: CursorDiagnosticLevel.warning,
        );
        _log.fine(
          'Ignoring unknown Cursor notification ${notification.method}',
        );
      }
      return;
    }
    final sessionId = notification.params['sessionId']?.toString();
    final update = _asMap(notification.params['update']);
    final updateKind = update?['sessionUpdate']?.toString();
    if (sessionId != null && updateKind == 'config_option_update') {
      final options = _sessionConfigMapper.tryMapConfigOptions(
        update?['configOptions'],
      );
      if (options != null) {
        _applyConfigOptions(
          sessionId: sessionId,
          options: options,
          usesLegacyModes: false,
        );
      }
      return;
    }
    if (sessionId != null && updateKind == 'current_mode_update') {
      final current = sessionConfigOptions(sessionId);
      final updated = _sessionConfigMapper.applyCurrentMode(
        current,
        update?['modeId'],
      );
      if (!identical(current, updated)) {
        _applyConfigOptions(
          sessionId: sessionId,
          options: updated,
          usesLegacyModes: _legacyModeSessions.contains(sessionId),
        );
      }
      return;
    }
    if (sessionId != null && updateKind == 'session_info_update') {
      _handleSessionInfoUpdate(sessionId: sessionId, update: update!);
    }
    final replayCollector = sessionId == null
        ? null
        : _replayCollectors[sessionId];
    if (replayCollector != null) {
      replayCollector.record(notification.params);
      return;
    }
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
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'compatibility warning; unknown session update=$unmatched',
        level: CursorDiagnosticLevel.warning,
      );
      _log.fine('Ignoring unknown Cursor update $unmatched');
    }
  }

  Future<void> _handleServerRequest(JsonRpcRequest request) async {
    try {
      switch (request.method) {
        case 'session/request_permission':
          await _handlePermissionRequest(request);
          return;
        case 'cursor/ask_question':
          await _handleQuestionRequest(request);
          return;
        case 'cursor/create_plan':
          await _handlePlanRequest(request);
          return;
        case 'cursor/generate_image':
          await _requirePeer().sendScopedResponse(
            request.id,
            runtimeScope: request.runtimeScope,
            error: const JsonRpcError(
              code: -32601,
              message: 'Client-side image generation is not supported',
            ),
          );
          return;
      }
      await _requirePeer().sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        error: JsonRpcError(
          code: -32601,
          message: 'Method not supported: ${request.method}',
        ),
      );
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message: 'unsupported server request=${request.method}',
        level: CursorDiagnosticLevel.warning,
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Cursor server request ${request.method} failed',
        error,
        stackTrace,
      );
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message:
            'server request failed; stage=mapping; method=${request.method}; error=$error',
        level: CursorDiagnosticLevel.error,
      );
      try {
        await _requirePeer().sendScopedResponse(
          request.id,
          runtimeScope: request.runtimeScope,
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
      runtimeScope: request.runtimeScope,
      mapping: mapping,
    );
    pending.timer = Timer(
      blockingRequestTimeout,
      () => unawaited(_timeoutPermission(pending)),
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

  Future<void> _handleQuestionRequest(JsonRpcRequest request) async {
    final sessionId =
        _optionalString(request.params['sessionId']) ?? _session?.id;
    final mapped = _extensionMapper.mapAskQuestion(
      requestId: request.id,
      params: request.params,
      sessionId: sessionId,
      turnId: _runningTurnId(sessionId),
    );
    if (mapped.questions.isEmpty) {
      await _requirePeer().sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        result: <String, Object?>{
          'outcome': <String, Object?>{
            'outcome': 'skipped',
            'reason': 'No valid questions were provided',
          },
        },
      );
      return;
    }
    final pending = _PendingCursorQuestion(
      requestId: request.id,
      requestKey: mapped.id,
      runtimeScope: request.runtimeScope,
      request: mapped,
    );
    pending.timer = Timer(
      blockingRequestTimeout,
      () => unawaited(_timeoutQuestion(pending)),
    );
    _pendingQuestions[pending.requestKey] = pending;
    _events.add(AgentPermissionRequestedEvent(mapped));
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for input: ${mapped.title}',
      ),
    );
  }

  Future<void> _handlePlanRequest(JsonRpcRequest request) async {
    final sessionId =
        _optionalString(request.params['sessionId']) ?? _session?.id;
    final mapped = _extensionMapper.mapCreatePlan(
      requestId: request.id,
      params: request.params,
      sessionId: sessionId,
      turnId: _runningTurnId(sessionId),
    );
    final pending = _PendingCursorPlan(
      requestId: request.id,
      requestKey: mapped.id,
      runtimeScope: request.runtimeScope,
      request: mapped,
    );
    pending.timer = Timer(
      blockingRequestTimeout,
      () => unawaited(_timeoutPlan(pending)),
    );
    _pendingPlans[pending.requestKey] = pending;
    _events.add(AgentPlanApprovalRequestedEvent(mapped));
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for plan review: ${mapped.title}',
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

  Future<void> _cancelPendingInteractions(
    ProviderRuntimeJsonRpcPeer peer,
  ) async {
    for (final pending in _pendingPermissions.values.toList()) {
      try {
        await _respondPermissionCancelled(peer, pending);
      } catch (_) {
        _pendingPermissions.remove(pending.requestKey);
        pending.timer.cancel();
        _resolvePermissionUi(pending);
      }
    }
    for (final pending in _pendingQuestions.values.toList()) {
      try {
        await _respondQuestionCancelled(peer, pending);
      } catch (_) {
        _pendingQuestions.remove(pending.requestKey);
        _resolveQuestionUi(pending);
      }
    }
    for (final pending in _pendingPlans.values.toList()) {
      try {
        await _respondPlanCancelled(peer, pending);
      } catch (_) {
        _pendingPlans.remove(pending.requestKey);
        _resolvePlanUi(pending);
      }
    }
  }

  Future<void> _respondPermissionCancelled(
    ProviderRuntimeJsonRpcPeer peer,
    _PendingCursorPermission pending,
  ) async {
    _pendingPermissions.remove(pending.requestKey);
    pending.timer.cancel();
    await peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
    );
    _resolvePermissionUi(pending);
  }

  Future<void> _respondQuestionCancelled(
    ProviderRuntimeJsonRpcPeer peer,
    _PendingCursorQuestion pending,
  ) async {
    _pendingQuestions.remove(pending.requestKey);
    pending.timer.cancel();
    await peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
    );
    _resolveQuestionUi(pending);
  }

  Future<void> _respondPlanCancelled(
    ProviderRuntimeJsonRpcPeer peer,
    _PendingCursorPlan pending,
  ) async {
    _pendingPlans.remove(pending.requestKey);
    pending.timer.cancel();
    await peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
    );
    _resolvePlanUi(pending);
  }

  Future<void> _timeoutPermission(_PendingCursorPermission pending) async {
    if (!identical(_pendingPermissions[pending.requestKey], pending)) {
      return;
    }
    final peer = _peer;
    if (peer != null) {
      try {
        await _respondPermissionCancelled(peer, pending);
        return;
      } catch (_) {
        // 连接关闭时仍需清理 UI 和 pending 状态。
      }
    }
    _pendingPermissions.remove(pending.requestKey);
    pending.timer.cancel();
    _resolvePermissionUi(pending);
  }

  Future<void> _timeoutQuestion(_PendingCursorQuestion pending) async {
    if (!identical(_pendingQuestions[pending.requestKey], pending)) {
      return;
    }
    final peer = _peer;
    if (peer != null) {
      try {
        await _respondQuestionCancelled(peer, pending);
        return;
      } catch (_) {
        // 连接关闭时仍需清理 UI 和 pending 状态。
      }
    }
    _pendingQuestions.remove(pending.requestKey);
    pending.timer.cancel();
    _resolveQuestionUi(pending);
  }

  Future<void> _timeoutPlan(_PendingCursorPlan pending) async {
    if (!identical(_pendingPlans[pending.requestKey], pending)) {
      return;
    }
    final peer = _peer;
    if (peer != null) {
      try {
        await _respondPlanCancelled(peer, pending);
        return;
      } catch (_) {
        // 连接关闭时仍需清理 UI 和 pending 状态。
      }
    }
    _pendingPlans.remove(pending.requestKey);
    pending.timer.cancel();
    _resolvePlanUi(pending);
  }

  void _resolvePermissionUi(_PendingCursorPermission pending) {
    final sessionId = pending.mapping.request.sessionId ?? _session?.id;
    if (!_events.isClosed && sessionId != null) {
      _events.add(
        AgentPermissionResolvedEvent(
          requestId: pending.requestKey,
          threadId: sessionId,
        ),
      );
    }
  }

  void _resolveQuestionUi(_PendingCursorQuestion pending) {
    final sessionId = pending.request.sessionId ?? _session?.id;
    if (!_events.isClosed && sessionId != null) {
      _events.add(
        AgentPermissionResolvedEvent(
          requestId: pending.requestKey,
          threadId: sessionId,
        ),
      );
    }
  }

  void _resolvePlanUi(_PendingCursorPlan pending) {
    if (!_events.isClosed) {
      _events.add(
        AgentPlanApprovalResolvedEvent(
          requestId: pending.requestKey,
          sessionId: pending.request.sessionId ?? _session?.id,
        ),
      );
    }
  }

  void _discardPendingInteractions() {
    for (final pending in _pendingPermissions.values) {
      pending.timer.cancel();
      _resolvePermissionUi(pending);
    }
    for (final pending in _pendingQuestions.values) {
      pending.timer.cancel();
      _resolveQuestionUi(pending);
    }
    for (final pending in _pendingPlans.values) {
      pending.timer.cancel();
      _resolvePlanUi(pending);
    }
    _pendingPermissions.clear();
    _pendingQuestions.clear();
    _pendingPlans.clear();
  }

  Future<void> _closeCurrentPeer() async {
    final peer = _peer;
    peer?.beginClosing();
    _peer = null;
    _detachedLifecycleState = peer == null
        ? (_disposed
              ? AgentProviderLifecycleState.closed
              : AgentProviderLifecycleState.stopped)
        : AgentProviderLifecycleState.closing;
    _peerGeneration += 1;
    _initialized = false;
    _initializationOperation = null;
    _runningTurnIdsBySessionId.clear();
    _replayCollectors.clear();
    _sessionLoadOperations.clear();
    _loadedSessions.clear();
    _sessionTitles.clear();
    _sessionConfigOptions.clear();
    _legacyModeSessions.clear();
    _extensionMapper.clear();
    _supportsRemoteSessionList = false;
    if (peer == null) {
      _discardPendingInteractions();
      return;
    }
    _closingPeer = true;
    try {
      await _cancelPendingInteractions(peer);
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
      _detachedLifecycleState = _disposed
          ? AgentProviderLifecycleState.closed
          : AgentProviderLifecycleState.stopped;
    }
  }

  void _handlePeerClosed() {
    if (_disposed || _closingPeer) {
      return;
    }
    _initialized = false;
    _detachedLifecycleState = AgentProviderLifecycleState.failed;
    _peer = null;
    _discardPendingInteractions();
    _session = null;
    _runningTurnIdsBySessionId.clear();
    _peerGeneration += 1;
    _replayCollectors.clear();
    _sessionLoadOperations.clear();
    _loadedSessions.clear();
    _sessionTitles.clear();
    _sessionConfigOptions.clear();
    _legacyModeSessions.clear();
    _extensionMapper.clear();
    _supportsRemoteSessionList = false;
    _capabilities = AgentProviderCapabilities.cursorAcp;
    _diagnostics.recordExit('process closed unexpectedly');
    _emitUnavailable('Cursor Agent 进程已意外退出');
  }

  ProviderRuntimeJsonRpcPeer _requirePeer() {
    final peer = _peer;
    if (peer == null) {
      throw StateError('Cursor ACP peer 尚未启动');
    }
    return peer;
  }

  String? _runningTurnId(String? sessionId) {
    return sessionId == null ? null : _runningTurnIdsBySessionId[sessionId];
  }

  String _requiredWorkspace(AgentContext context) {
    final workspace = normalizeCursorWorkspacePath(context.projectPath);
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
  _PendingCursorPermission({
    required this.requestId,
    required this.requestKey,
    required this.runtimeScope,
    required this.mapping,
  });

  final Object requestId;
  final String requestKey;
  final AgentRuntimeScope? runtimeScope;
  final AcpPermissionMapping mapping;
  late final Timer timer;
}

class _PendingCursorQuestion {
  _PendingCursorQuestion({
    required this.requestId,
    required this.requestKey,
    required this.runtimeScope,
    required this.request,
  });

  final Object requestId;
  final String requestKey;
  final AgentRuntimeScope? runtimeScope;
  final AgentPermissionRequest request;
  late final Timer timer;
}

class _PendingCursorPlan {
  _PendingCursorPlan({
    required this.requestId,
    required this.requestKey,
    required this.runtimeScope,
    required this.request,
  });

  final Object requestId;
  final String requestKey;
  final AgentRuntimeScope? runtimeScope;
  final AgentPlanApprovalRequest request;
  late final Timer timer;
}

class _LoadedCursorSession {
  const _LoadedCursorSession({required this.session, required this.history});

  final AgentSession session;
  final AgentThreadHistorySnapshot history;
}

const String _localListCursorPrefix = 'cursor-index:';
const int _maxRemoteListPages = 20;
const int _maxRemoteSessions = 500;

int _cursorOffset(String? cursor) {
  if (cursor == null || !cursor.startsWith(_localListCursorPrefix)) {
    return 0;
  }
  return int.tryParse(cursor.substring(_localListCursorPrefix.length)) ?? 0;
}

int _compareThreadRecency(AgentThreadSummary left, AgentThreadSummary right) {
  final byTime = (right.recencyAt ?? right.updatedAt).compareTo(
    left.recencyAt ?? left.updatedAt,
  );
  return byTime != 0 ? byTime : left.id.compareTo(right.id);
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _decodeDateTime(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
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
