part of 'codex_app_server_agent_provider.dart';

/// 封装 Codex app-server 的 JSON-RPC 请求与响应解码。
class _CodexAppServerClient {
  _CodexAppServerClient({
    required this._peer,
    required this._config,
    required this._modelListMapper,
    required this._threadHistoryReader,
  });

  final JsonRpcPeer _peer;
  final AgentProviderConfig _config;
  final _CodexModelListMapper _modelListMapper;
  final _CodexThreadHistoryReader _threadHistoryReader;

  Future<AgentModelList> fetchModelList({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    final result = await _peer.sendRequest(
      'model/list',
      params: <String, Object?>{'limit': limit, 'includeHidden': includeHidden},
    );
    return _modelListMapper.modelListFromResult(result);
  }

  Future<AgentSession> startSession({
    required AgentContext context,
    String? previousSessionId,
  }) async {
    final result = await _peer.sendRequest(
      'thread/start',
      params: _threadParams(context),
    );
    return _sessionFromThreadStartResult(
      result,
      previousSessionId: previousSessionId,
    );
  }

  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    String? previousSessionId,
  }) async {
    final result = await _peer.sendRequest(
      'thread/resume',
      params: <String, Object?>{
        'threadId': sessionId,
        ..._threadParams(context),
      },
    );
    return _sessionFromThreadStartResult(
      result,
      fallbackId: sessionId,
      previousSessionId: previousSessionId,
    );
  }

  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
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

  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    final localHistory = await _threadHistoryReader
        .threadHistoryFromSessionFile(threadId, sessionPath);
    if (localHistory != null) {
      return localHistory;
    }

    final result = await _peer.sendRequest(
      'thread/read',
      params: <String, Object?>{
        'threadId': threadId,
        'includeTurns': true,
        'itemsView': 'full',
      },
    );
    return _threadHistoryReader.threadHistoryFromReadResult(result, threadId);
  }

  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
    required AgentModelSelection selection,
  }) async {
    final model = selection.modelId ?? _config.defaultModel;
    final result = await _peer.sendRequest(
      'turn/start',
      params: <String, Object?>{
        'threadId': session.id,
        'input': <Object?>[
          <String, Object?>{'type': 'text', 'text': message},
        ],
        if (context.projectPath != null) 'cwd': context.projectPath,
        'model': ?model,
        // 协议字段名是 `effort`(TurnStartParams），域模型内仍叫
        // reasoningEffort；`summary`（推理摘要模式）暂无 UI 来源，不发送。
        'effort': ?selection.reasoningEffort,
        'serviceTier': ?selection.serviceTierId,
        'approvalPolicy': 'on-request',
      },
    );
    return _turnFromResult(result, session.id);
  }

  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) {
    return _peer.sendRequest(
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

  Future<void> cancelTurn(AgentTurn turn) {
    return _peer.sendRequest(
      'turn/interrupt',
      params: <String, Object?>{'threadId': turn.sessionId, 'turnId': turn.id},
    );
  }

  Map<String, Object?> _threadParams(AgentContext context) {
    return <String, Object?>{
      if (context.projectPath != null) 'cwd': context.projectPath,
      if (_config.defaultModel != null) 'model': _config.defaultModel,
      'approvalPolicy': 'on-request',
    };
  }

  AgentSession _sessionFromThreadStartResult(
    Object? value, {
    String? fallbackId,
    String? previousSessionId,
  }) {
    final map = _map(value);
    final thread = _map(map['thread']);
    final id =
        _string(thread['id']) ??
        fallbackId ??
        previousSessionId ??
        'codex-thread';
    return AgentSession(
      id: id,
      providerId: _config.id,
      title: _string(thread['title']) ?? _string(thread['name']),
      raw: map,
    );
  }

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
      providerId: _config.id,
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

  AgentTurn _turnFromResult(Object? value, String sessionId) {
    final map = _map(value);
    final turn = _map(map['turn']);
    return AgentTurn(
      id: _string(turn['id']) ?? 'codex-turn',
      sessionId: sessionId,
      raw: map,
    );
  }
}
