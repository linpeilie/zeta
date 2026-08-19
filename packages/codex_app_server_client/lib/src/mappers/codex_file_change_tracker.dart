part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// Codex fileChange 工具在一次通知后的完整投影。
final class CodexToolFileChangeProjection {
  /// Creates a projection from one Codex file-change notification.
  const CodexToolFileChangeProjection({
    required this.snapshot,
    required this.locations,
    this.turnFallbackClear,
  });

  /// Canonical file-change snapshot, or null when no valid change exists.
  final AgentFileChangeSnapshot? snapshot;

  /// Normalized locations derived from [snapshot].
  final List<String> locations;

  /// tool 证据后到时，用该空快照撤下已经可见的 turn fallback。
  final AgentFileChangeSnapshot? turnFallbackClear;
}

/// Codex turn/diff 的 Provider-local 投影。
final class CodexTurnFileChangeProjection {
  /// Creates the projection for a turn-level unified diff.
  const CodexTurnFileChangeProjection({
    this.snapshot,
    this.suppressedByTool = false,
    this.malformed = false,
  });

  /// Canonical snapshot created from the turn diff, when available.
  final AgentFileChangeSnapshot? snapshot;

  /// Whether structured tool evidence superseded the turn diff.
  final bool suppressedByTool;

  /// Whether a non-empty turn diff could not be parsed safely.
  final bool malformed;
}

/// 按 runtime/thread/turn 隔离 Codex tool 证据与 turn fallback 的累计器。
///
/// 只有 `fileChange` / `patchUpdated` 或本地历史 `patch_apply_end` 的结构化
/// `changes` 会建立 tool snapshot；`commandExecution` 不调用本类，因此不会从
/// 命令或审批参数猜文件语义。
final class CodexFileChangeTracker {
  final Map<_CodexTurnScope, _CodexTurnFileChangeState> _turns =
      <_CodexTurnScope, _CodexTurnFileChangeState>{};

  /// Projects and accumulates one structured tool file-change notification.
  CodexToolFileChangeProjection projectTool({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
    required String turnId,
    required String toolCallId,
    required bool hasStructuredChanges,
    Object? changes,
  }) {
    final mappedChanges = hasStructuredChanges
        ? _codexToolChangesFromWire(toolCallId: toolCallId, value: changes)
        : null;
    return _projectToolChanges(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      toolCallId: toolCallId,
      mappedChanges: mappedChanges,
    );
  }

  /// 把本地 session JSONL 的 `patch_apply_end.changes` 投影为历史证据。
  ///
  /// 该私有历史形状是以路径为 key 的 map，与 App-Server `fileChange.changes[]`
  /// 不同；必须在 Codex data 层显式归一化，不能把 raw 交给共享层或 UI 猜测。
  CodexToolFileChangeProjection projectJsonlPatchApply({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
    required String turnId,
    required String toolCallId,
    required bool hasStructuredChanges,
    Object? changes,
  }) {
    final mappedChanges = hasStructuredChanges
        ? _codexJsonlPatchApplyChangesFromWire(
            toolCallId: toolCallId,
            value: changes,
          )
        : null;
    return _projectToolChanges(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      toolCallId: toolCallId,
      mappedChanges: mappedChanges,
    );
  }

  CodexToolFileChangeProjection _projectToolChanges({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
    required String turnId,
    required String toolCallId,
    required List<AgentFileChange>? mappedChanges,
  }) {
    final state = _stateFor(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
    );
    final tool = state.tools.putIfAbsent(
      toolCallId,
      _CodexToolFileChangeState.new,
    );

    if (mappedChanges != null) {
      tool.snapshot = _codexNextSnapshot(
        previous: tool.snapshot,
        changes: mappedChanges,
        replayability: AgentFileChangeReplayability.replayable,
      );
    }

    final snapshot = tool.snapshot;
    AgentFileChangeSnapshot? turnFallbackClear;
    if (snapshot != null &&
        snapshot.changes.isNotEmpty &&
        state.turnFallbackVisible) {
      turnFallbackClear = _codexNextSnapshot(
        previous: state.turnFallback,
        changes: const <AgentFileChange>[],
        replayability: AgentFileChangeReplayability.liveOnly,
      );
      state
        ..turnFallback = turnFallbackClear
        ..turnFallbackVisible = false;
    }

    return CodexToolFileChangeProjection(
      snapshot: snapshot,
      locations: _codexSnapshotLocations(snapshot),
      turnFallbackClear: turnFallbackClear,
    );
  }

