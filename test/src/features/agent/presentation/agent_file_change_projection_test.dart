import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';

void main() {
  test('projects ordered actions, statistics, and all detail variants', () {
    final changes = <AgentFileChange>[
      const AgentFileChange(
        id: 'replace',
        path: 'lib/replace.dart',
        kind: AgentFileChangeKind.modified,
        evidence: AgentTextReplacementEvidence(
          oldText: 'old 1\nold 2\n',
          newText: 'new\n',
          replaceAll: true,
        ),
      ),
      const AgentFileChange(
        id: 'write',
        path: 'lib/write.dart',
        kind: AgentFileChangeKind.unknown,
        evidence: AgentWrittenContentEvidence(content: 'one\ntwo\n'),
      ),
      const AgentFileChange(
        id: 'patch',
        path: 'trusted/source.dart',
        destinationPath: 'trusted/target.dart',
        kind: AgentFileChangeKind.moved,
        evidence: AgentUnifiedPatchEvidence(
          patch:
              'diff --git a/wrong.dart b/wrong.dart\n'
              '--- a/wrong.dart\n'
              '+++ b/wrong.dart\n'
              '@@ -1 +1 @@\n'
              '-before\n'
              '+after\n'
              ' context',
        ),
      ),
      const AgentFileChange(
        id: 'summary',
        path: 'lib/summary.dart',
        kind: AgentFileChangeKind.deleted,
      ),
    ];

    final items = <AgentFileChangeItemProjection>[
      for (final change in changes)
        projectAgentFileChange(
          ownerEntryId: 'tool-1',
          snapshotRevision: 7,
          replayability: AgentFileChangeReplayability.liveOnly,
          change: change,
        ),
    ];

    expect(items.map((item) => item.changeId), <String>[
      'replace',
      'write',
      'patch',
      'summary',
    ]);
    expect(items.first.kind, AgentFileChangeKind.modified);
    expect(items.first.stableIdentity, (
      ownerEntryId: 'tool-1',
      changeId: 'replace',
    ));
    final replacement = items[0].detail as AgentTextReplacementDetailProjection;
    expect(replacement.beforeLines, <String>['old 1', 'old 2']);
    expect(replacement.afterLines, <String>['new']);
    expect(replacement.replaceAll, isTrue);
    expect(items[0].statistics?.addedLines, 1);
    expect(items[0].statistics?.removedLines, 2);

    final written = items[1].detail as AgentWrittenContentDetailProjection;
    expect(written.lines, <String>['one', 'two']);
    expect(items[1].statistics?.totalLines, 2);
    expect(items[1].statistics?.addedLines, isNull);

    final patch = items[2].detail as AgentUnifiedPatchDetailProjection;
    expect(items[2].path, 'trusted/source.dart');
    expect(items[2].destinationPath, 'trusted/target.dart');
    expect(items[2].statistics?.addedLines, 1);
    expect(items[2].statistics?.removedLines, 1);
    expect(patch.lines[1].kind, AgentUnifiedPatchLineKind.metadata);
    expect(patch.lines[3].kind, AgentUnifiedPatchLineKind.hunkHeader);
    expect(patch.lines[4].kind, AgentUnifiedPatchLineKind.removed);
    expect(patch.lines[5].kind, AgentUnifiedPatchLineKind.added);
    expect(items[3].detail, isNull);
    expect(items[3].statistics, isNull);
  });

  test('empty evidence remains an explicit immutable detail', () {
    final item = projectAgentFileChange(
      ownerEntryId: 'turn-1',
      snapshotRevision: 1,
      replayability: AgentFileChangeReplayability.liveOnly,
      change: const AgentFileChange(
        id: 'empty',
        path: 'empty.txt',
        kind: AgentFileChangeKind.modified,
        evidence: AgentTextReplacementEvidence(oldText: '', newText: ''),
      ),
    );

    final detail = item.detail as AgentTextReplacementDetailProjection;
    expect(detail.beforeLines, isEmpty);
    expect(detail.afterLines, isEmpty);
    expect(item.statistics?.totalLines, 0);
    expect(() => detail.beforeLines.add('mutate'), throwsUnsupportedError);
  });
}
