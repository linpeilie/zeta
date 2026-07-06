import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logging/app_logging.dart';
import '../../domain/agent/agent_models.dart';
import '../../domain/agent/agent_provider.dart';
import 'json_rpc_stdio_transport.dart';

final _log = loggerFor('zeta.agent.codex_app_server');

/// 根据 provider 配置创建 JSON-RPC 端点。
typedef JsonRpcPeerFactory = JsonRpcPeer Function(AgentProviderConfig config);

/// Codex app-server 的 Agent provider 实现。
///
/// 该类把 Codex 稳定 app-server API 映射到领域层事件：
/// `thread/*` -> 会话事件，`turn/*` -> 回合事件，`item/*` -> 消息/工具/审批事件。
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
       _peer = peer ?? (peerFactory ?? _defaultPeerFactory)(config);

  /// JSON-RPC 通信对等体，负责与 Codex app-server 进程交换消息。
  final JsonRpcPeer _peer;

  /// 广播事件流控制器，所有 Agent 事件（会话、回合、消息、工具、审批等）通过此流发出。
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  /// 等待用户审批的服务端 JSON-RPC 请求。
  ///
  /// key 使用 UI 可展示的字符串 id，value 保留原始 request id 以便回写响应。
  final Map<String, _PendingApproval> _pendingApprovals =
      <String, _PendingApproval>{};

  /// 当前活跃的 Agent 会话，由 thread/start 或 thread/resume 设置。
  AgentSession? _session;

  /// 各 thread 当前运行中的 turn id。
  ///
  /// provider 是全局共享实例，不能再假设同一时间只有一个 active turn。
  final Map<String, String> _runningTurnIdsBySessionId = <String, String>{};

  /// 用户在输入框选择的模型组合，由 config 初始化，运行时通过
  /// [updateModelSelection] 同步；turn/start 会用它覆盖默认 model。
  AgentModelSelection _modelSelection;

  /// 缓存的模型列表，initialize 握手后自动拉取。
  AgentModelList? _modelList;

  /// 是否已完成 initialize 握手。
  bool _initialized = false;

  /// 正在执行的初始化操作，用于去重并发初始化调用。
  Future<void>? _initializationOperation;

  /// 是否已调用 dispose，防止重复释放资源。
  bool _disposed = false;

  /// JSON-RPC 通知（服务端推送事件）的订阅。
  StreamSubscription<JsonRpcNotification>? _notificationSubscription;

  /// JSON-RPC 服务端请求（需要客户端回复）的订阅，典型场景是审批请求。
  StreamSubscription<JsonRpcRequest>? _serverRequestSubscription;

  /// 子进程 stderr 输出的行级订阅。
  StreamSubscription<String>? _stderrSubscription;

  /// JSON-RPC 协议错误的订阅。
  StreamSubscription<JsonRpcProtocolException>? _protocolErrorSubscription;

  @override
  final AgentProviderConfig config;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    /// 已初始化则直接返回；若存在正在进行的初始化操作则等待其完成，
    /// 避免并发调用时重复启动子进程和握手。详见 _initializeOnce。
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
  ///
  /// 成功后 _initialized 置为 true；失败时通过 _emitUnavailable 或
  /// AgentErrorEvent 通知上层，并向上抛出异常。
  Future<void> _initializeOnce() async {
    _log.info('Initializing Agent provider ${config.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.connecting,
        message: 'Starting Codex CLI',
      ),
    );

    try {
      /// 启动底层 JSON-RPC 传输（默认为 stdio 子进程），并订阅其各事件流。
      await _peer.start();
      _listenToPeer();

      /// 发送 Codex LSP 风格的 initialize 请求，告知客户端名称和版本。
      /// Codex app-server 要求先 initialize 再接收 initialized 通知。
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

      /// 发送 initialized 通知，告诉服务端客户端已完成初始化。
      _peer.sendNotification('initialized');
      _initialized = true;
      _emitStatus(
        AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: '${config.displayName} ready',
        ),
      );
      _log.info('Agent provider ${config.id} initialized');

      /// 握手完成后立即拉取模型列表，供输入框下方展示模型/思考/速率控件。
      /// 拉取失败不阻断初始化，UI 会退化为不显示选择控件。
      await _fetchModelList();
    } on ProcessException catch (error, stackTrace) {
      /// ProcessException 表示无法启动子进程（如命令不存在或权限不足），
      /// 标记为 unavailable 让上层尝试其他 provider 或提示用户安装。
      _log.warning(
        'Could not start Agent provider process ${config.id}',
        error,
        stackTrace,
      );
      _emitUnavailable(error.message, details: error.toString());
      rethrow;
    } catch (error, stackTrace) {
      /// 其他异常（如握手超时、协议错误）标记为 error 状态并抛出。
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
    /// 确保 provider 已初始化完成再发送 thread/start 请求。
    await initialize();
    _log.fine('Starting Codex thread for provider ${config.id}');

    /// thread/start 创建 Codex 线程；cwd/model/approvalPolicy 由 _threadParams 统一注入。
    final result = await _peer.sendRequest(
      'thread/start',
      params: _threadParams(context),
    );
    final session = _sessionFromThreadStartResult(result);
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
    /// 确保 provider 已初始化完成再发送 thread/resume 请求。
    await initialize();
    _log.fine('Resuming Codex thread $sessionId');

    /// thread/resume 恢复一个已有的 Codex 线程（基于 threadId）。
    /// 恢复失败由上层 ViewModel 捕获，然后回退为新建线程。
    final result = await _peer.sendRequest(
      'thread/resume',
      params: <String, Object?>{
        'threadId': sessionId,
        ..._threadParams(context),
      },
    );
    final session = _sessionFromThreadStartResult(
      result,
      fallbackId: sessionId,
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
    /// 确保 provider 已初始化完成再发送 thread/list 请求。
    await initialize();
    _log.fine(
      'Listing Codex threads for ${query.projectPath} '
      'limit=${query.limit} cursor=${query.cursor}',
    );

    /// thread/list 是 app-server 的分页 thread 索引；cwd 精确过滤当前项目，
    /// sortKey=recency_at 按最近活动时间降序排列，archived=false 排除已归档。
    final result = await _peer.sendRequest(
      'thread/list',
      params: <String, Object?>{
        'cwd': query.projectPath,
        'limit': query.limit,
        if (query.cursor != null) 'cursor': query.cursor,
        'sortKey': 'recency_at',
        'sortDirection': 'desc',
        'archived': false,
      },
    );
    return _threadPageFromResult(result, query.projectPath);
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    /// 已有缓存直接返回，避免重复请求。
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
  ///
  /// 拉取失败时只记录日志，不向外抛，保证 initialize 不被模型列表错误阻断。
  Future<void> _fetchModelList() async {
    try {
      final result = await _peer.sendRequest(
        'model/list',
        params: <String, Object?>{'limit': 20, 'includeHidden': false},
      );
      final list = _modelListFromResult(result);
      _modelList = list;
      _events.add(AgentModelListEvent(list));
      _log.fine('Fetched ${list.models.length} models from Codex');
    } catch (error, stackTrace) {
      _log.warning('Could not fetch Codex model list', error, stackTrace);
    }
  }

  /// 从 `model/list` 响应中解析模型列表。
  AgentModelList _modelListFromResult(Object? value) {
    final map = _map(value);
    final data = map['data'];
    final models = <AgentModelInfo>[];
    if (data is List<Object?>) {
      for (final item in data) {
        final model = _modelInfoFromItem(item);
        if (model != null) {
          models.add(model);
        }
      }
    }
    return AgentModelList(
      models: List<AgentModelInfo>.unmodifiable(models),
      nextCursor: _string(map['nextCursor']),
    );
  }

  /// 将单个 model item 映射成 [AgentModelInfo]。
  AgentModelInfo? _modelInfoFromItem(Object? value) {
    final item = _map(value);
    final id = _string(item['id']) ?? _string(item['model']);
    final model = _string(item['model']) ?? id;
    if (id == null || model == null) {
      return null;
    }
    final efforts = <AgentModelReasoningEffort>[];
    final rawEfforts = item['supportedReasoningEfforts'];
    if (rawEfforts is List<Object?>) {
      for (final effortValue in rawEfforts) {
        final effortMap = _map(effortValue);
        final effortId = _string(effortMap['reasoningEffort']);
        if (effortId != null) {
          efforts.add(
            AgentModelReasoningEffort(
              effort: effortId,
              description: _string(effortMap['description']),
            ),
          );
        }
      }
    }
    final tiers = <AgentModelServiceTier>[];
    final rawTiers = item['serviceTiers'];
    if (rawTiers is List<Object?>) {
      for (final tierValue in rawTiers) {
        final tierMap = _map(tierValue);
        final tierId = _string(tierMap['id']);
        final tierName = _string(tierMap['name']) ?? tierId;
        if (tierId != null) {
          tiers.add(
            AgentModelServiceTier(
              id: tierId,
              name: tierName ?? tierId,
              description: _string(tierMap['description']),
            ),
          );
        }
      }
    }
    return AgentModelInfo(
      id: id,
      model: model,
      displayName: _string(item['displayName']) ?? model,
      description: _string(item['description']),
      hidden: item['hidden'] == true,
      supportedReasoningEfforts: efforts,
      defaultReasoningEffort: _string(item['defaultReasoningEffort']),
      serviceTiers: tiers,
      defaultServiceTier: _string(item['defaultServiceTier']),
      isDefault: item['isDefault'] == true,
      raw: item,
    );
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    /// 确保 provider 已初始化完成再发送 thread/read 请求。
    await initialize();
    _log.fine('Reading Codex thread history $threadId');

    /// 优先从本地 session jsonl 文件恢复时间线，避免网络请求。
    final localHistory = await _threadHistoryFromSessionFile(
      threadId,
      sessionPath,
    );
    if (localHistory != null) {
      return localHistory;
    }

    /// 本地恢复失败则通过 thread/read 从服务端拉取完整历史。
    /// 历史读取必须包含 turns/items，ViewModel 会先渲染历史再恢复实时会话。
    final result = await _peer.sendRequest(
      'thread/read',
      params: <String, Object?>{
        'threadId': threadId,
        'includeTurns': true,
        'itemsView': 'full',
      },
    );
    return _threadHistoryFromReadResult(result, threadId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    /// 确保 provider 已初始化完成再发送 turn/start 请求。
    await initialize();
    _log.info('Starting Codex turn for thread ${session.id}');
    _emitStatus(
      const AgentProviderStatus(
        state: AgentProviderConnectionState.running,
        message: 'Agent is working',
      ),
    );

    /// turn/start 创建一个新的 Agent 回合来处理用户消息。
    /// V1 只发送文本 input；当前文件路径由 ViewModel 追加到文本上下文，不读取文件内容。
    /// approvalPolicy=on-request 要求每次命令执行/文件写入都需用户确认。
    /// model/reasoningEffort/serviceTier 由用户在输入框选择，覆盖 config 默认值。
    final selection = _modelSelection;
    final model = selection.modelId ?? config.defaultModel;
    final result = await _peer.sendRequest(
      'turn/start',
      params: <String, Object?>{
        'threadId': session.id,
        'input': <Object?>[
          <String, Object?>{'type': 'text', 'text': message},
        ],
        if (context.projectPath != null) 'cwd': context.projectPath,
        'model': ?model,
        'reasoningEffort': ?selection.reasoningEffort,
        'serviceTier': ?selection.serviceTierId,
        'approvalPolicy': 'on-request',
      },
    );
    final turn = _turnFromResult(result, session.id);
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
    /// 确保 provider 已初始化完成再发送 turn/steer 请求。
    await initialize();
    _log.info('Steering Codex turn for thread ${session.id}');

    /// turn/steer 在正在执行的回合中追加用户指令，而不是重新开启一个回合。
    /// 适用于对话中用户中途提出新要求或修正方向。
    await _peer.sendRequest(
      'turn/steer',
      params: <String, Object?>{
        'threadId': session.id,
        'input': <Object?>[
          <String, Object?>{'type': 'text', 'text': message},
        ],
        if (context.projectPath != null) 'cwd': context.projectPath,
      },
    );
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    _log.info('Interrupting Codex turn ${turn.id}');

    /// turn/interrupt 向服务端发送中断请求，无需初始化检查即可调用。
    /// Codex 的取消接口以 threadId + turnId 定位正在执行的回合。
    await _peer.sendRequest(
      'turn/interrupt',
      params: <String, Object?>{'threadId': turn.sessionId, 'turnId': turn.id},
    );
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    /// 从等待审批列表中移除对应请求，若不存在则忽略（可能是超时或重复响应）。
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

    /// 服务端审批是 JSON-RPC request，必须用原始 request id 回写 response。
    /// _approvalResponse 根据方法名生成不同结构的响应体。
    await _peer.sendResponse(
      pending.requestId,
      result: _approvalResponse(pending, decision),
    );
  }

  @override
  Future<void> dispose() async {
    /// 防止重复释放资源，幂等调用。
    if (_disposed) {
      return;
    }
    _log.fine('Disposing Agent provider ${config.id}');
    _disposed = true;

    /// 取消所有订阅，关闭 JSON-RPC 对等体及事件流。
    await _notificationSubscription?.cancel();
    await _serverRequestSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _protocolErrorSubscription?.cancel();
    await _peer.close();
    await _events.close();
  }

  /// 订阅 JSON-RPC 对等体的各事件流：
  /// - notifications: 服务端推送的事件通知（会话/回合状态、消息增量、工具进度等）
  /// - serverRequests: 服务端发起的请求（主要是审批流）
  /// - stderrLines: 子进程标准错误输出
  /// - protocolErrors: JSON-RPC 协议层面的错误
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

      /// stderr 不一定是致命错误，但需要展示给用户/调试面板。
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

  /// 处理服务端推送的 JSON-RPC 通知，将其映射为领域事件并发出。
  ///
  /// 只处理 V1 使用到的稳定通知；未知通知保留为 no-op，避免绑定本机 CLI 版本。
  /// 已处理的通知类型包括：
  /// - thread/started -> AgentSessionStartedEvent
  /// - turn/started / turn/completed -> AgentTurnStartedEvent / AgentTurnCompletedEvent
  /// - item/agentMessage/delta -> AgentMessageDeltaEvent（消息流式增量）
  /// - turn/plan/updated -> AgentPlanUpdatedEvent（计划步骤更新）
  /// - item/started / item/completed -> AgentMessageUpdatedEvent / AgentToolCallEvent
  /// - 进度类通知 -> AgentToolCallEvent（工具执行进度）
  /// - error/warning 类 -> AgentErrorEvent
  void _handleNotification(JsonRpcNotification notification) {
    switch (notification.method) {
      case 'thread/started':

        /// 服务端通知线程已创建，提取会话信息并发出事件。
        final session = _sessionFromNotification(notification.params);
        if (session != null) {
          _session = session;
          _events.add(AgentSessionStartedEvent(session));
        }
      case 'turn/started':

        /// 服务端通知回合已开始，记录活跃回合并发出事件。
        final turn = _turnFromNotification(notification.params);
        if (turn != null) {
          _markRunningTurn(turn.sessionId, turn.id);
          _events.add(AgentTurnStartedEvent(turn));
        }
      case 'turn/completed':

        /// 服务端通知回合已完成，清除活跃回合标记，恢复 ready 状态并发出完成事件。
        final threadId = _string(notification.params['threadId']);
        final turn = _map(notification.params['turn']);
        final turnId =
            _string(turn['id']) ??
            _string(notification.params['turnId']) ??
            (threadId == null ? null : _runningTurnIdsBySessionId[threadId]);
        if (threadId != null && turnId != null) {
          _completeRunningTurn(threadId, turnId);
          if (_runningTurnIdsBySessionId.isEmpty) {
            _emitStatus(
              AgentProviderStatus(
                state: AgentProviderConnectionState.ready,
                message: '${config.displayName} ready',
              ),
            );
          }
          _events.add(
            AgentTurnCompletedEvent(
              sessionId: threadId,
              turnId: turnId,
              raw: notification.params,
            ),
          );
        }
      case 'item/agentMessage/delta':

        /// 消息以增量形式到达，每个 delta 通知携带片段文本。
        /// ViewModel 会按 itemId 合并为一条完整气泡。
        final delta = _string(notification.params['delta']);
        final itemId = _string(notification.params['itemId']);
        if (delta != null && itemId != null) {
          final item = _map(notification.params['item']);
          _events.add(
            AgentMessageDeltaEvent(
              messageId: itemId,
              delta: delta,
              role: AgentMessageRole.agent,
              phase: _messagePhase(
                _string(notification.params['phase']) ?? _string(item['phase']),
              ),
              status: _messageStatus(
                _string(notification.params['status']) ??
                    _string(item['status']),
              ),
              duration: _messageDuration(item, notification.params),
              raw: notification.params,
              sessionId: _string(notification.params['threadId']),
              turnId: _string(notification.params['turnId']),
            ),
          );
        }
      case 'turn/plan/updated':

        /// 计划步骤更新通知，将 Codex 原始 plan schema 转成统一的 AgentPlanEntry 列表。
        _events.add(
          AgentPlanUpdatedEvent(
            entries: _planEntries(notification.params),
            sessionId: _string(notification.params['threadId']),
            turnId: _string(notification.params['turnId']),
          ),
        );
      case 'item/started':
      case 'item/completed':

        /// item 通知可能是 agentMessage 的 metadata 更新（如 phase/status 变更），
        /// 也可能是命令执行、文件变更、读文件等工具调用。
        /// 优先尝试转为消息更新事件，否则转为工具调用事件。
        final messageUpdate = _messageUpdateFromItemNotification(notification);
        if (messageUpdate != null) {
          _events.add(messageUpdate);
          break;
        }
        final toolCall = _toolCallFromItemNotification(notification);
        if (toolCall != null) {
          _events.add(AgentToolCallEvent(toolCall));
        }
      case 'item/commandExecution/outputDelta':
      case 'command/exec/outputDelta':
      case 'item/fileChange/outputDelta':
      case 'item/fileChange/patchUpdated':

        /// 进度类通知没有完整 item 结构，仅包含增量文本或 patch 内容，
        /// 也会转成同一个工具卡片进行增量展示。
        final toolCall = _toolCallFromProgressNotification(notification);
        if (toolCall != null) {
          _events.add(AgentToolCallEvent(toolCall));
        }
      case 'turn/tokenCount':
      case 'item/tokenCount':
      case 'tokenCount':

        /// 服务端推送的 token 用量更新，转成 AgentTokenUsageEvent 供 UI 展示成本。
        final usage = _tokenUsageFromNotification(notification.params);
        final threadId = _string(notification.params['threadId']);
        if (usage != null) {
          _events.add(
            AgentTokenUsageEvent(
              sessionId: threadId,
              turnId:
                  _string(notification.params['turnId']) ??
                  (threadId == null
                      ? null
                      : _runningTurnIdsBySessionId[threadId]),
              tokenUsage: usage,
              raw: notification.params,
            ),
          );
        }
      case 'error':
      case 'warning':
      case 'guardianWarning':
      case 'configWarning':

        /// 服务端报告的错误或警告，记录日志并发出 AgentErrorEvent。
        _log.warning(
          'Codex ${notification.method}: '
          '${_string(notification.params['message']) ?? 'No message'}',
        );
        _events.add(
          AgentErrorEvent(
            message:
                _string(notification.params['message']) ?? notification.method,
            details: _string(notification.params['details']),
            sessionId: _string(notification.params['threadId']),
            turnId: _string(notification.params['turnId']),
            raw: notification.params,
          ),
        );
      default:
        break;
    }
  }

  /// 处理服务端发起的 JSON-RPC 请求（非通知），目前全是审批类请求。
  ///
  /// Codex 将审批作为服务端 JSON-RPC request 发给客户端；这里统一转成
  /// AgentPermissionRequestedEvent 供 UI 展示审批卡片，并将原始请求信息
  /// 存入 _pendingApprovals 等待用户决策后回写响应。
  void _handleServerRequest(JsonRpcRequest request) {
    _log.fine('Received Codex server request ${request.method}');
    switch (request.method) {
      case 'item/commandExecution/requestApproval':
      case 'execCommandApproval':

        /// 命令执行审批：用户需决定是否允许运行指定命令。
        _addPendingApproval(
          request,
          AgentPermissionKind.commandExecution,
          _string(request.params['command']) ?? 'Run command',
        );
      case 'item/fileChange/requestApproval':
      case 'applyPatchApproval':

        /// 文件变更审批：用户需决定是否允许应用文件修改。
        _addPendingApproval(
          request,
          AgentPermissionKind.fileChange,
          'Apply file changes',
        );
      case 'item/permissions/requestApproval':

        /// 权限扩展审批：用户需决定是否授予额外文件系统或网络权限。
        _addPendingApproval(
          request,
          AgentPermissionKind.permissions,
          'Grant additional permissions',
        );
      case 'item/tool/requestUserInput':
      case 'mcpServer/elicitation/request':

        /// 用户输入请求：Agent 需要用户补充信息才能继续。
        _addPendingApproval(
          request,
          AgentPermissionKind.userInput,
          'Agent requests input',
        );
      default:

        /// 未知审批类型，兜底为 other 保留原始方法名。
        _addPendingApproval(request, AgentPermissionKind.other, request.method);
    }
  }

  /// 将服务端审批请求加入等待列表，并向 UI 层发出 AgentPermissionRequestedEvent。
  ///
  /// [request] 原始 JSON-RPC 请求，保存到 _pendingApprovals 以便用户决策后
  /// 用相同的 request id 回写响应。
  /// [kind] 审批类型（命令执行、文件变更、用户输入等）。
  /// [title] UI 上显示的审批卡片标题。
  void _addPendingApproval(
    JsonRpcRequest request,
    AgentPermissionKind kind,
    String title,
  ) {
    final id = '${request.id}';
    _log.info('Queued Codex permission ${kind.name} from ${request.method}');

    /// 保存原始请求，用户点击 approve/deny 后才能用同一个 id 回复 app-server。
    _pendingApprovals[id] = _PendingApproval(
      requestId: request.id,
      method: request.method,
      params: request.params,
    );
    final reason = _string(request.params['reason']);
    _events.add(
      AgentPermissionRequestedEvent(
        AgentPermissionRequest(
          id: id,
          title: title,
          kind: kind,
          description: reason,
          command: _string(request.params['command']),
          cwd: _string(request.params['cwd']),
          sessionId: _string(request.params['threadId']),
          turnId: _string(request.params['turnId']),
          fileChanges: _map(request.params['fileChanges']),
          raw: request.params,
        ),
      ),
    );
  }

  /// 构建创建/恢复 Codex 线程所需的公共参数。
  ///
  /// 当前项目路径（cwd）、默认模型（model）和审批策略（approvalPolicy）
  /// 在每次创建或恢复线程时统一注入。
  /// approvalPolicy 固定为 on-request，确保文件写入、命令执行和权限扩展都由用户确认。
  Map<String, Object?> _threadParams(AgentContext context) {
    return <String, Object?>{
      if (context.projectPath != null) 'cwd': context.projectPath,
      if (config.defaultModel != null) 'model': config.defaultModel,
      'approvalPolicy': 'on-request',
    };
  }

  /// 从 thread/start 或 thread/resume 的响应中提取领域会话。
  ///
  /// [value] 服务端返回的 JSON-RPC 响应体。
  /// [fallbackId] 在响应中未找到 thread.id 时的兜底会话 ID，用于 resume 场景。
  AgentSession _sessionFromThreadStartResult(
    Object? value, {
    String? fallbackId,
  }) {
    final map = _map(value);
    final thread = _map(map['thread']);
    final id =
        _string(thread['id']) ?? fallbackId ?? _session?.id ?? 'codex-thread';
    return AgentSession(
      id: id,
      providerId: config.id,
      title: _string(thread['title']) ?? _string(thread['name']),
      raw: map,
    );
  }

  /// 从 thread/started 通知中提取领域会话。
  ///
  /// 通知中包含完整的 thread 对象，从中提取 id 和 title。
  /// 返回 null 表示通知中缺少必要字段，无法构建有效会话。
  AgentSession? _sessionFromNotification(Map<String, Object?> params) {
    final thread = _map(params['thread']);
    final id = _string(thread['id']) ?? _string(params['threadId']);
    if (id == null) {
      return null;
    }
    return AgentSession(
      id: id,
      providerId: config.id,
      title: _string(thread['title']) ?? _string(thread['name']),
      raw: params,
    );
  }

  /// 从 thread/list 响应中提取分页摘要。
  ///
  /// 解析服务端返回的 data 数组,每个元素转成 AgentThreadSummary，
  /// 同时透传 nextCursor 用于后续分页请求。
  /// [projectPath] 作为摘要中缺少项目路径时的兜底值。
  AgentThreadPage _threadPageFromResult(Object? value, String projectPath) {
    final map = _map(value);
    final data = map['data'];
    final threads = <AgentThreadSummary>[];
    if (data is List<Object?>) {
      for (final item in data) {
        final summary = _threadSummaryFromThread(item, projectPath);
        if (summary != null) {
          threads.add(summary);
        }
      }
    }
    return AgentThreadPage(
      threads: List<AgentThreadSummary>.unmodifiable(threads),
      nextCursor: _string(map['nextCursor']),
    );
  }

  /// 从 thread/read 响应中提取历史时间线。
  AgentThreadHistorySnapshot _threadHistoryFromReadResult(
    Object? value,
    String fallbackThreadId,
  ) {
    final map = _map(value);
    final thread = _map(map['thread']);
    final threadId = _string(thread['id']) ?? fallbackThreadId;
    final turns = <AgentHistoryTurn>[];
    AgentHistoryTurn? currentTurn;
    final turnsList = thread['turns'];

    if (turnsList is List<Object?>) {
      for (final turnValue in turnsList) {
        final turn = _map(turnValue);
        final turnId = _string(turn['id']) ?? threadId;
        final turnEntries = <AgentHistoryEntry>[];
        final items = turn['items'];
        if (items is List<Object?>) {
          for (final itemValue in items) {
            final entry = _historyEntryFromItem(itemValue, turnId: turnId);
            if (entry != null) {
              turnEntries.add(entry);
            }
          }
        }
        final startedAt = _dateTimeFromAny(
          turn['startedAt'] ?? turn['startedAtMs'],
        );
        final completedAt = _dateTimeFromAny(
          turn['completedAt'] ?? turn['completedAtMs'],
        );
        final historyTurn = AgentHistoryTurn(
          id: turnId,
          entries: List<AgentHistoryEntry>.unmodifiable(turnEntries),
          status: _historyTurnStatus(_string(turn['status']), completedAt),
          startedAt: startedAt,
          completedAt: completedAt,
          duration: _durationFromMilliseconds(turn['durationMs']),
          cwd: _string(turn['cwd']),
          model: _string(turn['model']),
          modelContextWindow:
              _numberToInt(turn['modelContextWindow']) ??
              _numberToInt(turn['model_context_window']),
          collaborationMode:
              _string(turn['collaborationMode']) ??
              _string(turn['collaboration_mode']),
          tokenUsage: _tokenUsageFromTurnPayload(turn),
          raw: turn,
        );
        turns.add(historyTurn);
        currentTurn = historyTurn;
      }
    }

    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: currentTurn,
      raw: map,
    );
  }

  /// 从 thread/read 的 turn payload 中宽容提取 token 用量。
  ///
  /// 支持两种结构：
  /// - `tokenUsage`: { inputTokens, cachedInputTokens, outputTokens, ... }
  /// - `token_usage` / `total_token_usage` 嵌套 snake_case 字段。
  /// 两者都缺时返回 null。
  AgentTokenUsage? _tokenUsageFromTurnPayload(Map<String, Object?> turn) {
    final direct = _map(turn['tokenUsage']);
    final nested = direct.isNotEmpty ? direct : _map(turn['token_usage']);
    final total = nested.isNotEmpty ? nested : _map(turn['total_token_usage']);
    if (total.isEmpty) {
      return null;
    }
    final last = _map(turn['last_token_usage']);
    return AgentTokenUsage(
      inputTokens:
          _numberToInt(total['input_tokens']) ??
          _numberToInt(total['inputTokens']),
      cachedInputTokens:
          _numberToInt(total['cached_input_tokens']) ??
          _numberToInt(total['cachedInputTokens']),
      outputTokens:
          _numberToInt(total['output_tokens']) ??
          _numberToInt(total['outputTokens']),
      reasoningOutputTokens:
          _numberToInt(total['reasoning_output_tokens']) ??
          _numberToInt(total['reasoningOutputTokens']),
      totalTokens:
          _numberToInt(total['total_tokens']) ??
          _numberToInt(total['totalTokens']),
      lastInputTokens: _numberToInt(last['input_tokens']),
      lastCachedInputTokens: _numberToInt(last['cached_input_tokens']),
      lastOutputTokens: _numberToInt(last['output_tokens']),
      lastReasoningOutputTokens: _numberToInt(last['reasoning_output_tokens']),
      lastTotalTokens: _numberToInt(last['total_tokens']),
    );
  }

  /// 从实时 token_count 通知的 params 中提取 token 用量。
  ///
  /// Codex app-server 推送 `turn/tokenCount` 时，params 形如：
  /// ```
  /// { "turnId": "...", "info": { "total_token_usage": {...}, "last_token_usage": {...} } }
  /// ```
  /// 也兼容直接把 `info` 字段铺平到 params 的情况。
  AgentTokenUsage? _tokenUsageFromNotification(Map<String, Object?> params) {
    final info = _map(params['info']);
    final effectiveInfo = info.isEmpty ? params : info;
    final total = _map(effectiveInfo['total_token_usage']);
    final last = _map(effectiveInfo['last_token_usage']);
    if (total.isEmpty && last.isEmpty) {
      return null;
    }
    return AgentTokenUsage(
      inputTokens: _numberToInt(total['input_tokens']),
      cachedInputTokens: _numberToInt(total['cached_input_tokens']),
      outputTokens: _numberToInt(total['output_tokens']),
      reasoningOutputTokens: _numberToInt(total['reasoning_output_tokens']),
      totalTokens: _numberToInt(total['total_tokens']),
      lastInputTokens: _numberToInt(last['input_tokens']),
      lastCachedInputTokens: _numberToInt(last['cached_input_tokens']),
      lastOutputTokens: _numberToInt(last['output_tokens']),
      lastReasoningOutputTokens: _numberToInt(last['reasoning_output_tokens']),
      lastTotalTokens: _numberToInt(last['total_tokens']),
    );
  }

  /// 优先从本地 session `jsonl` 恢复时间线。
  Future<AgentThreadHistorySnapshot?> _threadHistoryFromSessionFile(
    String threadId,
    String? sessionPath,
  ) async {
    final path = sessionPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }

    final file = File(path);
    if (!await file.exists()) {
      _log.fine('Session file missing for thread $threadId: $path');
      return null;
    }

    final parser = _JsonlHistoryParser(
      fallbackThreadId: threadId,
      sessionPath: path,
    );

    try {
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        parser.consumeLine(line);
      }
    } on FileSystemException catch (error, stackTrace) {
      _log.warning(
        'Could not read Codex session file for thread $threadId: $path',
        error,
        stackTrace,
      );
      return null;
    }

    final snapshot = parser.build();
    if (snapshot.entries.isEmpty && snapshot.turnsById.isEmpty) {
      _log.fine('Session file had no displayable history for thread $threadId');
      return null;
    }
    return snapshot;
  }

  /// 将 Codex ThreadItem 映射成历史消息或工具卡片。
  ///
  /// 根据 item 的 type 字段分发到不同的映射逻辑：
  /// - userMessage / agentMessage / plan -> _historyMessage（文本消息）
  /// - reasoning -> AgentToolCall（思考步骤）
  /// - commandExecution -> AgentToolCall（命令执行卡片）
  /// - fileChange -> AgentToolCall（文件变更卡片）
  /// - mcpToolCall / dynamicToolCall -> AgentToolCall（MCP/动态工具调用卡片）
  /// - 其他类型返回 null（不展示）
  AgentHistoryEntry? _historyEntryFromItem(
    Object? value, {
    required String turnId,
  }) {
    final item = _map(value);
    final type = _string(item['type']);
    final normalizedType = _normalizedAgentItemType(type);
    final id = _string(item['id']) ?? '$turnId-${type ?? 'item'}';

    return switch (normalizedType) {
      'usermessage' => _historyMessage(
        id: id,
        role: AgentMessageRole.user,
        text: _userInputText(item['content']),
        raw: item,
      ),
      'agentmessage' => _historyMessage(
        id: id,
        role: AgentMessageRole.agent,
        text: _string(item['text']),
        phase: _messagePhase(_string(item['phase'])),
        status: _messageStatus(_string(item['status'])),
        duration: _messageDuration(item),
        raw: item,
      ),
      'plan' => _historyMessage(
        id: id,
        role: AgentMessageRole.agent,
        text: _string(item['text']),
        status: AgentMessageStatus.completed,
        raw: item,
      ),
      'reasoning' => _historyTool(
        AgentToolCall(
          id: id,
          title: 'Reasoning',
          kind: AgentToolKind.think,
          status: AgentToolStatus.completed,
          content:
              _joinedStrings(item['summary']) ??
              _joinedStrings(item['content']),
          raw: item,
        ),
      ),
      'commandexecution' => _historyTool(
        AgentToolCall(
          id: id,
          title: _string(item['command']) ?? 'Command',
          kind: AgentToolKind.execute,
          status: _historyToolStatus(_string(item['status'])),
          content:
              _string(item['aggregatedOutput']) ?? _string(item['command']),
          locations: _singleLocation(_string(item['cwd'])),
          raw: item,
        ),
      ),
      'filechange' => _historyTool(
        AgentToolCall(
          id: id,
          title: 'File change',
          kind: AgentToolKind.edit,
          status: _historyToolStatus(_string(item['status'])),
          content: _joinedStrings(_fileChangeLocations(item['changes'])),
          locations: _fileChangeLocations(item['changes']),
          raw: item,
        ),
      ),
      'mcptoolcall' => _historyTool(
        AgentToolCall(
          id: id,
          title: _toolPathTitle(
            prefix: 'MCP',
            first: _string(item['server']),
            second: _string(item['tool']),
          ),
          kind: AgentToolKind.other,
          status: _historyToolStatus(_string(item['status'])),
          content:
              _string(_map(item['error'])['message']) ??
              _joinedContentItems(item['result']) ??
              _objectPreview(item['arguments']),
          rawInput: _map(item['arguments']),
          rawOutput: _map(item['result']),
          raw: item,
        ),
      ),
      'dynamictoolcall' => _historyTool(
        AgentToolCall(
          id: id,
          title: _toolPathTitle(
            first: _string(item['namespace']),
            second: _string(item['tool']),
          ),
          kind: AgentToolKind.other,
          status: _historyToolStatus(_string(item['status'])),
          content:
              _joinedContentItems(item['contentItems']) ??
              _objectPreview(item['arguments']),
          rawInput: _map(item['arguments']),
          raw: item,
        ),
      ),
      _ => null,
    };
  }

  /// 创建历史消息条目，空文本或纯空白文本返回 null。
  ///
  /// [phase] 消息阶段（如 commentary/response），[status] 消息状态（如 completed/streaming）。
  AgentHistoryMessageEntry? _historyMessage({
    required String id,
    required AgentMessageRole role,
    required String? text,
    AgentMessagePhase? phase,
    AgentMessageStatus? status,
    Duration? duration,
    required Map<String, Object?> raw,
  }) {
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return AgentHistoryMessageEntry(
      id: id,
      role: role,
      text: trimmed,
      phase: phase,
      status: status,
      duration: duration,
      raw: raw,
    );
  }

  /// 将工具调用对象包装为历史工具条目。
  AgentHistoryToolEntry _historyTool(AgentToolCall toolCall) {
    return AgentHistoryToolEntry(toolCall: toolCall);
  }

  /// 将 Codex Thread 转成项目列表可展示的轻量摘要。
  ///
  /// 从 thread 对象中提取 id、标题、项目路径、会话文件路径、预览文本、
  /// 时间戳和运行时状态。缺少 id 的线程返回 null 以过滤无效数据。
  AgentThreadSummary? _threadSummaryFromThread(
    Object? value,
    String fallbackProjectPath,
  ) {
    final thread = _map(value);
    final id = _string(thread['id']);
    if (id == null) {
      return null;
    }

    final now = DateTime.now();
    return AgentThreadSummary(
      id: id,
      providerId: config.id,
      projectPath: _string(thread['cwd']) ?? fallbackProjectPath,
      title: _string(thread['name']) ?? _string(thread['title']),
      sessionPath: _string(thread['path']),
      preview: _string(thread['preview']) ?? '',
      createdAt: _unixSecondsToDateTime(thread['createdAt']) ?? now,
      updatedAt: _unixSecondsToDateTime(thread['updatedAt']) ?? now,
      recencyAt: _unixSecondsToDateTime(thread['recencyAt']),
      status: _threadRuntimeStatus(_map(thread['status'])),
      raw: thread,
    );
  }

  /// 从 turn/start 响应中提取领域回合。
  ///
  /// 响应中应包含 turn 对象，从中提取 id；若缺少则使用兜底值 'codex-turn'。
  /// [sessionId] 是所属线程的会话 ID。
  AgentTurn _turnFromResult(Object? value, String sessionId) {
    final map = _map(value);
    final turn = _map(map['turn']);
    return AgentTurn(
      id: _string(turn['id']) ?? 'codex-turn',
      sessionId: sessionId,
      raw: map,
    );
  }

  /// 从 turn/started 通知中提取领域回合。
  ///
  /// 通知中包含 turn 对象和 threadId，两者都需有效。
  /// 缺少 id 或 sessionId 时返回 null 表示无效通知。
  AgentTurn? _turnFromNotification(Map<String, Object?> params) {
    final turn = _map(params['turn']);
    final id = _string(turn['id']);
    final sessionId = _string(params['threadId']);
    if (id == null || sessionId == null) {
      return null;
    }
    return AgentTurn(id: id, sessionId: sessionId, raw: params);
  }

  /// 将 Codex 计划结构宽容转换成统一计划条目。
  ///
  /// 兼容 entries 和 plan 两种字段名。每个计划条目提取 content/text、
  /// status（如 completed/inProgress）和 priority（如 high/medium/low）。
  List<AgentPlanEntry> _planEntries(Map<String, Object?> params) {
    final entries = params['entries'] ?? params['plan'];
    if (entries is! List<Object?>) {
      return const <AgentPlanEntry>[];
    }
    return entries.map((item) {
      final map = _map(item);
      return AgentPlanEntry(
        content: _string(map['content']) ?? _string(map['text']) ?? '$item',
        status: _string(map['status']),
        priority: _string(map['priority']),
      );
    }).toList();
  }

  /// 将 item/started 或 item/completed 通知转成工具调用事件。
  ///
  /// 只处理非消息类型的 item；agentMessage 和 plan 由 _messageUpdateFromItemNotification 处理。
  /// 根据通知方法名区分工具状态：item/completed 标记为 completed，item/started 标记为 inProgress。
  AgentToolCall? _toolCallFromItemNotification(
    JsonRpcNotification notification,
  ) {
    final item = _map(notification.params['item']);
    final normalizedType = _normalizedAgentItemType(_string(item['type']));
    if (normalizedType == 'agentmessage' || normalizedType == 'plan') {
      return null;
    }
    final id = _string(item['id']) ?? _string(notification.params['itemId']);
    if (id == null) {
      return null;
    }
    return AgentToolCall(
      id: id,
      title: _toolTitle(item),
      kind: _toolKind(_string(item['kind']) ?? _string(item['type'])),
      status: notification.method == 'item/completed'
          ? AgentToolStatus.completed
          : AgentToolStatus.inProgress,
      content: _string(item['text']) ?? _string(item['command']),
      locations: _locations(item),
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
      rawInput: _map(item['rawInput']),
      rawOutput: _map(item['rawOutput']),
      raw: notification.params,
    );
  }

  /// 将 agentMessage / plan item 的 started/completed 通知转成消息更新事件。
  ///
  /// 与 item/agentMessage/delta（增量文本）不同，此方法处理 item 的 phase/status/duration
  /// 等 metadata 变化。item/completed 标记为 completed 状态，item/started 从通知中提取 status。
  AgentMessageUpdatedEvent? _messageUpdateFromItemNotification(
    JsonRpcNotification notification,
  ) {
    final item = _map(notification.params['item']);
    final type = _string(item['type']) ?? _string(notification.params['type']);
    final normalizedType = _normalizedAgentItemType(type);
    if (normalizedType != 'agentmessage' && normalizedType != 'plan') {
      return null;
    }

    final id = _string(item['id']) ?? _string(notification.params['itemId']);
    if (id == null) {
      return null;
    }

    return AgentMessageUpdatedEvent(
      messageId: id,
      text: _string(item['text']) ?? _string(notification.params['text']),
      role: AgentMessageRole.agent,
      phase: _messagePhase(
        _string(item['phase']) ?? _string(notification.params['phase']),
      ),
      status: notification.method == 'item/completed'
          ? AgentMessageStatus.completed
          : _messageStatus(
              _string(item['status']) ?? _string(notification.params['status']),
            ),
      duration: _messageDuration(item, notification.params),
      raw: notification.params,
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
    );
  }

  /// 将输出/patch 增量通知转成工具调用进度事件。
  ///
  /// 处理以下增量通知类型：
  /// - item/commandExecution/outputDelta / command/exec/outputDelta（命令输出增量）
  /// - item/fileChange/outputDelta / item/fileChange/patchUpdated（文件变更增量）
  /// 这些通知没有完整 item 结构，仅包含 itemId/delta/output/patch 等字段，
  /// 统一转为 AgentToolStatus.inProgress 的 AgentToolCall 供 UI 增量展示。
  AgentToolCall? _toolCallFromProgressNotification(
    JsonRpcNotification notification,
  ) {
    final id =
        _string(notification.params['itemId']) ??
        _string(notification.params['toolCallId']) ??
        notification.method;
    return AgentToolCall(
      id: id,
      title: _progressTitle(notification.method),
      kind: notification.method.contains('fileChange')
          ? AgentToolKind.edit
          : AgentToolKind.execute,
      status: AgentToolStatus.inProgress,
      content:
          _string(notification.params['delta']) ??
          _string(notification.params['output']) ??
          _string(notification.params['patch']),
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
      raw: notification.params,
    );
  }

  /// 根据 Codex 请求类型生成对应审批响应。
  ///
  /// app-server 新旧接口的响应字段略有不同：稳定 item/* 使用 accept/decline，
  /// 旧兼容方法使用 approved/denied。
  /// 对 item/permissions/requestApproval 需要传入允许的权限范围。
  /// [decision.cancelTurn] 为 true 时拒绝并取消当前回合。
  Object? _approvalResponse(
    _PendingApproval pending,
    AgentPermissionDecision decision,
  ) {
    final declined = decision.cancelTurn ? 'cancel' : 'decline';
    final accepted = 'accept';
    return switch (pending.method) {
      'item/commandExecution/requestApproval' => <String, Object?>{
        'decision': decision.approved ? accepted : declined,
      },
      'item/fileChange/requestApproval' => <String, Object?>{
        'decision': decision.approved ? accepted : declined,
      },
      'item/permissions/requestApproval' => <String, Object?>{
        'permissions': decision.approved
            ? pending.params['permissions']
            : <String, Object?>{'fileSystem': null, 'network': null},
        'scope': 'turn',
      },
      'execCommandApproval' => <String, Object?>{
        'decision': decision.approved ? 'approved' : 'denied',
      },
      'applyPatchApproval' => <String, Object?>{
        'decision': decision.approved ? 'approved' : 'denied',
      },
      _ => decision.approved ? <String, Object?>{} : null,
    };
  }

  /// 发出 provider 连接状态事件（如 connecting/ready/running/error）。
  void _emitStatus(AgentProviderStatus status) {
    _events.add(AgentStatusEvent(status));
  }

  /// 发出 unavailable 状态事件和错误事件。
  ///
  /// 用于子进程无法启动的场景，标记 provider 为不可用状态，
  /// 让上层 UI 可以提示用户安装或切换 provider。
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

