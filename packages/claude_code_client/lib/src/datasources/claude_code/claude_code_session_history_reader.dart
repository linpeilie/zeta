import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_event_mapper.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:claude_code_client/src/mappers/claude_code_stream_identity.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Runs `Function`.
typedef ClaudeCodeHistoryTurnIdFactory = String Function(
  String sessionId,
  String sourceTurnId,
  int ordinal,
);

/// 一次历史解析的中立事件、快照与无敏感信息 identity 状态。
final class ClaudeCodeHistoryReadResult {
  /// Creates a [ClaudeCodeHistoryReadResult].
  const ClaudeCodeHistoryReadResult({
    required this.events,
    required this.snapshot,
    required this.identitySnapshots,
  });

  /// The `events` value.
  final List<AgentEvent> events;

  /// The `snapshot` value.
  final AgentThreadHistorySnapshot snapshot;

  /// The `identitySnapshots` value.
  final Map<String, ClaudeCodeTurnIdentitySnapshot> identitySnapshots;
}

/// 从 Claude Code 本地历史文件解析出的中立定位信息与历史结果。
///
/// 该对象不携带 session 文件路径；调用方若需要增量缓存，应在自己的 data 层内
/// 单独管理源文件身份，不能把路径放进共享读模型。
final class ClaudeCodeLocalHistoryReadResult {
  /// Creates a [ClaudeCodeLocalHistoryReadResult].
  const ClaudeCodeLocalHistoryReadResult({
    required this.threadId,
    required this.projectPath,
    required this.history,
  });

  /// The `threadId` value.
  final String threadId;

  /// The `projectPath` value.
  final String projectPath;

  /// The `history` value.
  final ClaudeCodeHistoryReadResult history;
}

/// 只读扫描 Claude Code 本地历史目录，生成轻量 thread 摘要。
///
/// reader 只采样每个 JSONL 文件的头尾窗口，不改写 `~/.claude`，也不会把
/// prompt / 回复正文放入 [AgentThreadSummary.raw]。
class ClaudeCodeSessionHistoryReader {
  /// Creates a [ClaudeCodeSessionHistoryReader].
  ClaudeCodeSessionHistoryReader({
    this.claudeHome,
    this.homeResolver,
    this.sampleWindowBytes = 128 * 1024,
    this.sampleLineLimit = 64,
    ClaudeCodeStreamIdentity Function()? historyIdentityFactory,
    ClaudeCodeHistoryTurnIdFactory? historyTurnIdFactory,
    ClaudeCodeHiddenThreadStore? hiddenThreadStore,
    FileSystemEntityType Function(String path)? fileTypeReader,
    Stream<List<int>> Function(File file)? fileStreamReader,
    FileStat Function(File file)? fileStatReader,
    AppLogger? logger,
  }) : assert(sampleWindowBytes > 0, 'sampleWindowBytes must be positive'),
       assert(sampleLineLimit > 0, 'sampleLineLimit must be positive'),
       _historyIdentityFactory =
           historyIdentityFactory ?? ClaudeCodeStreamIdentity.new,
       _historyTurnIdFactory = historyTurnIdFactory ?? _defaultHistoryTurnId,
       _hiddenThreadStore =
           hiddenThreadStore ?? MemoryClaudeCodeHiddenThreadStore(),
       _fileTypeReader = fileTypeReader ?? _defaultFileTypeReader,
       _fileStreamReader = fileStreamReader ?? _defaultFileStreamReader,
       _fileStatReader = fileStatReader ?? _defaultFileStatReader,
       _log = logger ?? loggerFor('zeta.agent.claude_code.history');

  /// 测试可注入的 Claude Code 家目录。
  final String? claudeHome;

  /// 测试可注入的用户 home 解析。
  final String? Function()? homeResolver;

  /// 文件头与文件尾各自最多读取的字节数。
  final int sampleWindowBytes;

  /// 文件头与文件尾各自最多解析的行数。
  final int sampleLineLimit;

  final ClaudeCodeStreamIdentity Function() _historyIdentityFactory;
  final ClaudeCodeHistoryTurnIdFactory _historyTurnIdFactory;
  final ClaudeCodeHiddenThreadStore _hiddenThreadStore;
  final FileSystemEntityType Function(String path) _fileTypeReader;
  final Stream<List<int>> Function(File file) _fileStreamReader;
  final FileStat Function(File file) _fileStatReader;
  final AppLogger _log;
  final Map<String, String> _hiddenKeyByThreadId = <String, String>{};
  Future<void> _hiddenMutationTail = Future<void>.value();

  int _malformedLineCount = 0;

  /// 已跳过的损坏 JSONL 采样行累计数。
  int get malformedLineCount => _malformedLineCount;

  /// 按 Claude Code 现行规则编码绝对工作区路径。
  static String encodeProjectPath(String projectPath) {
    return projectPath.replaceAll(RegExp(r'[\\/:]'), '-');
  }

