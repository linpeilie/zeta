import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/codex_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/provider_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

import '../../../testing/agent_provider_stub_base.dart';

void main() {
  test(
    'aggregates model calls by turn, deduplicates sessions, and caches V2',
    () async {
      final provider = _UsageProvider();
      final scanner = _UsageScanner(_sessions());
      final store = MemoryUsageStatisticsIndexStore();
      final repository = CodexUsageStatisticsRepository(
        providerLoader: () async => provider,
        indexStore: store,
        scanner: scanner,
        environment: const <String, String>{'CODEX_HOME': r'C:\env-codex'},
        clock: () => DateTime(2026, 7, 10, 12),
      );

      final first = await repository.load(earliest: DateTime(2026, 7, 1));

      expect(scanner.codexHomes, <String>[r'C:\configured-codex']);
      expect(first.records, hasLength(2));
      final parent = first.records.firstWhere(
        (record) => record.threadId == 'parent',
      );
      expect(parent.tokens.inputTokens, 65);
      expect(parent.tokens.cachedInputTokens, 15);
      expect(parent.tokens.outputTokens, 24);
      expect(parent.tokens.reasoningTokens, 6);
      expect(parent.tokens.totalTokens, 110);
      final fork = first.records.firstWhere(
        (record) => record.threadId == 'fork',
      );
      // fork 中复制的 sample-a 被全局去重，只保留真正新增的 sample-c。
      expect(fork.tokens.totalTokens, 30);
      expect(first.quota?.planType, 'plus');

      expect(store.snapshot.sessions, hasLength(2));
      final encodedIndex = jsonEncode(store.snapshot.toJson());
      expect(encodedIndex, contains('reasoningTokens'));
      expect(encodedIndex, isNot(contains('prompt')));

      await repository.load(earliest: DateTime(2026, 7, 1));
      expect(scanner.cachedSessionCounts, <int>[0, 2]);
      await repository.load(earliest: DateTime(2026, 7, 1), forceRefresh: true);
      expect(scanner.forceRefreshes, <bool>[false, false, true]);
    },
  );

  test(
    'falls back from CODEX_HOME to injected environment and home directory',
    () async {
      final provider = _UsageProvider(configuredCodexHome: null);
      final scanner = _UsageScanner(
        const <String, CodexUsageSessionSnapshot>{},
      );
      final repository = CodexUsageStatisticsRepository(
        providerLoader: () async => provider,
        indexStore: MemoryUsageStatisticsIndexStore(),
        scanner: scanner,
        environment: const <String, String>{'CODEX_HOME': '/env/codex'},
        homeDirectory: '/home/test',
      );

      await repository.load(earliest: DateTime(2026, 7, 1));
      expect(scanner.codexHomes.single, '/env/codex');
    },
  );

  test('coalesces duplicate thread turns across rollout files', () async {
    final repository = CodexUsageStatisticsRepository(
      providerLoader: () async => _UsageProvider(),
      indexStore: MemoryUsageStatisticsIndexStore(),
      scanner: _UsageScanner(_duplicateTurnSessions()),
      environment: const <String, String>{},
      clock: () => DateTime(2026, 7, 10, 12),
    );

    final snapshot = await repository.load(earliest: DateTime(2026, 7, 1));

    expect(snapshot.records, hasLength(1));
    final record = snapshot.records.single;
    expect(record.id, 'thread-duplicate/turn-duplicate');
    expect(record.status, UsageTaskStatus.completed);
    expect(record.model, 'gpt-5');
    expect(record.projectPath, r'C:\work\zeta');
    expect(record.tokens.totalTokens, 30);
    expect(record.duration, const Duration(minutes: 2));
  });

  test('quota failure is a warning and does not hide local records', () async {
    final provider = _UsageProvider(quotaFails: true);
    final repository = CodexUsageStatisticsRepository(
      providerLoader: () async => provider,
      indexStore: MemoryUsageStatisticsIndexStore(),
      scanner: _UsageScanner(_sessions()),
    );

    final source = await repository.load(earliest: DateTime(2026, 7, 1));

    expect(source.records, isNotEmpty);
    expect(source.warnings, contains('Codex 当前未返回套餐额度信息。'));
  });

  test(
    'panel repository groups enabled configs and limits tokens to today',
    () async {
      final provider = _UsageProvider();
      final scanner = _UsageScanner(_sessions());
      final grokScanner = _GrokUsageScanner(<GrokUsageSessionSnapshot>[
        _grokUsageSession(),
      ]);
      final repository = ProviderAgentUsagePanelRepository(
        enabledProviderLoader: () async => <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig.defaultGrok,
        ],
        providerLoader: (_) async => provider,
        isSharedProvider: (_) => true,
        seedIndexStore: MemoryUsageStatisticsIndexStore(),
        scanner: scanner,
        grokScanner: grokScanner,
        clock: () => DateTime(2026, 7, 8, 12),
      );

      final events = await repository.load().toList();
      final directory = events
          .whereType<AgentUsagePanelProvidersDiscovered>()
          .single;
      final entries = events
          .whereType<AgentUsagePanelProviderLoaded>()
          .map((event) => event.entry)
          .toList();

      expect(events.first, same(directory));
      expect(
        directory.providers.map((provider) => provider.providerId),
        <String>[defaultAgentProviderId, grokAgentProviderId],
      );
      expect(entries, hasLength(2));
      final codex = entries.singleWhere(
        (entry) => entry.providerId == defaultAgentProviderId,
      );
      final grok = entries.singleWhere(
        (entry) => entry.providerId == grokAgentProviderId,
      );
      expect(codex.providerName, 'Codex');
      expect(grok.providerName, 'Grok');
      expect(codex.todayTokens?.totalTokens, 110);
      expect(codex.quota?.planType, 'plus');
      expect(grok.todayTokens?.totalTokens, 60);
      expect(grok.todayTokens?.inputTokens, 40);
      expect(grok.todayTokens?.cachedInputTokens, 10);
      expect(grok.todayTokens?.outputTokens, 8);
      expect(grok.todayTokens?.reasoningTokens, 2);
      expect(events.last, isA<AgentUsagePanelLoadCompleted>());
      expect(scanner.codexHomes, hasLength(1));
      expect(provider.quotaReadCount, 2);
    },
  );

  test(
    'panel repository starts providers in parallel and isolates failures',
    () async {
      final firstConfig = AgentProviderConfig.defaultGrok.copyWith(
        id: 'grok-first',
        displayName: 'Grok First',
      );
      final secondConfig = AgentProviderConfig.defaultGrok.copyWith(
        id: 'grok-second',
        displayName: 'Grok Second',
      );
      final providerLoads = <String, Completer<AgentProvider>>{
        firstConfig.id: Completer<AgentProvider>(),
        secondConfig.id: Completer<AgentProvider>(),
      };
      final startedProviders = <String>[];
      final repository = ProviderAgentUsagePanelRepository(
        enabledProviderLoader: () async => <AgentProviderConfig>[
          firstConfig,
          secondConfig,
        ],
        providerLoader: (config) {
          startedProviders.add(config.id);
          return providerLoads[config.id]!.future;
        },
        isSharedProvider: (_) => true,
        seedIndexStore: MemoryUsageStatisticsIndexStore(),
        scanner: _UsageScanner(const <String, CodexUsageSessionSnapshot>{}),
        grokScanner: _GrokUsageScanner(const <GrokUsageSessionSnapshot>[]),
        clock: () => DateTime(2026, 7, 8, 12),
      );

      final emitted = <AgentUsagePanelLoadEvent>[];
      final completed = repository.load().forEach(emitted.add);
      await Future<void>.delayed(Duration.zero);

      expect(startedProviders, <String>['grok-first', 'grok-second']);
      expect(emitted, hasLength(1));
      expect(emitted.single, isA<AgentUsagePanelProvidersDiscovered>());

      providerLoads['grok-second']!.complete(_UsageProvider());
      await Future<void>.delayed(Duration.zero);
      expect(
        (emitted[1] as AgentUsagePanelProviderLoaded).entry.providerId,
        'grok-second',
      );

      providerLoads['grok-first']!.completeError(StateError('offline'));
      await completed;

      expect(emitted[2], isA<AgentUsagePanelProviderFailed>());
      expect(
        (emitted[2] as AgentUsagePanelProviderFailed).provider.providerId,
        'grok-first',
      );
      expect(emitted.last, isA<AgentUsagePanelLoadCompleted>());
    },
  );

  test('safe cached index preserves the derived error category', () async {
    final createdAt = DateTime.utc(2026, 7, 8, 9);
    final session = CodexUsageSessionSnapshot(
      sourcePath: '/codex/rollout.jsonl',
      fingerprint: '100:1',
      threadId: 'thread-failed',
      projectPath: '/workspace/zeta',
      sourceKind: 'codex_cli_rs',
      createdAt: createdAt,
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-failed',
          status: AgentHistoryTurnStatus.failed,
          startedAt: createdAt,
          completedAt: createdAt.add(const Duration(seconds: 1)),
          errorMessage: 'network connection failed with private payload',
          samples: const <CodexUsageSample>[],
        ),
      ],
    );
    final encoded = jsonEncode(
      UsageStatisticsIndexSnapshot(
        sessions: <String, CodexUsageSessionSnapshot>{
          session.sourcePath: session,
        },
      ).toJson(),
    );
    final restored = UsageStatisticsIndexSnapshot.tryDecode(
      jsonDecode(encoded),
    );
    final indexStore = MemoryUsageStatisticsIndexStore()..snapshot = restored;
    final repository = CodexUsageStatisticsRepository(
      providerLoader: () async => _UsageProvider(),
      indexStore: indexStore,
      scanner: _UsageScanner(restored.sessions),
      clock: () => DateTime(2026, 7, 10),
    );

    final source = await repository.load(earliest: DateTime(2026, 7, 1));

    expect(encoded, contains('"errorCategoryHint":"network"'));
    expect(encoded, isNot(contains('private payload')));
    expect(source.records.single.errorCategory, UsageErrorCategory.network);
    expect(source.records.single.errorMessage, isNull);
  });

  test('damaged and V1 index content decode as an empty V2 snapshot', () {
    expect(
      UsageStatisticsIndexSnapshot.tryDecode(<String, Object?>{
        'version': 1,
        'threads': <Object?>[],
      }).sessions,
      isEmpty,
    );
    expect(UsageStatisticsIndexSnapshot.tryDecode('bad').sessions, isEmpty);
  });

  test('token breakdown persists reasoning and repairs old timestamps', () {
    final record = AgentUsageRecord.tryDecode(<String, Object?>{
      'threadId': 'thread-legacy',
      'turnId': 'turn-legacy',
      'providerId': 'codex',
      'providerName': 'Codex CLI',
      'projectPath': r'C:\work\zeta',
      'sourceKind': 'cli',
      'startedAt': 1783144800,
      'completedAt': 1783144803,
      'durationMs': 3000,
      'status': 'completed',
      'tokens': <String, Object?>{'totalTokens': 42, 'reasoningTokens': 7},
    });

    expect(record, isNotNull);
    expect(record!.providerName, 'Codex');
    expect(record.tokens.reasoningTokens, 7);
    expect(
      record.startedAt.toUtc(),
      DateTime.parse('2026-07-04T06:00:00.000Z'),
    );
    expect(record.toJson()['startedAt'], 1783144800000);
  });
}

