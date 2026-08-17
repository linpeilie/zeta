part of 'codex_app_server_agent_provider.dart';

/// 封装 Codex app-server 的 JSON-RPC 请求与响应解码。
class _CodexAppServerClient {
  _CodexAppServerClient({
    required this._peer,
    required this._config,
    required this._modelListMapper,
    required this._collaborationModeMapper,
    required this._skillsMapper,
    required this._turnStartParamsEncoder,
    required this._threadHistoryReader,
    required this._configPermissionFallback,
    required this._textCatalog,
  });

  final JsonRpcPeer _peer;
  final AgentProviderConfig _config;
  final _CodexModelListMapper _modelListMapper;
  final _CodexCollaborationModeMapper _collaborationModeMapper;
  final _CodexSkillsMapper _skillsMapper;
  final _CodexTurnStartParamsEncoder _turnStartParamsEncoder;
  final _CodexThreadHistoryReader _threadHistoryReader;
  final CodexPermissionRuntimeSnapshot _configPermissionFallback;
  final AgentUiTextCatalog _textCatalog;

  Future<AgentModelList> fetchModelList({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    final models = <AgentModelInfo>[];
    final seenModelIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    do {
      final result = await _peer.sendRequest(
        'model/list',
        params: <String, Object?>{
          'limit': limit,
          'includeHidden': includeHidden,
          'cursor': ?cursor,
        },
      );
      final page = _modelListMapper.modelListFromResult(result);
      for (final model in page.models) {
        if (seenModelIds.add(model.id)) {
          models.add(model);
        }
      }
      final nextCursor = page.nextCursor;
      if (nextCursor == null ||
          nextCursor.isEmpty ||
          !seenCursors.add(nextCursor)) {
        cursor = null;
      } else {
        cursor = nextCursor;
      }
    } while (cursor != null);
    return AgentModelList(models: List<AgentModelInfo>.unmodifiable(models));
  }

  Future<AgentConversationModeCatalog> fetchCollaborationModeCatalog() async {
    final result = await _peer.sendRequest(
      'collaborationMode/list',
      params: const <String, Object?>{},
    );
    final mapping = _collaborationModeMapper.catalogFromResult(result);
    if (mapping.invalidEntryCount > 0 || mapping.duplicateEntryCount > 0) {
      _log.t(
        'Normalized Codex collaboration mode catalog '
        '(invalid=${mapping.invalidEntryCount}, '
        'duplicates=${mapping.duplicateEntryCount})',
      );
    }
    return mapping.catalog;
  }

  Future<AgentSkillsCatalog> fetchSkillsCatalog({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  }) async {
    final result = await _peer.sendRequest(
      'skills/list',
      params: <String, Object?>{
        if (cwds.isNotEmpty) 'cwds': cwds,
        'forceReload': forceReload,
      },
    );
    final mapping = _skillsMapper.catalogFromResult(result);
    if (mapping.invalidEntryCount > 0 || mapping.droppedSkillCount > 0) {
      _log.t(
        'Normalized Codex skills catalog '
        '(invalid=${mapping.invalidEntryCount}, '
        'dropped=${mapping.droppedSkillCount})',
      );
    }
    return mapping.catalog;
  }

  Future<AgentSession> startSession({
    required AgentContext context,
    required AgentPermissionRequestSnapshot permissionSnapshot,
    String? previousSessionId,
  }) async {
    final result = await _peer.sendRequest(
      'thread/start',
      params: _threadParams(context, permissionSnapshot),
    );
    return _sessionFromThreadStartResult(
      result,
      previousSessionId: previousSessionId,
    );
  }

  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    required AgentPermissionRequestSnapshot permissionSnapshot,
    String? previousSessionId,
  }) async {
    final result = await _peer.sendRequest(
      'thread/resume',
      params: <String, Object?>{
        'threadId': sessionId,
        ..._threadParams(context, permissionSnapshot),
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
    final searchTerm = query.searchTerm?.trim();
    final result = await _peer.sendRequest(
      'thread/list',
      params: <String, Object?>{
        'cwd': ?query.projectPath,
        'limit': query.limit,
        if (query.cursor != null) 'cursor': query.cursor,
        'sortKey': 'updated_at',
        'sortDirection': 'desc',
        'archived': query.archived,
        if (query.sourceKinds.isNotEmpty) 'sourceKinds': query.sourceKinds,
        if (searchTerm != null && searchTerm.isNotEmpty)
          'searchTerm': searchTerm,
      },
    );
    return _threadPageFromResult(result, query.projectPath ?? '');
  }

  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    final result = await _peer.sendRequest(
      'account/rateLimits/read',
      params: const <String, Object?>{},
    );
    final response = _map(result);
    final rateLimits = _map(response['rateLimits']);
    final resetCredits = _map(response['rateLimitResetCredits']);
    final rawResetCreditCount = _numberToInt(resetCredits['availableCount']);
    final availableResetCreditCount =
        rawResetCreditCount != null && rawResetCreditCount >= 0
        ? rawResetCreditCount
        : null;

    final limitName = _string(rateLimits['limitName']);
    final windows = <AgentUsageWindow>[];
    _appendUsageWindow(
      windows,
      value: rateLimits['primary'],
      fallbackLabel: limitName ?? _textCatalog.primaryQuotaLabel,
    );
    _appendUsageWindow(
      windows,
      value: rateLimits['secondary'],
      fallbackLabel: _textCatalog.extraQuotaLabel,
    );
    final creditsMap = _map(rateLimits['credits']);
    final credits = creditsMap.isEmpty
        ? null
        : AgentUsageCredits(
            hasCredits: creditsMap['hasCredits'] == true,
            unlimited: creditsMap['unlimited'] == true,
            balance: _string(creditsMap['balance']),
          );
    if (windows.isEmpty &&
        credits == null &&
        availableResetCreditCount == null) {
      return null;
    }
    return AgentUsageQuotaSnapshot(
      providerId: _config.id,
      providerName: _config.displayName,
      planType: _string(rateLimits['planType']),
      limitName: limitName,
      windows: List<AgentUsageWindow>.unmodifiable(windows),
      credits: credits,
      availableResetCreditCount: availableResetCreditCount,
      reachedReason: _string(rateLimits['rateLimitReachedType']),
    );
  }

  void _appendUsageWindow(
    List<AgentUsageWindow> target, {
    required Object? value,
    required String fallbackLabel,
  }) {
    final window = _map(value);
    final usedPercent = _numberToInt(window['usedPercent']);
    if (usedPercent == null) {
      return;
    }
    final resetsAtSeconds = _numberToInt(window['resetsAt']);
    final durationMinutes = _numberToInt(window['windowDurationMins']);
    target.add(
      AgentUsageWindow(
        // 优先用 windowDurationMins 生成可读时长；缺失时回退 limitName / 默认文案。
        label:
            formatAgentUsageWindowLabelFromMinutes(durationMinutes) ??
            fallbackLabel,
        usedPercent: usedPercent.clamp(0, 100),
        resetsAt: resetsAtSeconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                resetsAtSeconds * Duration.millisecondsPerSecond,
                isUtc: true,
              ).toLocal(),
        windowDuration: durationMinutes == null
            ? null
            : Duration(minutes: durationMinutes),
      ),
    );
  }

  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    final localHistory = await _threadHistoryReader
        .threadHistoryFromSessionFile(threadId, sessionPath);

    // 本地 JSONL 优先（内容更完整），但 error 通知通常不落盘；
    // 再 best-effort 读 thread/read，把 failed + error 叠到对应 turn。
    Object? remoteResult;
    try {
      remoteResult = await _peer.sendRequest(
        'thread/read',
        params: <String, Object?>{'threadId': threadId, 'includeTurns': true},
      );
    } catch (error, stackTrace) {
      if (localHistory != null) {
        _log.t(
          'thread/read failed while enriching local history for $threadId; '
          'keeping session-file snapshot',
          error: error,
          stackTrace: stackTrace,
        );
        return localHistory;
      }
      rethrow;
    }

    final remoteHistory = _threadHistoryReader.threadHistoryFromReadResult(
      remoteResult,
      threadId,
    );
    if (localHistory == null) {
      return remoteHistory;
    }
    return _threadHistoryReader.mergeRemoteTurnFailures(
      local: localHistory,
      remote: remoteHistory,
    );
  }

  /// 取消 thread 通知订阅；返回协议 status（未加载/未订阅/已取消）。
  Future<String?> unsubscribeThread(String threadId) async {
    final result = await _peer.sendRequest(
      'thread/unsubscribe',
      params: <String, Object?>{'threadId': threadId},
    );
    return _string(_map(result)['status']);
  }

  Future<void> renameThread({required String threadId, required String name}) {
    return _peer.sendRequest(
      'thread/name/set',
      params: <String, Object?>{'threadId': threadId, 'name': name},
    );
  }

  Future<void> archiveThread(String threadId) {
    return _peer.sendRequest(
      'thread/archive',
      params: <String, Object?>{'threadId': threadId},
    );
  }

  Future<void> unarchiveThread(String threadId) {
    return _peer.sendRequest(
      'thread/unarchive',
      params: <String, Object?>{'threadId': threadId},
    );
  }

  Future<void> deleteThread(String threadId) {
    return _peer.sendRequest(
      'thread/delete',
      params: <String, Object?>{'threadId': threadId},
    );
  }

  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    required AgentForkBoundary boundary,
    required AgentPermissionRequestSnapshot permissionSnapshot,
    String? previousSessionId,
  }) async {
    final result = await _peer.sendRequest(
      'thread/fork',
      params: <String, Object?>{
        'threadId': threadId,
        if (boundary case AgentForkThroughTurn(:final turnId))
          'lastTurnId': turnId,
        ..._threadParams(context, permissionSnapshot),
      },
    );
    return _sessionFromThreadStartResult(
      result,
      previousSessionId: previousSessionId,
    );
  }

  Future<void> compactThread(String threadId) {
    return _peer.sendRequest(
      'thread/compact/start',
      params: <String, Object?>{'threadId': threadId},
    );
  }

  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required List<AgentUserInput> inputs,
    required AgentContext context,
    required AgentModelSelection selection,
    required AgentPermissionRequestSnapshot permissionSnapshot,
    required AgentTurnConfiguration turnConfiguration,
    String? clientUserMessageId,
  }) async {
    final result = await _peer.sendRequest(
      'turn/start',
      params: _turnStartParamsEncoder.encode(
        session: session,
        inputs: inputs,
        context: context,
        modelSelection: selection,
        permissionSnapshot: permissionSnapshot,
        configPermissionFallback: _configPermissionFallback,
        turnConfiguration: turnConfiguration,
        clientUserMessageId: clientUserMessageId,
      ),
    );
    return _turnFromResult(result, session.id);
  }

  /// 在启动运行时之前校验回合级模式，保证无效配置不产生 RPC 副作用。
  void validateTurnConfiguration(AgentTurnConfiguration turnConfiguration) {
    _turnStartParamsEncoder.validate(turnConfiguration);
  }

  Future<void> steerTurn({
    required AgentSession session,
    required List<AgentUserInput> inputs,
    required String expectedTurnId,
    String? clientUserMessageId,
  }) {
    return _peer.sendRequest(
      'turn/steer',
      params: <String, Object?>{
        'threadId': session.id,
        'input': _encodeCodexUserInputs(inputs),
        'expectedTurnId': expectedTurnId,
        'clientUserMessageId': ?clientUserMessageId,
      },
    );
  }

  Future<void> cancelTurn(AgentTurn turn) {
    return _peer.sendRequest(
      'turn/interrupt',
      params: <String, Object?>{'threadId': turn.sessionId, 'turnId': turn.id},
    );
  }

  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) {
    return _peer.sendRequest(
      'thread/approveGuardianDeniedAction',
      params: <String, Object?>{'threadId': threadId, 'event': event},
    );
  }

  Map<String, Object?> _threadParams(
    AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot,
  ) {
    return <String, Object?>{
      if (context.projectPath != null) 'cwd': context.projectPath,
      if (_config.defaultModel != null) 'model': _config.defaultModel,
      ...CodexPermissionPolicyCodec.encodeThreadRequestPermissionFields(
        permissionSnapshot,
        configFallback: _configPermissionFallback,
      ),
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
    final statusMap = _map(thread['status']);
    final flags = _threadActiveFlags(statusMap);
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
      status: _threadRuntimeStatus(statusMap),
      waitingOnApproval: flags.waitingOnApproval,
      waitingOnUserInput: flags.waitingOnUserInput,
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