  /// 隐藏列表中的稳定键；保留 project 作用域，避免不同目录下的 id 冲突。
  static String hiddenThreadKey(String projectPath, String threadId) {
    return '${encodeProjectPath(projectPath)}/$threadId';
  }

  /// 解析 Claude Code 家目录：注入路径优先，否则使用用户 home 下的 `.claude`。
  ///
  /// [environment] 是 Provider 级环境变量覆盖，不是一份完整的进程环境；未覆盖
  /// HOME/USERPROFILE 时必须继续继承系统环境，避免空配置把历史目录降级为相对路径。
  String resolveClaudeHome({Map<String, String>? environment}) {
    final injected = claudeHome?.trim();
    if (injected != null && injected.isNotEmpty) {
      return injected;
    }
    final homeKey = Platform.isWindows ? 'USERPROFILE' : 'HOME';
    final home = _firstNonEmpty(<String?>[
      homeResolver?.call(),
      environment?[homeKey],
      Platform.environment[homeKey],
    ]);
    if (home == null) {
      return '.claude';
    }
    return '$home${Platform.pathSeparator}.claude';
  }

  /// 列出指定项目下的 Claude Code 本地 session 摘要。
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
    required String providerId,
    Map<String, String>? environment,
  }) async {
    final projectPath = query.projectPath?.trim() ?? '';
    if (projectPath.isEmpty || query.archived) {
      return AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }

    final projectDirectory = Directory(
      '${resolveClaudeHome(environment: environment)}'
      '${Platform.pathSeparator}projects'
      '${Platform.pathSeparator}${encodeProjectPath(projectPath)}',
    );
    if (!projectDirectory.existsSync()) {
      return AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }

    final hiddenThreadKeys = await _hiddenThreadStore.load();
    final summaries = <AgentThreadSummary>[];
    await for (final entity in projectDirectory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.jsonl')) {
        continue;
      }
      final summary = await _readSummary(
        file: entity,
        providerId: providerId,
        projectPath: projectPath,
      );
      if (summary != null) {
        final hiddenKey = hiddenThreadKey(projectPath, summary.id);
        _hiddenKeyByThreadId[summary.id] = hiddenKey;
        if (!hiddenThreadKeys.contains(hiddenKey)) {
          summaries.add(summary);
        }
      }
    }

    final searchTerm = query.searchTerm?.trim().toLowerCase();
    final filtered =
        (searchTerm == null || searchTerm.isEmpty
              ? summaries
              : summaries
                    .where(
                      (summary) =>
                          summary.displayName.toLowerCase().contains(
                            searchTerm,
                          ) ||
                          summary.preview.toLowerCase().contains(searchTerm),
                    )
                    .toList(growable: false))
          ..sort((a, b) {
            final aTime = a.recencyAt ?? a.updatedAt;
            final bTime = b.recencyAt ?? b.updatedAt;
            return bTime.compareTo(aTime);
          });

    final limit = query.limit <= 0 ? 50 : query.limit;
    final offset = _parseOffset(query.cursor);
    final page = filtered.skip(offset).take(limit).toList(growable: false);
    final nextOffset = offset + page.length;

    return AgentThreadPage(
      threads: List<AgentThreadSummary>.unmodifiable(page),
      nextCursor: nextOffset < filtered.length ? '$nextOffset' : null,
    );
  }

  /// 把最近一次 list 解析到的 thread 加入 Zeta 自有隐藏列表。
  Future<void> removeThreadFromList(String threadId) {
    final hiddenKey = _hiddenKeyByThreadId[threadId];
    if (hiddenKey == null) {
      throw StateError(
        'Claude Code thread $threadId has no resolved project history key',
      );
    }
    final operation = _hiddenMutationTail.then((_) async {
      final hidden = await _hiddenThreadStore.load();
      if (hidden.add(hiddenKey)) {
        await _hiddenThreadStore.save(hidden);
      }
    });
    _hiddenMutationTail = operation.catchError((Object _) {});
    return operation;
  }

  /// 读取完整历史，并通过独立 identity + mapper + 纯同步 reducer 生成快照。
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    required String providerId,
    required String projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    final result = await readHistoryEvents(
      threadId: threadId,
      providerId: providerId,
      projectPath: projectPath,
      sessionPath: sessionPath,
      environment: environment,
    );
    return result.snapshot;
  }

  /// 读取完整历史事件；供 history/live canonical parity 测试复用。
  Future<ClaudeCodeHistoryReadResult> readHistoryEvents({
    required String threadId,
    required String providerId,
    required String projectPath,
    String? sessionPath,
    Map<String, String>? environment,
    AgentRuntimeScope runtimeScope = const AgentRuntimeScope(
      runtimeId: 'claude-code-history',
      connectionEpoch: 1,
    ),
  }) async {
    final file = await _resolveHistoryFile(
      threadId: threadId,
      projectPath: projectPath,
      sessionPath: sessionPath,
      environment: environment,
    );
    if (file == null) {
      return _emptyHistory(threadId);
    }

    final frames = await _readHistoryFrames(file);
    if (frames == null) {
      return _emptyHistory(threadId);
    }

    return _mapHistoryFrames(
      frames: frames,
      threadId: threadId,
      providerId: providerId,
      projectPath: projectPath,
      runtimeScope: runtimeScope,
    );
  }

  /// 读取 `projects/**.jsonl` 中的一份本地历史，并从帧内恢复 thread/project。
  ///
  /// 这是跨项目派生统计使用的窄只读入口。只接受 Claude home 的 `projects`
  /// 目录内普通 JSONL 文件；不跟随链接，也不返回源路径或消息正文之外的新 raw。
  Future<ClaudeCodeLocalHistoryReadResult?> readLocalHistoryFile({
    required File file,
    required String providerId,
    Map<String, String>? environment,
    AgentRuntimeScope runtimeScope = const AgentRuntimeScope(
      runtimeId: 'claude-code-local-history',
      connectionEpoch: 1,
    ),
  }) async {
    final projectsDirectory = Directory(
      '${resolveClaudeHome(environment: environment)}'
      '${Platform.pathSeparator}projects',
    );
    if (!file.path.toLowerCase().endsWith('.jsonl') ||
        !_isWithinDirectory(file.path, projectsDirectory.path)) {
      return null;
    }
    try {
      if (_fileTypeReader(file.path) != FileSystemEntityType.file) {
        return null;
      }
    } on FileSystemException {
      return null;
    }

    final frames = await _readHistoryFrames(file);
    if (frames == null) {
      return null;
    }
    final threadId = _firstNonEmpty(<String?>[
      for (final frame in frames)
        _string(frame['sessionId']) ?? _string(frame['session_id']),
      _fileStem(file),
    ]);
    if (threadId == null) {
      return null;
    }
    final projectPath = _firstNonEmpty(<String?>[
      for (final frame in frames) _string(frame['cwd']),
      'unknown',
    ])!;
    return ClaudeCodeLocalHistoryReadResult(
      threadId: threadId,
      projectPath: projectPath,
      history: _mapHistoryFrames(
        frames: frames,
        threadId: threadId,
        providerId: providerId,
        projectPath: projectPath,
        runtimeScope: runtimeScope,
      ),
    );
  }

  Future<List<Map<String, Object?>>?> _readHistoryFrames(File file) async {
    final frames = <Map<String, Object?>>[];
    try {
      final lines = _fileStreamReader(file)
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }
        final frame = _tryDecodeObject(trimmed);
        if (frame == null) {
          _malformedLineCount += 1;
          continue;
        }
        frames.add(frame);
      }
      return frames;
    } on FileSystemException {
      return null;
    }
  }

  ClaudeCodeHistoryReadResult _emptyHistory(String threadId) {
    return ClaudeCodeHistoryReadResult(
      events: const <AgentEvent>[],
      snapshot: AgentThreadHistorySnapshot(
        threadId: threadId,
        turns: const <AgentHistoryTurn>[],
      ),
      identitySnapshots: const <String, ClaudeCodeTurnIdentitySnapshot>{},
    );
  }

  Future<File?> _resolveHistoryFile({
    required String threadId,
    required String projectPath,
    required String? sessionPath,
    required Map<String, String>? environment,
  }) async {
    final expected = File(
      '${resolveClaudeHome(environment: environment)}'
      '${Platform.pathSeparator}projects'
      '${Platform.pathSeparator}${encodeProjectPath(projectPath)}'
      '${Platform.pathSeparator}$threadId.jsonl',
    );
    if (expected.existsSync()) {
      return expected;
    }

    final direct = sessionPath?.trim();
    if (direct == null || direct.isEmpty) {
      return null;
    }
    final candidate = File(direct);
    if (_normalizedPath(candidate.path) != _normalizedPath(expected.path)) {
      return null;
    }
    return candidate.existsSync() ? candidate : null;
  }

  ClaudeCodeHistoryReadResult _mapHistoryFrames({
    required List<Map<String, Object?>> frames,
    required String threadId,
    required String providerId,
    required String projectPath,
    required AgentRuntimeScope runtimeScope,
  }) {
    final sessionId = _firstNonEmpty(<String?>[
      for (final frame in frames)
        _string(frame['sessionId']) ?? _string(frame['session_id']),
      threadId,
    ])!;
    final cwd = _firstNonEmpty(<String?>[
      for (final frame in frames) _string(frame['cwd']),
      projectPath,
    ]);
    final initialModel = _firstNonEmpty(<String?>[
      for (final frame in frames) _model(frame),
    ]);
    final identity = _historyIdentityFactory();
    final mapper = ClaudeCodeEventMapper(
      providerId: providerId,
      identity: identity,
      logger: _log,
    );
    final reducer = _ClaudeCodeHistoryEventReducer(threadId: threadId);
    final events = <AgentEvent>[];
    final turnIds = <String>[];
    var turnOrdinal = 0;
    String? activeTurnId;
    DateTime? activeStartedAt;
    DateTime? lastObservedAt;
    DateTime? lastAssistantAt;
    DateTime? lastEndTurnAt;
    var activeTerminal = false;
    var usage = _HistoryUsageAccumulator();

    DateTime? activeCompletedAt({DateTime? fallback}) {
      return lastEndTurnAt ?? lastAssistantAt ?? fallback;
    }

    void resetTurnClock() {
      lastAssistantAt = null;
      lastEndTurnAt = null;
    }

    void addEvents(Iterable<AgentEvent> mapped, DateTime? occurredAt) {
      for (final event in mapped) {
        events.add(event);
        reducer.apply(event, occurredAt: occurredAt);
      }
    }

    void finishActiveTurn({
      required DateTime? completedAt,
      Map<String, Object?>? sourceResult,
    }) {
      final turnId = activeTurnId;
      if (turnId == null || activeTerminal) {
        return;
      }
      final duration = activeStartedAt == null || completedAt == null
          ? null
          : completedAt.difference(activeStartedAt);
      final result = sourceResult == null
          ? <String, Object?>{
              'type': 'result',
              'subtype': 'success',
              'session_id': sessionId,
              'uuid': 'history-result-${_stableToken(turnId)}',
              'duration_ms': duration?.inMilliseconds,
              'usage': ?usage.toJson(),
            }
          : _normalizeHistoryFrame(sourceResult, sessionId: sessionId);
      final mapped = mapper.mapFrame(
        raw: result,
        runtimeScope: runtimeScope,
        runningTurnId: turnId,
      );
      addEvents(mapped.events, completedAt);
      activeTerminal = mapped.events.any(
        (event) => event is AgentTurnCompletedEvent,
      );
    }

    final init = <String, Object?>{
      'type': 'system',
      'subtype': 'init',
      'session_id': sessionId,
      'cwd': ?cwd,
      'model': ?initialModel,
    };
    addEvents(
      mapper.mapFrame(raw: init, runtimeScope: runtimeScope).events,
      frames.map((frame) => _decodeTimestamp(frame['timestamp'])).firstOrNull,
    );

    try {
      for (final frame in frames) {
        final type = _string(frame['type']);
        final occurredAt = _decodeTimestamp(frame['timestamp']);
        lastObservedAt = occurredAt ?? lastObservedAt;

        if (type == 'user') {
          final message = _objectMap(frame['message']);
          final content = message['content'];
          if (_containsToolResult(content)) {
            final turnId = activeTurnId;
            if (turnId != null) {
              final mapped = mapper.mapFrame(
                raw: _normalizeHistoryFrame(frame, sessionId: sessionId),
                runtimeScope: runtimeScope,
                runningTurnId: turnId,
              );
              addEvents(mapped.events, occurredAt);
            }
            continue;
          }

          final userText = _contentText(content);
          if (userText == null) {
            continue;
          }
          // 下一条用户正文才是 turn 边界。磁盘 JSONL 会把同一条 API
          // message 拆成多行并复制 stop_reason，不能用当前行时间提前收口。
          finishActiveTurn(completedAt: activeCompletedAt());
          resetTurnClock();
          turnOrdinal += 1;
          final sourceTurnId = _firstNonEmpty(<String?>[
            _string(frame['promptId']),
            _string(frame['uuid']),
            'turn-$turnOrdinal',
          ])!;
          final turnId = _historyTurnIdFactory(
            sessionId,
            sourceTurnId,
            turnOrdinal,
          );
          activeTurnId = turnId;
          activeStartedAt = occurredAt;
          activeTerminal = false;
          usage = _HistoryUsageAccumulator();
          turnIds.add(turnId);
          mapper.beginTurn(
            runtimeScope: runtimeScope,
            sessionId: sessionId,
            turnId: turnId,
          );
          addEvents(<AgentEvent>[
            AgentTurnStartedEvent(AgentTurn(id: turnId, sessionId: sessionId)),
            AgentMessageUpdatedEvent(
              messageId: _historyUserEntryId(
                sessionId: sessionId,
                turnId: turnId,
                sourceId: sourceTurnId,
              ),
              sourceMessageId: _string(frame['uuid']),
              text: userText,
              role: AgentMessageRole.user,
              phase: AgentMessagePhase.other,
              status: AgentMessageStatus.completed,
              sessionId: sessionId,
              turnId: turnId,
            ),
          ], occurredAt);
          reducer.updateTurnMetadata(
            turnId: turnId,
            cwd: _string(frame['cwd']) ?? cwd,
          );
          continue;
        }

        if (type == 'assistant') {
          if (activeTurnId == null) {
            turnOrdinal += 1;
            final sourceTurnId =
                _string(frame['uuid']) ?? 'orphan-$turnOrdinal';
            final turnId = _historyTurnIdFactory(
              sessionId,
              sourceTurnId,
              turnOrdinal,
            );
            activeTurnId = turnId;
            activeStartedAt = occurredAt;
            activeTerminal = false;
            resetTurnClock();
            usage = _HistoryUsageAccumulator();
            turnIds.add(turnId);
            mapper.beginTurn(
              runtimeScope: runtimeScope,
              sessionId: sessionId,
              turnId: turnId,
            );
            addEvents(<AgentEvent>[
              AgentTurnStartedEvent(
                AgentTurn(id: turnId, sessionId: sessionId),
              ),
            ], occurredAt);
          }
          final turnId = activeTurnId;
          final normalized = _normalizeHistoryFrame(
            frame,
            sessionId: sessionId,
          );
          final mapped = mapper.mapFrame(
            raw: normalized,
            runtimeScope: runtimeScope,
            runningTurnId: turnId,
          );
          addEvents(mapped.events, occurredAt);
          final message = _objectMap(frame['message']);
          usage.record(
            messageId: _string(message['id']),
            usage: _objectMap(message['usage']),
          );
          reducer.updateTurnMetadata(
            turnId: turnId,
            cwd: _string(frame['cwd']) ?? cwd,
            modelId: _string(message['model']),
            reasoningEffort: _string(frame['effort']),
          );
          lastAssistantAt = occurredAt ?? lastAssistantAt;
          // stop_reason 是整条 message 的 metadata，会被复制到拆开的每一行。
          // 只记录终态时间，等下一条用户正文 / result / EOF 再收口。
          if (_string(message['stop_reason']) == 'end_turn') {
            lastEndTurnAt = occurredAt ?? lastEndTurnAt;
          }
          continue;
        }

        if (type == 'result' && activeTurnId != null) {
          finishActiveTurn(
            completedAt: occurredAt ?? activeCompletedAt(),
            sourceResult: frame,
          );
        }
      }

      finishActiveTurn(
        completedAt: activeCompletedAt(fallback: lastObservedAt),
      );
      final snapshots = <String, ClaudeCodeTurnIdentitySnapshot>{};
      for (final turnId in turnIds) {
        final snapshot = identity.snapshot(
          runtimeScope: runtimeScope,
          sessionId: sessionId,
          turnId: turnId,
        );
        if (snapshot != null) {
          snapshots[turnId] = snapshot;
        }
      }
      return ClaudeCodeHistoryReadResult(
        events: List<AgentEvent>.unmodifiable(events),
        snapshot: reducer.build(),
        identitySnapshots:
            Map<String, ClaudeCodeTurnIdentitySnapshot>.unmodifiable(snapshots),
      );
    } finally {
      mapper.dispose();
    }
  }

  Future<AgentThreadSummary?> _readSummary({
    required File file,
    required String providerId,
    required String projectPath,
  }) async {
    try {
      final stat = _fileStatReader(file);
      final lines = await _readHeadAndTailLines(file, stat.size);
      final frames = <Map<String, Object?>>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final frame = _tryDecodeObject(trimmed);
        if (frame == null) {
          _malformedLineCount += 1;
          continue;
        }
        frames.add(frame);
      }

      final sessionId = _firstNonEmpty(<String?>[
        for (final frame in frames) _string(frame['sessionId']),
        _fileStem(file),
      ]);
      if (sessionId == null) {
        return null;
      }

      final firstUserMessage = _firstUserMessage(frames);
      final timestamps = frames
          .map((frame) => _decodeTimestamp(frame['timestamp']))
          .whereType<DateTime>()
          .toList(growable: false);
      final createdAt = timestamps.isEmpty
          ? stat.modified
          : timestamps.reduce((a, b) => a.isBefore(b) ? a : b);
      final updatedAt = timestamps.isEmpty
          ? stat.modified
          : timestamps.reduce((a, b) => a.isAfter(b) ? a : b);
      final model = _firstNonEmpty(<String?>[
        for (final frame in frames.reversed) _model(frame),
      ]);
      final messageCount = frames
          .where(
            (frame) => frame['type'] == 'user' || frame['type'] == 'assistant',
          )
          .length;

      return AgentThreadSummary(
        id: sessionId,
        providerId: providerId,
        projectPath: projectPath,
        title: _truncate(firstUserMessage, 60),
        sessionPath: file.path,
        preview: _truncate(firstUserMessage, 160) ?? '',
        createdAt: createdAt,
        updatedAt: updatedAt,
        recencyAt: updatedAt,
        status: AgentThreadRuntimeStatus.idle,
        raw: <String, Object?>{
          'source': 'claude_code_history',
          'model': ?model,
          'sampledMessageCount': messageCount,
        },
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<List<String>> _readHeadAndTailLines(File file, int fileLength) async {
    if (fileLength <= sampleWindowBytes * 2) {
      final bytes = await file.readAsBytes();
      return const LineSplitter().convert(
        const Utf8Decoder(allowMalformed: true).convert(bytes),
      );
    }

    final handle = await file.open();
    try {
      final headBytes = await handle.read(sampleWindowBytes);
      await handle.setPosition(fileLength - sampleWindowBytes);
      final tailBytes = await handle.read(sampleWindowBytes);

      final head = const LineSplitter()
          .convert(const Utf8Decoder(allowMalformed: true).convert(headBytes))
          .take(sampleLineLimit);
      final tailText = const Utf8Decoder(
        allowMalformed: true,
      ).convert(tailBytes);
      final tailLines = const LineSplitter().convert(tailText);
      final completeTail = tailLines.length <= 1
          ? const <String>[]
          : tailLines.skip(1).toList(growable: false);
      final tailStart = completeTail.length > sampleLineLimit
          ? completeTail.length - sampleLineLimit
          : 0;
      return <String>[...head, ...completeTail.skip(tailStart)];
    } finally {
      await handle.close();
    }
  }
}

final class _ClaudeCodeHistoryEventReducer {
  _ClaudeCodeHistoryEventReducer({required this.threadId});

  final String threadId;
  final List<String> _turnOrder = <String>[];
  final Map<String, _MutableHistoryTurn> _turns =
      <String, _MutableHistoryTurn>{};

  void apply(AgentEvent event, {required DateTime? occurredAt}) {
    switch (event) {
      case AgentTurnStartedEvent(:final turn):
        _turns.putIfAbsent(turn.id, () {
          _turnOrder.add(turn.id);
          return _MutableHistoryTurn(id: turn.id, startedAt: occurredAt);
        });
      case AgentMessageUpdatedEvent(:final turnId) when turnId != null:
        _turns[turnId]?.upsertMessage(event, occurredAt: occurredAt);
      case AgentReasoningDeltaEvent(:final turnId) when turnId != null:
        _turns[turnId]?.upsertReasoning(event, occurredAt: occurredAt);
      case AgentToolCallEvent(:final toolCall):
        final turnId = toolCall.turnId;
        if (turnId != null) {
          _turns[turnId]?.upsertTool(toolCall, occurredAt: occurredAt);
        }
      case AgentTokenUsageEvent(:final turnId) when turnId != null:
        final turn = _turns[turnId];
        if (turn != null) {
          turn
            ..tokenUsage = event.tokenUsage
            ..tokenUsageIsSessionCumulative = event.isSessionCumulative;
        }
      case AgentTurnCompletedEvent(:final turnId):
        final turn = _turns[turnId];
        if (turn != null) {
          turn
            ..status = event.status
            ..completedAt = occurredAt
            ..duration = event.duration
            ..errorMessage = event.errorMessage
            ..errorCode = event.errorCode;
        }
      default:
        break;
    }
  }

  void updateTurnMetadata({
    required String turnId,
    String? cwd,
    String? modelId,
    String? reasoningEffort,
  }) {
    final turn = _turns[turnId];
    if (turn == null) {
      return;
    }
    turn
      ..cwd = cwd ?? turn.cwd
      ..modelId = modelId ?? turn.modelId
      ..observeReasoningEffort(reasoningEffort);
  }

  AgentThreadHistorySnapshot build() {
    final turns = <AgentHistoryTurn>[
      for (final turnId in _turnOrder) _turns[turnId]!.build(),
    ];
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: turns.isEmpty ? null : turns.last,
      raw: const <String, Object?>{'source': 'claude_code_history'},
    );
  }
}