Map<String, CodexUsageSessionSnapshot> _sessions() {
  final parentCreated = DateTime(2026, 7, 8, 9);
  final forkCreated = DateTime(2026, 7, 9, 9);
  final sampleA = CodexUsageSample(
    deduplicationKey: 'sample-a',
    timestamp: parentCreated.add(const Duration(seconds: 1)),
    inputTokens: 50,
    cachedInputTokens: 10,
    outputTokens: 16,
    reasoningTokens: 4,
    totalTokens: 80,
  );
  final sampleB = CodexUsageSample(
    deduplicationKey: 'sample-b',
    timestamp: parentCreated.add(const Duration(seconds: 2)),
    inputTokens: 15,
    cachedInputTokens: 5,
    outputTokens: 8,
    reasoningTokens: 2,
    totalTokens: 30,
  );
  final sampleC = CodexUsageSample(
    deduplicationKey: 'sample-c',
    timestamp: forkCreated.add(const Duration(seconds: 10)),
    inputTokens: 20,
    cachedInputTokens: 0,
    outputTokens: 8,
    reasoningTokens: 2,
    totalTokens: 30,
  );
  return <String, CodexUsageSessionSnapshot>{
    '/codex/parent.jsonl': CodexUsageSessionSnapshot(
      sourcePath: '/codex/parent.jsonl',
      fingerprint: '100:1',
      threadId: 'parent',
      projectPath: r'C:\work\zeta',
      sourceKind: 'codex_cli_rs',
      createdAt: parentCreated,
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-parent',
          status: AgentHistoryTurnStatus.completed,
          startedAt: parentCreated,
          completedAt: parentCreated.add(const Duration(minutes: 1)),
          model: 'gpt-5',
          samples: <CodexUsageSample>[sampleA, sampleB],
        ),
      ],
    ),
    '/codex/fork.jsonl': CodexUsageSessionSnapshot(
      sourcePath: '/codex/fork.jsonl',
      fingerprint: '120:2',
      threadId: 'fork',
      projectPath: r'C:\work\zeta',
      sourceKind: 'codex_cli_rs',
      createdAt: forkCreated,
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-fork',
          status: AgentHistoryTurnStatus.completed,
          startedAt: forkCreated,
          completedAt: forkCreated.add(const Duration(minutes: 1)),
          model: 'gpt-5',
          samples: <CodexUsageSample>[sampleA, sampleC],
        ),
      ],
    ),
  };
}

