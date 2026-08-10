import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'zeta-usage-statistics-index-',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  group('FileUsageStatisticsIndexStore', () {
    test('returns an empty snapshot when the file is missing', () async {
      // Arrange
      final store = FileUsageStatisticsIndexStore(
        file: File.fromUri(
          tempDirectory.uri.resolve('state/usage_statistics_index.json'),
        ),
      );

      // Act
      final snapshot = await store.load();

      // Assert
      expect(snapshot.codexSessions, isEmpty);
      expect(snapshot.grokSessions, isEmpty);
    });

    test('saves and reloads multi-provider partitions after restart', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      final original = _snapshot();

      // Act
      await FileUsageStatisticsIndexStore(file: file).save(original);
      final encoded = await file.readAsString();
      final reloaded = await FileUsageStatisticsIndexStore(file: file).load();

      // Assert
      expect(await file.exists(), isTrue);
      expect(encoded, contains('"version":3'));
      expect(encoded, contains('"providers"'));
      expect(encoded, contains('sourceId'));
      expect(encoded, isNot(contains('sourcePath')));
      expect(encoded, isNot(contains('/codex/sessions/rollout.jsonl')));
      expect(encoded, isNot(contains('/grok/session/updates.jsonl')));
      expect(encoded, isNot(contains('errorMessage')));
      expect(encoded, isNot(contains('secret prompt text')));
      expect(encoded, isNot(contains('provider-secret-code')));
      expect(encoded, contains('errorCategoryHint'));
      expect(reloaded.codexSessions, hasLength(1));
      expect(reloaded.grokSessions, hasLength(1));
      final codex = reloaded.codexSessions.values.single;
      expect(
        reloaded.codexSessions.keys.single,
        original.codexSessions.values.single.sourceId,
      );
      expect(codex.sourcePath, isEmpty);
      expect(codex.threadId, 'thread-1');
      expect(codex.turns.single.errorCode, isNull);
      expect(codex.turns.single.samples.single.totalTokens, 42);
      final grok = reloaded.grokSessions.values.single;
      expect(grok.sourcePath, isEmpty);
      expect(grok.threadId, 'grok-thread');
      expect(grok.turns.single.totalTokens, 60);
      expect(grok.turns.single.errorMessage, isNull);
    });

    test('migrates legacy V2 codex-only index into codex partition', () {
      // Arrange
      final v2Json = <String, Object?>{
        'version': 2,
        'sessions': _snapshot().codexSessions.values
            .map((session) => session.toJson())
            .toList(),
      };

      // Act
      final migrated = UsageStatisticsIndexSnapshot.tryDecode(v2Json);

      // Assert
      expect(migrated.codexSessions, hasLength(1));
      expect(migrated.grokSessions, isEmpty);
      expect(migrated.codexSessions.values.single.threadId, 'thread-1');
    });

    test('mergeSave keeps the other provider partition', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      final store = FileUsageStatisticsIndexStore(file: file);
      final original = _snapshot();
      await store.save(original);

      final nextCodex = CodexUsageSessionSnapshot(
        sourcePath: '/codex/sessions/other.jsonl',
        fingerprint: '200:2',
        threadId: 'thread-2',
        projectPath: '/workspace/other',
        sourceKind: 'codex',
        createdAt: DateTime.utc(2026, 7, 15),
        turns: const <CodexUsageTurnSnapshot>[],
      );

      // Act
      await store.mergeSave(
        codexSessions: <String, CodexUsageSessionSnapshot>{
          nextCodex.sourceId: nextCodex,
        },
      );
      final reloaded = await store.load();

      // Assert
      expect(reloaded.codexSessions.keys.single, nextCodex.sourceId);
      expect(reloaded.grokSessions, hasLength(1));
      expect(reloaded.grokSessions.values.single.threadId, 'grok-thread');
    });

    test('parallel mergeSave does not drop either partition', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      final store = FileUsageStatisticsIndexStore(file: file);
      final codex = _snapshot().codexSessions;
      final grok = _snapshot().grokSessions;

      // Act
      await Future.wait(<Future<void>>[
        store.mergeSave(codexSessions: codex),
        store.mergeSave(grokSessions: grok),
      ]);
      final reloaded = await store.load();

      // Assert
      expect(reloaded.codexSessions, hasLength(1));
      expect(reloaded.grokSessions, hasLength(1));
    });

    test('treats damaged JSON as an empty snapshot', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('{damaged');

      // Act
      final snapshot = await FileUsageStatisticsIndexStore(file: file).load();

      // Assert
      expect(snapshot.codexSessions, isEmpty);
      expect(snapshot.grokSessions, isEmpty);
    });

    test('treats invalid UTF-8 as an empty snapshot', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[0xff]);

      // Act
      final snapshot = await FileUsageStatisticsIndexStore(file: file).load();

      // Assert
      expect(snapshot.codexSessions, isEmpty);
    });

    test('treats semantically damaged fields as an empty snapshot', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"version":3,"providers":{"codex":{"sessions":[{'
        '"sourceId":"source","fingerprint":"fingerprint",'
        '"threadId":"thread","projectPath":"project",'
        '"sourceKind":"codex","createdAt":9223372036854775807,'
        '"turns":[]}]}}}',
      );

      // Act
      final snapshot = await FileUsageStatisticsIndexStore(file: file).load();

      // Assert
      expect(snapshot.codexSessions, isEmpty);
    });

    test('propagates write failures', () async {
      // Arrange
      final blockingParent = File.fromUri(
        tempDirectory.uri.resolve('not-a-directory'),
      );
      await blockingParent.writeAsString('blocked');
      final store = FileUsageStatisticsIndexStore(
        file: File.fromUri(
          tempDirectory.uri.resolve(
            'not-a-directory/usage_statistics_index.json',
          ),
        ),
      );

      // Act / Assert
      await expectLater(store.save(_snapshot()), throwsA(isA<IOException>()));
    });
  });
}