/// 按 jsonl 日志顺序重建 thread 历史。
///
/// 解析器会宽容跳过坏行或不识别事件；只要能恢复出任何可展示条目，就视为本地恢复
/// 成功，并保持这些条目在原日志中的出现顺序。
///
/// jsonl 格式的每一行是一个 JSON 记录，包含 type 和 payload 字段。
/// 主要处理三种记录类型：
/// - event_msg: 用户消息、Agent 消息、任务开始/完成、工具调用等事件
/// - turn_context: 回合上下文（cwd、model 等）
/// - response_item: 函数调用/工具搜索/Web 搜索等响应项
/// - session_meta: 会话元信息（session_id）
class _JsonlHistoryParser {
  /// 创建 jsonl 历史解析器。
  ///
  /// [fallbackThreadId] 在线程 ID 无法从日志中提取时的兜底值。
  /// [sessionPath] 日志文件的完整路径，仅用于构建 raw 信息中的 source 字段。
  _JsonlHistoryParser({
    required this.fallbackThreadId,
    required this.sessionPath,
  });

  /// 未从日志中提取到线程 ID 时使用的兜底值。
  final String fallbackThreadId;

  /// session jsonl 文件的路径，用于构建快照中的 source 信息。
  final String sessionPath;

  /// 没有 turn_id 的条目归入此合成 turn，id 带上 threadId 避免与真实 turn 冲突。
  late final String _unscopedTurnId = '${fallbackThreadId}__unscoped__';

