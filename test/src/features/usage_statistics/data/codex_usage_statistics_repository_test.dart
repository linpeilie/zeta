import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/codex_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

import '../../../testing/agent_provider_stub_base.dart';

void main() {
  test(
    'indexes root Codex turns, deltas cumulative tokens, and reuses cache',
    () async {
      final provider = _UsageProvider();
      final store = MemoryUsageStatisticsIndexStore();
      final repository = CodexUsageStatisticsRepository(
        providerLoader: () async => provider,
        indexStore: store,
        clock: () => DateTime(2026, 7, 10, 12),
      );

      final first = await repository.load(earliest: DateTime(2026, 7, 1));

      expect(provider.queries, hasLength(2));
      expect(
        provider.queries.every((query) => query.projectPath == null),
        isTrue,
      );
      expect(provider.queries.first.sourceKinds, [
        'cli',
        'vscode',
        'exec',
        'appServer',
      ]);
      expect(provider.historyReads, 1);
      expect(first.records, hasLength(2));
      expect(first.records.first.tokens.totalTokens, 150);
      expect(first.records.last.tokens.totalTokens, 100);
      expect(first.records.first.status, UsageTaskStatus.interrupted);
      expect(first.records.first.errorCategory, UsageErrorCategory.cancelled);
      expect(first.quota?.planType, 'plus');

      final encodedIndex = jsonEncode(store.snapshot.toJson());
      expect(encodedIndex, isNot(contains('prompt')));
      expect(encodedIndex, isNot(contains('reply')));
      expect(encodedIndex, isNot(contains('.jsonl')));
      expect(encodedIndex, isNot(contains('user_cancelled')));

      await repository.load(earliest: DateTime(2026, 7, 1));
      expect(provider.historyReads, 1);

      await repository.load(earliest: DateTime(2026, 7, 1), forceRefresh: true);
      expect(provider.historyReads, 2);
    },
  );

  test('damaged or older index content decodes as an empty snapshot', () {
    expect(
      UsageStatisticsIndexSnapshot.tryDecode(<String, Object?>{
        'version': 99,
        'threads': 'damaged',
      }).threads,
      isEmpty,
    );
    expect(UsageStatisticsIndexSnapshot.tryDecode('bad').threads, isEmpty);
  });
}

class _UsageProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider, AgentUsageQuotaProvider {
  final List<AgentThreadListQuery> queries = <AgentThreadListQuery>[];
  int historyReads = 0;

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    queries.add(query);
    if (query.archived) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }
    return AgentThreadPage(
      threads: <AgentThreadSummary>[
        AgentThreadSummary(
          id: 'thread-1',
          providerId: config.id,
          projectPath: r'C:\work\zeta',
          sessionPath: r'C:\users\me\.codex\thread-1.jsonl',
          preview: 'private text must not be indexed',
          createdAt: DateTime(2026, 7, 8, 9),
          updatedAt: DateTime(2026, 7, 9, 10),
          status: AgentThreadRuntimeStatus.idle,
          raw: const <String, Object?>{
            'source': <String, Object?>{'type': 'cli'},
          },
        ),
      ],
      nextCursor: null,
    );
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    historyReads += 1;
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: <AgentHistoryTurn>[
        AgentHistoryTurn(
          id: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          startedAt: DateTime(2026, 7, 8, 9),
          completedAt: DateTime(2026, 7, 8, 9, 2),
          duration: const Duration(minutes: 2),
          timeToFirstToken: const Duration(seconds: 2),
          cwd: r'C:\work\zeta',
          model: 'gpt-5',
          tokenUsage: const AgentTokenUsage(
            inputTokens: 70,
            outputTokens: 30,
            totalTokens: 100,
          ),
        ),
        AgentHistoryTurn(
          id: 'turn-2',
          status: AgentHistoryTurnStatus.interrupted,
          startedAt: DateTime(2026, 7, 9, 9),
          completedAt: DateTime(2026, 7, 9, 9, 1),
          duration: const Duration(minutes: 1),
          cwd: r'C:\work\zeta',
          model: 'gpt-5',
          tokenUsage: const AgentTokenUsage(
            inputTokens: 180,
            outputTokens: 70,
            totalTokens: 250,
          ),
          errorMessage: 'user_cancelled',
        ),
      ],
    );
  }

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    return const AgentUsageQuotaSnapshot(
      providerId: 'codex',
      providerName: 'Codex CLI',
      planType: 'plus',
      windows: <AgentUsageWindow>[
        AgentUsageWindow(label: '主要额度', usedPercent: 25),
      ],
    );
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) {
    throw UnimplementedError();
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {}

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async =>
      const <AgentPermissionProfileSummary>[];

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  @override
  Future<void> unsubscribeThread(String threadId) async {}

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {}
}