Map<String, CodexUsageSessionSnapshot> _duplicateTurnSessions() {
  final startedAt = DateTime(2026, 7, 8, 9);
  final firstSample = CodexUsageSample(
    deduplicationKey: 'duplicate-sample-a',
    timestamp: startedAt.add(const Duration(seconds: 1)),
    inputTokens: 6,
    cachedInputTokens: 1,
    outputTokens: 2,
    reasoningTokens: 1,
    totalTokens: 10,
  );
  final secondSample = CodexUsageSample(
    deduplicationKey: 'duplicate-sample-b',
    timestamp: startedAt.add(const Duration(seconds: 2)),
    inputTokens: 12,
    cachedInputTokens: 2,
    outputTokens: 4,
    reasoningTokens: 2,
    totalTokens: 20,
  );
  return <String, CodexUsageSessionSnapshot>{
    '/codex/duplicate-partial.jsonl': CodexUsageSessionSnapshot(
      sourcePath: '/codex/duplicate-partial.jsonl',
      fingerprint: '100:1',
      threadId: 'thread-duplicate',
      projectPath: r'C:\work\old',
      sourceKind: 'codex_cli_rs',
      createdAt: startedAt,
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-duplicate',
          status: AgentHistoryTurnStatus.running,
          startedAt: startedAt,
          samples: <CodexUsageSample>[firstSample],
        ),
      ],
    ),
    '/codex/duplicate-complete.jsonl': CodexUsageSessionSnapshot(
      sourcePath: '/codex/duplicate-complete.jsonl',
      fingerprint: '200:2',
      threadId: 'thread-duplicate',
      projectPath: r'C:\work\new',
      sourceKind: 'codex_cli_rs',
      createdAt: startedAt.add(const Duration(minutes: 1)),
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-duplicate',
          status: AgentHistoryTurnStatus.completed,
          startedAt: startedAt,
          completedAt: startedAt.add(const Duration(minutes: 2)),
          cwd: r'C:\work\zeta',
          model: 'gpt-5',
          samples: <CodexUsageSample>[firstSample, secondSample],
        ),
      ],
    ),
  };
}

