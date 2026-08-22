import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_decoder.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Grok 工具 content 的 Provider-local 投影。
///
/// 普通 content block 继续形成工具正文；`diff` block 单独保留为结构化证据，
/// 不再生成 `diff: <path>` 占位文本。
final class GrokToolContentProjection {
  GrokToolContentProjection._({
    required this.content,
    required List<_GrokDiffBlock> diffBlocks,
    required this.hasMalformedDiff,
  }) : _diffBlocks = List<_GrokDiffBlock>.unmodifiable(diffBlocks);

  factory GrokToolContentProjection.parse(Object? content) {
    if (content == null || content is String) {
      return GrokToolContentProjection._(
        content: content as String?,
        diffBlocks: const <_GrokDiffBlock>[],
        hasMalformedDiff: false,
      );
    }
    final blocks = content is List<Object?> ? content : <Object?>[content];
    final texts = <String>[];
    final diffs = <_GrokDiffBlock>[];
    var malformed = false;
    for (final rawBlock in blocks) {
      final block = _stringKeyedMap(rawBlock);
      if (block == null) {
        if (content is! List<Object?> && rawBlock != null) {
          texts.add(rawBlock.toString());
        }
        continue;
      }
      if (block['type']?.toString() == 'diff') {
        final path = block['path'];
        final oldText = block['oldText'];
        final newText = block['newText'];
        if (path is! String ||
            path.trim().isEmpty ||
            oldText is! String ||
            newText is! String) {
          malformed = true;
          continue;
        }
        diffs.add(
          _GrokDiffBlock(path.trim(), oldText: oldText, newText: newText),
        );
        continue;
      }
      final text = AcpContentCodec.textFromContent(
        block['type']?.toString() == 'content' ? block['content'] : block,
      );
      if (text != null) {
        texts.add(text);
      }
    }
    final text = texts.join('\n');
    return GrokToolContentProjection._(
      content: text.isEmpty ? null : text,
      diffBlocks: diffs,
      hasMalformedDiff: malformed,
    );
  }

  final String? content;
  final bool hasMalformedDiff;
  final List<_GrokDiffBlock> _diffBlocks;
}

/// 一次 Grok tool update 的完整可见投影。
final class GrokTrackedToolProjection {
  const GrokTrackedToolProjection({this.content, this.fileChanges});

  final String? content;
  final AgentFileChangeSnapshot? fileChanges;
}

/// 按 runtime/session/turn/tool 隔离的 Grok 文件变更累计器。
final class GrokFileChangeTracker {
  final Map<_GrokToolScope, _GrokFileChangeState> _states =
      <_GrokToolScope, _GrokFileChangeState>{};

  GrokTrackedToolProjection project({
    required AcpToolCallUpdate update,
    required AgentToolKind toolKind,
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) {
    final scope = _GrokToolScope(
      runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      toolCallId: update.toolCallId,
    );
    final state = _states.putIfAbsent(scope, _GrokFileChangeState.new);
    final projection = GrokToolContentProjection.parse(update.content);
    final explicitKind = _explicitKind(update.toolKind, toolKind);
    final explicitReplaceAll = _replaceAll(update.rawInput);
    if (projection.hasMalformedDiff) {
      // 损坏的新 diff 不覆盖 last-valid；首次完整 diff 仍可复用已确认 metadata。
      if (state.snapshot == null) {
        state
          ..kind = explicitKind ?? state.kind
          ..replaceAll = explicitReplaceAll ?? state.replaceAll;
      }
      return GrokTrackedToolProjection(
        content: projection.content,
        fileChanges: state.snapshot,
      );
    }

    state
      ..kind = explicitKind ?? state.kind
      ..replaceAll = explicitReplaceAll ?? state.replaceAll;
    if (projection._diffBlocks.isNotEmpty) {
      final changes = <AgentFileChange>[
        for (var index = 0; index < projection._diffBlocks.length; index += 1)
          _mapDiff(
            projection._diffBlocks[index],
            toolCallId: update.toolCallId,
            ordinal: index + 1,
            kind: state.kind ?? AgentFileChangeKind.unknown,
            replaceAll: state.replaceAll,
          ),
      ];
      state.snapshot = _nextSnapshot(state.snapshot, changes);
    }
    return GrokTrackedToolProjection(
      content: projection.content,
      fileChanges: state.snapshot,
    );
  }

  /// 新 turn 开始时释放同 session 的旧累计状态。
  void beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
  }) => _states.removeWhere(
    (scope, _) =>
        scope.runtimeScope == runtimeScope && scope.sessionId == sessionId,
  );

  void invalidateTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) => _states.removeWhere(
    (scope, _) =>
        scope.runtimeScope == runtimeScope &&
        scope.sessionId == sessionId &&
        scope.turnId == turnId,
  );

  void invalidateSession({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
  }) => beginTurn(runtimeScope: runtimeScope, sessionId: sessionId);

  void invalidateRuntime(AgentRuntimeScope runtimeScope) =>
      _states.removeWhere((scope, _) => scope.runtimeScope == runtimeScope);

  void dispose() => _states.clear();
}