  /// Projects a turn-level diff unless tool evidence already owns the turn.
  CodexTurnFileChangeProjection projectTurnDiff({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
    required String turnId,
    required String diff,
  }) {
    final state = _stateFor(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
    );
    if (state.tools.values.any(
      (tool) => tool.snapshot?.changes.isNotEmpty ?? false,
    )) {
      return const CodexTurnFileChangeProjection(suppressedByTool: true);
    }

    final changes = diff.isEmpty
        ? const <AgentFileChange>[]
        : _codexTurnChangesFromUnifiedDiff(turnId: turnId, diff: diff);
    if (changes == null) {
      return const CodexTurnFileChangeProjection(malformed: true);
    }
    final snapshot = _codexNextSnapshot(
      previous: state.turnFallback,
      changes: changes,
      replayability: AgentFileChangeReplayability.liveOnly,
    );
    state
      ..turnFallback = snapshot
      ..turnFallbackVisible = snapshot.changes.isNotEmpty;
    return CodexTurnFileChangeProjection(snapshot: snapshot);
  }

  /// Clears stale state before a new turn begins in [sessionId].
  void beginTurn({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
  }) => invalidateSession(runtimeScope: runtimeScope, sessionId: sessionId);

  /// Removes accumulated state for the completed [turnId].
  void completeTurn({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
    required String turnId,
  }) => _turns.remove(
    _CodexTurnScope(runtimeScope, sessionId: sessionId, turnId: turnId),
  );

  /// Removes every tracked turn belonging to [sessionId].
  void invalidateSession({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
  }) => _turns.removeWhere(
    (scope, _) =>
        scope.runtimeScope == runtimeScope && scope.sessionId == sessionId,
  );

  /// Removes every tracked turn belonging to [runtimeScope].
  void invalidateRuntime(AgentRuntimeScope? runtimeScope) =>
      _turns.removeWhere((scope, _) => scope.runtimeScope == runtimeScope);

  /// Releases all in-memory tracking state.
  void dispose() => _turns.clear();

  _CodexTurnFileChangeState _stateFor({
    required AgentRuntimeScope? runtimeScope,
    required String sessionId,
    required String turnId,
  }) => _turns.putIfAbsent(
    _CodexTurnScope(runtimeScope, sessionId: sessionId, turnId: turnId),
    _CodexTurnFileChangeState.new,
  );
}

@immutable
final class _CodexTurnScope {
  const _CodexTurnScope(
    this.runtimeScope, {
    required this.sessionId,
    required this.turnId,
  });

  final AgentRuntimeScope? runtimeScope;
  final String sessionId;
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is _CodexTurnScope &&
      other.runtimeScope == runtimeScope &&
      other.sessionId == sessionId &&
      other.turnId == turnId;

  @override
  int get hashCode => Object.hash(runtimeScope, sessionId, turnId);
}

final class _CodexTurnFileChangeState {
  final Map<String, _CodexToolFileChangeState> tools =
      <String, _CodexToolFileChangeState>{};
  AgentFileChangeSnapshot? turnFallback;
  bool turnFallbackVisible = false;
}

final class _CodexToolFileChangeState {
  AgentFileChangeSnapshot? snapshot;
}

List<AgentFileChange>? _codexToolChangesFromWire({
  required String toolCallId,
  required Object? value,
}) {
  if (value is! List<Object?>) {
    return null;
  }
  final changes = <AgentFileChange>[];
  for (var index = 0; index < value.length; index += 1) {
    final raw = _map(value[index]);
    final pathValue = raw['path'];
    final patchValue = raw['diff'];
    final kindValue = raw['kind'];
    if (pathValue is! String ||
        pathValue.trim().isEmpty ||
        patchValue is! String ||
        kindValue is! Map) {
      return null;
    }
    final path = pathValue.trim();
    final kindMap = _map(kindValue);
    final wireKind = _string(kindMap['type']);
    final movePathValue = kindMap['move_path'];
    final destinationPath =
        movePathValue is String && movePathValue.trim().isNotEmpty
        ? movePathValue.trim()
        : null;
    final kind = switch (wireKind) {
      'add' => AgentFileChangeKind.created,
      'delete' => AgentFileChangeKind.deleted,
      'update' when destinationPath != null => AgentFileChangeKind.moved,
      'update' => AgentFileChangeKind.modified,
      _ => AgentFileChangeKind.unknown,
    };
    changes.add(
      AgentFileChange(
        id: _codexChangeId(
          ownerPrefix: 'codex',
          ownerId: toolCallId,
          ordinal: index + 1,
          path: path,
          destinationPath: destinationPath,
        ),
        path: path,
        destinationPath: destinationPath,
        kind: kind,
        evidence: AgentUnifiedPatchEvidence(patch: patchValue),
      ),
    );
  }
  return changes;
}