final class _MutableHistoryTurn {
  _MutableHistoryTurn({required this.id, required this.startedAt});

  final String id;
  final List<AgentHistoryEntry> entries = <AgentHistoryEntry>[];
  final Map<String, int> _entryIndexes = <String, int>{};
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.running;
  DateTime? startedAt;
  DateTime? completedAt;
  Duration? duration;
  String? cwd;
  String? modelId;
  AgentHistoryReasoningEffort reasoningEffort =
      const AgentHistoryReasoningEffort.unknown();
  bool _hasReasoningEffortConflict = false;
  AgentTokenUsage? tokenUsage;
  bool tokenUsageIsSessionCumulative = false;
  String? errorMessage;
  String? errorCode;

  void observeReasoningEffort(String? incoming) {
    if (incoming == null || _hasReasoningEffortConflict) {
      return;
    }
    final current = reasoningEffort.value;
    if (!reasoningEffort.isKnown) {
      reasoningEffort = AgentHistoryReasoningEffort.explicit(incoming);
      return;
    }
    if (current != incoming) {
      // 同一 turn 的 effort 按协议应保持稳定。冲突说明历史证据不可靠，
      // Provider 边界保守丢弃，避免共享层或 UI 猜测应展示哪一个值。
      reasoningEffort = const AgentHistoryReasoningEffort.unknown();
      _hasReasoningEffortConflict = true;
    }
  }

