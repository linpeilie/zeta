import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  const runtimeScope = AgentRuntimeScope(
    runtimeId: 'grok-file-change-test',
    connectionEpoch: 7,
  );
  late GrokFileChangeTracker tracker;

  setUp(() => tracker = GrokFileChangeTracker());
  tearDown(() => tracker.dispose());

  test('projects real diff shape and removes the placeholder text', () {
    // Arrange / Act
    final projected = _project(
      tracker,
      _update(
        toolKind: 'edit',
        rawInput: const <String, Object?>{'replace_all': false},
        content: <Object?>[
          <String, Object?>{
            'type': 'content',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'Applying edit',
            },
          },
          _diff(r'C:\workspace\sample.txt', 'before\n', 'after\n'),
        ],
      ),
      kind: AgentToolKind.edit,
    );

    // Assert
    expect(projected.content, 'Applying edit');
    expect(projected.content, isNot(contains('diff:')));
    final snapshot = projected.fileChanges!;
    expect(snapshot.revision, 1);
    expect(snapshot.replayability, AgentFileChangeReplayability.replayable);
    final change = snapshot.changes.single;
    expect(change.id, contains('tool-1'));
    expect(change.path, r'C:\workspace\sample.txt');
    expect(change.kind, AgentFileChangeKind.modified);
    final evidence = change.evidence as AgentTextReplacementEvidence;
    expect(evidence.oldText, 'before\n');
    expect(evidence.newText, 'after\n');
    expect(evidence.replaceAll, isFalse);
  });

  test('status-only, duplicate, and malformed updates keep last-valid', () {
    // Arrange
    final first = _project(
      tracker,
      _update(
        toolKind: 'edit',
        rawInput: const <String, Object?>{'replace_all': true},
        content: <Object?>[_diff('sample.txt', 'a', 'b')],
      ),
      kind: AgentToolKind.edit,
    ).fileChanges!;

    // Act
    final duplicate = _project(
      tracker,
      _update(content: <Object?>[_diff('sample.txt', 'a', 'b')]),
    );
    final statusOnly = _project(tracker, _update(status: 'completed'));
    final malformed = _project(
      tracker,
      _update(
        content: <Object?>[
          <String, Object?>{
            'type': 'content',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'Malformed evidence ignored',
            },
          },
          <String, Object?>{
            'type': 'diff',
            'path': 'sample.txt',
            'oldText': 'b',
          },
        ],
      ),
    );

    // Assert
    expect(duplicate.fileChanges, same(first));
    expect(statusOnly.fileChanges, same(first));
    expect(malformed.fileChanges, same(first));
    expect(malformed.content, 'Malformed evidence ignored');
    final evidence =
        first.changes.single.evidence as AgentTextReplacementEvidence;
    expect(evidence.replaceAll, isTrue);
  });

  test('changed evidence increments revision and empty strings stay valid', () {
    // Arrange
    final first = _project(
      tracker,
      _update(
        content: <Object?>[_diff('empty.txt', '', '')],
        rawInput: const <String, Object?>{'replace_all': 'false'},
      ),
    ).fileChanges!;

    // Act
    final changed = _project(
      tracker,
      _update(content: <Object?>[_diff('empty.txt', '', 'new')]),
    ).fileChanges!;

    // Assert
    expect(first.changes.single.kind, AgentFileChangeKind.unknown);
    final firstEvidence =
        first.changes.single.evidence as AgentTextReplacementEvidence;
    expect(firstEvidence.oldText, isEmpty);
    expect(firstEvidence.newText, isEmpty);
    expect(firstEvidence.replaceAll, isNull);
    expect(changed.revision, 2);
    expect(changed.changes.single.id, first.changes.single.id);
  });

  test('turn/session/runtime/new-turn cleanup releases cumulative state', () {
    AgentFileChangeSnapshot seed(AgentRuntimeScope scope, String turn) =>
        tracker
            .project(
              update: _update(
                toolKind: 'edit',
                content: <Object?>[_diff('a.txt', 'a', 'b')],
              ),
              toolKind: AgentToolKind.edit,
              runtimeScope: scope,
              sessionId: 'session-1',
              turnId: turn,
            )
            .fileChanges!;
    AgentFileChangeSnapshot? carry(AgentRuntimeScope scope, String turn) =>
        tracker
            .project(
              update: _update(status: 'completed'),
              toolKind: AgentToolKind.other,
              runtimeScope: scope,
              sessionId: 'session-1',
              turnId: turn,
            )
            .fileChanges;

    // Arrange / Act / Assert
    seed(runtimeScope, 'turn-1');
    tracker.invalidateTurn(
      runtimeScope: runtimeScope,
      sessionId: 'session-1',
      turnId: 'turn-1',
    );
    expect(carry(runtimeScope, 'turn-1'), isNull);

    seed(runtimeScope, 'turn-2');
    tracker.invalidateSession(
      runtimeScope: runtimeScope,
      sessionId: 'session-1',
    );
    expect(carry(runtimeScope, 'turn-2'), isNull);

    const nextRuntime = AgentRuntimeScope(
      runtimeId: 'grok-file-change-test',
      connectionEpoch: 8,
    );
    seed(nextRuntime, 'turn-3');
    tracker.invalidateRuntime(nextRuntime);
    expect(carry(nextRuntime, 'turn-3'), isNull);

    seed(runtimeScope, 'turn-4');
    tracker.beginTurn(runtimeScope: runtimeScope, sessionId: 'session-1');
    expect(carry(runtimeScope, 'turn-4'), isNull);
  });
}

GrokTrackedToolProjection _project(
  GrokFileChangeTracker tracker,
  AcpToolCallUpdate update, {
  AgentToolKind kind = AgentToolKind.other,
}) => tracker.project(
  update: update,
  toolKind: kind,
  runtimeScope: const AgentRuntimeScope(
    runtimeId: 'grok-file-change-test',
    connectionEpoch: 7,
  ),
  sessionId: 'session-1',
  turnId: 'turn-1',
);

AcpToolCallUpdate _update({
  String? toolKind,
  String? status,
  Object? content,
  Map<String, Object?> rawInput = const <String, Object?>{},
}) => AcpToolCallUpdate(
  sessionId: 'session-1',
  kind: 'tool_call_update',
  toolCallId: 'tool-1',
  toolKind: toolKind,
  status: status,
  content: content,
  rawInput: rawInput,
);

Map<String, Object?> _diff(String path, String oldText, String newText) =>
    <String, Object?>{
      'type': 'diff',
      'path': path,
      'oldText': oldText,
      'newText': newText,
    };