final class _GrokDiffBlock {
  const _GrokDiffBlock(
    this.path, {
    required this.oldText,
    required this.newText,
  });

  final String path;
  final String oldText;
  final String newText;
}

final class _GrokToolScope {
  const _GrokToolScope(
    this.runtimeScope, {
    required this.sessionId,
    required this.turnId,
    required this.toolCallId,
  });

  final AgentRuntimeScope runtimeScope;
  final String sessionId;
  final String turnId;
  final String toolCallId;

  @override
  bool operator ==(Object other) =>
      other is _GrokToolScope &&
      other.runtimeScope == runtimeScope &&
      other.sessionId == sessionId &&
      other.turnId == turnId &&
      other.toolCallId == toolCallId;

  @override
  int get hashCode => Object.hash(runtimeScope, sessionId, turnId, toolCallId);
}

final class _GrokFileChangeState {
  AgentFileChangeKind? kind;
  bool? replaceAll;
  AgentFileChangeSnapshot? snapshot;
}

AgentFileChange _mapDiff(
  _GrokDiffBlock block, {
  required String toolCallId,
  required int ordinal,
  required AgentFileChangeKind kind,
  required bool? replaceAll,
}) {
  final pathKey = block.path.replaceAll('\\', '/');
  return AgentFileChange(
    id:
        'grok:${Uri.encodeComponent(toolCallId)}:'
        '$ordinal:${Uri.encodeComponent(pathKey)}',
    path: block.path,
    kind: kind,
    evidence: AgentTextReplacementEvidence(
      oldText: block.oldText,
      newText: block.newText,
      replaceAll: replaceAll,
    ),
  );
}

AgentFileChangeSnapshot _nextSnapshot(
  AgentFileChangeSnapshot? previous,
  List<AgentFileChange> changes,
) {
  if (previous != null && _sameChanges(previous.changes, changes)) {
    return previous;
  }
  return AgentFileChangeSnapshot(
    revision: (previous?.revision ?? 0) + 1,
    replayability: AgentFileChangeReplayability.replayable,
    changes: changes,
  );
}

bool _sameChanges(List<AgentFileChange> left, List<AgentFileChange> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final a = left[index];
    final b = right[index];
    final aEvidence = a.evidence;
    final bEvidence = b.evidence;
    if (a.id != b.id ||
        a.path != b.path ||
        a.kind != b.kind ||
        aEvidence is! AgentTextReplacementEvidence ||
        bEvidence is! AgentTextReplacementEvidence ||
        aEvidence.oldText != bEvidence.oldText ||
        aEvidence.newText != bEvidence.newText ||
        aEvidence.replaceAll != bEvidence.replaceAll) {
      return false;
    }
  }
  return true;
}

AgentFileChangeKind? _explicitKind(String? rawKind, AgentToolKind toolKind) {
  if (rawKind == null || rawKind.trim().isEmpty) {
    return null;
  }
  return toolKind == AgentToolKind.edit
      ? AgentFileChangeKind.modified
      : AgentFileChangeKind.unknown;
}

bool? _replaceAll(Map<String, Object?> input) {
  final value = input.containsKey('replace_all')
      ? input['replace_all']
      : input['replaceAll'];
  return value is bool ? value : null;
}

Map<String, Object?>? _stringKeyedMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item as Object?))
    : null;