class _UsageScanner implements CodexUsageLogScanner {
  _UsageScanner(this.sessions);

  final Map<String, CodexUsageSessionSnapshot> sessions;
  final List<String> codexHomes = <String>[];
  final List<int> cachedSessionCounts = <int>[];
  final List<bool> forceRefreshes = <bool>[];

  @override
  Future<CodexUsageScanResult> scan({
    required String codexHome,
    required Map<String, CodexUsageSessionSnapshot> cachedSessions,
    bool forceRefresh = false,
  }) async {
    codexHomes.add(codexHome);
    cachedSessionCounts.add(cachedSessions.length);
    forceRefreshes.add(forceRefresh);
    return CodexUsageScanResult(sessions: sessions, warnings: const <String>[]);
  }
}

GrokUsageSessionSnapshot _grokUsageSession() {
  final startedAt = DateTime(2026, 7, 8, 10);
  return GrokUsageSessionSnapshot(
    sourcePath: '/grok/session/updates.jsonl',
    threadId: 'grok-thread',
    projectPath: '/work/grok',
    modifiedAt: startedAt,
    history: AgentThreadHistorySnapshot(
      threadId: 'grok-thread',
      turns: <AgentHistoryTurn>[
        AgentHistoryTurn(
          id: 'grok-turn',
          status: AgentHistoryTurnStatus.completed,
          startedAt: startedAt,
          tokenUsage: const AgentTokenUsage(
            inputTokens: 50,
            cachedInputTokens: 10,
            outputTokens: 10,
            reasoningOutputTokens: 2,
            totalTokens: 60,
          ),
          tokenUsageIsSessionCumulative: false,
        ),
      ],
    ),
  );
}

class _GrokUsageScanner implements GrokUsageLogScanner {
  _GrokUsageScanner(this.sessions);

  final List<GrokUsageSessionSnapshot> sessions;

  @override
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    bool forceRefresh = false,
  }) async {
    return GrokUsageScanResult(sessions: sessions, warnings: const <String>[]);
  }
}

class _UsageProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider, AgentUsageQuotaProvider {
  _UsageProvider({
    this.configuredCodexHome = r'C:\configured-codex',
    this.quotaFails = false,
  });

  final String? configuredCodexHome;
  final bool quotaFails;
  var quotaReadCount = 0;

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex.copyWith(
    environment: <String, String>{'CODEX_HOME': ?configuredCodexHome},
  );

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query}) =>
      throw StateError('usage statistics must scan JSONL directly');

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) => throw StateError('usage statistics must scan JSONL directly');

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    quotaReadCount += 1;
    if (quotaFails) {
      throw StateError('quota unavailable');
    }
    return const AgentUsageQuotaSnapshot(
      providerId: 'codex',
      providerName: 'Codex',
      planType: 'plus',
      windows: <AgentUsageWindow>[
        AgentUsageWindow(label: '主要额度', usedPercent: 25),
      ],
    );
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) =>
      throw UnimplementedError();

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) => throw UnimplementedError();

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) => throw UnimplementedError();

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
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) => throw UnimplementedError();

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
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
