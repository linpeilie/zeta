import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('Agent file change evidence', () {
    test('keeps empty replacement fragments as explicit values', () {
      const evidence = AgentTextReplacementEvidence(
        oldText: '',
        newText: '',
        replaceAll: false,
      );

      expect(evidence, isA<AgentFileChangeEvidence>());
      expect(evidence.oldText, isEmpty);
      expect(evidence.newText, isEmpty);
      expect(evidence.replaceAll, isFalse);
    });

    test('keeps empty written content and unified patch', () {
      const written = AgentWrittenContentEvidence(content: '');
      const patch = AgentUnifiedPatchEvidence(patch: '');

      expect(written, isA<AgentFileChangeEvidence>());
      expect(written.content, isEmpty);
      expect(patch, isA<AgentFileChangeEvidence>());
      expect(patch.patch, isEmpty);
    });
  });

  group('AgentFileChange', () {
    test('represents an unknown summary without inventing evidence', () {
      const change = AgentFileChange(
        id: 'change-summary',
        path: 'lib/unknown.dart',
        kind: AgentFileChangeKind.unknown,
      );

      expect(change.kind, AgentFileChangeKind.unknown);
      expect(change.destinationPath, isNull);
      expect(change.evidence, isNull);
    });

    test('keeps an explicit move destination', () {
      const change = AgentFileChange(
        id: 'change-move',
        path: 'lib/before.dart',
        destinationPath: 'lib/after.dart',
        kind: AgentFileChangeKind.moved,
      );

      expect(change.kind, AgentFileChangeKind.moved);
      expect(change.path, 'lib/before.dart');
      expect(change.destinationPath, 'lib/after.dart');
    });
  });

  group('AgentFileChangeSnapshot', () {
    test('defensively freezes changes while preserving their order', () {
      const first = AgentFileChange(
        id: 'change-1',
        path: 'lib/first.dart',
        kind: AgentFileChangeKind.modified,
      );
      const second = AgentFileChange(
        id: 'change-2',
        path: 'lib/second.dart',
        kind: AgentFileChangeKind.created,
      );
      final input = <AgentFileChange>[first, second];

      final snapshot = AgentFileChangeSnapshot(
        revision: 7,
        replayability: AgentFileChangeReplayability.replayable,
        changes: input,
      );
      input
        ..clear()
        ..add(second);

      expect(snapshot.revision, 7);
      expect(snapshot.replayability, AgentFileChangeReplayability.replayable);
      expect(snapshot.changes, <AgentFileChange>[first, second]);
      expect(() => snapshot.changes.add(first), throwsUnsupportedError);
    });

    test('keeps an empty live-only snapshot as an authoritative value', () {
      final snapshot = AgentFileChangeSnapshot(
        revision: 8,
        replayability: AgentFileChangeReplayability.liveOnly,
        changes: const <AgentFileChange>[],
      );

      expect(snapshot.changes, isEmpty);
      expect(snapshot.replayability, AgentFileChangeReplayability.liveOnly);
      expect(snapshot.changes, isNotNull);
    });
  });

  group('AgentToolCall fileChanges', () {
    final initialSnapshot = AgentFileChangeSnapshot(
      revision: 1,
      replayability: AgentFileChangeReplayability.replayable,
      changes: const <AgentFileChange>[
        AgentFileChange(
          id: 'change-1',
          path: 'lib/first.dart',
          kind: AgentFileChangeKind.modified,
        ),
      ],
    );
    final replacementSnapshot = AgentFileChangeSnapshot(
      revision: 2,
      replayability: AgentFileChangeReplayability.replayable,
      changes: const <AgentFileChange>[],
    );

    test('defaults to no snapshot', () {
      const toolCall = AgentToolCall(id: 'tool-1', title: 'Edit');

      expect(toolCall.fileChanges, isNull);
    });

    test('copyWith preserves and replaces the snapshot', () {
      final toolCall = AgentToolCall(
        id: 'tool-1',
        title: 'Edit',
        fileChanges: initialSnapshot,
      );

      final preserved = toolCall.copyWith(status: AgentToolStatus.inProgress);
      final replaced = toolCall.copyWith(fileChanges: replacementSnapshot);

      expect(preserved.fileChanges, same(initialSnapshot));
      expect(replaced.fileChanges, same(replacementSnapshot));
    });

    test('clearFileChanges explicitly removes a snapshot', () {
      final toolCall = AgentToolCall(
        id: 'tool-1',
        title: 'Edit',
        fileChanges: initialSnapshot,
      );

      final cleared = toolCall.copyWith(
        fileChanges: replacementSnapshot,
        clearFileChanges: true,
      );

      expect(cleared.fileChanges, isNull);
    });
  });
}