  /// 从 session_meta 记录中提取的线程 ID，若未找到则使用 fallbackThreadId。
  late String _threadId = fallbackThreadId;

  /// 按解析顺序存储的所有历史条目。
  final List<AgentHistoryEntry> _entries = <AgentHistoryEntry>[];

  /// 每个条目所属的 turn ID，与 _entries 等长且一一对应。
  final List<String?> _entryTurnIds = <String?>[];

  /// 按 turn ID 索引的 turn 构建器，用于收集和管理每个 turn 的 metadata。
  final Map<String, _JsonlTurnBuilder> _turnsById =
      <String, _JsonlTurnBuilder>{};

  /// 工具调用的 call_id 到条目索引的映射。
  ///
  /// 主要用于后续像 patch_apply_end 这类关联事件定位已有工具卡片；
  /// function_call_output / custom_tool_call_output 已不再回填执行结果。
  final Map<String, _JsonlPendingTool> _pendingToolsByCallId =
      <String, _JsonlPendingTool>{};

  /// 历史事件（如搜索、权限请求）的 call_id 到条目索引的映射，
  /// 用于后续关联事件更新内容；tool_search_output 已不再回填搜索结果。
  final Map<String, _JsonlPendingHistoryEvent> _pendingEventsByCallId =
      <String, _JsonlPendingHistoryEvent>{};

