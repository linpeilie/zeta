import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  const runtime = AgentRuntimeScope(
    runtimeId: 'codex-file-change-test',
    connectionEpoch: 1,
  );

  group('CodexFileChangeTracker', () {
    test('maps schema changes and only increments revision on content', () {
      final tracker = CodexFileChangeTracker();
      final first = tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        hasStructuredChanges: true,
        changes: _wireChanges(updatePatch: '[PATCH_V1]'),
      );

      expect(first.snapshot?.revision, 1);
      expect(
        first.snapshot?.replayability,
        AgentFileChangeReplayability.replayable,
      );
      expect(first.locations, <String>[
        'lib/update.dart',
        'lib/created.dart',
        'lib/deleted.dart',
        'lib/source.dart',
        'lib/destination.dart',
      ]);
      expect(
        first.snapshot?.changes.map((change) => change.kind),
        <AgentFileChangeKind>[
          AgentFileChangeKind.modified,
          AgentFileChangeKind.created,
          AgentFileChangeKind.deleted,
          AgentFileChangeKind.moved,
        ],
      );
      expect(
        first.snapshot?.changes.last.destinationPath,
        'lib/destination.dart',
      );

      final repeated = tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        hasStructuredChanges: true,
        changes: _wireChanges(updatePatch: '[PATCH_V1]'),
      );
      expect(repeated.snapshot?.revision, 1);
      expect(repeated.snapshot, same(first.snapshot));

      final changed = tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        hasStructuredChanges: true,
        changes: _wireChanges(updatePatch: '[PATCH_V2]'),
      );
      expect(changed.snapshot?.revision, 2);
      expect(
        (changed.snapshot?.changes.first.evidence as AgentUnifiedPatchEvidence?)
            ?.patch,
        '[PATCH_V2]',
      );
    });

    test(
      'carries last valid snapshot across text-only and malformed updates',
      () {
        final tracker = CodexFileChangeTracker();
        final valid = tracker.projectTool(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'tool-1',
          hasStructuredChanges: true,
          changes: _wireChanges(updatePatch: '[PATCH_VALID]'),
        );
        final textOnly = tracker.projectTool(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'tool-1',
          hasStructuredChanges: false,
        );
        final malformed = tracker.projectTool(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'tool-1',
          hasStructuredChanges: true,
          changes: <Object?>[
            <String, Object?>{
              'path': 'lib/update.dart',
              'kind': <String, Object?>{'type': 'update'},
            },
          ],
        );

        expect(textOnly.snapshot, same(valid.snapshot));
        expect(malformed.snapshot, same(valid.snapshot));
        expect(malformed.snapshot?.revision, 1);
      },
    );

    test('maps local JSONL patch_apply_end changes without raw inference', () {
      final tracker = CodexFileChangeTracker();
      final first = tracker.projectJsonlPatchApply(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'patch-1',
        hasStructuredChanges: true,
        changes: _jsonlPatchApplyChanges(updatePatch: '[JSONL_PATCH_V1]'),
      );

      expect(first.snapshot?.revision, 1);
      expect(
        first.snapshot?.replayability,
        AgentFileChangeReplayability.replayable,
      );
      expect(first.locations, <String>[
        'lib/update.dart',
        'lib/created.dart',
        'lib/deleted.dart',
        'lib/source.dart',
        'lib/destination.dart',
      ]);
      final changes = first.snapshot!.changes;
      expect(changes.map((change) => change.kind), <AgentFileChangeKind>[
        AgentFileChangeKind.modified,
        AgentFileChangeKind.created,
        AgentFileChangeKind.deleted,
        AgentFileChangeKind.moved,
      ]);
      expect(
        (changes[0].evidence as AgentUnifiedPatchEvidence).patch,
        '[JSONL_PATCH_V1]',
      );
      expect(
        (changes[1].evidence as AgentWrittenContentEvidence).content,
        '[CREATED_CONTENT]',
      );
      expect(changes[2].evidence, isNull);
      expect(changes[3].destinationPath, 'lib/destination.dart');
      expect(
        (changes[3].evidence as AgentUnifiedPatchEvidence).patch,
        '[MOVE_PATCH]',
      );

      final repeated = tracker.projectJsonlPatchApply(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'patch-1',
        hasStructuredChanges: true,
        changes: _jsonlPatchApplyChanges(updatePatch: '[JSONL_PATCH_V1]'),
      );
      expect(repeated.snapshot, same(first.snapshot));
      expect(repeated.snapshot?.revision, 1);
    });

    test(
      'keeps JSONL summary-only changes and rejects malformed replacements',
      () {
        final tracker = CodexFileChangeTracker();
        final summaryOnly = tracker.projectJsonlPatchApply(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'patch-summary',
          hasStructuredChanges: true,
          changes: <String, Object?>{
            'lib/summary.dart': <String, Object?>{'type': 'update'},
          },
        );
        expect(
          summaryOnly.snapshot?.changes.single.kind,
          AgentFileChangeKind.modified,
        );
        expect(summaryOnly.snapshot?.changes.single.evidence, isNull);

        final valid = tracker.projectJsonlPatchApply(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'patch-valid',
          hasStructuredChanges: true,
          changes: _jsonlPatchApplyChanges(updatePatch: '[VALID]'),
        );
        final malformed = tracker.projectJsonlPatchApply(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'patch-valid',
          hasStructuredChanges: true,
          changes: <Object?, Object?>{'lib/update.dart': '[MALFORMED_CHANGE]'},
        );
        final missing = tracker.projectJsonlPatchApply(
          runtimeScope: runtime,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          toolCallId: 'patch-missing',
          hasStructuredChanges: false,
        );

        expect(malformed.snapshot, same(valid.snapshot));
        expect(missing.snapshot, isNull);
      },
    );

    test('splits turn aggregate into live-only per-file changes', () {
      final tracker = CodexFileChangeTracker();
      final first = tracker.projectTurnDiff(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        diff: _turnDiff,
      );

      expect(first.suppressedByTool, isFalse);
      expect(first.malformed, isFalse);
      expect(first.snapshot?.revision, 1);
      expect(
        first.snapshot?.replayability,
        AgentFileChangeReplayability.liveOnly,
      );
      expect(first.snapshot?.changes, hasLength(2));
      expect(first.snapshot?.changes[0].path, 'lib/update.dart');
      expect(first.snapshot?.changes[0].kind, AgentFileChangeKind.modified);
      expect(first.snapshot?.changes[1].path, 'lib/created.dart');
      expect(first.snapshot?.changes[1].kind, AgentFileChangeKind.created);
      expect(
        (first.snapshot?.changes[1].evidence as AgentUnifiedPatchEvidence?)
            ?.patch,
        contains('[CREATED_AFTER]'),
      );

      final repeated = tracker.projectTurnDiff(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        diff: _turnDiff,
      );
      expect(repeated.snapshot, same(first.snapshot));

      final cleared = tracker.projectTurnDiff(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        diff: '',
      );
      expect(cleared.snapshot?.revision, 2);
      expect(cleared.snapshot?.changes, isEmpty);
    });

    test('clears visible turn fallback before preferring tool evidence', () {
      final tracker = CodexFileChangeTracker();
      final fallback = tracker.projectTurnDiff(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        diff: _turnDiff,
      );
      expect(fallback.snapshot?.changes, isNotEmpty);

      final tool = tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        hasStructuredChanges: true,
        changes: _wireChanges(updatePatch: '[TOOL_PATCH]'),
      );
      expect(tool.turnFallbackClear?.revision, 2);
      expect(tool.turnFallbackClear?.changes, isEmpty);
      expect(tool.snapshot?.changes, isNotEmpty);

      final suppressed = tracker.projectTurnDiff(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        diff: _turnDiff,
      );
      expect(suppressed.suppressedByTool, isTrue);
      expect(suppressed.snapshot, isNull);
    });

    test('isolates and clears turn state by runtime lifecycle', () {
      final tracker = CodexFileChangeTracker();
      tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        hasStructuredChanges: true,
        changes: _wireChanges(updatePatch: '[PATCH]'),
      );
      tracker.completeTurn(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
      );

      final afterTurn = tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        hasStructuredChanges: false,
      );
      expect(afterTurn.snapshot, isNull);

      tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-2',
        toolCallId: 'tool-2',
        hasStructuredChanges: true,
        changes: _wireChanges(updatePatch: '[PATCH]'),
      );
      tracker.invalidateRuntime(runtime);
      final afterRuntime = tracker.projectTool(
        runtimeScope: runtime,
        sessionId: 'thread-1',
        turnId: 'turn-2',
        toolCallId: 'tool-2',
        hasStructuredChanges: false,
      );
      expect(afterRuntime.snapshot, isNull);
    });
  });
}