UsageStatisticsIndexSnapshot _snapshot() {
  final createdAt = DateTime.utc(2026, 7, 14);
  final codex = CodexUsageSessionSnapshot(
    sourcePath: '/codex/sessions/rollout.jsonl',
    fingerprint: '100:1',
    threadId: 'thread-1',
    projectPath: '/workspace/zeta',
    sourceKind: 'codex_cli_rs',
    createdAt: createdAt,
    turns: <CodexUsageTurnSnapshot>[
      CodexUsageTurnSnapshot(
        id: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        startedAt: createdAt,
        completedAt: createdAt.add(const Duration(seconds: 1)),
        errorMessage: 'secret prompt text',
        errorCode: 'provider-secret-code',
        samples: <CodexUsageSample>[
          CodexUsageSample(
            deduplicationKey: 'sample-1',
            timestamp: createdAt,
            inputTokens: 30,
            cachedInputTokens: 5,
            outputTokens: 12,
            reasoningTokens: 2,
            totalTokens: 42,
          ),
        ],
      ),
    ],
  );
  final grok = GrokUsageIndexedSession(
    sourcePath: '/grok/session/updates.jsonl',
    fingerprint: '200:2',
    threadId: 'grok-thread',
    projectPath: '/work/grok',
    sourceKind: 'grok_acp',
    modifiedAt: createdAt,
    turns: <GrokUsageIndexedTurn>[
      GrokUsageIndexedTurn(
        id: 'grok-turn',
        status: AgentHistoryTurnStatus.completed,
        startedAt: createdAt,
        totalTokens: 60,
        errorMessage: 'secret prompt text',
        errorCode: 'provider-secret-code',
        errorCategoryHint: 'other',
      ),
    ],
  );
  return UsageStatisticsIndexSnapshot(
    codexSessions: <String, CodexUsageSessionSnapshot>{codex.sourceId: codex},
    grokSessions: <String, GrokUsageIndexedSession>{grok.sourceId: grok},
  );
}