  /// 当前正在处理的 turn ID，由 _turnIdFromRecord 从记录中提取。
  String? _currentTurnId;

  /// 当前处理的行号，用于生成兜底条目 ID。
  int _lineNumber = 0;

  /// 消费一行 jsonl 日志，解析并记录其中的事件。
  ///
  /// 宽容处理：跳过空行、非 JSON 行、空 payload 的记录。
  /// 根据 recordType 分发到对应的消费方法：
  /// - session_meta -> _consumeSessionMeta
  /// - event_msg -> _consumeEventMessage
  /// - turn_context -> _consumeTurnContext
  /// - response_item -> _consumeResponseItem
  void consumeLine(String line) {
    _lineNumber += 1;
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return;
    }

    final record = _map(decoded);
    if (record.isEmpty) {
      return;
    }

    final recordType = _string(record['type']);
    final payload = _map(record['payload']);
    if (recordType == 'session_meta') {
      _consumeSessionMeta(payload);
      return;
    }
    if (payload.isEmpty) {
      return;
    }

    final turnId = _turnIdFromRecord(record, payload);
    if (turnId != null) {
      _currentTurnId = turnId;
      _ensureTurn(turnId);
    }

    switch (recordType) {
      case 'event_msg':
        _consumeEventMessage(payload, raw: record);
        return;
      case 'turn_context':
        _consumeTurnContext(payload, raw: record);
        return;
      case 'response_item':
        _consumeResponseItem(payload, raw: record);
        return;
      case _:
        return;
    }
  }

  /// 构建解析完成的历史时间线快照。
  ///
  /// 将所有已解析的条目按 turnId 分组，使用 _turnsById 中的 turn builder
  /// 完成每个 turn 的构建，最终返回包含所有 turns 的完整快照。
  /// 最后一个被处理的 turn 标记为 currentTurn。
  AgentThreadHistorySnapshot build() {
    final groupedEntriesByTurnId = <String, List<AgentHistoryEntry>>{};
    for (var index = 0; index < _entries.length; index += 1) {
      final turnId = _entryTurnIds[index];
      if (turnId == null) {
        continue;
      }
      groupedEntriesByTurnId
          .putIfAbsent(turnId, () => <AgentHistoryEntry>[])
          .add(_entries[index]);
    }

    final turns = <AgentHistoryTurn>[];
    for (final builder in _turnsById.values) {
      turns.add(
        builder.build(
          groupedEntriesByTurnId[builder.id] ?? const <AgentHistoryEntry>[],
        ),
      );
    }

    AgentHistoryTurn? currentTurn;
    final currentTurnId = _currentTurnId;
    if (currentTurnId != null) {
      for (final turn in turns) {
        if (turn.id == currentTurnId) {
          currentTurn = turn;
          break;
        }
      }
    }

    return AgentThreadHistorySnapshot(
      threadId: _threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: currentTurn,
      raw: <String, Object?>{
        'source': 'sessionFile',
        'sessionPath': sessionPath,
        'turnIds': turns.map((turn) => turn.id).toList(),
      },
    );
  }

  /// 消费 session_meta 记录，提取线程 ID（session_id / id）。
  void _consumeSessionMeta(Map<String, Object?> payload) {
    final sessionId = _string(payload['session_id']) ?? _string(payload['id']);
    if (sessionId != null) {
      _threadId = sessionId;
    }
  }

  /// 消费 event_msg 记录，根据 payload 中的 type 分发到对应的消费方法。
  ///
  /// 处理的事件类型：
  /// - task_started / task_complete: 回合开始/完成 metadata
  /// - user_message / agent_message: 用户/Agent 文本消息
  /// - patch_apply_end: 补丁应用结果
  /// - mcp_tool_call_end: MCP 工具调用结果
  /// - web_search_end: Web 搜索结果
  /// - 其他: 尝试按特殊 payload 生成历史事件条目
  void _consumeEventMessage(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final type = _string(payload['type']);
    switch (type) {
      case 'task_started':
        _consumeTaskStarted(payload, raw: raw);
        return;
      case 'task_complete':
        _consumeTaskComplete(payload, raw: raw);
        return;
      case 'user_message':
        final text = _trimmedText(_jsonlUserMessageText(payload));
        if (text == null) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(payload['client_id']) ?? _nextHistoryId('history-user'),
            role: AgentMessageRole.user,
            text: text,
            raw: raw,
          ),
        );
        return;
      case 'agent_message':
        final text = _trimmedText(_string(payload['message']));
        if (text == null) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(payload['id']) ?? _nextHistoryId('history-agent'),
            role: AgentMessageRole.agent,
            text: text,
            phase: _messagePhase(_string(payload['phase'])),
            status: AgentMessageStatus.completed,
            raw: raw,
          ),
        );
        return;
      case 'patch_apply_end':
        _consumePatchApplyEnd(payload, raw: raw);
        return;
      case 'mcp_tool_call_end':
        _consumeMcpToolCallEnd(payload, raw: raw);
        return;
      case 'web_search_end':
        return;
      case 'token_count':
        _consumeTokenCount(payload, raw: raw);
        return;
      case 'item_completed':
        _consumeCompletedItem(payload, raw: raw);
        return;
      default:
        final historyEvent = _historyEventFromSpecialPayload(
          type: type,
          raw: raw,
          id: _nextHistoryId('history-event'),
        );
        if (historyEvent != null) {
          _appendEntry(historyEvent);
        }
        return;
    }
  }

  /// 消费 jsonl 中的 item_completed 事件。
  ///
  /// 当前只把 `Plan` 项恢复成历史消息，避免与已记录的工具调用重复。
  void _consumeCompletedItem(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final item = _map(payload['item']);
    if (_normalizedAgentItemType(_string(item['type'])) != 'plan') {
      return;
    }
    final text = _trimmedText(_string(item['text']));
    if (text == null) {
      return;
    }
    _appendEntry(
      AgentHistoryMessageEntry(
        id: _string(item['id']) ?? _nextHistoryId('history-plan'),
        role: AgentMessageRole.agent,
        text: text,
        status: AgentMessageStatus.completed,
        raw: raw,
      ),
    );
  }

  /// 消费 task_started 事件，更新当前回合的状态为 running，
  /// 并记录开始时间、model context window 和协作模式。
  void _consumeTaskStarted(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.running
      ..startedAt =
          _dateTimeFromAny(payload['started_at']) ??
          _dateTimeFromAny(raw['timestamp']) ??
          turn.startedAt
      ..modelContextWindow =
          _numberToInt(payload['model_context_window']) ??
          turn.modelContextWindow
      ..collaborationMode =
          _string(payload['collaboration_mode_kind']) ?? turn.collaborationMode;
    turn.raw['taskStarted'] = payload;
  }

  /// 消费 task_complete 事件，更新当前回合的状态为 completed，
  /// 并记录完成时间、耗时和首 token 到达时间。
  void _consumeTaskComplete(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.completed
      ..completedAt =
          _dateTimeFromAny(payload['completed_at']) ??
          _dateTimeFromAny(raw['timestamp']) ??
          turn.completedAt
      ..duration =
          _durationFromMilliseconds(payload['duration_ms']) ?? turn.duration
      ..timeToFirstToken =
          _durationFromMilliseconds(payload['time_to_first_token_ms']) ??
          turn.timeToFirstToken;
    turn.raw['taskComplete'] = payload;
  }

  /// 消费 turn_context 记录，更新当前回合的 cwd、model、窗口大小和协作模式。
  void _consumeTurnContext(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..cwd = _string(payload['cwd']) ?? turn.cwd
      ..model = _string(payload['model']) ?? turn.model
      ..effort = _string(payload['effort']) ?? turn.effort
      ..modelContextWindow =
          _numberToInt(payload['model_context_window']) ??
          turn.modelContextWindow
      ..collaborationMode =
          _string(payload['collaboration_mode']) ?? turn.collaborationMode;
    turn.raw['turnContext'] = payload;
  }

  /// 消费 token_count 事件，把累计/最近一次 token 用量记录到当前 turn。
  ///
  /// payload 结构：
  /// ```
  /// { "type": "token_count", "info": {
  ///   "total_token_usage": { input, cached_input, output, reasoning_output, total },
  ///   "last_token_usage":  { ... },
  ///   "model_context_window": int
  /// }, "rate_limits": { ... } }
  /// ```
  /// UI 据此在回合分隔线展示 token 成本。
  void _consumeTokenCount(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    final info = _map(payload['info']);
    final totalUsage = _map(info['total_token_usage']);
    final lastUsage = _map(info['last_token_usage']);
    final modelContextWindow = _numberToInt(info['model_context_window']);
    turn.tokenUsage = AgentTokenUsage(
      inputTokens: _numberToInt(totalUsage['input_tokens']),
      cachedInputTokens: _numberToInt(totalUsage['cached_input_tokens']),
      outputTokens: _numberToInt(totalUsage['output_tokens']),
      reasoningOutputTokens: _numberToInt(
        totalUsage['reasoning_output_tokens'],
      ),
      totalTokens: _numberToInt(totalUsage['total_tokens']),
      lastInputTokens: _numberToInt(lastUsage['input_tokens']),
      lastCachedInputTokens: _numberToInt(lastUsage['cached_input_tokens']),
      lastOutputTokens: _numberToInt(lastUsage['output_tokens']),
      lastReasoningOutputTokens: _numberToInt(
        lastUsage['reasoning_output_tokens'],
      ),
      lastTotalTokens: _numberToInt(lastUsage['total_tokens']),
    );
    if (modelContextWindow != null) {
      turn.modelContextWindow = modelContextWindow;
    }
    turn.raw['tokenCount'] = payload;
  }

  /// 消费 response_item 记录，根据 payload 中的 type 分发到对应的消费方法。
  ///
  /// 处理的响应类型：
  /// - function_call / custom_tool_call: 记录工具调用本身
  /// - function_call_output / custom_tool_call_output / tool_search_output:
  ///   默认忽略执行结果；仅 request_user_input 的 output 会回填回答
  /// - tool_search_call: 记录工具搜索请求
  /// - web_search_call: Web 搜索查询
  /// - message / reasoning / token_count: 忽略（不需要展示的中间信息）
  /// - 其他: 尝试按特殊 payload 生成历史事件条目
  void _consumeResponseItem(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final type = _string(payload['type']);
    switch (type) {
      case 'function_call':
        _consumeFunctionCall(payload, raw: raw);
        return;
      case 'function_call_output':
        _consumeFunctionCallOutput(payload, raw: raw);
        return;
      case 'custom_tool_call':
        _consumeCustomToolCall(payload, raw: raw);
        return;
      case 'custom_tool_call_output':
        _consumeCustomToolCallOutput(payload);
        return;
      case 'tool_search_call':
        _consumeToolSearchCall(payload, raw: raw);
        return;
      case 'tool_search_output':
        _consumeToolSearchOutput(payload);
        return;
      case 'web_search_call':
        _consumeWebSearchCall(payload, raw: raw);
        return;
      case 'message':
      case 'reasoning':
      case 'token_count':
        return;
      default:
        final historyEvent = _historyEventFromSpecialPayload(
          type: type,
          raw: raw,
          id: _nextHistoryId('history-event'),
        );
        if (historyEvent != null) {
          _appendEntry(historyEvent);
        }
        return;
    }
  }

  /// 消费 function_call 响应项，将工具调用转成历史工具条目。
  ///
  /// 特殊处理 request_user_input 和 request_permissions 两种权限类工具名，
  /// 将其转为 AgentHistoryEventKind.permission 事件。
  /// 其他工具调用转为 AgentToolCall，并保留调用时的标题、内容和路径信息。
  void _consumeFunctionCall(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final name = _string(payload['name']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('tool-call');
    final arguments = _decodedObjectMap(payload['arguments']);

    if (_isPermissionHistoryToolName(name)) {
      /// 权限类调用（request_user_input / request_permissions）转成历史事件条目，
      /// 而不是工具卡片，以便 UI 渲染问答对或权限描述。
      final event = _permissionEventFromToolInvocation(
        id: 'permission-$callId',
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
        raw: raw,
      );
      final index = _appendEntry(event);
      _pendingEventsByCallId[callId] = _JsonlPendingHistoryEvent(index: index);
      return;
    }

    /// 普通工具调用直接创建工具卡片，执行结果事件不再回填内容。
    /// 仍保留 call_id 到条目索引的映射，供后续关联事件（如 patch_apply_end）复用。
    final toolCall = AgentToolCall(
      id: callId,
      title: _jsonlToolTitle(
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      kind: _jsonlToolKind(name),
      status: AgentToolStatus.completed,
      content: _jsonlToolInvocationContent(
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      locations: _jsonlToolLocations(
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      rawInput: _jsonlRawInputMap(
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      raw: raw,
    );
    final index = _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
    _pendingToolsByCallId[callId] = _JsonlPendingTool(index: index);
  }

  /// 消费 function_call_output 响应项。
  ///
  /// 默认仍忽略大部分工具输出，只对 request_user_input 的回答做回填，
  /// 这样时间线里的问答列表可以展示用户实际选择，而不是占位符。
  void _consumeFunctionCallOutput(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final callId = _responseCallId(payload);
    if (callId == null) {
      return;
    }

    final pending = _pendingEventsByCallId[callId];
    if (pending == null) {
      return;
    }

    final entry = _entries[pending.index];
    if (entry is! AgentHistoryEventEntry) {
      return;
    }

    final currentQaPairs = entry.qaPairs;
    if (currentQaPairs == null || currentQaPairs.isEmpty) {
      return;
    }

    final answersByQuestionId = _userInputAnswersByQuestionId(
      payload['output'],
    );
    if (answersByQuestionId.isEmpty) {
      return;
    }

    final updatedQaPairs = _mergeUserInputQaPairsWithAnswers(
      currentQaPairs,
      answersByQuestionId,
    );
    if (_sameUserInputQaPairs(updatedQaPairs, currentQaPairs)) {
      return;
    }

    _entries[pending.index] = AgentHistoryEventEntry(
      id: entry.id,
      kind: entry.kind,
      title: entry.title,
      description: entry.description,
      content: entry.content,
      qaPairs: updatedQaPairs,
      raw: entry.raw.isEmpty
          ? raw
          : <String, Object?>{...entry.raw, 'functionCallOutput': raw},
    );
  }

  /// 消费 custom_tool_call 响应项，记录自定义工具调用的初始状态。
  ///
  /// 与 function_call 类似但使用 payload 中的 status 字段决定初始状态，
  /// input 字段作为调用参数。
  void _consumeCustomToolCall(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final name = _string(payload['name']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('tool-call');
    final stringInput = _string(payload['input']);
    final arguments = _decodedObjectMap(payload['input']);
    final toolCall = AgentToolCall(
      id: callId,
      title: _jsonlToolTitle(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      kind: _jsonlToolKind(name),
      status: _historyToolStatus(_string(payload['status'])),
      content: _jsonlToolInvocationContent(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      locations: _jsonlToolLocations(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      rawInput: _jsonlRawInputMap(
        arguments: arguments,
        stringInput: stringInput,
      ),
      raw: raw,
    );
    final index = _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
    _pendingToolsByCallId[callId] = _JsonlPendingTool(index: index);
  }

  /// 消费 custom_tool_call_output 响应项。
  ///
  /// 本地历史只展示工具调用本身，不再处理执行结果。
  void _consumeCustomToolCallOutput(Map<String, Object?> _) {}

  /// 消费 patch_apply_end 事件，记录补丁应用的结果。
  ///
  /// 优先更新已有的待处理工具条目（通过 call_id 匹配），
  /// 若找不到则创建一个新的工具卡片。根据 success 字段决定状态。
  void _consumePatchApplyEnd(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final callId = _string(payload['call_id']);
    final locations = _patchApplyLocations(payload['changes']);
    final content =
        _patchApplySummary(
          locations,
          stdout: _string(payload['stdout']),
          stderr: _string(payload['stderr']),
        ) ??
        _jsonlToolOutputPreview(_string(payload['stdout'])) ??
        _jsonlToolOutputPreview(_string(payload['stderr']));

    if (callId != null && _pendingToolsByCallId.containsKey(callId)) {
      _updatePendingTool(
        callId,
        title: 'Apply patch',
        kind: AgentToolKind.edit,
        status: payload['success'] == false
            ? AgentToolStatus.failed
            : AgentToolStatus.completed,
        content: content,
        locations: locations,
        rawOutput: payload,
        raw: raw,
      );
      return;
    }

    final toolCall = AgentToolCall(
      id: callId ?? _nextHistoryId('patch'),
      title: 'Apply patch',
      kind: AgentToolKind.edit,
      status: payload['success'] == false
          ? AgentToolStatus.failed
          : AgentToolStatus.completed,
      content: content,
      locations: locations,
      rawOutput: payload,
      raw: raw,
    );
    _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
  }

  /// 消费 mcp_tool_call_end 事件，记录 MCP 工具调用结果。
  ///
  /// 从 invocation 中提取服务端名称和工具名称构建标题，
  /// 根据 result 判断是否出错（调用失败）。
  void _consumeMcpToolCallEnd(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final invocation = _map(payload['invocation']);
    final arguments = _map(invocation['arguments']);
    final result = _mcpResultMap(payload['result']);
    final toolName = _string(invocation['tool']);
    final toolCall = AgentToolCall(
      id: _string(payload['call_id']) ?? _nextHistoryId('mcp'),
      title: _toolPathTitle(
        prefix: 'MCP',
        first: _string(invocation['server']),
        second: toolName,
      ),
      kind: _jsonlToolKind(toolName),
      status: _mcpResultIsError(result)
          ? AgentToolStatus.failed
          : AgentToolStatus.completed,
      content:
          _mcpResultPreview(result) ??
          _jsonlToolInvocationContent(name: toolName, arguments: arguments),
      locations: _jsonlToolLocations(name: toolName, arguments: arguments),
      rawInput: arguments,
      rawOutput: result,
      raw: raw,
    );
    _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
  }

  /// 消费 tool_search_call 响应项，记录工具搜索调用事件。
  ///
  /// 创建 AgentHistoryEventKind.search 事件条目，携带搜索查询参数。
  void _consumeToolSearchCall(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final arguments = _map(payload['arguments']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('search');
    final query = _trimmedText(_string(arguments['query']));
    final entry = AgentHistoryEventEntry(
      id: 'search-$callId',
      kind: AgentHistoryEventKind.search,
      title: 'Tool search',
      description: query,
      content: _toolSearchQueryPreview(arguments),
      raw: raw,
    );
    final index = _appendEntry(entry);
    _pendingEventsByCallId[callId] = _JsonlPendingHistoryEvent(index: index);
  }

  /// 消费 tool_search_output 响应项。
  ///
  /// 本地历史只展示搜索请求本身，不再处理搜索结果列表。
  void _consumeToolSearchOutput(Map<String, Object?> _) {}

  /// 消费 web_search_call 响应项，记录 Web 搜索调用事件。
  ///
  /// 创建 AgentHistoryEventKind.search 事件条目，携带搜索查询和 action 参数。
  void _consumeWebSearchCall(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final callId = _responseCallId(payload) ?? _nextHistoryId('search');
    final action = _map(payload['action']);
    final entry = AgentHistoryEventEntry(
      id: 'search-$callId',
      kind: AgentHistoryEventKind.search,
      title: 'Web search',
      description:
          _trimmedText(_string(action['query'])) ??
          _trimmedText(_string(payload['query'])),
      content: _webSearchQueryPreview(action),
      raw: raw,
    );
    final index = _appendEntry(entry);
    _pendingEventsByCallId[callId] = _JsonlPendingHistoryEvent(index: index);
  }

  /// 从工具调用中创建权限请求类型的历史事件条目。
  ///
  /// request_user_input 事件携带结构化问答对（qaPairs），UI 据此渲染"问题/回答"样式。
  /// request_permissions 事件包含权限申请原因和范围说明。
  AgentHistoryEventEntry _permissionEventFromToolInvocation({
    required String id,
    required String? name,
    required Map<String, Object?> arguments,
    required String? stringInput,
    required Map<String, Object?> raw,
  }) {
    return AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.permission,
      title: switch (name) {
        'request_user_input' => 'Requested user input',
        'request_permissions' => 'Requested permissions',
        _ => 'Permission request',
      },
      description: _permissionEventDescription(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      content: _permissionEventContent(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),

      /// request_user_input 携带结构化问答对，UI 据此渲染“问题/回答”样式。
      qaPairs: name == 'request_user_input'
          ? _userInputQaPairs(arguments)
          : null,
      raw: raw,
    );
  }

  /// 从特殊事件通知中创建历史事件条目。
  ///
  /// 根据类型名智能分类：
  /// - warning/guardian -> AgentHistoryEventKind.warning
  /// - system/notice/error -> AgentHistoryEventKind.system
  /// 类型名通过 _humanizeIdentifier 转换为 UI 友好的显示文字。
  /// 无法识别的类型返回 null。
  AgentHistoryEventEntry? _historyEventFromSpecialPayload({
    required String? type,
    required Map<String, Object?> raw,
    required String id,
  }) {
    final payload = _map(raw['payload']);
    final normalizedType = type?.toLowerCase();
    if (normalizedType == null || normalizedType.isEmpty) {
      return null;
    }

    final message =
        _trimmedText(_string(payload['message'])) ??
        _trimmedText(_string(payload['title'])) ??
        _trimmedText(_string(payload['description']));
    final content = _specialEventContent(payload);

    if (normalizedType.contains('warning') ||
        normalizedType.contains('guardian')) {
      return AgentHistoryEventEntry(
        id: id,
        kind: AgentHistoryEventKind.warning,
        title: _humanizeIdentifier(type!),
        description: message,
        content: content,
        raw: raw,
      );
    }

    if (normalizedType.contains('system') ||
        normalizedType.contains('notice') ||
        normalizedType.contains('error')) {
      return AgentHistoryEventEntry(
        id: id,
        kind: AgentHistoryEventKind.system,
        title: _humanizeIdentifier(type!),
        description: message,
        content: content,
        raw: raw,
      );
    }

    return null;
  }

  /// 追加一个历史条目到列表，并将其关联到当前 turn。
  ///
  /// 没有显式 turn_id 的记录（通常是 turn_context 之前的早期事件）归入一个
  /// 合成的 unscoped turn，避免在以 turn 集合为返回结构时丢失这些条目。
  /// 返回该条目在列表中的索引，供后续更新使用。
  int _appendEntry(AgentHistoryEntry entry) {
    final turnId = _currentTurnId ?? _unscopedTurnId;
    _entries.add(entry);
    _entryTurnIds.add(turnId);
    _ensureTurn(turnId);
    return _entries.length - 1;
  }

  /// 更新指定 call_id 的待处理工具调用的属性。
  ///
  /// 通过 call_id 在 _pendingToolsByCallId 中找到条目索引，
  /// 然后用新值替换旧值（只替换有提供的字段），实现工具卡片的增量更新。
  void _updatePendingTool(
    String callId, {
    String? title,
    AgentToolKind? kind,
    AgentToolStatus? status,
    String? content,
    List<String>? locations,
    Map<String, Object?>? rawInput,
    Map<String, Object?>? rawOutput,
    Map<String, Object?>? raw,
  }) {
    final pending = _pendingToolsByCallId[callId];
    if (pending == null) {
      return;
    }

    final entry = _entries[pending.index];
    if (entry is! AgentHistoryToolEntry) {
      return;
    }

    final current = entry.toolCall;
    _entries[pending.index] = AgentHistoryToolEntry(
      toolCall: AgentToolCall(
        id: current.id,
        title: title ?? current.title,
        kind: kind ?? current.kind,
        status: status ?? current.status,
        content: content ?? current.content,
        locations: locations ?? current.locations,
        rawInput: rawInput ?? current.rawInput,
        rawOutput: rawOutput ?? current.rawOutput,
        raw: raw ?? current.raw,
      ),
    );
  }

  /// 生成一个基于行号的 ID，用于没有显式 ID 的条目。
  String _nextHistoryId(String prefix) => '$prefix-$_lineNumber';

  /// 确保指定 turnId 的 turn builder 已存在并返回。
  _JsonlTurnBuilder _ensureTurn(String turnId) {
    return _turnsById.putIfAbsent(turnId, () => _JsonlTurnBuilder(turnId));
  }

  /// 获取当前正在处理的 turn builder，若无当前 turn 则返回 null。
  _JsonlTurnBuilder? _currentTurn() {
    final turnId = _currentTurnId;
    if (turnId == null) {
      return null;
    }
    return _ensureTurn(turnId);
  }
}

/// 从 jsonl 记录及其 payload 中提取 turn_id。
///
/// 优先使用 payload 中的 turn_id 字段，其次尝试从
/// internal_chat_message_metadata_passthrough 嵌入数据中提取。
String? _turnIdFromRecord(
  Map<String, Object?> record,
  Map<String, Object?> payload,
) {
  return _string(payload['turn_id']) ??
      _string(
        _map(payload['internal_chat_message_metadata_passthrough'])['turn_id'],
      ) ??
      _string(
        _map(record['internal_chat_message_metadata_passthrough'])['turn_id'],
      );
}

/// 用于在 jsonl 解析过程中累积一个 turn 的 metadata，最后构建出 AgentHistoryTurn。
class _JsonlTurnBuilder {
  _JsonlTurnBuilder(this.id);

  /// turn ID，对应 Codex 线程中的唯一标识。
  final String id;

  /// 回合运行状态，由 task_started/task_complete 事件更新。
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.unknown;

  /// 回合开始时间，来自 task_started 的 started_at 字段。
  DateTime? startedAt;

  /// 回合完成时间，来自 task_complete 的 completed_at 字段。
  DateTime? completedAt;

  /// 回合总耗时，来自 task_complete 的 duration_ms 字段。
  Duration? duration;

  /// 首 token 到达时间，来自 task_complete 的 time_to_first_token_ms 字段。
  Duration? timeToFirstToken;

  /// 回合的工作目录，来自 turn_context 记录的 cwd 字段。
  String? cwd;

  /// 回合使用的模型名称，来自 turn_context 记录的 model 字段。
  String? model;

  String? effort;

  /// 模型的 context window 大小（token 数）。
  int? modelContextWindow;

  /// 协作模式，如 'normal' / 'pair' / 'review'。
  String? collaborationMode;

  /// 该 turn 的 token 消耗统计，由 token_count 事件更新。
  AgentTokenUsage? tokenUsage;

  /// 原始数据缓存，包含 taskStarted、taskComplete、turnContext 等原始记录。
  final Map<String, Object?> raw = <String, Object?>{};

  /// 使用累积的 metadata 构建 AgentHistoryTurn 对象。
  ///
  /// [entries] 是该 turn 下所有历史条目列表。
  /// 若状态为 unknown 但已有 completedAt，则自动推断为 completed。
  AgentHistoryTurn build(List<AgentHistoryEntry> entries) {
    final effectiveStatus =
        status == AgentHistoryTurnStatus.unknown && completedAt != null
        ? AgentHistoryTurnStatus.completed
        : status;
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(entries),
      status: effectiveStatus,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      timeToFirstToken: timeToFirstToken,
      cwd: cwd,
      model: model,
      modelContextWindow: modelContextWindow,
      collaborationMode: collaborationMode,
      tokenUsage: tokenUsage,
      raw: Map<String, Object?>.unmodifiable(raw),
    );
  }
}

/// 一个已创建但后续可能还有关联事件的工具调用。
///
/// 保存工具调用在 _entries 列表中的索引，供 patch_apply_end 之类的事件
/// 定位并更新已有工具卡片。
class _JsonlPendingTool {
  const _JsonlPendingTool({required this.index});

  /// 工具条目在 _entries 列表中的索引。
  final int index;
}

/// 一个可能被后续关联事件更新的历史事件（如搜索、权限请求等）。
class _JsonlPendingHistoryEvent {
  const _JsonlPendingHistoryEvent({required this.index});

  /// 事件条目在 _entries 列表中的索引。
  final int index;
}

/// 一个尚未回复的 app-server 审批请求。
///
/// 保存原始 JSON-RPC 请求的 id、方法名和参数，
/// 用户决策后通过同 requestId 回写响应到服务端。
class _PendingApproval {
  const _PendingApproval({
    required this.requestId,
    required this.method,
    required this.params,
  });

  /// JSON-RPC 请求的原始 id，用于回写响应时定位。
  final Object requestId;

  /// 审批方法名，如 item/commandExecution/requestApproval。
  final String method;

  /// 审批请求的原始参数，包含命令、文件变更等上下文信息。
  final Map<String, Object?> params;
}

/// 默认通过 stdio 启动 Codex app-server 子进程。
///
/// 使用 JsonRpcStdioTransport 创建 JSON-RPC 对等体，
/// 从 config 中读取命令、参数和环境变量来启动子进程。
JsonRpcPeer _defaultPeerFactory(AgentProviderConfig config) {
  return JsonRpcStdioTransport(
    command: config.command,
    arguments: config.arguments,
    environment: config.environment,
  );
}

/// 宽容读取 map。
Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return result;
  }
  return const <String, Object?>{};
}

/// 非空字符串读取。
String? _string(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

/// 本地 MCP 软件未启动时，Codex/mrmcp 会持续向 stderr 写 transport worker
/// 断开日志；这类日志不影响 thread 本身，避免刷进用户可见的 Agent 时间线。
bool _isIgnorableMcpTransportStderr(String line) {
  if (!line.contains('mrmcp::transport::worker')) {
    return false;
  }
  if (!line.contains('127.0.0.1')) {
    return false;
  }
  return line.contains('Transport channel closed') ||
      line.contains('http/request failed') ||
      line.contains('/stream') ||
      line.contains('/mcp');
}

/// 从 Codex item 中挑选最适合 UI 展示的标题。
String _toolTitle(Map<String, Object?> item) {
  return _string(item['title']) ??
      _string(item['name']) ??
      _string(item['command']) ??
      _string(item['type']) ??
      'Tool call';
}

/// 根据进度通知方法名生成标题。
String _progressTitle(String method) {
  if (method.contains('fileChange')) {
    return 'File change';
  }
  if (method.contains('command')) {
    return 'Command output';
  }
  return 'Tool progress';
}

/// 将 Codex 工具类型映射到统一工具分类。
AgentToolKind _toolKind(String? value) {
  return switch (value) {
    'read' => AgentToolKind.read,
    'edit' => AgentToolKind.edit,
    'delete' => AgentToolKind.delete,
    'move' => AgentToolKind.move,
    'search' => AgentToolKind.search,
    'execute' ||
    'command_execution' ||
    'commandExecution' => AgentToolKind.execute,
    'think' || 'reasoning' => AgentToolKind.think,
    'fetch' => AgentToolKind.fetch,
    _ => AgentToolKind.other,
  };
}

/// 从 item 中提取文件位置。
List<String> _locations(Map<String, Object?> item) {
  final locations = item['locations'];
  if (locations is! List<Object?>) {
    return const <String>[];
  }
  return locations.map((location) {
    if (location is String) {
      return location;
    }
    final map = _map(location);
    return _string(map['path']) ?? '$location';
  }).toList();
}

/// 将用户输入数组转成历史消息文本。
String? _userInputText(Object? value) {
  if (value is! List<Object?>) {
    return _string(value);
  }

  final parts = <String>[];
  for (final itemValue in value) {
    final item = _map(itemValue);
    final type = _string(item['type']);
    switch (type) {
      case 'text':
        final text = _string(item['text']);
        if (text != null) {
          parts.add(text);
        }
      case 'image':
        final url = _string(item['url']);
        parts.add(url == null ? '[Image]' : '[Image: $url]');
      case 'localImage':
        final path = _string(item['path']);
        parts.add(path == null ? '[Image]' : '[Image: $path]');
      case 'skill':
      case 'mention':
        final name = _string(item['name']) ?? _string(item['id']);
        if (name != null) {
          parts.add('@$name');
        }
      default:
        final text = _string(item['text']) ?? _string(item['content']);
        if (text != null) {
          parts.add(text);
        }
    }
  }

  return parts.isEmpty ? null : parts.join('\n');
}

/// 宽容拼接字符串数组。
String? _joinedStrings(Object? value) {
  if (value is List<String>) {
    final parts = value.where((item) => item.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('\n');
  }
  if (value is List<Object?>) {
    final parts = value
        .map(_string)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join('\n');
  }
  return _string(value);
}

/// 从工具返回内容里挑选一段适合卡片预览的文本。
String? _joinedContentItems(Object? value) {
  final map = _map(value);
  final content = map.isEmpty ? value : map['content'];
  if (content is List<Object?>) {
    final parts = <String>[];
    for (final itemValue in content) {
      if (itemValue is String) {
        parts.add(itemValue);
        continue;
      }
      final item = _map(itemValue);
      final text = _string(item['text']) ?? _string(item['content']);
      if (text != null) {
        parts.add(text);
      }
    }
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return _string(content) ?? _string(map['text']);
}

/// 根据 Codex 历史 item 状态映射工具状态。
AgentToolStatus _historyToolStatus(String? status) {
  return switch (status) {
    'inProgress' || 'running' => AgentToolStatus.inProgress,
    'failed' || 'error' => AgentToolStatus.failed,
    'declined' || 'cancelled' || 'canceled' => AgentToolStatus.cancelled,
    'pending' => AgentToolStatus.pending,
    _ => AgentToolStatus.completed,
  };
}

/// 将单个路径字符串包装为列表，用于工具卡片的位置展示。
List<String> _singleLocation(String? location) {
  return location == null ? const <String>[] : <String>[location];
}

/// 从 Codex item 的 changes 中提取受影响的文件路径列表。
List<String> _fileChangeLocations(Object? value) {
  if (value is! List<Object?>) {
    return const <String>[];
  }
  return value
      .map((item) {
        if (item is String) {
          return item;
        }
        return _string(_map(item)['path']);
      })
      .whereType<String>()
      .toList();
}

/// 拼接工具调用的路径式标题，如 "MCP: serverName: toolName" 或 "namespace: toolName"。
String _toolPathTitle({String? prefix, String? first, String? second}) {
  final parts = <String>[?prefix, ?first, ?second];
  return parts.isEmpty ? 'Tool call' : parts.join(': ');
}

/// 去除字符串首尾空白，空字符串或 null 返回 null。
String? _trimmedText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

/// 将任意对象转为适合 UI 预览的短文本。
///
/// null/空 map/空 list 返回 null，字符串原样返回，其他对象调用 toString。
String? _objectPreview(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map && value.isEmpty) {
    return null;
  }
  if (value is List && value.isEmpty) {
    return null;
  }
  if (value is String) {
    return _string(value);
  }
  return '$value';
}

/// 尝试将字符串值解析为 JSON，失败则返回原始字符串。
Object? _decodedJsonValue(Object? value) {
  if (value is! String) {
    return value;
  }
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

/// 将值尝试作为 JSON 解析后再转为 map，常用于处理双重编码的参数。
Map<String, Object?> _decodedObjectMap(Object? value) {
  return _map(_decodedJsonValue(value));
}

/// 从 payload 中提取响应 call_id，兼容 call_id 和 id 两种字段名。
String? _responseCallId(Map<String, Object?> payload) {
  return _string(payload['call_id']) ?? _string(payload['id']);
}

String? _jsonlUserMessageText(Map<String, Object?> payload) {
  final parts = <String>[];
  final message = _trimmedText(_string(payload['message']));
  if (message != null) {
    parts.add(message);
  }

  final textElements = payload['text_elements'];
  if (textElements is List<Object?>) {
    for (final itemValue in textElements) {
      final item = _map(itemValue);
      final text = _trimmedText(
        _string(item['text']) ?? _string(item['content']),
      );
      if (text != null && !parts.contains(text)) {
        parts.add(text);
      }
    }
  }

  final images = payload['images'];
  if (images is List<Object?> && images.isNotEmpty) {
    parts.add('[Images: ${images.length}]');
  }

  final localImages = payload['local_images'];
  if (localImages is List<Object?> && localImages.isNotEmpty) {
    parts.add('[Local images: ${localImages.length}]');
  }

  return parts.isEmpty ? null : parts.join('\n');
}

/// 判断工具调用名是否为权限类（用户输入或权限申请），需要特殊的历史事件渲染。
bool _isPermissionHistoryToolName(String? name) {
  return switch (name) {
    'request_user_input' || 'request_permissions' => true,
    _ => false,
  };
}

/// 根据 jsonl 历史中的工具名称映射到统一工具分类。
///
/// 覆盖 jsonl 特有的工具名（exec_command、apply_patch、tool_search_tool 等），
/// 未知名称回退到 _toolKind 通用映射。
AgentToolKind _jsonlToolKind(String? name) {
  return switch (name) {
    'exec_command' => AgentToolKind.execute,
    'apply_patch' => AgentToolKind.edit,
    'read_mcp_resource' ||
    'read_package_uris' ||
    'open' ||
    'find' => AgentToolKind.read,
    'rip_grep_packages' ||
    'tool_search_tool' ||
    'search_query' ||
    'image_query' => AgentToolKind.search,
    'web_search' || 'web.run' => AgentToolKind.search,
    'request_user_input' => AgentToolKind.other,
    _ => _toolKind(name),
  };
}

/// 根据 jsonl 历史中的工具名称和参数生成 UI 友好的工具卡片标题。
///
/// exec_command 从 arguments['cmd'] 提取命令文本，
/// apply_patch 固定标题为 "Apply patch"，
/// 其他名称通过 _humanizeIdentifier 转换为可读文字。
String _jsonlToolTitle({
  required String? name,
  Map<String, Object?> arguments = const <String, Object?>{},
  String? stringInput,
}) {
  if (name == 'exec_command') {
    return _trimmedText(_string(arguments['cmd'])) ?? 'Run command';
  }
  if (name == 'apply_patch') {
    return 'Apply patch';
  }
  if (name == null || name.isEmpty) {
    return 'Tool call';
  }
  return _humanizeIdentifier(name);
}

/// 根据 jsonl 历史中的工具名称和参数生成工具卡片的内容预览。
///
/// exec_command 显示命令本身，apply_patch 显示受影响文件路径，
/// 其他工具显示参数预览或原始输入字符串。
String? _jsonlToolInvocationContent({
  required String? name,
  Map<String, Object?> arguments = const <String, Object?>{},
  String? stringInput,
}) {
  if (name == 'exec_command') {
    return _trimmedText(_string(arguments['cmd']));
  }
  if (name == 'apply_patch') {
    final paths = _patchPathsFromText(stringInput);
    return paths.isEmpty ? 'Patch prepared' : paths.join('\n');
  }
  return _trimmedText(_objectPreview(arguments)) ?? _trimmedText(stringInput);
}

/// 从工具调用参数中构建用于保存的 rawInput map。
///
/// 优先使用解析后的 arguments map，若为空则使用原始字符串。
Map<String, Object?> _jsonlRawInputMap({
  required Map<String, Object?> arguments,
  String? stringInput,
}) {
  if (arguments.isNotEmpty) {
    return arguments;
  }
  if (stringInput == null || stringInput.isEmpty) {
    return const <String, Object?>{};
  }
  return <String, Object?>{'input': stringInput};
}

/// 从 jsonl 历史工具调用参数中提取相关的文件/目录路径列表。
///
/// 检查 path、cwd、workdir、uri、uris 等字段，
/// apply_patch 额外从 patch 文本中解析文件路径。
List<String> _jsonlToolLocations({
  required String? name,
  Map<String, Object?> arguments = const <String, Object?>{},
  String? stringInput,
}) {
  final locations = <String>{};

  void addString(Object? value) {
    final text = _string(value);
    if (text != null) {
      locations.add(text);
    }
  }

  addString(arguments['path']);
  addString(arguments['cwd']);
  addString(arguments['workdir']);
  addString(arguments['uri']);

  final uris = arguments['uris'];
  if (uris is List<Object?>) {
    for (final uri in uris) {
      addString(uri);
    }
  }

  if (name == 'apply_patch') {
    locations.addAll(_patchPathsFromText(stringInput));
  }

  return locations.toList();
}

String? _jsonlToolOutputPreview(String? output) {
  final trimmed = _trimmedText(output);
  if (trimmed == null) {
    return null;
  }

  final marker = '\nOutput:\n';
  final markerIndex = trimmed.indexOf(marker);
  if (markerIndex != -1) {
    return _trimmedText(trimmed.substring(markerIndex + marker.length)) ??
        trimmed;
  }

  return trimmed;
}

List<String> _patchPathsFromText(String? patchText) {
  if (patchText == null || patchText.isEmpty) {
    return const <String>[];
  }

  final paths = <String>{};
  final lineExp = RegExp(r'^\*\*\* (?:Add|Delete|Update) File: (.+)$');
  final moveExp = RegExp(r'^\*\*\* Move to: (.+)$');

  for (final line in const LineSplitter().convert(patchText)) {
    final match = lineExp.firstMatch(line);
    if (match != null) {
      paths.add(match.group(1)!);
      continue;
    }
    final moveMatch = moveExp.firstMatch(line);
    if (moveMatch != null) {
      paths.add(moveMatch.group(1)!);
    }
  }

  return paths.toList();
}

List<String> _patchApplyLocations(Object? value) {
  if (value is Map) {
    return value.keys
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toList();
  }
  return _fileChangeLocations(value);
}

String? _patchApplySummary(
  List<String> locations, {
  String? stdout,
  String? stderr,
}) {
  if (locations.isNotEmpty) {
    return locations.join('\n');
  }
  return _jsonlToolOutputPreview(stdout) ?? _jsonlToolOutputPreview(stderr);
}

Map<String, Object?> _mcpResultMap(Object? value) {
  final map = _map(value);
  if (map.containsKey('Ok')) {
    return _map(map['Ok']);
  }
  if (map.containsKey('Err')) {
    return _map(map['Err']);
  }
  return map;
}

/// 判断 MCP 工具调用结果是否包含错误（isError 标记或 error 字段）。
bool _mcpResultIsError(Map<String, Object?> result) {
  return result['isError'] == true || _string(result['error']) != null;
}

String? _mcpResultPreview(Map<String, Object?> result) {
  final content = result['content'];
  if (content is List<Object?>) {
    final parts = <String>[];
    for (final itemValue in content) {
      final item = _map(itemValue);
      final text = _trimmedText(
        _string(item['text']) ?? _string(item['content']),
      );
      if (text != null) {
        parts.add(text);
      }
    }
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return _trimmedText(_string(result['text'])) ??
      _trimmedText(_string(result['message']));
}

String? _toolSearchQueryPreview(Map<String, Object?> arguments) {
  final query = _trimmedText(_string(arguments['query']));
  final limit = arguments['limit'];
  if (query == null) {
    return null;
  }
  return limit == null ? query : '$query\nlimit=$limit';
}

String? _webSearchQueryPreview(Map<String, Object?> action) {
  final queries = action['queries'];
  if (queries is List<Object?>) {
    final values = queries
        .map(_string)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (values.isNotEmpty) {
      return values.join('\n');
    }
  }
  return _trimmedText(_string(action['query']));
}

String? _permissionEventDescription({
  required String? name,
  required Map<String, Object?> arguments,
  String? stringInput,
}) {
  if (name == 'request_user_input') {
    final questions = arguments['questions'];
    if (questions is List<Object?> && questions.isNotEmpty) {
      final first = _map(questions.first);
      return _trimmedText(_string(first['question'])) ??
          _trimmedText(_string(first['header']));
    }
  }
  return _trimmedText(_string(arguments['reason'])) ??
      _trimmedText(stringInput);
}

String? _permissionEventContent({
  required String? name,
  required Map<String, Object?> arguments,
  String? stringInput,
}) {
  if (name == 'request_user_input') {
    final questions = arguments['questions'];
    if (questions is! List<Object?> || questions.isEmpty) {
      return null;
    }
    final parts = <String>[];
    for (final questionValue in questions) {
      final question = _map(questionValue);
      final header = _trimmedText(_string(question['header']));
      final text = _trimmedText(_string(question['question']));
      final options = question['options'];
      final optionLabels = <String>[];
      if (options is List<Object?>) {
        for (final optionValue in options) {
          final option = _map(optionValue);
          final label = _trimmedText(_string(option['label']));
          if (label != null) {
            optionLabels.add(label);
          }
        }
      }

      final buffer = StringBuffer();
      if (header != null) {
        buffer.write(header);
      }
      if (text != null) {
        if (buffer.length > 0) {
          buffer.write(': ');
        }
        buffer.write(text);
      }
      if (optionLabels.isNotEmpty) {
        if (buffer.length > 0) {
          buffer.write('\n');
        }
        buffer.write(optionLabels.join(', '));
      }
      final line = _trimmedText(buffer.toString());
      if (line != null) {
        parts.add(line);
      }
    }
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  if (arguments.isNotEmpty) {
    return _trimmedText(_objectPreview(arguments));
  }
  return _trimmedText(stringInput);
}

/// 从 `request_user_input` 的 arguments 中解析结构化问答对。
///
/// 先保留问题与选项；若后续收到 function_call_output，会再回填答案。
List<AgentUserInputQaPair> _userInputQaPairs(Map<String, Object?> arguments) {
  final questions = arguments['questions'];
  if (questions is! List<Object?>) {
    return const <AgentUserInputQaPair>[];
  }
  final pairs = <AgentUserInputQaPair>[];
  for (final questionValue in questions) {
    final question = _map(questionValue);
    final id =
        _trimmedText(_string(question['id'])) ??
        _trimmedText(_string(question['header'])) ??
        '';
    final header = _trimmedText(_string(question['header']));
    final text = _trimmedText(_string(question['question'])) ?? header ?? id;
    final options = <String>[];
    final opts = question['options'];
    if (opts is List<Object?>) {
      for (final optionValue in opts) {
        final option = _map(optionValue);
        final label = _trimmedText(_string(option['label']));
        if (label != null) {
          options.add(label);
        }
      }
    }
    if (text.isEmpty) {
      continue;
    }
    pairs.add(
      AgentUserInputQaPair(
        questionId: id,
        question: text,
        header: header,
        options: List<String>.unmodifiable(options),
      ),
    );
  }
  return List<AgentUserInputQaPair>.unmodifiable(pairs);
}

/// 从 `request_user_input` 的 output 中提取“问题 id -> 已选答案标签”的映射。
Map<String, List<String>> _userInputAnswersByQuestionId(Object? output) {
  final decoded = _decodedObjectMap(output);
  final rawAnswers = _map(decoded['answers']);
  final source = rawAnswers.isNotEmpty ? rawAnswers : decoded;
  if (source.isEmpty) {
    return const <String, List<String>>{};
  }

  final answersByQuestionId = <String, List<String>>{};
  for (final entry in source.entries) {
    final questionId = _trimmedText(entry.key);
    if (questionId == null) {
      continue;
    }
    final answers = _userInputAnswerLabels(entry.value);
    if (answers.isEmpty) {
      continue;
    }
    answersByQuestionId[questionId] = List<String>.unmodifiable(answers);
  }
  return Map<String, List<String>>.unmodifiable(answersByQuestionId);
}

/// 宽容提取单个问题的答案标签，兼容 string / list / {answers: [...]} 等结构。
List<String> _userInputAnswerLabels(Object? value) {
  if (value is List<Object?>) {
    return value
        .map(_string)
        .whereType<String>()
        .map(_trimmedText)
        .whereType<String>()
        .toList();
  }

  final map = _map(value);
  if (map.isNotEmpty) {
    final nestedAnswers = _userInputAnswerLabels(map['answers']);
    if (nestedAnswers.isNotEmpty) {
      return nestedAnswers;
    }

    final answer = _trimmedText(
      _string(map['answer']) ?? _string(map['label']) ?? _string(map['value']),
    );
    if (answer != null) {
      return <String>[answer];
    }
  }

  final text = _trimmedText(_string(value));
  return text == null ? const <String>[] : <String>[text];
}

/// 将已解析出的答案回填到对应问题上；未命中的问题保持原样。
List<AgentUserInputQaPair> _mergeUserInputQaPairsWithAnswers(
  List<AgentUserInputQaPair> qaPairs,
  Map<String, List<String>> answersByQuestionId,
) {
  return List<AgentUserInputQaPair>.unmodifiable(
    qaPairs.map((pair) {
      final answers = answersByQuestionId[pair.questionId];
      if (answers == null) {
        return pair;
      }
      return AgentUserInputQaPair(
        questionId: pair.questionId,
        question: pair.question,
        header: pair.header,
        options: pair.options,
        answers: answers,
      );
    }),
  );
}

/// 比较问答列表是否发生了可见变化，避免无意义替换条目。
bool _sameUserInputQaPairs(
  List<AgentUserInputQaPair> left,
  List<AgentUserInputQaPair> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final a = left[index];
    final b = right[index];
    if (a.questionId != b.questionId ||
        a.question != b.question ||
        a.header != b.header) {
      return false;
    }
    if (a.options.length != b.options.length ||
        a.answers.length != b.answers.length) {
      return false;
    }
    for (
      var optionIndex = 0;
      optionIndex < a.options.length;
      optionIndex += 1
    ) {
      if (a.options[optionIndex] != b.options[optionIndex]) {
        return false;
      }
    }
    for (
      var answerIndex = 0;
      answerIndex < a.answers.length;
      answerIndex += 1
    ) {
      if (a.answers[answerIndex] != b.answers[answerIndex]) {
        return false;
      }
    }
  }
  return true;
}

String? _specialEventContent(Map<String, Object?> payload) {
  final content = _trimmedText(
    _string(payload['content']) ??
        _string(payload['details']) ??
        _string(payload['query']),
  );
  if (content != null) {
    return content;
  }

  final action = _map(payload['action']);
  if (action.isNotEmpty) {
    return _webSearchQueryPreview(action) ??
        _trimmedText(_objectPreview(action));
  }

  return null;
}

/// 将标识符（如 snake_case 或 kebab-case）转换为 UI 友好的标题文字。
///
/// 例如: "request_user_input" -> "Request User Input"，"guardianWarning" -> "Guardian Warning"。
String _humanizeIdentifier(String value) {
  final cleaned = value.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (cleaned.isEmpty) {
    return value;
  }
  return cleaned
      .split(RegExp(r'\s+'))
      .map((part) {
        if (part.isEmpty) {
          return part;
        }
        return '${part[0].toUpperCase()}${part.substring(1)}';
      })
      .join(' ');
}

/// 将 provider 原始消息 phase 映射到领域枚举。
AgentMessagePhase? _messagePhase(String? phase) {
  return switch (phase) {
    'commentary' || 'commetary' => AgentMessagePhase.commentary,
    'response' || 'answer' || 'final' => AgentMessagePhase.response,
    null => null,
    _ => AgentMessagePhase.other,
  };
}

String? _normalizedAgentItemType(String? type) {
  final trimmed = type?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
}

/// 将 provider 原始消息状态映射到领域枚举。
AgentMessageStatus? _messageStatus(String? status) {
  return switch (status) {
    'completed' || 'complete' || 'done' => AgentMessageStatus.completed,
    'streaming' ||
    'inProgress' ||
    'running' ||
    'started' => AgentMessageStatus.streaming,
    null => null,
    _ => AgentMessageStatus.other,
  };
}

/// 从 Codex item/通知中提取或计算消息耗时。
///
/// 优先使用显式的 durationMs/elapsedMs 字段，其次通过 startedAtMs 和
/// completedAtMs 的差值计算。无效值返回 null。
Duration? _messageDuration(
  Map<String, Object?> item, [
  Map<String, Object?> notification = const <String, Object?>{},
]) {
  final explicitMs =
      _numberToInt(item['durationMs']) ??
      _numberToInt(notification['durationMs']) ??
      _numberToInt(item['elapsedMs']) ??
      _numberToInt(notification['elapsedMs']);
  if (explicitMs != null && explicitMs >= 0) {
    return Duration(milliseconds: explicitMs);
  }

  final startedAtMs =
      _numberToInt(item['startedAtMs']) ??
      _numberToInt(notification['startedAtMs']);
  final completedAtMs =
      _numberToInt(item['completedAtMs']) ??
      _numberToInt(notification['completedAtMs']);
  if (startedAtMs == null || completedAtMs == null) {
    return null;
  }

  final elapsedMs = completedAtMs - startedAtMs;
  return elapsedMs < 0 ? null : Duration(milliseconds: elapsedMs);
}

/// 宽容地将值转为整数，支持 int 和 double 类型。
int? _numberToInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  return null;
}

/// 从多种格式中解析 DateTime：ISO 8601 字符串或毫秒时间戳。
DateTime? _dateTimeFromAny(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  final milliseconds = _numberToInt(value);
  if (milliseconds == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

/// 从毫秒值创建 Duration，负值或 null 返回 null。
Duration? _durationFromMilliseconds(Object? value) {
  final milliseconds = _numberToInt(value);
  if (milliseconds == null || milliseconds < 0) {
    return null;
  }
  return Duration(milliseconds: milliseconds);
}

/// 将 Codex 历史回合的状态字符串映射到领域枚举。
///
/// 当 status 为 unknown 但提供了 completedAt 时，推断为 completed。
AgentHistoryTurnStatus _historyTurnStatus(
  String? status, [
  DateTime? completedAt,
]) {
  return switch (status) {
    'completed' || 'complete' || 'done' => AgentHistoryTurnStatus.completed,
    'running' ||
    'started' ||
    'active' ||
    'inProgress' => AgentHistoryTurnStatus.running,
    _ when completedAt != null => AgentHistoryTurnStatus.completed,
    _ => AgentHistoryTurnStatus.unknown,
  };
}

/// Codex thread 时间戳是 Unix 秒。
DateTime? _unixSecondsToDateTime(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
  }
  return null;
}

/// 宽容映射 Codex thread status。
AgentThreadRuntimeStatus _threadRuntimeStatus(Map<String, Object?> status) {
  return switch (_string(status['type'])) {
    'notLoaded' => AgentThreadRuntimeStatus.notLoaded,
    'idle' => AgentThreadRuntimeStatus.idle,
    'active' => AgentThreadRuntimeStatus.active,
    'systemError' => AgentThreadRuntimeStatus.systemError,
    _ => AgentThreadRuntimeStatus.unknown,
  };
}
