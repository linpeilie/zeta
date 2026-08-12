import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection_cache.dart';

void main() {
  test('10,000 lines are parsed once across repeated resize resolves', () {
    final contentLines = <String>[
      for (var index = 0; index < 10000; index += 1)
        index.isEven ? '-before $index' : '+after $index',
    ];
    final snapshot = _snapshot(
      revision: 1,
      patch: <String>[
        '--- a/untrusted-header.dart',
        '+++ b/untrusted-header.dart',
        '@@ -1 +1 @@',
        ...contentLines,
      ].join('\n'),
    );
    final cache = AgentFileChangeProjectionCache();

    final first = cache.resolve(ownerEntryId: 'tool-1', snapshot: snapshot);
    for (final width in <double>[639, 640, 641, 1280, 1000, 1280]) {
      expect(width, greaterThan(0));
      expect(
        identical(
          cache.resolve(ownerEntryId: 'tool-1', snapshot: snapshot),
          first,
        ),
        isTrue,
      );
    }

    final detail =
        first.items.single.detail as AgentUnifiedPatchDetailProjection;
    expect(detail.lines, hasLength(10003));
    expect(first.items.single.path, 'lib/trusted.dart');
    expect(first.items.single.statistics?.addedLines, 5000);
    expect(first.items.single.statistics?.removedLines, 5000);
    expect(cache.computeCount, 1);
  });

  test('owner, revision, and change id define invalidation and retention', () {
    final cache = AgentFileChangeProjectionCache();
    final first = cache.resolve(
      ownerEntryId: 'tool-a',
      snapshot: _snapshot(revision: 1, patch: '-old\n+first'),
    );
    final otherOwner = cache.resolve(
      ownerEntryId: 'tool-b',
      snapshot: _snapshot(revision: 1, patch: '-old\n+first'),
    );
    final revised = cache.resolve(
      ownerEntryId: 'tool-a',
      snapshot: _snapshot(revision: 2, patch: '-first\n+second'),
    );

    expect(identical(first, otherOwner), isFalse);
    expect(identical(first, revised), isFalse);
    expect(cache.computeCount, 3);
    expect(cache.cachedOwnerCount, 2);
    expect(cache.cachedItemCount, 2, reason: 'tool-a old revision is evicted');
    expect(revised.items.single.snapshotRevision, 2);

    cache.retainOnly(<String>{'tool-a'});
    expect(cache.cachedOwnerCount, 1);
    expect(cache.cachedItemCount, 1);
    cache.clear();
    expect(cache.cachedOwnerCount, 0);
    expect(cache.cachedItemCount, 0);
    expect(cache.computeCount, 0);
  });
}

AgentFileChangeSnapshot _snapshot({
  required int revision,
  required String patch,
}) {
  return AgentFileChangeSnapshot(
    revision: revision,
    replayability: AgentFileChangeReplayability.replayable,
    changes: <AgentFileChange>[
      AgentFileChange(
        id: 'change-1',
        path: 'lib/trusted.dart',
        kind: AgentFileChangeKind.modified,
        evidence: AgentUnifiedPatchEvidence(patch: patch),
      ),
    ],
  );
}