  void upsertMessage(
    AgentMessageUpdatedEvent event, {
    required DateTime? occurredAt,
  }) {
    final index = _entryIndexes[event.messageId];
    final previous = index == null ? null : entries[index];
    final previousMessage = previous is AgentHistoryMessageEntry
        ? previous
        : null;
    final role = event.role ?? previousMessage?.role;
    final text = event.text ?? previousMessage?.text;
    if (role == null || text == null) {
      return;
    }
    final entry = AgentHistoryMessageEntry(
      id: event.messageId,
      sourceMessageId: event.sourceMessageId,
      role: role,
      text: text,
      kind: event.kind,
      phase: event.phase,
      status: event.status,
      duration: event.duration,
    );
    _upsert(entry);
  }

  void upsertReasoning(
    AgentReasoningDeltaEvent event, {
    required DateTime? occurredAt,
  }) {
    final index = _entryIndexes[event.itemId];
    final previous = index == null ? null : entries[index];
    final previousTool = previous is AgentHistoryToolEntry
        ? previous.toolCall
        : null;
    final content = '${previousTool?.content ?? ''}${event.delta}';
    _upsert(
      AgentHistoryToolEntry(
        toolCall: AgentToolCall(
          id: event.itemId,
          title: 'Thinking',
          kind: AgentToolKind.think,
          status: AgentToolStatus.completed,
          content: content,
          sessionId: event.sessionId,
          turnId: event.turnId,
          startedAt: previousTool?.startedAt ?? occurredAt,
          completedAt: occurredAt,
        ),
      ),
    );
  }

