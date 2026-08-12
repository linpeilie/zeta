import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Claude Code tool_use 的累计投影；tool_result 用同一记录补全终态工具事件。
final class ClaudeCodeTrackedTool {
  ClaudeCodeTrackedTool({
    required this.title,
    required this.kind,
    required List<String> locations,
    required Map<String, Object?> rawInput,
    required this.fileChanges,
  }) : locations = List<String>.unmodifiable(locations),
       rawInput = Map<String, Object?>.unmodifiable(rawInput);

  final String title;
  final AgentToolKind kind;
  final List<String> locations;
  final Map<String, Object?> rawInput;
  final AgentFileChangeSnapshot? fileChanges;
}

/// 按 runtime/session/turn/toolUseId 隔离的 Claude Code 文件变更跟踪器。
final class ClaudeCodeFileChangeTracker {
  final Map<_ClaudeCodeToolScope, ClaudeCodeTrackedTool> _tools =
      <_ClaudeCodeToolScope, ClaudeCodeTrackedTool>{};

  ClaudeCodeTrackedTool recordToolUse({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
    required String toolUseId,
    required String toolName,
    required AgentToolKind kind,
    required List<String> locations,
    required Map<String, Object?> input,
  }) {
    final scope = _ClaudeCodeToolScope(
      runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      toolUseId: toolUseId,
    );
    final previous = _tools[scope];
    final changes = _changesForTool(
      toolUseId: toolUseId,
      toolName: toolName,
      input: input,
      locations: locations,
    );
    final snapshot = changes == null
        ? previous?.fileChanges
        : _nextSnapshot(previous?.fileChanges, changes);
    final tracked = ClaudeCodeTrackedTool(
      title: toolName,
      kind: kind,
      locations: locations,
      rawInput: input,
      fileChanges: snapshot,
    );
    _tools[scope] = tracked;
    return tracked;
  }

  ClaudeCodeTrackedTool? resolveToolResult({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
    required String toolUseId,
  }) =>
      _tools[_ClaudeCodeToolScope(
        runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
        toolUseId: toolUseId,
      )];

  /// 新 turn 开始时释放同 session 的旧状态。
  void beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
  }) => invalidateSession(runtimeScope: runtimeScope, sessionId: sessionId);

  void completeTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) => _tools.removeWhere(
    (scope, _) =>
        scope.runtimeScope == runtimeScope &&
        scope.sessionId == sessionId &&
        scope.turnId == turnId,
  );

  void invalidateSession({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
  }) => _tools.removeWhere(
    (scope, _) =>
        scope.runtimeScope == runtimeScope && scope.sessionId == sessionId,
  );

  void invalidateRuntime(AgentRuntimeScope runtimeScope) =>
      _tools.removeWhere((scope, _) => scope.runtimeScope == runtimeScope);

  void dispose() => _tools.clear();
}

final class _ClaudeCodeToolScope {
  const _ClaudeCodeToolScope(
    this.runtimeScope, {
    required this.sessionId,
    required this.turnId,
    required this.toolUseId,
  });

  final AgentRuntimeScope runtimeScope;
  final String sessionId;
  final String turnId;
  final String toolUseId;

  @override
  bool operator ==(Object other) =>
      other is _ClaudeCodeToolScope &&
      other.runtimeScope == runtimeScope &&
      other.sessionId == sessionId &&
      other.turnId == turnId &&
      other.toolUseId == toolUseId;

  @override
  int get hashCode => Object.hash(runtimeScope, sessionId, turnId, toolUseId);
}

List<AgentFileChange>? _changesForTool({
  required String toolUseId,
  required String toolName,
  required Map<String, Object?> input,
  required List<String> locations,
}) {
  final normalizedName = toolName.trim().toLowerCase();
  final path = _pathForTool(normalizedName, input, locations);
  if (path == null) {
    return null;
  }
  final id = _changeId(toolUseId, path);
  return switch (normalizedName) {
    'edit'
        when input['old_string'] is String && input['new_string'] is String =>
      <AgentFileChange>[
        AgentFileChange(
          id: id,
          path: path,
          kind: AgentFileChangeKind.modified,
          evidence: AgentTextReplacementEvidence(
            oldText: input['old_string']! as String,
            newText: input['new_string']! as String,
            replaceAll: input['replace_all'] is bool
                ? input['replace_all']! as bool
                : null,
          ),
        ),
      ],
    'write' when input['content'] is String => <AgentFileChange>[
      AgentFileChange(
        id: id,
        path: path,
        kind: AgentFileChangeKind.unknown,
        evidence: AgentWrittenContentEvidence(
          content: input['content']! as String,
        ),
      ),
    ],
    'notebookedit' || 'multiedit' => <AgentFileChange>[
      AgentFileChange(id: id, path: path, kind: AgentFileChangeKind.unknown),
    ],
    _ => null,
  };
}

String? _pathForTool(
  String toolName,
  Map<String, Object?> input,
  List<String> locations,
) {
  if (toolName != 'edit' &&
      toolName != 'write' &&
      toolName != 'notebookedit' &&
      toolName != 'multiedit') {
    return null;
  }
  final preferred = toolName == 'notebookedit'
      ? input['notebook_path']
      : input['file_path'];
  final value = preferred is String && preferred.trim().isNotEmpty
      ? preferred.trim()
      : locations.firstOrNull;
  return value == null || value.trim().isEmpty ? null : value.trim();
}

String _changeId(String toolUseId, String path) {
  final pathKey = path.replaceAll('\\', '/');
  return 'claude:${Uri.encodeComponent(toolUseId)}:'
      '1:${Uri.encodeComponent(pathKey)}';
}

AgentFileChangeSnapshot _nextSnapshot(
  AgentFileChangeSnapshot? previous,
  List<AgentFileChange> changes,
) {
  if (previous != null &&
      _sameChange(previous.changes.single, changes.single)) {
    return previous;
  }
  return AgentFileChangeSnapshot(
    revision: (previous?.revision ?? 0) + 1,
    replayability: AgentFileChangeReplayability.replayable,
    changes: changes,
  );
}

bool _sameChange(AgentFileChange left, AgentFileChange right) {
  if (left.id != right.id ||
      left.path != right.path ||
      left.kind != right.kind ||
      left.evidence.runtimeType != right.evidence.runtimeType) {
    return false;
  }
  return switch ((left.evidence, right.evidence)) {
    (null, null) => true,
    (
      AgentTextReplacementEvidence(
        :final oldText,
        :final newText,
        :final replaceAll,
      ),
      AgentTextReplacementEvidence(
        oldText: final otherOld,
        newText: final otherNew,
        replaceAll: final otherReplaceAll,
      ),
    ) =>
      oldText == otherOld &&
          newText == otherNew &&
          replaceAll == otherReplaceAll,
    (
      AgentWrittenContentEvidence(:final content),
      AgentWrittenContentEvidence(content: final otherContent),
    ) =>
      content == otherContent,
    _ => false,
  };
}