List<AgentFileChange>? _codexJsonlPatchApplyChangesFromWire({
  required String toolCallId,
  required Object? value,
}) {
  if (value is! Map) {
    return null;
  }
  final changes = <AgentFileChange>[];
  var ordinal = 0;
  for (final entry in value.entries) {
    final pathValue = entry.key;
    if (pathValue is! String || pathValue.trim().isEmpty) {
      return null;
    }
    final rawValue = entry.value;
    if (rawValue is! Map) {
      return null;
    }
    ordinal += 1;
    final path = pathValue.trim();
    final raw = _map(rawValue);
    final wireKind = _string(raw['type'])?.trim().toLowerCase();
    final movePathValue = raw['move_path'];
    final destinationPath =
        movePathValue is String && movePathValue.trim().isNotEmpty
        ? movePathValue.trim()
        : null;
    final kind = switch (wireKind) {
      'add' => AgentFileChangeKind.created,
      'delete' => AgentFileChangeKind.deleted,
      'update' when destinationPath != null => AgentFileChangeKind.moved,
      'update' => AgentFileChangeKind.modified,
      _ => AgentFileChangeKind.unknown,
    };
    final unifiedDiff = raw['unified_diff'];
    final content = raw['content'];
    final evidence = unifiedDiff is String
        ? AgentUnifiedPatchEvidence(patch: unifiedDiff)
        : kind == AgentFileChangeKind.created && content is String
        ? AgentWrittenContentEvidence(content: content)
        : null;
    changes.add(
      AgentFileChange(
        id: _codexChangeId(
          ownerPrefix: 'codex',
          ownerId: toolCallId,
          ordinal: ordinal,
          path: path,
          destinationPath: destinationPath,
        ),
        path: path,
        destinationPath: destinationPath,
        kind: kind,
        evidence: evidence,
      ),
    );
  }
  return changes;
}

List<AgentFileChange>? _codexTurnChangesFromUnifiedDiff({
  required String turnId,
  required String diff,
}) {
  final chunks = _codexUnifiedDiffChunks(diff);
  if (chunks == null || chunks.isEmpty) {
    return null;
  }
  return <AgentFileChange>[
    for (var index = 0; index < chunks.length; index += 1)
      AgentFileChange(
        id: _codexChangeId(
          ownerPrefix: 'codex-turn',
          ownerId: turnId,
          ordinal: index + 1,
          path: chunks[index].path,
          destinationPath: chunks[index].destinationPath,
        ),
        path: chunks[index].path,
        destinationPath: chunks[index].destinationPath,
        kind: chunks[index].kind,
        evidence: AgentUnifiedPatchEvidence(patch: chunks[index].patch),
      ),
  ];
}

List<_CodexUnifiedDiffChunk>? _codexUnifiedDiffChunks(String diff) {
  final headers = RegExp('^diff --git ', multiLine: true).allMatches(diff);
  final starts = headers.map((match) => match.start).toList(growable: false);
  final rawChunks = starts.isEmpty
      ? <String>[diff]
      : <String>[
          for (var index = 0; index < starts.length; index += 1)
            diff.substring(
              starts[index],
              index + 1 < starts.length ? starts[index + 1] : diff.length,
            ),
        ];
  final chunks = <_CodexUnifiedDiffChunk>[];
  for (final patch in rawChunks) {
    final chunk = _codexUnifiedDiffChunk(patch);
    if (chunk == null) {
      return null;
    }
    chunks.add(chunk);
  }
  return chunks;
}

_CodexUnifiedDiffChunk? _codexUnifiedDiffChunk(String patch) {
  final lines = const LineSplitter().convert(patch);
  String? minusPath;
  String? plusPath;
  String? renameFrom;
  String? renameTo;
  String? gitSource;
  String? gitDestination;
  var isCreated = false;
  var isDeleted = false;
  for (final line in lines) {
    if (line.startsWith('--- ')) {
      minusPath = _codexPatchPath(line.substring(4));
    } else if (line.startsWith('+++ ')) {
      plusPath = _codexPatchPath(line.substring(4));
    } else if (line.startsWith('rename from ')) {
      renameFrom = _codexPatchPath(line.substring('rename from '.length));
    } else if (line.startsWith('rename to ')) {
      renameTo = _codexPatchPath(line.substring('rename to '.length));
    } else if (line.startsWith('new file mode ')) {
      isCreated = true;
    } else if (line.startsWith('deleted file mode ')) {
      isDeleted = true;
    } else if (line.startsWith('diff --git ')) {
      final paths = _codexGitHeaderPaths(line);
      gitSource = paths?.$1;
      gitDestination = paths?.$2;
    }
  }

  final moved = renameFrom != null && renameTo != null;
  final kind = moved
      ? AgentFileChangeKind.moved
      : isCreated || (minusPath == null && plusPath != null)
      ? AgentFileChangeKind.created
      : isDeleted || (minusPath != null && plusPath == null)
      ? AgentFileChangeKind.deleted
      : AgentFileChangeKind.modified;
  final path = moved
      ? renameFrom
      : kind == AgentFileChangeKind.deleted
      ? minusPath ?? gitSource
      : plusPath ?? gitDestination ?? minusPath ?? gitSource;
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  return _CodexUnifiedDiffChunk(
    path: path,
    destinationPath: moved ? renameTo : null,
    kind: kind,
    patch: patch,
  );
}