  void upsertTool(AgentToolCall incoming, {required DateTime? occurredAt}) {
    final index = _entryIndexes[incoming.id];
    final previous = index == null ? null : entries[index];
    final previousTool = previous is AgentHistoryToolEntry
        ? previous.toolCall
        : null;
    final terminalAt = incoming.isTerminalStatus ? occurredAt : null;
    _upsert(
      AgentHistoryToolEntry(
        toolCall: incoming.copyWith(
          title: incoming.title,
          kind: incoming.kind,
          content: incoming.content ?? previousTool?.content,
          locations: incoming.locations,
          startedAt: previousTool?.startedAt ?? occurredAt,
          completedAt: terminalAt,
          rawInput: incoming.rawInput,
          rawOutput: incoming.rawOutput.isEmpty
              ? previousTool?.rawOutput
              : incoming.rawOutput,
        ),
      ),
    );
  }

  void _upsert(AgentHistoryEntry entry) {
    final index = _entryIndexes[entry.id];
    if (index == null) {
      _entryIndexes[entry.id] = entries.length;
      entries.add(entry);
      return;
    }
    entries[index] = entry;
  }

  AgentHistoryTurn build() {
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(entries),
      status: status,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      cwd: cwd,
      modelId: modelId,
      reasoningEffort: reasoningEffort,
      tokenUsage: tokenUsage,
      tokenUsageIsSessionCumulative: tokenUsageIsSessionCumulative,
      errorMessage: errorMessage,
      errorCode: errorCode,
      raw: const <String, Object?>{'source': 'claude_code_history'},
    );
  }
}

