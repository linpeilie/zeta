import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  const scope = AgentRuntimeScope(
    runtimeId: 'claude-file-change-test',
    connectionEpoch: 3,
  );
  late ClaudeCodeFileChangeTracker tracker;

  setUp(() => tracker = ClaudeCodeFileChangeTracker());
  tearDown(() => tracker.dispose());

  test('Edit records replacement evidence and stable revision', () {
    // Arrange / Act
    final first = _record(
      tracker,
      toolName: 'Edit',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': r'C:\workspace\sample.txt',
        'old_string': 'before\n',
        'new_string': 'after\n',
        'replace_all': false,
      },
    );
    final duplicate = _record(
      tracker,
      toolName: 'Edit',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': r'C:\workspace\sample.txt',
        'old_string': 'before\n',
        'new_string': 'after\n',
        'replace_all': false,
      },
    );

    // Assert
    expect(duplicate.fileChanges, same(first.fileChanges));
    final snapshot = first.fileChanges!;
    expect(snapshot.revision, 1);
    expect(snapshot.replayability, AgentFileChangeReplayability.replayable);
    final change = snapshot.changes.single;
    expect(change.id, contains('tool-1'));
    expect(change.kind, AgentFileChangeKind.modified);
    final evidence = change.evidence as AgentTextReplacementEvidence;
    expect(evidence.oldText, 'before\n');
    expect(evidence.newText, 'after\n');
    expect(evidence.replaceAll, isFalse);
  });

  test('Write keeps empty content and does not guess created or modified', () {
    // Arrange / Act
    final tracked = _record(
      tracker,
      toolName: 'Write',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': '/workspace/empty.txt',
        'content': '',
      },
    );

    // Assert
    final change = tracked.fileChanges!.changes.single;
    expect(change.kind, AgentFileChangeKind.unknown);
    final evidence = change.evidence as AgentWrittenContentEvidence;
    expect(evidence.content, isEmpty);
  });

  test('NotebookEdit and MultiEdit emit summary while other tools do not', () {
    // Arrange / Act
    final notebook = _record(
      tracker,
      toolUseId: 'notebook-1',
      toolName: 'NotebookEdit',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'notebook_path': '/workspace/sample.ipynb',
        'new_source': 'redacted',
      },
      locations: const <String>['/workspace/sample.ipynb'],
    );
    final multi = _record(
      tracker,
      toolUseId: 'multi-1',
      toolName: 'MultiEdit',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': '/workspace/sample.txt',
        'edits': <Object?>[],
      },
      locations: const <String>['/workspace/sample.txt'],
    );
    final bash = _record(
      tracker,
      toolUseId: 'bash-1',
      toolName: 'Bash',
      kind: AgentToolKind.execute,
      input: const <String, Object?>{'command': 'redacted'},
      locations: const <String>[],
    );

    // Assert
    expect(notebook.fileChanges!.changes.single.evidence, isNull);
    expect(
      notebook.fileChanges!.changes.single.kind,
      AgentFileChangeKind.unknown,
    );
    expect(multi.fileChanges!.changes.single.evidence, isNull);
    expect(bash.fileChanges, isNull);
  });

  test('tool result lookup is scoped and lifecycle cleanup releases state', () {
    // Arrange
    final tracked = _record(
      tracker,
      toolName: 'Edit',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': '/workspace/a.txt',
        'old_string': '',
        'new_string': '',
      },
    );

    // Act / Assert: same scope resolves the complete projection.
    expect(
      tracker.resolveToolResult(
        runtimeScope: scope,
        sessionId: 'session-1',
        turnId: 'turn-1',
        toolUseId: 'tool-1',
      ),
      same(tracked),
    );
    tracker.completeTurn(
      runtimeScope: scope,
      sessionId: 'session-1',
      turnId: 'turn-1',
    );
    expect(_resolve(tracker, scope, 'turn-1'), isNull);

    _record(
      tracker,
      toolName: 'Write',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': '/workspace/b.txt',
        'content': 'b',
      },
      turnId: 'turn-2',
    );
    tracker.beginTurn(runtimeScope: scope, sessionId: 'session-1');
    expect(_resolve(tracker, scope, 'turn-2'), isNull);

    const nextScope = AgentRuntimeScope(
      runtimeId: 'claude-file-change-test',
      connectionEpoch: 4,
    );
    _record(
      tracker,
      toolName: 'Write',
      kind: AgentToolKind.edit,
      input: const <String, Object?>{
        'file_path': '/workspace/c.txt',
        'content': 'c',
      },
      runtimeScope: nextScope,
      turnId: 'turn-3',
    );
    tracker.invalidateRuntime(nextScope);
    expect(_resolve(tracker, nextScope, 'turn-3'), isNull);
  });
}

ClaudeCodeTrackedTool _record(
  ClaudeCodeFileChangeTracker tracker, {
  String toolUseId = 'tool-1',
  required String toolName,
  required AgentToolKind kind,
  required Map<String, Object?> input,
  List<String>? locations,
  AgentRuntimeScope runtimeScope = const AgentRuntimeScope(
    runtimeId: 'claude-file-change-test',
    connectionEpoch: 3,
  ),
  String turnId = 'turn-1',
}) => tracker.recordToolUse(
  runtimeScope: runtimeScope,
  sessionId: 'session-1',
  turnId: turnId,
  toolUseId: toolUseId,
  toolName: toolName,
  kind: kind,
  locations: locations ?? <String>[input['file_path'] as String? ?? ''],
  input: input,
);

ClaudeCodeTrackedTool? _resolve(
  ClaudeCodeFileChangeTracker tracker,
  AgentRuntimeScope scope,
  String turnId,
) => tracker.resolveToolResult(
  runtimeScope: scope,
  sessionId: 'session-1',
  turnId: turnId,
  toolUseId: 'tool-1',
);