List<Object?> _wireChanges({required String updatePatch}) => <Object?>[
  <String, Object?>{
    'path': 'lib/update.dart',
    'kind': <String, Object?>{'type': 'update', 'move_path': null},
    'diff': updatePatch,
  },
  <String, Object?>{
    'path': 'lib/created.dart',
    'kind': <String, Object?>{'type': 'add'},
    'diff': '[CREATE_PATCH]',
  },
  <String, Object?>{
    'path': 'lib/deleted.dart',
    'kind': <String, Object?>{'type': 'delete'},
    'diff': '[DELETE_PATCH]',
  },
  <String, Object?>{
    'path': 'lib/source.dart',
    'kind': <String, Object?>{
      'type': 'update',
      'move_path': 'lib/destination.dart',
    },
    'diff': '[MOVE_PATCH]',
  },
];

Map<String, Object?> _jsonlPatchApplyChanges({required String updatePatch}) =>
    <String, Object?>{
      'lib/update.dart': <String, Object?>{
        'type': 'update',
        'move_path': null,
        'unified_diff': updatePatch,
      },
      'lib/created.dart': <String, Object?>{
        'type': 'add',
        'content': '[CREATED_CONTENT]',
      },
      'lib/deleted.dart': <String, Object?>{
        'type': 'delete',
        'content': '[DELETED_CONTENT]',
      },
      'lib/source.dart': <String, Object?>{
        'type': 'update',
        'move_path': 'lib/destination.dart',
        'unified_diff': '[MOVE_PATCH]',
      },
    };

const _turnDiff =
    'diff --git a/lib/update.dart b/lib/update.dart\n'
    '--- a/lib/update.dart\n'
    '+++ b/lib/update.dart\n'
    '@@ -1 +1 @@\n'
    '-[UPDATE_BEFORE]\n'
    '+[UPDATE_AFTER]\n'
    'diff --git a/lib/created.dart b/lib/created.dart\n'
    'new file mode 100644\n'
    '--- /dev/null\n'
    '+++ b/lib/created.dart\n'
    '@@ -0,0 +1 @@\n'
    '+[CREATED_AFTER]\n';