final class _HistoryUsageAccumulator {
  final Map<String, Map<String, Object?>> _usageByMessageKey =
      <String, Map<String, Object?>>{};
  var _anonymousOrdinal = 0;

  /// 同一 [messageId] 的拆行 usage 只保留最后一次；不同 id 在收口时再求和。
  void record({
    required String? messageId,
    required Map<String, Object?> usage,
  }) {
    if (!_hasHistoryUsageFields(usage)) {
      return;
    }
    final key = messageId ?? 'anon:${_anonymousOrdinal++}';
    _usageByMessageKey[key] = Map<String, Object?>.of(usage);
  }

  Map<String, Object?>? toJson() {
    int? inputTokens;
    int? outputTokens;
    int? cacheCreationInputTokens;
    int? cacheReadInputTokens;
    for (final usage in _usageByMessageKey.values) {
      inputTokens = _sumNullable(inputTokens, _integer(usage['input_tokens']));
      outputTokens = _sumNullable(
        outputTokens,
        _integer(usage['output_tokens']),
      );
      cacheCreationInputTokens = _sumNullable(
        cacheCreationInputTokens,
        _integer(usage['cache_creation_input_tokens']),
      );
      cacheReadInputTokens = _sumNullable(
        cacheReadInputTokens,
        _integer(usage['cache_read_input_tokens']),
      );
    }
    if (inputTokens == null &&
        outputTokens == null &&
        cacheCreationInputTokens == null &&
        cacheReadInputTokens == null) {
      return null;
    }
    return <String, Object?>{
      'input_tokens': ?inputTokens,
      'output_tokens': ?outputTokens,
      'cache_creation_input_tokens': ?cacheCreationInputTokens,
      'cache_read_input_tokens': ?cacheReadInputTokens,
    };
  }
}

