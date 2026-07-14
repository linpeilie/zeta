import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
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
      expect(snapshot.sessions, isEmpty);
    });

    test('saves and reloads the index after restart', () async {
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
      expect(encoded, contains('sourceId'));
      expect(encoded, isNot(contains('sourcePath')));
      expect(encoded, isNot(contains('/codex/sessions/rollout.jsonl')));
      expect(encoded, isNot(contains('errorMessage')));
      expect(encoded, isNot(contains('secret prompt text')));
      expect(encoded, isNot(contains('provider-secret-code')));
      expect(encoded, contains('errorCategoryHint'));
      expect(reloaded.sessions, hasLength(1));
      final session = reloaded.sessions.values.single;
      expect(
        reloaded.sessions.keys.single,
        original.sessions.values.single.sourceId,
      );
      expect(session.sourcePath, isEmpty);
      expect(session.threadId, 'thread-1');
      expect(session.turns.single.errorCode, isNull);
      expect(session.turns.single.samples.single.totalTokens, 42);
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
      expect(snapshot.sessions, isEmpty);
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
      expect(snapshot.sessions, isEmpty);
    });

    test('treats semantically damaged fields as an empty snapshot', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/usage_statistics_index.json'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"version":2,"sessions":[{'
        '"sourceId":"source","fingerprint":"fingerprint",'
        '"threadId":"thread","projectPath":"project",'
        '"sourceKind":"codex","createdAt":9223372036854775807,'
        '"turns":[]}]}',
      );

      // Act
      final snapshot = await FileUsageStatisticsIndexStore(file: file).load();

      // Assert
      expect(snapshot.sessions, isEmpty);
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
  final session = CodexUsageSessionSnapshot(
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
  return UsageStatisticsIndexSnapshot(
    sessions: <String, CodexUsageSessionSnapshot>{session.sourcePath: session},
  );
}