(String?, String?)? _codexGitHeaderPaths(String line) {
  final body = line.substring('diff --git '.length).trim();
  final parts = body.split(RegExp(r'\s+'));
  if (parts.length != 2) {
    return null;
  }
  return (_codexPatchPath(parts[0]), _codexPatchPath(parts[1]));
}

String? _codexPatchPath(String raw) {
  var path = raw.trim();
  final tabIndex = path.indexOf('\t');
  if (tabIndex != -1) {
    path = path.substring(0, tabIndex);
  }
  if (path == '/dev/null') {
    return null;
  }
  if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
    try {
      final decoded = jsonDecode(path);
      if (decoded is String) {
        path = decoded;
      }
    } on FormatException {
      return null;
    }
  }
  if (path.startsWith('a/') || path.startsWith('b/')) {
    path = path.substring(2);
  }
  return path.trim().isEmpty ? null : path.trim();
}

String _codexChangeId({
  required String ownerPrefix,
  required String ownerId,
  required int ordinal,
  required String path,
  String? destinationPath,
}) {
  final pathKey = path.replaceAll(r'\', '/');
  final destinationKey = destinationPath?.replaceAll(r'\', '/');
  final identityKey = destinationKey == null
      ? pathKey
      : '$pathKey->$destinationKey';
  return '$ownerPrefix:${Uri.encodeComponent(ownerId)}:'
      '$ordinal:${Uri.encodeComponent(identityKey)}';
}

List<String> _codexSnapshotLocations(AgentFileChangeSnapshot? snapshot) {
  if (snapshot == null) {
    return const <String>[];
  }
  final values = <String>[];
  for (final change in snapshot.changes) {
    if (!values.contains(change.path)) {
      values.add(change.path);
    }
    final destination = change.destinationPath;
    if (destination != null && !values.contains(destination)) {
      values.add(destination);
    }
  }
  return List<String>.unmodifiable(values);
}

AgentFileChangeSnapshot _codexNextSnapshot({
  required AgentFileChangeSnapshot? previous,
  required List<AgentFileChange> changes,
  required AgentFileChangeReplayability replayability,
}) {
  if (previous != null &&
      previous.replayability == replayability &&
      _codexSameChanges(previous.changes, changes)) {
    return previous;
  }
  return AgentFileChangeSnapshot(
    revision: (previous?.revision ?? 0) + 1,
    replayability: replayability,
    changes: changes,
  );
}

bool _codexSameChanges(
  List<AgentFileChange> left,
  List<AgentFileChange> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final a = left[index];
    final b = right[index];
    if (a.id != b.id ||
        a.path != b.path ||
        a.destinationPath != b.destinationPath ||
        a.kind != b.kind ||
        !_codexSameEvidence(a.evidence, b.evidence)) {
      return false;
    }
  }
  return true;
}

bool _codexSameEvidence(
  AgentFileChangeEvidence? left,
  AgentFileChangeEvidence? right,
) => switch ((left, right)) {
  (null, null) => true,
  (
    AgentUnifiedPatchEvidence(:final patch),
    AgentUnifiedPatchEvidence(patch: final otherPatch),
  ) =>
    patch == otherPatch,
  (
    AgentWrittenContentEvidence(:final content),
    AgentWrittenContentEvidence(content: final otherContent),
  ) =>
    content == otherContent,
  _ => false,
};

final class _CodexUnifiedDiffChunk {
  const _CodexUnifiedDiffChunk({
    required this.path,
    required this.kind,
    required this.patch,
    this.destinationPath,
  });

  final String path;
  final String? destinationPath;
  final AgentFileChangeKind kind;
  final String patch;
}