bool _hasHistoryUsageFields(Map<String, Object?> usage) {
  return _integer(usage['input_tokens']) != null ||
      _integer(usage['output_tokens']) != null ||
      _integer(usage['cache_creation_input_tokens']) != null ||
      _integer(usage['cache_read_input_tokens']) != null;
}

Map<String, Object?> _normalizeHistoryFrame(
  Map<String, Object?> frame, {
  required String sessionId,
}) {
  return <String, Object?>{
    ...frame,
    'session_id':
        _string(frame['session_id']) ??
        _string(frame['sessionId']) ??
        sessionId,
  };
}

bool _containsToolResult(Object? content) {
  if (content is! List) {
    return false;
  }
  return content.any((block) => _objectMap(block)['type'] == 'tool_result');
}

String _historyUserEntryId({
  required String sessionId,
  required String turnId,
  required String sourceId,
}) {
  final token = _stableToken('$sessionId\u0000$turnId\u0000$sourceId');
  return 'cc-history-user:$token';
}

String _defaultHistoryTurnId(
  String sessionId,
  String sourceTurnId,
  int ordinal,
) {
  final token = _stableToken('$sessionId\u0000$sourceTurnId\u0000$ordinal');
  return 'cc-history-turn:$token';
}

String _stableToken(String value) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _normalizedPath(String path) {
  final normalized = File(path).absolute.path.replaceAll(r'\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool _isWithinDirectory(String candidatePath, String directoryPath) {
  final candidate = _normalizedPath(candidatePath);
  final directory = _normalizedPath(
    directoryPath,
  ).replaceFirst(RegExp(r'/+$'), '');
  return candidate.startsWith('$directory/');
}

int? _integer(Object? value) {
  return switch (value) {
    final int number => number,
    final num number => number.toInt(),
    _ => null,
  };
}

int? _sumNullable(int? left, int? right) {
  if (left == null && right == null) {
    return null;
  }
  return (left ?? 0) + (right ?? 0);
}

Map<String, Object?>? _tryDecodeObject(String line) {
  try {
    final value = jsonDecode(line);
    if (value is! Map) {
      return null;
    }
    return value.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  } on FormatException {
    return null;
  }
}

String? _firstUserMessage(List<Map<String, Object?>> frames) {
  for (final frame in frames) {
    if (frame['type'] != 'user') {
      continue;
    }
    final message = _objectMap(frame['message']);
    final text = _contentText(message['content']);
    if (text != null) {
      return text;
    }
  }
  return null;
}

String? _contentText(Object? content) {
  if (content is String) {
    return _normalizeText(content);
  }
  if (content is! List) {
    return null;
  }
  final parts = <String>[];
  for (final block in content) {
    final map = _objectMap(block);
    if (map['type'] != 'text') {
      continue;
    }
    final text = _normalizeText(_string(map['text']));
    if (text != null) {
      parts.add(text);
    }
  }
  return parts.isEmpty ? null : parts.join(' ');
}

String? _model(Map<String, Object?> frame) {
  return _firstNonEmpty(<String?>[
    _string(frame['model']),
    _string(_objectMap(frame['message'])['model']),
  ]);
}

DateTime? _decodeTimestamp(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  final raw = _string(value);
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map((key, value) => MapEntry(key.toString(), value as Object?));
}

String? _string(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _normalizeText(Object? value) {
  final text = _string(value);
  if (text == null) {
    return null;
  }
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

FileSystemEntityType _defaultFileTypeReader(String path) {
  return FileSystemEntity.typeSync(path, followLinks: false);
}

Stream<List<int>> _defaultFileStreamReader(File file) => file.openRead();

FileStat _defaultFileStatReader(File file) => file.statSync();

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final normalized = _string(value);
    if (normalized != null) {
      return normalized;
    }
  }
  return null;
}

String? _truncate(String? value, int maxRunes) {
  final normalized = _normalizeText(value);
  if (normalized == null) {
    return null;
  }
  final runes = normalized.runes.toList(growable: false);
  if (runes.length <= maxRunes) {
    return normalized;
  }
  return String.fromCharCodes(runes.take(maxRunes));
}

String _fileStem(File file) {
  final name = file.uri.pathSegments.last;
  return name.toLowerCase().endsWith('.jsonl')
      ? name.substring(0, name.length - '.jsonl'.length)
      : name;
}

int _parseOffset(String? cursor) {
  final offset = int.tryParse(cursor ?? '');
  return offset == null || offset < 0 ? 0 : offset;
}
