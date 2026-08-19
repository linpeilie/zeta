import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/claude_code_cli_locator.dart';
import 'package:claude_code_client/src/claude_static_capabilities.dart';
import 'package:claude_code_client/src/claude_text_catalog.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata_probe.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_control_request_handler.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_event_mapper.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_model_catalog.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_plan_approval_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_process_starter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_question_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_session_history_reader.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_usage_quota_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/stream_json_peer.dart';
import 'package:claude_code_client/src/mappers/claude_code_permission_mode_codec.dart';
import 'package:claude_code_client/src/mappers/claude_code_stream_identity.dart';
import 'package:clock/clock.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart' show ProcessStarter;
import 'package:zeta_logging/zeta_logging.dart';

/// Claude Code stream-json Provider。
///
/// 进程常驻 + 串行 turn；`--permission-mode default` 下高风险工具走
/// [ClaudeCodeControlRequestHandler] 的 UI 审批（T20），未知 control 类型
/// 仍 fail-closed deny。`ExitPlanMode` 由独立的
/// [ClaudeCodePlanApprovalAdapter] 接管，`AskUserQuestion` 由独立的
/// [ClaudeCodeQuestionAdapter] 接管，二者都不进入普通权限 registry。
class ClaudeCodeAgentProvider
    implements
        AgentRuntimePort,
        AgentConversationPort,
        AgentThreadCatalogPort,
        AgentThreadCompactionPort,
        AgentPermissionResponsePort,
        AgentQuestionResponsePort,
        AgentModelCatalogPort,
        AgentLocalThreadListPort,
        AgentPlanApprovalPort,
        AgentUsageQuotaProvider {
  /// Creates a [ClaudeCodeAgentProvider].
  ClaudeCodeAgentProvider({
    required this.config,
    ProcessStarter? processStarter,
    StreamJsonPeerBuilder? peerFactory,
    AppLogger? logger,
    this.clock = const Clock(),
    ClaudeCodeCliLocator? locator,
    ClaudeCodeEventMapper? mapper,
    ClaudeCodeModelCatalog? modelCatalog,
    ClaudeCodeCliMetadataLoader? metadataLoader,
    ClaudeCodeCliMetadataCoordinator? metadataCoordinator,
    ClaudeCodeUsageQuotaAdapter? usageQuotaAdapter,
    ClaudeCodeControlRequestHandler? controlRequestHandler,
    ClaudeCodeQuestionAdapter? questionAdapter,
    ClaudeCodeSessionDecisionStoreFactory? sessionDecisionStoreFactory,
    ClaudeCodeSessionHistoryReader? sessionHistoryReader,
    ClaudeCodeHiddenThreadStore? hiddenThreadStore,
    this.textCatalog = const ClaudeCodeTextCatalog(),
    String Function()? idFactory,
  }) : _processStarterDelegate = processStarter ?? Process.start,
       _peerFactory = peerFactory ?? _defaultPeerFactory,
       _log = logger ?? loggerFor('zeta.agent.claude_code.provider'),
       _cliLocator = locator,
       _mapper =
           mapper ??
           ClaudeCodeEventMapper(
             providerId: config.id,
             textCatalog: textCatalog,
             now: clock.now,
             logger: logger,
           ),
       _controlHandler =
           controlRequestHandler ??
           ClaudeCodeControlRequestHandler(
             textCatalog: textCatalog,
             logger: logger,
           ),
       _questionAdapter = questionAdapter ?? ClaudeCodeQuestionAdapter(),
       _sessionHistoryReader =
           sessionHistoryReader ??
           ClaudeCodeSessionHistoryReader(
             hiddenThreadStore: hiddenThreadStore,
             logger: logger,
           ),
       _modelSelection = AgentModelSelection(
         modelId: config.selectedModel,
         reasoningEffort: config.selectedReasoningEffort,
         serviceTierId: config.selectedServiceTier,
       ),
       _idFactory = idFactory ?? _defaultIdFactory {
    final sharedMetadata =
        metadataCoordinator ??
        ClaudeCodeCliMetadataCoordinator(
          clock: clock.now,
          metadataLoader:
              metadataLoader ??
              ClaudeCodeCliMetadataProbe(
                config: config,
                locator: locator,
                processStarter: processStarter,
              ).probe,
        );
    final credentialsReader = ClaudeCodeOAuthCredentialsReader(
      clock: clock.now,
      environment: <String, String>{
        ...Platform.environment,
        ...config.environment,
      },
    );
    _modelCatalog =
        modelCatalog ??
        ClaudeCodeModelCatalog(metadataLoader: sharedMetadata.refreshForModels);
    _usageQuotaAdapter =
        usageQuotaAdapter ??
        ClaudeCodeUsageQuotaAdapter(
          providerId: config.id,
          providerName: config.displayName,
          textCatalog: textCatalog,
          metadataLoader: sharedMetadata.readForQuota,
          accountDataEnrichmentEnabled:
              config.extra[claudeCodeAccountDataEnrichmentKey] != false,
          usesApiKey: _usesClaudeCodeApiKey(config),
          claudeCodeVersion: _nonEmptyConfigValue(
            config.extra['detectedCurrentVersion'],
          ),
          credentialsLoader: credentialsReader.read,
          clock: clock.now,
          logger: logger,
        );
    _planApprovalAdapter = _mapper.planApprovalAdapter;
    _permissionMode = ClaudeCodePermissionModeCodec.parseOptionId(
      config.resolvedPermissionOptionId,
    );
    _permissionPolicy = ClaudeCodePermissionPolicyAdapter(
      applyPermissionMode: _applyPermissionMode,
      sessionDecisionStoreFactory: sessionDecisionStoreFactory,
      textCatalog: textCatalog,
      logger: logger,
    );
  }

  @override
  final AgentProviderConfig config;

  /// The `textCatalog` value.
  final ClaudeCodeTextCatalog textCatalog;

  /// The `clock` value.
  final Clock clock;

  final ProcessStarter _processStarterDelegate;
  final StreamJsonPeerBuilder _peerFactory;
  final AppLogger _log;
  final ClaudeCodeCliLocator? _cliLocator;
  final ClaudeCodeEventMapper _mapper;
  late final ClaudeCodeModelCatalog _modelCatalog;
  late final ClaudeCodeUsageQuotaAdapter _usageQuotaAdapter;
  final ClaudeCodeControlRequestHandler _controlHandler;
  final ClaudeCodeQuestionAdapter _questionAdapter;
  final ClaudeCodeSessionHistoryReader _sessionHistoryReader;
  final String Function() _idFactory;
  AgentModelSelection _modelSelection;
  late final ClaudeCodePlanApprovalAdapter _planApprovalAdapter;
  late final ClaudeCodePermissionPolicyAdapter _permissionPolicy;
  late ClaudeCodePermissionMode _permissionMode;

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  StreamJsonPeer? _peer;
  StreamSubscription<StreamJsonEvent>? _peerEventsSubscription;
  StreamSubscription<StreamJsonProtocolException>? _protocolErrorSubscription;
  Future<void>? _initializationOperation;
  Future<void>? _disposeOperation;
  Future<void>? _permissionModeSwitchOperation;
  bool _turnAdmissionInProgress = false;

  AgentRuntimeScope? _runtimeScope;
  int _connectionEpoch = 0;
  String? _expectedPeerSessionId;
  String? _sessionId;
  String? _workingDirectory;
  String? _activePeerModel;
  String? _activePeerReasoningEffort;
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};

  bool _initialized = false;
  bool _disposed = false;

  @override
  AgentProviderCapabilities get capabilities => ClaudeStaticCapabilities.value;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentRuntimeInfo? get runtimeInfo => null;

  @override
  AgentProviderLifecycleState get lifecycleState {
    if (_disposed) {
      return AgentProviderLifecycleState.closed;
    }
    if (_initialized) {
      return AgentProviderLifecycleState.ready;
    }
    return AgentProviderLifecycleState.stopped;
  }

  @override
  AgentRuntimeScope? get runtimeScope => _runtimeScope;

  /// The `permissionPolicy` value.
  AgentPermissionPolicyPort get permissionPolicy => _permissionPolicy;

  /// 测试/诊断：立即 deny 的 control_request 计数（malformed / 未知 type）。
  int get controlDeniedCount => _controlHandler.deniedCount;

  /// 测试/诊断：等待用户决策的 can_use_tool 数。
  int get controlPendingCount => _controlHandler.pendingCount;

  /// 测试/诊断：等待用户决定的 Plan 审批数（与普通工具权限完全隔离）。
  int get planApprovalPendingCount => _planApprovalAdapter.pendingCount;

  /// 测试/诊断：等待用户回答的 Claude Code 提问数。
  int get questionPendingCount => _questionAdapter.pendingCount;

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
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
    _log.i('Initializing Claude Code provider ${config.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        code: AgentProviderStatusCode.connecting,
      ),
    );
    // 进程在 startSession 时按 cwd 拉起；initialize 只完成 provider 就绪标记。
    _initialized = true;
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.ready,
        code: AgentProviderStatusCode.ready,
      ),
    );
    _log.i('Claude Code provider ${config.id} initialized');
  }

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    await initialize();
    final cwd = context.projectPath?.trim();
    if (cwd == null || cwd.isEmpty) {
      throw StateError('Claude Code requires projectPath as working directory');
    }

    final sessionId = _idFactory();
    final requestedPermission = permissionSnapshot.selection?.optionId;
    if (requestedPermission != null) {
      _permissionMode = ClaudeCodePermissionModeCodec.parseOptionId(
        requestedPermission,
      );
    }
    await _permissionPolicy.bindSession(sessionId);
    await _ensurePeer(
      sessionId: sessionId,
      workingDirectory: cwd,
      resumeSessionId: null,
      model: _effectiveModel,
      reasoningEffort: _effectiveReasoningEffort,
    );
    _sessionId = sessionId;
    _workingDirectory = cwd;

    return AgentSession(
      id: sessionId,
      providerId: config.id,
      raw: <String, Object?>{'cwd': cwd},
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    await initialize();
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    final cwd = context.projectPath?.trim();
    if (cwd == null || cwd.isEmpty) {
      throw StateError('Claude Code requires projectPath as working directory');
    }

    final requestedPermission = permissionSnapshot.selection?.optionId;
    if (requestedPermission != null) {
      _permissionMode = ClaudeCodePermissionModeCodec.parseOptionId(
        requestedPermission,
      );
    }
    await _permissionPolicy.bindSession(normalizedSessionId);
    await _ensurePeer(
      sessionId: normalizedSessionId,
      workingDirectory: cwd,
      resumeSessionId: normalizedSessionId,
      model: _effectiveModel,
      reasoningEffort: _effectiveReasoningEffort,
    );
    _sessionId = normalizedSessionId;
    _workingDirectory = cwd;

    return AgentSession(
      id: normalizedSessionId,
      providerId: config.id,
      raw: <String, Object?>{'cwd': cwd},
    );
  }

  @override
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query}) {
    return _sessionHistoryReader.listThreads(
      query: query,
      providerId: config.id,
      environment: config.environment,
    );
  }

  @override
  Future<void> removeThreadFromList(String threadId) {
    return _sessionHistoryReader.removeThreadFromList(threadId);
  }

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() {
    _ensureNotDisposed();
    return _usageQuotaAdapter.readUsageQuota();
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
    return _modelCatalog.listModels(limit: limit, includeHidden: includeHidden);
  }

  /// Runs `refreshModels`.
  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  }) {
    return _modelCatalog.refreshModels(
      limit: limit,
      includeHidden: includeHidden,
    );
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    _modelSelection = selection;
    _log.t('Updated Claude Code model selection');
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) {
    final normalizedProjectPath = projectPath?.trim();
    if (normalizedProjectPath == null || normalizedProjectPath.isEmpty) {
      throw ArgumentError.value(
        projectPath,
        'projectPath',
        'Claude Code history requires a project path',
      );
    }
    return _sessionHistoryReader.readThreadHistory(
      threadId: threadId,
      providerId: config.id,
      projectPath: normalizedProjectPath,
      sessionPath: sessionPath,
      environment: config.environment,
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    final normalizedThreadId = threadId.trim();
    if (normalizedThreadId.isEmpty) {
      throw ArgumentError.value(threadId, 'threadId', 'must not be empty');
    }
    if (normalizedThreadId != _sessionId) {
      throw StateError(
        'Claude Code provider is bound to session $_sessionId, '
        'not $normalizedThreadId',
      );
    }
    // A matching session id is installed together with its working directory.
    final workingDirectory = _workingDirectory!;

    // Claude 没有独立 compact 控制帧；斜杠命令仍是普通用户回合，必须复用
    // sendMessage 的并发、权限、模型与 session 绑定检查。
    final turn = await sendMessage(
      session: AgentSession(
        id: normalizedThreadId,
        providerId: config.id,
        raw: <String, Object?>{'cwd': workingDirectory},
      ),
      context: AgentContext(projectPath: workingDirectory),
      message: '/compact',
    );
    if (_runningTurnIdsBySessionId[normalizedThreadId] != turn.id) {
      // 极短回合可能在 stdin 写入完成前已经收到终态。
      return;
    }

    final terminal = Completer<void>();
    late final StreamSubscription<AgentEvent> subscription;
    subscription = events.listen(
      (event) {
        if (event is AgentTurnCompletedEvent &&
            event.sessionId == normalizedThreadId &&
            event.turnId == turn.id &&
            !terminal.isCompleted) {
          terminal.complete();
        }
      },
      onDone: () {
        if (!terminal.isCompleted) {
          terminal.completeError(
            StateError('Claude Code compact ended before turn completion'),
          );
        }
      },
    );
    try {
      await terminal.future;
    } finally {
      await subscription.cancel();
    }
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
    final switchOperation = _permissionModeSwitchOperation;
    if (switchOperation != null) {
      await switchOperation;
    }
    if (_turnAdmissionInProgress) {
      throw StateError('Claude Code is already starting another turn');
    }
    _turnAdmissionInProgress = true;
    late final StreamJsonPeer peer;
    late final AgentRuntimeScope runtimeScope;
    late final String turnId;
    late final String text;
    try {
      await initialize();
      if (_peer == null || _runtimeScope == null || _sessionId == null) {
        throw StateError(
          'Claude Code session is not started; call startSession first',
        );
      }
      if (session.id != _sessionId) {
        throw StateError(
          'Claude Code provider is bound to session $_sessionId, '
          'not ${session.id}',
        );
      }

      final existingTurnId = _runningTurnIdsBySessionId[session.id];
      if (existingTurnId != null) {
        throw StateError(
          'Claude Code session ${session.id} already has an active turn '
          '($existingTurnId)',
        );
      }
      final requestedModel = _effectiveModel;
      final requestedReasoningEffort = _effectiveReasoningEffort;

      text = _resolvePromptText(message: message, inputs: inputs);
      if (text.trim().isEmpty) {
        throw ArgumentError('Claude Code prompt text must not be empty');
      }

      await _applyTurnPermissionSnapshot(
        session: session,
        snapshot: configuration.permissionSnapshot,
      );
      await _applyTurnModelConfiguration(
        session: session,
        requestedModel: requestedModel,
        requestedReasoningEffort: requestedReasoningEffort,
      );
      // The admission checks above establish both values. A failed mode switch
      // rethrows before reaching this point.
      final activePeer = _peer!;
      runtimeScope = _runtimeScope!;

      turnId = _idFactory();
      _runningTurnIdsBySessionId[session.id] = turnId;
      _mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: session.id,
        turnId: turnId,
      );
      peer = activePeer;
    } finally {
      _turnAdmissionInProgress = false;
    }
    final turn = AgentTurn(id: turnId, sessionId: session.id);
    _addEvent(
      AgentTurnStartedEvent.fromModelSelection(
        turn: turn,
        selection: AgentModelSelection(
          modelId: _effectiveModel,
          reasoningEffort: _effectiveReasoningEffort,
          serviceTierId: _modelSelection.serviceTierId,
        ),
      ),
    );
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        code: AgentProviderStatusCode.running,
      ),
    );

    final userFrame = <String, Object?>{
      'type': 'user',
      'message': <String, Object?>{
        'role': 'user',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
      },
      'parent_tool_use_id': null,
      'session_id': session.id,
    };

    try {
      await peer.send(userFrame);
    } on Object catch (error, stackTrace) {
      _runningTurnIdsBySessionId.remove(session.id);
      _mapper.completeTurn(
        runtimeScope: runtimeScope,
        sessionId: session.id,
        runningTurnId: turnId,
        status: AgentHistoryTurnStatus.failed,
        source: ClaudeCodeTerminalSource.providerError,
        eventId: 'provider-send-failed',
        eventKind: 'provider.send.failed',
      );
      _planApprovalAdapter.completeTurn(sessionId: session.id, turnId: turnId);
      _completeQuestionTurn(sessionId: session.id, turnId: turnId);
      _log.w(
        'Failed to send Claude Code user frame (${error.runtimeType})',
        error: error,
        stackTrace: stackTrace,
      );
      _addEvent(
        AgentTurnCompletedEvent(
          sessionId: session.id,
          turnId: turnId,
          status: AgentHistoryTurnStatus.failed,
          errorMessage: textCatalog.failedToSendPrompt,
          completedAt: clock.now(),
        ),
      );
      _emitReadyIfIdle();
      rethrow;
    }

    return turn;
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    final peer = _peer;
    if (peer == null) {
      return;
    }
    _log.i('Cancelling Claude Code turn ${turn.id}');
    try {
      await peer.send(<String, Object?>{
        'type': 'control',
        'subtype': 'interrupt',
      });
    } on Object catch (error) {
      _log.w('Claude Code interrupt failed (${error.runtimeType})');
    }
    final runtimeScope = _runtimeScope;
    if (runtimeScope != null) {
      final terminal = _mapper.completeTurn(
        runtimeScope: runtimeScope,
        sessionId: turn.sessionId,
        runningTurnId: turn.id,
        status: AgentHistoryTurnStatus.interrupted,
        source: ClaudeCodeTerminalSource.interrupt,
        eventId: 'interrupt-${turn.id}',
        eventKind: 'control.interrupt',
      );
      if (terminal.accepted) {
        _planApprovalAdapter.completeTurn(
          sessionId: terminal.sessionId,
          turnId: terminal.turnId,
        );
        _completeQuestionTurn(
          sessionId: terminal.sessionId,
          turnId: terminal.turnId,
        );
        _addEvent(
          AgentTurnCompletedEvent(
            sessionId: terminal.sessionId,
            turnId: terminal.turnId,
            status: AgentHistoryTurnStatus.interrupted,
            completedAt: clock.now(),
          ),
        );
      }
    }
    if (_runningTurnIdsBySessionId[turn.sessionId] == turn.id) {
      _runningTurnIdsBySessionId.remove(turn.sessionId);
    }
    _emitReadyIfIdle();
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    _ensureNotDisposed();
    final resolved = _controlHandler.resolveDecision(decision);
    if (resolved == null) {
      return;
    }
    // Pending requests are cleared before the peer is detached.
    final peer = _peer!;
    try {
      await peer.send(resolved.responseFrame);
    } on Object catch (error, stackTrace) {
      _log.w(
        'Failed to send control_response (${error.runtimeType})',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final rememberedDecision = switch (resolved.outcome) {
      ClaudeCodeToolPermissionOutcome.allowAlways =>
        ClaudeCodeSessionToolDecision.allow,
      ClaudeCodeToolPermissionOutcome.denyAlways =>
        ClaudeCodeSessionToolDecision.deny,
      _ => null,
    };
    if (rememberedDecision != null) {
      try {
        await _permissionPolicy.rememberToolDecision(
          resolved.toolName,
          rememberedDecision,
        );
      } on Object catch (error) {
        _log.w(
          'Could not persist Claude Code session decision '
          '(${error.runtimeType})',
        );
      }
    }
    // cancel / denyAlways 时额外 interrupt，避免回合继续挂起等待工具结果。
    if (decision.cancelTurn ||
        resolved.outcome == ClaudeCodeToolPermissionOutcome.denyAlways) {
      try {
        await peer.send(<String, Object?>{
          'type': 'control',
          'subtype': 'interrupt',
        });
      } on Object catch (error) {
        _log.w(
          'Claude Code interrupt after permission deny failed '
          '(${error.runtimeType})',
        );
      }
    }
  }

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) async {
    _ensureNotDisposed();
    final resolved = _questionAdapter.resolveResponse(response);
    if (resolved == null) {
      return;
    }
    // Pending questions are cleared before the peer is detached.
    final peer = _peer!;
    try {
      await peer.send(resolved.responseFrame);
    } on Object catch (error, stackTrace) {
      _log.w(
        'Failed to send question control_response (${error.runtimeType})',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final sessionId = resolved.sessionId;
    if (sessionId != null) {
      _addEvent(
        AgentQuestionResolvedEvent(
          requestId: resolved.requestId,
          threadId: sessionId,
        ),
      );
    }
  }

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) async {
    _ensureNotDisposed();
    final resolved = _planApprovalAdapter.resolveDecision(decision);
    if (resolved == null) {
      return;
    }
    // Pending approvals are cleared before the peer is detached.
    final peer = _peer!;
    try {
      await peer.send(resolved.responseFrame);
    } on Object catch (error, stackTrace) {
      _log.w(
        'Failed to send plan control_response (${error.runtimeType})',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (resolved.interruptTurn) {
      try {
        await peer.send(<String, Object?>{
          'type': 'control',
          'subtype': 'interrupt',
        });
      } on Object catch (error) {
        _log.w(
          'Claude Code interrupt after plan decision failed '
          '(${error.runtimeType})',
        );
      }
    }
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
    if (_disposed) {
      return;
    }
    _disposed = true;
    _log.t('Disposing Claude Code provider ${config.id}');
    await _peerEventsSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    _peerEventsSubscription = null;
    _protocolErrorSubscription = null;
    final peer = _peer;
    _peer = null;
    _expectedPeerSessionId = null;
    _activePeerModel = null;
    _activePeerReasoningEffort = null;
    if (peer != null) {
      try {
        await peer.close();
      } on Object catch (_) {}
    }
    _controlHandler.clearPending();
    _questionAdapter.clear();
    _mapper.dispose();
    _runningTurnIdsBySessionId.clear();
    await _events.close();
  }

  Future<void> _ensurePeer({
    required String sessionId,
    required String workingDirectory,
    required String? resumeSessionId,
    required String? model,
    required String? reasoningEffort,
  }) async {
    final normalizedModel = _normalizeModel(model);
    final normalizedReasoningEffort = _normalizeReasoningEffort(
      reasoningEffort,
    );
    final existing = _peer;
    if (existing != null &&
        _sessionId == sessionId &&
        _workingDirectory == workingDirectory &&
        _activePeerModel == normalizedModel &&
        _activePeerReasoningEffort == normalizedReasoningEffort) {
      return;
    }
    if (existing != null) {
      await _tearDownPeer();
    }

    final resolved = await resolveClaudeCodeProcessCommand(
      config,
      sessionId: resumeSessionId == null ? sessionId : null,
      resumeSessionId: resumeSessionId,
      model: normalizedModel,
      reasoningEffort: normalizedReasoningEffort,
      useConfiguredReasoningEffort: false,
      permissionMode: ClaudeCodePermissionModeCodec.toCliPermissionMode(
        _permissionMode,
      ),
      locator: _cliLocator,
    );

    _connectionEpoch += 1;
    _runtimeScope = AgentRuntimeScope(
      runtimeId: 'claude-code-${config.id}',
      connectionEpoch: _connectionEpoch,
    );

    final peer = _peerFactory(
      command: resolved.executable,
      arguments: resolved.arguments,
      workingDirectory: workingDirectory,
      environment: config.environment,
      processStarter: _processStarterDelegate,
      logger: _log,
    );
    _expectedPeerSessionId = sessionId;
    _peer = peer;
    _listenToPeer(peer);

    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        code: AgentProviderStatusCode.connecting,
      ),
    );
    await peer.start();
    _activePeerModel = normalizedModel;
    _activePeerReasoningEffort = normalizedReasoningEffort;
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.ready,
        code: AgentProviderStatusCode.ready,
      ),
    );
  }

  Future<void> _tearDownPeer() async {
    await _peerEventsSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    _peerEventsSubscription = null;
    _protocolErrorSubscription = null;
    final peer = _peer;
    _peer = null;
    _expectedPeerSessionId = null;
    _activePeerModel = null;
    _activePeerReasoningEffort = null;
    _controlHandler.clearPending();
    _questionAdapter.clear();
    _planApprovalAdapter.clear();
    if (peer != null) {
      try {
        await peer.close();
      } on Object catch (_) {}
    }
    final scope = _runtimeScope;
    if (scope != null) {
      _mapper.invalidateRuntime(
        runtimeScope: scope,
        reason: ClaudeCodeIdentityInvalidationReason.peerClosed,
      );
    }
    _runningTurnIdsBySessionId.clear();
  }

  void _listenToPeer(StreamJsonPeer peer) {
    _peerEventsSubscription = peer.events.listen(
      _handlePeerEvent,
      onError: (Object error, StackTrace stackTrace) {
        _log.w(
          'Claude Code peer event stream error (${error.runtimeType})',
          error: error,
          stackTrace: stackTrace,
        );
      },
      onDone: () {
        _log.i('Claude Code peer event stream closed');
        if (!_disposed) {
          _emitStatus(
            const AgentProviderStatus(
              state: AgentProviderConnectionState.unavailable,
              code: AgentProviderStatusCode.unavailable,
            ),
          );
        }
      },
    );
    _protocolErrorSubscription = peer.protocolErrors.listen((error) {
      _log.w('Claude Code protocol error: $error');
    });
  }

  void _handlePeerEvent(StreamJsonEvent event) {
    if (_disposed) {
      return;
    }
    final runtimeScope = _runtimeScope;
    if (runtimeScope == null) {
      return;
    }

    final sessionId = _sessionId;
    final runningTurnId = sessionId == null
        ? null
        : _runningTurnIdsBySessionId[sessionId];

    if (event.type == 'control_request') {
      final planResult = _planApprovalAdapter.handleControlRequest(event.raw);
      if (planResult.handled) {
        planResult.events.forEach(_addEvent);
        final responseFrame = planResult.responseFrame;
        final peer = _peer;
        if (responseFrame != null && peer != null) {
          unawaited(
            peer.send(responseFrame).catchError((Object error) {
              _log.w(
                'Failed to send plan control_response '
                '(${error.runtimeType})',
              );
            }),
          );
        }
        return;
      }
      final questionResult = _questionAdapter.handleControlRequest(
        event.raw,
        sessionId: sessionId,
        turnId: runningTurnId,
      );
      if (questionResult.handled) {
        questionResult.events.forEach(_addEvent);
        final responseFrame = questionResult.responseFrame;
        final peer = _peer;
        if (responseFrame != null && peer != null) {
          unawaited(
            peer.send(responseFrame).catchError((Object error) {
              _log.w(
                'Failed to send question control_response '
                '(${error.runtimeType})',
              );
            }),
          );
        }
        return;
      }
      if (_tryHandleRememberedToolDecision(event.raw)) {
        return;
      }
      final result = _controlHandler.handle(
        event.raw,
        sessionId: sessionId,
        turnId: runningTurnId,
        cwd: _workingDirectory,
      );
      result.events.forEach(_addEvent);
      final responseFrame = result.responseFrame;
      final peer = _peer;
      if (responseFrame != null && peer != null) {
        unawaited(
          peer.send(responseFrame).catchError((Object error) {
            _log.w('Failed to send control_response (${error.runtimeType})');
          }),
        );
      }
      return;
    }

    final mapped = _mapper.mapFrame(
      raw: event.raw,
      runtimeScope: runtimeScope,
      runningTurnId: runningTurnId,
      expectedSessionId: _expectedPeerSessionId,
    );
    for (final domainEvent in mapped.events) {
      _addEvent(domainEvent);
      if (domainEvent is AgentTurnCompletedEvent) {
        _completeQuestionTurn(
          sessionId: domainEvent.sessionId,
          turnId: domainEvent.turnId,
        );
        if (_runningTurnIdsBySessionId[domainEvent.sessionId] ==
            domainEvent.turnId) {
          _runningTurnIdsBySessionId.remove(domainEvent.sessionId);
        }
        _emitReadyIfIdle();
      }
    }
  }

  void _completeQuestionTurn({
    required String sessionId,
    required String turnId,
  }) {
    final completed = _questionAdapter.completeTurn(
      sessionId: sessionId,
      turnId: turnId,
    );
    for (final question in completed) {
      _addEvent(
        AgentQuestionResolvedEvent(
          requestId: question.requestId,
          threadId: sessionId,
        ),
      );
    }
  }

  bool _tryHandleRememberedToolDecision(Map<String, Object?> raw) {
    final requestId = raw['request_id'];
    final request = _stringKeyedMap(raw['request']);
    if (requestId is! String ||
        requestId.trim().isEmpty ||
        request?['subtype'] != 'can_use_tool') {
      return false;
    }
    final toolName = request?['tool_name'];
    if (toolName is! String) {
      return false;
    }
    final decision = _permissionPolicy.decisionForTool(toolName);
    if (decision == null) {
      return false;
    }
    final input = _stringKeyedMap(request?['input']);
    final outcome = switch (decision) {
      ClaudeCodeSessionToolDecision.allow =>
        ClaudeCodeToolPermissionOutcome.allowAlways,
      ClaudeCodeSessionToolDecision.deny =>
        ClaudeCodeToolPermissionOutcome.denyAlways,
    };
    final responseFrame = ClaudeCodeControlRequestHandler.buildControlResponse(
      requestId: requestId,
      outcome: outcome,
      toolInput: input ?? const <String, Object?>{},
    );
    final peer = _peer;
    if (peer != null) {
      unawaited(
        peer.send(responseFrame).catchError((Object error) {
          _log.w(
            'Failed to send cached control_response (${error.runtimeType})',
          );
        }),
      );
    }
    return true;
  }

  Future<AgentPermissionApplyScope> _applyPermissionMode(
    ClaudeCodePermissionMode nextMode,
  ) async {
    return _switchPermissionMode(nextMode, allowTurnAdmission: false);
  }

  Future<void> _applyTurnPermissionSnapshot({
    required AgentSession session,
    required AgentPermissionRequestSnapshot snapshot,
  }) async {
    final optionId = snapshot.selection?.optionId;
    if (optionId == null) {
      return;
    }
    final nextMode = ClaudeCodePermissionModeCodec.parseOptionId(optionId);
    if (nextMode == _permissionMode) {
      return;
    }
    await _switchPermissionMode(nextMode, allowTurnAdmission: true);
  }

  Future<void> _applyTurnModelConfiguration({
    required AgentSession session,
    required String? requestedModel,
    required String? requestedReasoningEffort,
  }) async {
    final normalizedModel = _normalizeModel(requestedModel);
    final normalizedReasoningEffort = _normalizeReasoningEffort(
      requestedReasoningEffort,
    );
    if (_activePeerModel == normalizedModel &&
        _activePeerReasoningEffort == normalizedReasoningEffort) {
      return;
    }
    if (_runningTurnIdsBySessionId.isNotEmpty ||
        _controlHandler.pendingCount > 0 ||
        _questionAdapter.pendingCount > 0 ||
        _planApprovalAdapter.pendingCount > 0) {
      throw StateError(
        'Claude Code model configuration cannot change while a turn is running',
      );
    }
    final workingDirectory = _workingDirectory!;

    final previousModel = _activePeerModel;
    final previousReasoningEffort = _activePeerReasoningEffort;
    await _tearDownPeer();
    try {
      await _ensurePeer(
        sessionId: session.id,
        workingDirectory: workingDirectory,
        resumeSessionId: session.id,
        model: normalizedModel,
        reasoningEffort: normalizedReasoningEffort,
      );
    } on Object catch (error, stackTrace) {
      await _tearDownPeer();
      try {
        await _ensurePeer(
          sessionId: session.id,
          workingDirectory: workingDirectory,
          resumeSessionId: session.id,
          model: previousModel,
          reasoningEffort: previousReasoningEffort,
        );
      } on Object catch (restoreError) {
        await _tearDownPeer();
        _log.w(
          'Could not restore Claude Code peer after model switch '
          '(${restoreError.runtimeType})',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<AgentPermissionApplyScope> _switchPermissionMode(
    ClaudeCodePermissionMode nextMode, {
    required bool allowTurnAdmission,
  }) async {
    _ensureNotDisposed();
    if (_permissionModeSwitchOperation != null) {
      throw StateError('Claude Code permission mode is already switching');
    }
    if ((!allowTurnAdmission && _turnAdmissionInProgress) ||
        _runningTurnIdsBySessionId.isNotEmpty ||
        _controlHandler.pendingCount > 0 ||
        _questionAdapter.pendingCount > 0 ||
        _planApprovalAdapter.pendingCount > 0) {
      throw StateError(
        'Claude Code permission mode cannot change while a turn is running',
      );
    }

    final completion = Completer<void>();
    _permissionModeSwitchOperation = completion.future;
    try {
      if (_peer == null) {
        _permissionMode = nextMode;
        return AgentPermissionApplyScope.nextSession;
      }
      if (nextMode == _permissionMode) {
        return AgentPermissionApplyScope.currentSession;
      }

      final sessionId = _sessionId!;
      final workingDirectory = _workingDirectory!;
      final previousMode = _permissionMode;
      final previousModel = _activePeerModel;
      final previousReasoningEffort = _activePeerReasoningEffort;
      final requestedModel = _effectiveModel;
      final requestedReasoningEffort = _effectiveReasoningEffort;
      await _tearDownPeer();
      _permissionMode = nextMode;
      try {
        await _ensurePeer(
          sessionId: sessionId,
          workingDirectory: workingDirectory,
          resumeSessionId: sessionId,
          model: requestedModel,
          reasoningEffort: requestedReasoningEffort,
        );
      } on Object catch (error, stackTrace) {
        await _tearDownPeer();
        _permissionMode = previousMode;
        try {
          await _ensurePeer(
            sessionId: sessionId,
            workingDirectory: workingDirectory,
            resumeSessionId: sessionId,
            model: previousModel,
            reasoningEffort: previousReasoningEffort,
          );
        } on Object catch (restoreError) {
          await _tearDownPeer();
          _log.w(
            'Could not restore Claude Code peer after permission switch '
            '(${restoreError.runtimeType})',
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return AgentPermissionApplyScope.currentSession;
    } finally {
      completion.complete();
      if (identical(_permissionModeSwitchOperation, completion.future)) {
        _permissionModeSwitchOperation = null;
      }
    }
  }

  String? get _effectiveModel {
    return _normalizeModel(_modelSelection.modelId) ??
        _normalizeModel(config.defaultModel);
  }

  String? get _effectiveReasoningEffort {
    return _normalizeReasoningEffort(_modelSelection.reasoningEffort);
  }

  String _resolvePromptText({
    required String? message,
    required List<AgentUserInput>? inputs,
  }) {
    final parts = <String>[];
    final trimmed = message?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      parts.add(trimmed);
    }
    if (inputs != null) {
      for (final input in inputs) {
        if (input is AgentTextUserInput) {
          final text = input.text.trim();
          if (text.isNotEmpty) {
            parts.add(text);
          }
        }
      }
    }
    return parts.join('\n');
  }

  static String? _normalizeModel(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _normalizeReasoningEffort(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Map<String, Object?>? _stringKeyedMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  void _emitReadyIfIdle() {
    if (_runningTurnIdsBySessionId.isEmpty && !_disposed) {
      _emitStatus(
        const AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          code: AgentProviderStatusCode.ready,
        ),
      );
    }
  }

  void _emitStatus(AgentProviderStatus status) {
    _addEvent(AgentStatusEvent(status));
  }

  void _addEvent(AgentEvent event) {
    if (_disposed || _events.isClosed) {
      return;
    }
    _events.add(event);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ClaudeCodeAgentProvider has been disposed');
    }
  }

  static String _defaultIdFactory() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).join();
    return '${b.substring(0, 8)}-${b.substring(8, 12)}-'
        '${b.substring(12, 16)}-${b.substring(16, 20)}-${b.substring(20)}';
  }
}

StreamJsonPeer _defaultPeerFactory({
  required String command,
  required List<String> arguments,
  required String? workingDirectory,
  required Map<String, String> environment,
  required ProcessStarter processStarter,
  required AppLogger logger,
}) {
  return StreamJsonPeer(
    command: command,
    arguments: arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    processStarter: processStarter,
    logger: logger,
  );
}

bool _usesClaudeCodeApiKey(AgentProviderConfig config) {
  if (config.extra['hasApiKey'] == true) {
    return true;
  }
  return _nonEmptyConfigValue(config.environment['ANTHROPIC_API_KEY']) !=
          null ||
      _nonEmptyConfigValue(Platform.environment['ANTHROPIC_API_KEY']) != null;
}

String? _nonEmptyConfigValue(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
