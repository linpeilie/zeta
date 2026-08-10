import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/agent_ignored_message_logger.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_models_cli.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_operation_scheduler.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_runtime_json_rpc_peer.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_permission_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_acp_notification_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_billing_quota_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_error_normalizer.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_question_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_skills_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.grok_acp');

/// 根据 provider 配置创建 JSON-RPC 端点。
typedef JsonRpcPeerFactory = JsonRpcPeer Function(AgentProviderConfig config);

/// Grok CLI ACP stdio provider。
///
/// 启动 `grok agent stdio`，通过标准 ACP JSON-RPC 完成会话、流式回复与审批。
/// 账号套餐额度通过 xAI 扩展 `_x.ai/billing` 读取。
/// Skill 目录通过 xAI 扩展 `_x.ai/skills/list` 读取（本地 SKILL.md 扫描）。
/// 结构化用户提问通过 `_x.ai/ask_user_question`（兼容 `x.ai/` 前缀）park 到 UI。
/// 不支持的 Codex 专有能力通过 [capabilities] 关闭，并在误调用时明确失败。
class GrokAcpAgentProvider
    implements
        AgentProvider,
        AgentUsageQuotaProvider,
        AgentRuntimeLifecycleProvider,
        AgentRuntimeScopeProvider,
        AgentRefreshableModelCatalogProvider,
        AgentSkillsCatalogProvider,
        AgentConversationModeCatalogProvider,
        AgentPlanApprovalProvider,
        AgentQuestionResponseProvider,
        AgentPermissionPolicyProvider {
  GrokAcpAgentProvider({
    required this.config,
    JsonRpcPeer? peer,
    JsonRpcPeerFactory? peerFactory,
    GrokSessionHistoryReader? sessionHistoryReader,
    GrokModelsCli? modelsCli,
    GrokAcpNotificationMapper? notificationMapper,
    GrokQuestionMapper? questionMapper,
    List<Duration>? generatedTitlePollDelays,
  }) : _modelSelection = AgentModelSelection(
         modelId: config.selectedModel ?? config.defaultModel,
         reasoningEffort: config.selectedReasoningEffort,
         serviceTierId: config.selectedServiceTier,
       ),
       _permissionMode = GrokPermissionModeCodec.parse(
         config.resolvedPermissionOptionId,
       ),
       _sessionHistoryReader =
           sessionHistoryReader ?? GrokSessionHistoryReader(),
       _modelsCli = modelsCli ?? const GrokModelsCli(),
       _notificationMapper = notificationMapper ?? GrokAcpNotificationMapper(),
       _questionMapper = questionMapper ?? const GrokQuestionMapper(),
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
    _permissionPolicyAdapter = GrokPermissionPolicyAdapter(
      isInitialized: () => _initialized,
      isDisposed: () => _disposed,
      currentMode: () => _permissionMode,
      onModeApplied: (mode) {
        _permissionMode = mode;
      },
      notifyLive: (method, params) {
        _peer.sendNotification(method, params: params);
      },
    );
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
  late final GrokPermissionPolicyAdapter _permissionPolicyAdapter;
  final GrokSessionHistoryReader _sessionHistoryReader;
  final GrokModelsCli _modelsCli;
  final GrokAcpNotificationMapper _notificationMapper;
  final List<Duration> _generatedTitlePollDelays;
  final GrokQuestionMapper _questionMapper;

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final StreamController<void> _skillsChanged =
      StreamController<void>.broadcast();
  final ProviderOperationScheduler _operationScheduler =
      ProviderOperationScheduler();

  final Map<String, _PendingAcpPermission> _pendingPermissions =
      <String, _PendingAcpPermission>{};

  /// 挂起的 `x.ai/exit_plan_mode` 计划审批，key 为 `AgentPlanApprovalRequest.id`
  ///（即 grok 的 `toolCallId`）。响应必须回到请求方，否则 shell 会一直等待。
  final Map<String, _PendingPlanApproval> _pendingPlanApprovals =
      <String, _PendingPlanApproval>{};

  /// 挂起的 `_x.ai/ask_user_question`，key 为领域请求 id（优先 toolCallId）。
  final Map<String, GrokPendingQuestion> _pendingQuestions =
      <String, GrokPendingQuestion>{};

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
  GrokPermissionMode _permissionMode;
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

  final AgentIgnoredMessageLogger _ignoredMessageLogger =
      AgentIgnoredMessageLogger(
        providerLabel: 'Grok',
        loggerName: 'zeta.agent.grok_acp',
      );
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

  /// 开发诊断：被忽略消息按 method + reason 的累计次数。
  @visibleForTesting
  Map<String, int> get ignoredNotificationCountsForTesting =>
      _ignoredMessageLogger.ignoredCounts;

  /// 开发诊断：未匹配消息按 method 的累计次数。
  @visibleForTesting
  Map<String, int> get unmatchedNotificationCountsForTesting =>
      _ignoredMessageLogger.unmatchedCounts;

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
    _log.i('Initializing Grok ACP provider ${config.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: 'Starting Grok',
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
            'title': 'Zeta',
            'version': '0.1.0',
          },
        },
      );
      final initMap =
          _asStringKeyedMap(initResult) ?? const <String, Object?>{};
      final caps = _asStringKeyedMap(initMap['agentCapabilities']);
      _loadSessionSupported = caps?['loadSession'] != false;
      _log.i(
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
      _log.i('Grok ACP provider ${config.id} initialized');
    } on ProcessException catch (error) {
      _peer.markFailed();
      _log.w('Could not start Grok CLI (errorCode=${error.errorCode})');
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error) {
      _peer.markFailed();
      _log.w('Could not initialize Grok ACP provider (${error.runtimeType})');
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
      _log.t('Grok ACP authenticated via $methodId');
    } catch (error) {
      _log.w(
        'Grok ACP authenticate($methodId) failed; continuing '
        '(${error.runtimeType})',
      );
    }
  }

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    // Grok 权限为 runtime-global；请求快照仅显式标记调用边界，协议仍读取 runtime。
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    await initialize();
    final cwd = context.projectPath?.trim();
    if (cwd == null || cwd.isEmpty) {
      throw StateError('Grok ACP session/new requires projectPath as cwd');
    }

    final result = await _peer.sendRequest(
      'session/new',
      params: <String, Object?>{
        'cwd': cwd,
        'mcpServers': <Object?>[],
        '_meta': _permissionPolicyAdapter.sessionMetaForCurrentMode(),
      },
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
    _rememberProjectPath(sessionId, cwd);
    _addEvent(AgentSessionStartedEvent(session));
    _log.i('Started Grok ACP session $sessionId');
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
              '_meta': _permissionPolicyAdapter.sessionMetaForCurrentMode(),
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
          if (cwd != null && cwd.isNotEmpty) {
            _rememberProjectPath(sessionId, cwd);
          }
          // 恢复已有会话时也可能已有 generated_title，主动同步一次。
          _scheduleGeneratedTitlePoll(sessionId);
          _addEvent(AgentSessionStartedEvent(session));
          _log.i('Loaded Grok ACP session $sessionId (replay suppressed)');
          return session;
        } catch (error) {
          _log.w('session/load failed for $sessionId (${error.runtimeType})');
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
        _log.t(
          'Could not load Grok model metadata before reading history',
          error: error,
          stackTrace: stackTrace,
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
      _setModelList(fromCli, source: 'grok models CLI');
    } else {
      _log.i(
        'Grok listModels returned empty '
        '(includeHidden=$includeHidden): ${fromCli.describeForLog()}',
      );
    }
    return fromCli;
  }

  @override
  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    await initialize();
    final fromCli = await _modelsCli.listModels(config);
    if (!_disposed && fromCli.models.isNotEmpty) {
      _setModelList(fromCli, source: 'grok models CLI refresh');
      return _modelList!;
    }
    _log.i(
      'Grok refreshModels kept previous list '
      '(cliEmpty=${fromCli.models.isEmpty}, '
      'cached=${_modelList?.models.length ?? 0}): '
      '${(fromCli.models.isNotEmpty ? fromCli : (_modelList ?? fromCli)).describeForLog()}',
    );
    return _modelList ?? fromCli;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    _modelSelection = selection;
  }

  @override
  AgentPermissionPolicyPort get permissionPolicy => _permissionPolicyAdapter;

  /// 读取 Grok 账号套餐剩余与重置时间。
  ///
  /// 走 xAI 扩展 `_x.ai/billing`；失败时向上抛出，由 usage 层降级为无套餐展示。
  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    await initialize();
    final result = await _peer.sendRequest(
      '_x.ai/billing',
      params: const <String, Object?>{},
      timeout: const Duration(seconds: 20),
    );
    return mapGrokBillingQuota(
      result,
      providerId: config.id,
      providerName: config.displayName,
    );
  }

  /// Skill 文件/插件变更失效信号（供 application 层 stale 刷新）。
  @override
  Stream<void> get skillsChanged => _skillsChanged.stream;

  /// Grok 的会话模式目录。
  ///
  /// 对应 grok-build 的 `SessionMode { Default, Plan }` 闭集，协议层面不提供
  /// 运行时探测；这里直接返回静态目录。模式通过 `session/prompt` 的
  /// `_meta.mode` 逐回合驱动（见 [AgentProvider.sendMessage]）。
  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
    return AgentConversationModeCatalog(
      presets: const <AgentConversationModePreset>[
        AgentConversationModePreset(
          id: AgentConversationModeId.defaultMode,
          displayName: 'Default',
        ),
        AgentConversationModePreset(
          id: AgentConversationModeId.plan,
          displayName: 'Plan',
        ),
      ],
    );
  }

  /// 读取指定 cwd 下 Grok 可用的 skill 目录。
  ///
  /// 走 xAI 扩展 `_x.ai/skills/list`；Grok 侧对每个 cwd 做一次本地 SKILL.md 扫描，
  /// 每个 cwd 产生一个目录条目。`forceReload` 由协议忽略（每次调用都是全新扫描）。
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
    // `_x.ai/skills/list` 的 `cwd` 为必填；无工作区时退化为进程自身目录。
    // 注意：方法名带前导下划线，与 `_x.ai/billing` / `_x.ai/session/*` 一致；
    // 误用 `x.ai/skills/list` 会得到 JSON-RPC -32601 Method not found。
    final resolvedCwds = normalizedCwds.isEmpty
        ? const <String>['.']
        : normalizedCwds;
    final key = resolvedCwds.join('\u0001');
    return _operationScheduler.schedule<AgentSkillsCatalog>(
      key: ProjectOperationKey(providerId: config.id, projectPath: key),
      access: ProviderOperationAccess.sharedRead,
      operation: () async {
        final entries = <AgentSkillsCatalogEntry>[];
        for (final cwd in resolvedCwds) {
          final result = await _peer.sendRequest(
            '_x.ai/skills/list',
            params: <String, Object?>{'cwd': cwd},
            timeout: const Duration(seconds: 20),
          );
          final mapped = mapGrokSkillsEntry(result, cwd: cwd);
          if (mapped.invalidEntryCount > 0 || mapped.droppedSkillCount > 0) {
            _log.t(
              'Normalized Grok skills for $cwd '
              '(invalid=${mapped.invalidEntryCount}, '
              'dropped=${mapped.droppedSkillCount})',
            );
          }
          entries.add(mapped.entry);
        }
        return AgentSkillsCatalog(entries: entries);
      },
    );
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {
    _log.t('Grok ACP has no Guardian; ignore approveGuardianDeniedAction');
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
  }) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw ArgumentError.value(name, 'name', 'Thread title cannot be empty');
      }
      await initialize();
      await _peer.sendRequest(
        '_x.ai/session/rename',
        params: <String, Object?>{'sessionId': threadId, 'title': trimmed},
        timeout: const Duration(seconds: 20),
      );
      // 记录用户标题，避免后续 generated_title 轮询用旧值覆盖。
      _emittedTitlesBySessionId[threadId] = trimmed;
      _historyCache.remove(threadId);
      _addEvent(
        AgentThreadNameUpdatedEvent(threadId: threadId, threadName: trimmed),
      );
      _log.i('Renamed Grok session $threadId');
    },
  );

  @override
  Future<void> archiveThread(String threadId) async {
    throw UnsupportedError('Grok ACP does not support archiving threads');
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    throw UnsupportedError('Grok ACP does not support unarchiving threads');
  }

  @override
  Future<void> deleteThread(String threadId) => _scheduleThreadOperation(
    threadId,
    ProviderOperationAccess.exclusive,
    () async {
      await initialize();
      await _peer.sendRequest(
        '_x.ai/session/delete',
        params: <String, Object?>{'sessionId': threadId},
        timeout: const Duration(seconds: 20),
      );
      _historyCache.remove(threadId);
      _sessionPathBySessionId.remove(threadId);
      _projectPathBySessionId.remove(threadId);
      _emittedTitlesBySessionId.remove(threadId);
      _titlePollTokensBySessionId[threadId] =
          (_titlePollTokensBySessionId[threadId] ?? 0) + 1;
      _runningTurnIdsBySessionId.remove(threadId);
      _addEvent(AgentThreadDeletedEvent(threadId: threadId));
      _log.i('Deleted Grok session $threadId');
    },
  );

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
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
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    final meta = _promptMetaFor(configuration.conversationMode);
    await initialize();
    // 同 session 同时只允许一个 live prompt；覆盖 runningTurnId 会丢终态关联。
    final existingTurnId = _runningTurnIdsBySessionId[session.id];
    if (existingTurnId != null) {
      throw StateError(
        'Grok session ${session.id} already has an active turn '
        '($existingTurnId); wait for it to finish or cancel it first',
      );
    }
    // 模型是 session 级配置；共享 Provider 下必须按本次发送目标应用，不能依赖
    // “最后激活会话”这种全局可变状态。
    await _applyModelSelectionIfNeeded(session.id);
    final cwd = context.projectPath?.trim();
    if (cwd != null && cwd.isNotEmpty) {
      _rememberProjectPath(session.id, cwd);
    }
    // Skill 以 `$name` marker 编入文本 block（composer serialize 已把 skill token
    // 展开为 `$name`），Grok 通过 prompt 文本中的 `$name` 调用 skill；结构化输入
    // 在此跳过以避免重复。仅剩 skill 输入（无其它文本）时，优先复用 `message`
    //（其已含 `$name`），否则兜底合成 `$name` 文本。
    final skillInputs = <AgentSkillUserInput>[];
    final otherInputs = <AgentUserInput>[];
    if (inputs != null) {
      for (final input in inputs) {
        if (input is AgentSkillUserInput) {
          skillInputs.add(input);
        } else {
          otherInputs.add(input);
        }
      }
    }
    final List<AgentUserInput>? resolvedInputs;
    if (otherInputs.isNotEmpty) {
      resolvedInputs = otherInputs;
    } else if (skillInputs.isEmpty) {
      resolvedInputs = inputs;
    } else if ((message?.trim().isNotEmpty ?? false)) {
      resolvedInputs = null;
    } else {
      resolvedInputs = <AgentUserInput>[
        for (final skill in skillInputs) AgentUserInput.text('\$${skill.name}'),
      ];
    }
    final prompt = AcpContentCodec.buildPromptBlocks(
      message: message,
      inputs: resolvedInputs,
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
        params: <String, Object?>{
          'sessionId': session.id,
          'prompt': prompt,
          if (meta.isNotEmpty) '_meta': meta,
        },
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
      _emitMapped(mapped, method: 'session/prompt', params: map);
      // 多 session 共享进程：仅当没有任何 running turn 时才广播 ready。
      _emitReadyIfIdle();
    } catch (error, stackTrace) {
      final failure = _normalizePromptFailure(error);
      _emitPromptFailure(
        runtimeScope: currentRuntimeScope,
        sessionId: session.id,
        turnId: turnId,
        failure: failure,
        error: error,
        stackTrace: stackTrace,
      );
      _notificationMapper.invalidateTurn(
        runtimeScope: currentRuntimeScope,
        sessionId: session.id,
        runningTurnId: turnId,
        promptId: null,
        reason: GrokIdentityInvalidationReason.promptError,
      );
      // prompt 失败也要清掉本 session 的 running 标记，否则会永久挡后续发送。
      if (_runningTurnIdsBySessionId[session.id] == turnId) {
        _runningTurnIdsBySessionId.remove(session.id);
      }
      if (failure.connectionLost) {
        if (_runningTurnIdsBySessionId.isEmpty) {
          _notificationMapper.invalidateRuntime(
            runtimeScope: currentRuntimeScope,
            reason: GrokIdentityInvalidationReason.peerClosed,
          );
        }
        _emitConnectionUnavailableStatus();
      } else {
        _emitReadyIfIdle();
      }
    }

    return turn;
  }

  /// 将回合级对话模式编码为 `session/prompt` 的 `_meta`。
  ///
  /// Grok 以 `_meta.mode` 驱动会话模式：`plan` 进入只读计划模式，
  /// `agent` 表示默认模式（[AgentConversationModeKind.defaultMode]）。
  /// 无模式选择时返回空 map，保持旧的顶层参数结构。
  Map<String, Object?> _promptMetaFor(
    AgentConversationModeSelection? conversationMode,
  ) {
    if (conversationMode == null) {
      return const <String, Object?>{};
    }
    final mode = switch (conversationMode.modeId.kind) {
      AgentConversationModeKind.defaultMode => 'agent',
      AgentConversationModeKind.plan => 'plan',
      AgentConversationModeKind.unknown => throw UnsupportedError(
        '${config.displayName} 不支持对话模式 ${conversationMode.modeId.rawValue}',
      ),
    };
    return <String, Object?>{'mode': mode};
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
    _log.i('Cancelling Grok ACP turn ${turn.id}');
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
      _emitMapped(
        mapped,
        method: 'session/cancel',
        params: <String, Object?>{'sessionId': turn.sessionId},
      );
      _notificationMapper.invalidateTurn(
        runtimeScope: currentRuntimeScope,
        sessionId: turn.sessionId,
        runningTurnId: turn.id,
        promptId: null,
        reason: GrokIdentityInvalidationReason.cancel,
      );
    }
    // 只清理本 session 的挂起交互，避免多 session 并发时误伤其它会话。
    await _clearPendingInteractionsForSession(
      turn.sessionId,
      reason: 'turnCancelled',
    );
    _emitReadyIfIdle();
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    final pending = _pendingPermissions.remove(decision.requestId);
    if (pending == null) {
      _log.w(
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
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) async {
    final pending = _pendingPlanApprovals.remove(decision.requestId);
    if (pending == null) {
      _log.w(
        'Ignoring response for unknown Grok plan approval ${decision.requestId}',
      );
      return;
    }

    // 与 grok-build `ExitPlanModeExtResponse` 对齐：
    // accepted → approved（退出 plan 模式并实施），
    // rejected → cancelled + feedback（留在 plan 模式继续修订），
    // cancelled → abandoned（退出 plan 模式且不启新回合）。
    final outcome = switch (decision.kind) {
      AgentPlanApprovalDecisionKind.accepted => 'approved',
      AgentPlanApprovalDecisionKind.rejected => 'cancelled',
      AgentPlanApprovalDecisionKind.cancelled => 'abandoned',
    };
    final feedback = decision.reason?.trim();
    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: <String, Object?>{
        'outcome': outcome,
        if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
      },
    );
  }

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) async {
    final pending = _pendingQuestions.remove(response.requestId);
    if (pending == null) {
      _log.w(
        'Ignoring response for unknown Grok question ${response.requestId}',
      );
      return;
    }

    _log.i(
      'Responding to Grok user question '
      '(${response.answers.length} answered questions)',
    );
    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: _questionMapper.response(response, pending: pending),
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
    // 与 permission 对称：dispose 时 best-effort 回 abandoned/skip，避免 shell
    // 继续 park 在 exit_plan_mode / ask_user_question 上直到进程退出。
    // 注意：此处 _disposed 已为 true，_addEvent 会短路；终态事件直接写入
    // 尚未 close 的 stream，便于 UI 在 provider 拆掉前清掉审批/提问卡片。
    for (final entry in _pendingPlanApprovals.entries.toList()) {
      try {
        await _respondPlanApprovalAbandoned(entry.value);
      } catch (_) {
        // peer 已关闭或响应失败时仍清理本地状态。
      }
      if (!_events.isClosed) {
        _events.add(AgentPlanApprovalResolvedEvent(requestId: entry.key));
      }
    }
    _pendingPlanApprovals.clear();
    for (final pending in _pendingQuestions.values.toList()) {
      try {
        await _peer.sendScopedResponse(
          pending.requestId,
          runtimeScope: pending.runtimeScope,
          result: _questionMapper.response(
            AgentQuestionResponse(requestId: pending.id),
            pending: pending,
          ),
        );
      } catch (_) {
        // peer 已关闭时忽略。
      }
      if (!_events.isClosed) {
        _events.add(
          AgentQuestionResolvedEvent(
            requestId: pending.id,
            threadId: pending.sessionId ?? '',
            raw: const <String, Object?>{'reason': 'disposed'},
          ),
        );
      }
    }
    _pendingQuestions.clear();
    await _notificationSubscription?.cancel();
    await _serverRequestSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    await _peer.close();
    await _operationScheduler.close();
    _notificationMapper.dispose();
    await _events.close();
    await _skillsChanged.close();
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
          StackTrace _,
        ) {
          _log.w(
            'Grok server request ${request.method} did not complete '
            '(${error.runtimeType})',
          );
        }),
      );
    });
    _stderrSubscription ??= _peer.stderrLines.listen((line) {
      if (line.trim().isEmpty) {
        return;
      }
      _log.t('Grok stderr (${line.length} chars)');
    });
    _protocolErrorSubscription ??= _peer.protocolErrors.listen((error) {
      if (error.kind == JsonRpcProtocolErrorKind.unexpectedResponse) {
        // Grok 偶尔会补发已超时或已完成请求的响应。该诊断不影响当前 turn，
        // 只保留在日志中，避免把 transport 噪声渲染成对话错误。
        _ignoredMessageLogger.record(
          method: 'json-rpc/response',
          reason: 'unexpected response',
          details: <String, Object?>{'errorKind': error.kind.toString()},
          unmatched: true,
        );
        return;
      }
      _log.w(
        'Grok protocol warning (${error.message.length} characters; '
        'cause=${error.causeType ?? 'unknown'})',
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
      _ignoredMessageLogger.record(
        method: method,
        reason: 'missing runtime scope',
        payload: params,
        rawPayload: notification.raw,
      );
      return;
    }

    // session/load 回放或带 isReplay 的更新：不进入直播时间线，避免与
    // readThreadHistory → applyHistorySnapshot 重复渲染。
    if (_shouldSuppressTimelineNotification(method: method, params: params)) {
      _ignoredMessageLogger.record(
        method: method,
        reason: 'suppressed replay notification',
        payload: params,
        rawPayload: notification.raw,
      );
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
      _emitMapped(
        mapped,
        method: method,
        params: params,
        rawPayload: notification.raw,
      );
      _emitReadyIfIdle();
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
      _emitMapped(
        mapped,
        method: method,
        params: params,
        rawPayload: notification.raw,
      );
      _emitReadyIfIdle();
      return;
    }

    // 终态兜底：prompt RPC 可能晚于 extension 通知；first-terminal-wins 去重。
    if (method == '_x.ai/session/prompt_complete' ||
        method == 'x.ai/session/prompt_complete') {
      _handlePromptCompleteNotification(
        method: method,
        params: params,
        runtimeScope: notificationRuntimeScope,
        rawPayload: notification.raw,
      );
      return;
    }

    // x.ai/session_notification 携带 sessionUpdate 枚举（tag `sessionUpdate`）；
    // 插件/hooks 变更会增删 skill，需失效本地 skill 目录让 composer 重新拉取。
    // turn_completed 亦可能经此通道到达，且常携带 usage；必须走 mapXaiSessionUpdate
    //（与 session/update 同源），否则 mapPromptTerminal 只会结束生命周期而丢掉
    // turn footer 所需的 token 元数据。
    // retry_state 表示传输层自动重试进度，同样共用 Grok mapper。
    if (method == 'x.ai/session_notification' ||
        method == '_x.ai/session_notification') {
      final update = _asStringKeyedMap(params['update']);
      final updateType = update?['sessionUpdate']?.toString();
      if (updateType == 'turn_completed' ||
          updateType == 'retry_state' ||
          updateType == 'session_summary_generated' ||
          updateType == 'session_info_update') {
        // 与 session/update 共用 mapper：终态 + usage、retry、实时标题/摘要。
        // 保持 params.update 嵌套结构，避免把 usage 摊平后无法被 decoder 识别。
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
        _emitMapped(
          mapped,
          method: method,
          params: params,
          rawPayload: notification.raw,
        );
        _emitReadyIfIdle();
        return;
      }
      _handleSessionNotificationInvalidation(
        method: method,
        params: params,
        rawPayload: notification.raw,
      );
      return;
    }

    // 其它 x.ai 扩展通知：逐条记录开发态诊断，生产构建由共享 logger 静默。
    if (method.startsWith('_x.ai/') || method.startsWith('x.ai/')) {
      _ignoredMessageLogger.record(
        method: method,
        reason: 'unsupported extension notification',
        payload: params,
        rawPayload: notification.raw,
        unmatched: true,
      );
      return;
    }

    _ignoredMessageLogger.record(
      method: method,
      reason: 'unsupported notification method',
      payload: params,
      rawPayload: notification.raw,
      unmatched: true,
    );
  }

  /// 处理 `x.ai/session_notification` 对 skill 目录的失效信号与列表旁文案。
  ///
  /// `update.sessionUpdate` 为 snake_case 变体名（如 `plugins_changed`）。
  /// 命中会影响 skill 集合的变体时广播 [skillsChanged]，供 application 层刷新；
  /// `last_turn_summary` 映射为中立 preview 事件；其余变体交给共享忽略消息诊断器。
  void _handleSessionNotificationInvalidation({
    required String method,
    required Map<String, Object?> params,
    required Map<String, Object?> rawPayload,
  }) {
    final update = _asStringKeyedMap(params['update']);
    final updateType = update?['sessionUpdate']?.toString();
    if (updateType == 'last_turn_summary') {
      _handleLastTurnSummaryNotification(
        method: method,
        params: params,
        update: update ?? const <String, Object?>{},
        rawPayload: rawPayload,
      );
      return;
    }
    final invalidatesSkills = switch (updateType) {
      'plugins_changed' || 'hooks_changed' || 'skills_changed' => true,
      _ => false,
    };
    if (invalidatesSkills) {
      if (!_skillsChanged.isClosed) {
        _skillsChanged.add(null);
      }
      _log.t(
        'Grok session notification $updateType → skills catalog invalidated',
      );
      return;
    }
    _ignoredMessageLogger.record(
      method: method,
      reason: 'unsupported session notification update',
      payload: params,
      rawPayload: rawPayload,
      details: <String, Object?>{'updateKind': updateType},
    );
  }

  /// 将 `_x.ai/session_notification` 的 `last_turn_summary` 映射为列表旁文案。
  void _handleLastTurnSummaryNotification({
    required String method,
    required Map<String, Object?> params,
    required Map<String, Object?> update,
    required Map<String, Object?> rawPayload,
  }) {
    final sessionId = params['sessionId']?.toString().trim();
    final summary = update['summary']?.toString().trim();
    if (sessionId == null || sessionId.isEmpty) {
      _ignoredMessageLogger.record(
        method: method,
        reason: 'missing session id',
        payload: params,
        rawPayload: rawPayload,
        details: const <String, Object?>{'updateKind': 'last_turn_summary'},
      );
      return;
    }
    if (summary == null || summary.isEmpty) {
      _ignoredMessageLogger.record(
        method: method,
        reason: 'missing last turn summary',
        payload: params,
        rawPayload: rawPayload,
        details: const <String, Object?>{'updateKind': 'last_turn_summary'},
      );
      return;
    }
    _log.t(
      'Grok session $sessionId last_turn_summary '
      '(${summary.length} characters)',
    );
    _addEvent(
      AgentThreadPreviewUpdatedEvent(
        threadId: sessionId,
        preview: summary,
        raw: params,
      ),
    );
  }

  void _emitMapped(
    GrokAcpMappedUpdate mapped, {
    String method = 'provider',
    Map<String, Object?> params = const <String, Object?>{},
    Object? rawPayload,
  }) {
    for (final event in mapped.events) {
      // live 标题到达后记录并去重，避免 summary/info 双通道与本地轮询重复推送。
      if (event is AgentThreadNameUpdatedEvent) {
        final name = event.threadName?.trim();
        if (name == null || name.isEmpty) {
          continue;
        }
        if (_emittedTitlesBySessionId[event.threadId] == name) {
          continue;
        }
        _emittedTitlesBySessionId[event.threadId] = name;
      }
      _addEvent(_enrichUsageEvent(event));
    }
    final unmatched = mapped.unmatchedKind;
    final ignoredReason = mapped.ignoredReason;
    if (ignoredReason != null || unmatched != null) {
      _ignoredMessageLogger.record(
        method: method,
        reason: ignoredReason ?? 'unmatched update kind',
        payload: params,
        rawPayload: rawPayload,
        details: <String, Object?>{'updateKind': ?unmatched},
        unmatched: unmatched != null,
      );
    }
  }

  /// 将 prompt 异常收敛为一次 turn-scoped 错误与同摘要失败终态。
  void _emitPromptFailure({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
    required _GrokPromptFailure failure,
    required Object error,
    required StackTrace stackTrace,
  }) {
    _notificationMapper.noteBoundary(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: turnId,
      kind: GrokNarrativeBoundaryKind.warningOrSystem,
    );
    final mapped = _notificationMapper.mapPromptTerminal(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      stopReason: 'prompt_error',
      source: GrokTerminalSource.promptError,
      errorMessage: failure.message,
      raw: failure.raw,
    );
    final accepted = mapped.events.any(
      (event) => event is AgentTurnCompletedEvent,
    );
    if (!accepted) {
      _emitMapped(mapped, method: 'session/prompt', params: failure.raw);
      return;
    }

    // 错误事件必须先于终态，ViewModel 才能用同摘要抑制 Turn failed 重复消息。
    _addEvent(
      AgentErrorEvent(
        message: failure.message,
        sessionId: sessionId,
        turnId: turnId,
        exception: error,
        stackTrace: stackTrace,
        raw: failure.raw,
      ),
    );
    _noteTurnCompletedFromMapped(sessionId: sessionId, mapped: mapped);
    _emitMapped(mapped, method: 'session/prompt', params: failure.raw);
  }

  _GrokPromptFailure _normalizePromptFailure(Object error) {
    final exceptionType = error.runtimeType.toString();
    if (error is JsonRpcException) {
      final rpcError = error.error;
      final raw = <String, Object?>{
        'operation': 'session/prompt',
        'exceptionType': exceptionType,
        'jsonRpcError': rpcError.toJson(),
      };
      if (rpcError.code == -32003) {
        return _GrokPromptFailure(message: grokRateLimitErrorMessage, raw: raw);
      }
      final serverMessage = rpcError.message.trim();
      return _GrokPromptFailure(
        message: serverMessage.isEmpty
            ? grokRequestFailedErrorMessage
            : 'Grok request failed: $serverMessage',
        raw: raw,
      );
    }
    if (error is TimeoutException) {
      return _GrokPromptFailure(
        message: 'Grok request timed out. Please try again.',
        raw: <String, Object?>{
          'operation': 'session/prompt',
          'exceptionType': exceptionType,
          'message': error.message,
          if (error.duration != null)
            'durationMs': error.duration!.inMilliseconds,
        },
      );
    }
    if (error is JsonRpcTransportClosedException ||
        error is ProviderConnectionClosedException) {
      return _GrokPromptFailure(
        message: 'Grok connection closed. Reconnect and try again.',
        raw: <String, Object?>{
          'operation': 'session/prompt',
          'exceptionType': exceptionType,
          'message': error.toString(),
        },
        connectionLost: true,
      );
    }
    return _GrokPromptFailure(
      message: grokRequestFailedErrorMessage,
      raw: <String, Object?>{
        'operation': 'session/prompt',
        'exceptionType': exceptionType,
        'message': error.toString(),
      },
    );
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
        _log.i(
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
        _log.t(
          'Grok session $sessionId title poll finished without generated_title',
        );
        return;
      }
      if (_emittedTitlesBySessionId[sessionId] == fallback) {
        return;
      }
      _emittedTitlesBySessionId[sessionId] = fallback;
      _log.t(
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
        // Grok 扩展方法在 wire 上常见 `_x.ai/` 前缀；同时兼容无下划线形式。
        case 'x.ai/exit_plan_mode':
        case '_x.ai/exit_plan_mode':
          await _handlePlanApprovalRequest(request);
        case 'x.ai/ask_user_question':
        case '_x.ai/ask_user_question':
          await _handleQuestionRequest(request);
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
          _log.t('Rejecting unsupported Grok server request ${request.method}');
          await _peer.sendScopedResponse(
            request.id,
            runtimeScope: request.runtimeScope,
            error: JsonRpcError(
              code: -32601,
              message: 'Method not supported: ${request.method}',
            ),
          );
      }
    } catch (error) {
      // 服务端请求必须始终应答，否则 session/prompt 会一直挂起。
      _log.w(
        'Grok server request ${request.method} failed '
        '(${error.runtimeType})',
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
    // 活动 prompt 的 pending RPC 会携带真实关闭异常完成；暂缓 runtime
    // invalidation，让对应 catch 能先生成带诊断信息的失败终态。
    if (closedRuntimeScope != null && _runningTurnIdsBySessionId.isEmpty) {
      _notificationMapper.invalidateRuntime(
        runtimeScope: closedRuntimeScope,
        reason: GrokIdentityInvalidationReason.peerClosed,
      );
    }
    _initialized = false;
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
    for (final entry in _pendingPlanApprovals.entries) {
      _addEvent(AgentPlanApprovalResolvedEvent(requestId: entry.key));
    }
    _pendingPlanApprovals.clear();
    for (final pending in _pendingQuestions.values) {
      _addEvent(
        AgentQuestionResolvedEvent(
          requestId: pending.id,
          threadId: pending.sessionId ?? '',
          raw: const <String, Object?>{'reason': 'connectionClosed'},
        ),
      );
    }
    _pendingQuestions.clear();
    _emitConnectionUnavailableStatus();
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

    _log.i('Grok permission requested; options=${mapping.options.length}');

    // 无选项时无法交互批准，立即 cancelled，避免 prompt 永久挂起。
    if (mapping.options.isEmpty) {
      _log.w(
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

  /// 处理 `_x.ai/ask_user_question` 结构化用户提问反请求。
  ///
  /// 与 permission / plan approval 相同：先 park JSON-RPC，再经
  /// [respondToQuestion] 回写；空 answers 编码为 `skip_interview`。
  Future<void> _handleQuestionRequest(JsonRpcRequest request) async {
    final params = request.params;
    final sessionId = params['sessionId']?.toString();
    final requestRuntimeScope = request.runtimeScope;
    if (sessionId != null && requestRuntimeScope != null) {
      _notificationMapper.noteBoundary(
        runtimeScope: requestRuntimeScope,
        sessionId: sessionId,
        runningTurnId: _runningTurnIdsBySessionId[sessionId],
        kind: GrokNarrativeBoundaryKind.userQuestion,
      );
    }

    final mapped = _questionMapper.mapRequest(
      requestId: request.id,
      params: params,
      runningTurnId: sessionId == null
          ? null
          : _runningTurnIdsBySessionId[sessionId],
    );

    // 同领域 id 已有在途提问时，先对旧 JSON-RPC 回 skip，再 park 新请求。
    final existing = _pendingQuestions.remove(mapped.pending.id);
    if (existing != null) {
      _log.w(
        'Replacing pending Grok question ${mapped.pending.id} '
        '(old rpc=${existing.requestId}, new rpc=${request.id})',
      );
      try {
        await _peer.sendScopedResponse(
          existing.requestId,
          runtimeScope: existing.runtimeScope,
          result: _questionMapper.response(
            AgentQuestionResponse(requestId: existing.id),
            pending: existing,
          ),
        );
      } catch (_) {
        // 旧响应失败时仍继续 park 新请求。
      }
      _addEvent(
        AgentQuestionResolvedEvent(
          requestId: existing.id,
          threadId: existing.sessionId ?? '',
          raw: const <String, Object?>{'reason': 'replaced'},
        ),
      );
    }

    if (mapped.event.request.questions.isEmpty) {
      _log.w('Grok question ${mapped.pending.id} has no questions; skipping');
      await _peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        result: _questionMapper.response(
          AgentQuestionResponse(requestId: mapped.pending.id),
          pending: mapped.pending,
        ),
      );
      return;
    }

    _pendingQuestions[mapped.pending.id] = mapped.pending.copyWith(
      runtimeScope: request.runtimeScope,
    );
    _log.i(
      'Grok user question requested '
      '(id=${mapped.pending.id}, questions=${mapped.event.request.questions.length})',
    );
    _addEvent(mapped.event);
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for answers: ${mapped.event.request.title}',
      ),
    );
  }

  /// 处理 `x.ai/exit_plan_mode` 计划审批反请求。
  ///
  /// grok 在模型调用 `exit_plan_mode` 工具时以阻塞 ext_method 反推计划正文给客户端。
  /// 这里构造 [AgentPlanApprovalRequest] 并发出事件，把审批决策面交给 UI；但**不立即
  /// 应答**——响应在用户作出决定后经 [respondToPlanApproval] 回写，否则 shell 会
  /// 一直 park 在当前工具调用上。
  Future<void> _handlePlanApprovalRequest(JsonRpcRequest request) async {
    final params = request.params;
    final sessionId = params['sessionId']?.toString();
    final toolCallId = params['toolCallId']?.toString();
    if (sessionId == null || toolCallId == null || toolCallId.isEmpty) {
      await _peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
        error: const JsonRpcError(
          code: -32602,
          message:
              'Invalid exit_plan_mode params: sessionId/toolCallId required',
        ),
      );
      return;
    }

    // 同 toolCallId 已有在途审批时，先对旧 JSON-RPC request 回 abandoned，
    // 再 park 新请求；否则 shell 会永远等旧 request id 的响应。
    final existing = _pendingPlanApprovals.remove(toolCallId);
    if (existing != null) {
      _log.w(
        'Replacing pending plan approval for $sessionId '
        '(old rpc=${existing.requestId}, new rpc=${request.id})',
      );
      try {
        await _respondPlanApprovalAbandoned(existing);
      } catch (_) {
        // 旧响应失败时仍继续 park 新请求，避免新的 exit_plan_mode 也被挂死。
      }
      _addEvent(AgentPlanApprovalResolvedEvent(requestId: toolCallId));
    }

    final planContent = params['planContent']?.toString();
    final approval = AgentPlanApprovalRequest(
      id: toolCallId,
      title: 'Plan approval',
      markdown: planContent ?? '',
      sessionId: sessionId,
      turnId: _runningTurnIdsBySessionId[sessionId],
      isProject: false,
      raw: _asStringKeyedMap(params) ?? const <String, Object?>{},
    );
    _pendingPlanApprovals[toolCallId] = _PendingPlanApproval(
      requestId: request.id,
      runtimeScope: request.runtimeScope,
      sessionId: sessionId,
    );

    _log.i('Grok plan approval requested (tool=$toolCallId)');
    _addEvent(AgentPlanApprovalRequestedEvent(approval));

    // 更新状态文案，避免 UI 看起来像「无响应卡住」。
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Waiting for plan approval',
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

  /// 对已 park 的 `x.ai/exit_plan_mode` 回写 abandoned（不启新回合、退出 plan）。
  ///
  /// 调用方负责从 [_pendingPlanApprovals] 移除条目并发出 resolved 事件；
  /// 本方法只写 JSON-RPC 响应，避免替换/dispose 路径漏应答导致 shell hang。
  Future<void> _respondPlanApprovalAbandoned(
    _PendingPlanApproval pending,
  ) async {
    await _peer.sendScopedResponse(
      pending.requestId,
      runtimeScope: pending.runtimeScope,
      result: const <String, Object?>{'outcome': 'abandoned'},
    );
  }

  /// 跳过已 park 的用户提问（cancel/dispose）；会清 pending 并发出 resolved。
  Future<void> _respondQuestionSkipped(
    GrokPendingQuestion pending, {
    required String reason,
  }) async {
    _pendingQuestions.remove(pending.id);
    try {
      await _peer.sendScopedResponse(
        pending.requestId,
        runtimeScope: pending.runtimeScope,
        result: _questionMapper.response(
          AgentQuestionResponse(requestId: pending.id),
          pending: pending,
        ),
      );
    } catch (_) {
      // peer 已关闭时忽略。
    }
    _addEvent(
      AgentQuestionResolvedEvent(
        requestId: pending.id,
        threadId: pending.sessionId ?? '',
        raw: <String, Object?>{'reason': reason},
      ),
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
      source: 'session/initialize payload',
    );
  }

  void _setModelList(
    AgentModelList incoming, {
    String? currentModelId,
    String source = 'unknown',
  }) {
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
    _log.i(
      'Applied Grok model list (source=$source): ${merged.describeForLog()}',
    );

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
    if (event is AgentContextWindowUsageEvent) {
      if (event.modelContextWindow != null) {
        return event;
      }
      final window = _contextWindowForModel();
      if (window == null) {
        return event;
      }
      return AgentContextWindowUsageEvent(
        usedTokens: event.usedTokens,
        modelContextWindow: window,
        sessionId: event.sessionId,
        turnId: event.turnId,
        raw: event.raw,
      );
    }
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
      _log.t(
        'session/set_model failed for $modelId',
        error: error,
        stackTrace: stackTrace,
      );
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

  /// 多 session 共享进程时，只有全部 turn 结束后才广播 ready。
  void _emitReadyIfIdle() {
    if (_runningTurnIdsBySessionId.isNotEmpty) {
      return;
    }
    _emitStatus(
      AgentProviderStatus(
        state: AgentProviderConnectionState.ready,
        message: '${config.displayName} ready',
      ),
    );
  }

  /// 将 `_x.ai/session/prompt_complete` / `turn_completed` 收敛为 turn 终态。
  ///
  /// 仅在该 session 仍有 running turn 时生效；与 prompt RPC 通过
  /// first-terminal-wins 去重，避免双重完成。
  void _handlePromptCompleteNotification({
    required String method,
    required Map<String, Object?> params,
    required AgentRuntimeScope runtimeScope,
    Object? rawPayload,
  }) {
    final sessionId = params['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      _ignoredMessageLogger.record(
        method: method,
        reason: 'missing session id',
        payload: params,
        rawPayload: rawPayload,
      );
      return;
    }
    final turnId = _runningTurnIdsBySessionId[sessionId];
    if (turnId == null) {
      _ignoredMessageLogger.record(
        method: method,
        reason: 'no active turn for session',
        payload: params,
        rawPayload: rawPayload,
      );
      return;
    }
    final stopReason =
        params['stopReason']?.toString() ??
        params['stop_reason']?.toString() ??
        params['reason']?.toString() ??
        'end_turn';
    final mapped = _notificationMapper.mapPromptTerminal(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      stopReason: stopReason,
      source: GrokTerminalSource.xaiNotification,
      raw: params,
    );
    if (mapped.events.isEmpty) {
      _emitMapped(
        mapped,
        method: method,
        params: params,
        rawPayload: rawPayload,
      );
      return;
    }
    _log.t(
      'Grok prompt terminal from notification for $sessionId '
      '(stopReason=$stopReason)',
    );
    _noteTurnCompletedFromMapped(sessionId: sessionId, mapped: mapped);
    _emitMapped(mapped, method: method, params: params, rawPayload: rawPayload);
    _emitReadyIfIdle();
  }

  /// 清理指定 session 上 park 的 permission / question / plan approval。
  Future<void> _clearPendingInteractionsForSession(
    String sessionId, {
    required String reason,
  }) async {
    for (final entry in List<_PendingAcpPermission>.from(
      _pendingPermissions.values,
    )) {
      if (entry.mapping.request.sessionId != sessionId) {
        continue;
      }
      await _respondPermissionCancelled(entry);
    }
    for (final pending in List<GrokPendingQuestion>.from(
      _pendingQuestions.values,
    )) {
      if (pending.sessionId != sessionId) {
        continue;
      }
      await _respondQuestionSkipped(pending, reason: reason);
    }
    for (final entry in _pendingPlanApprovals.entries.toList()) {
      if (entry.value.sessionId != sessionId) {
        continue;
      }
      _pendingPlanApprovals.remove(entry.key);
      try {
        await _respondPlanApprovalAbandoned(entry.value);
      } catch (_) {
        // peer 已关闭时忽略。
      }
      _addEvent(AgentPlanApprovalResolvedEvent(requestId: entry.key));
    }
  }

  void _emitConnectionUnavailableStatus() {
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.unavailable,
        message: 'Grok connection closed. Reconnect and try again.',
      ),
    );
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

/// 已 park 的 `x.ai/exit_plan_mode` 反请求，等待用户作出审批决定后回写响应。
class _PendingPlanApproval {
  _PendingPlanApproval({
    required this.requestId,
    required this.runtimeScope,
    required this.sessionId,
  });

  /// ext_method 的 JSON-RPC request id（响应的目标）。
  final Object requestId;

  final AgentRuntimeScope? runtimeScope;

  /// 所属 session，cancel 时只清理本会话，避免误伤并行会话。
  final String sessionId;
}

final class _GrokPromptFailure {
  const _GrokPromptFailure({
    required this.message,
    required this.raw,
    this.connectionLost = false,
  });

  final String message;
  final Map<String, Object?> raw;
  final bool connectionLost;
}
