// Test fixtures intentionally exercise the filesystem-shaped vendor readers.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/claude_code_client.dart';
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:test/test.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:usage_statistics_storage_client/usage_statistics_storage_client.dart';

void main() {
  final start = DateTime.utc(2026, 8, 20);
  final end = start.add(const Duration(days: 1));
  final refreshedAt = end.add(const Duration(minutes: 1));

  group('usage domain models', () {
    test('expose stable equality and derived status/token semantics', () {
      expect(UsageTaskStatus.running.isTerminal, isFalse);
      expect(UsageTaskStatus.unknown.isTerminal, isFalse);
      expect(UsageTaskStatus.completed.isTerminal, isTrue);
      expect(UsageTaskStatus.interrupted.isFailure, isTrue);
      expect(UsageTaskStatus.failed.isFailure, isTrue);
      expect(UsageTaskStatus.completed.isFailure, isFalse);
      const reported = UsageTokenBreakdown(totalTokens: 9);
      const calculated = UsageTokenBreakdown(
        inputTokens: 1,
        cachedInputTokens: 2,
        outputTokens: 3,
        reasoningTokens: 4,
      );
      const absent = UsageTokenBreakdown();
      expect(reported.effectiveTotal, 9);
      expect(calculated.effectiveTotal, 10);
      expect(absent.effectiveTotal, isNull);
      expect(calculated.props, [1, 2, 3, 4, null]);
      expect(
        calculated,
        const UsageTokenBreakdown(
          inputTokens: 1,
          cachedInputTokens: 2,
          outputTokens: 3,
          reasoningTokens: 4,
        ),
      );
    });

    test('freezes report collections and exposes value equality', () {
      final records = <UsageRecord>[_record(start)];
      final warnings = <UsageWarning>[
        const UsageWarning(
          providerId: 'codex-main',
          code: UsageWarningCode.providerFailure,
        ),
      ];
      final query = UsageStatisticsQuery(
        startInclusive: start,
        endExclusive: end,
      );
      const totals = UsageTotals(
        calls: 1,
        failures: 0,
        inputTokens: 1,
        cachedInputTokens: 2,
        outputTokens: 3,
        reasoningTokens: 4,
        totalTokens: 10,
      );
      final report = UsageStatisticsReport(
        query: query,
        records: records,
        totals: totals,
        warnings: warnings,
        refreshedAt: refreshedAt,
      );
      records.clear();
      warnings.clear();
      expect(report.records, hasLength(1));
      expect(report.warnings, hasLength(1));
      expect(report.records.clear, throwsUnsupportedError);
      expect(
        report,
        UsageStatisticsReport(
          query: UsageStatisticsQuery(startInclusive: start, endExclusive: end),
          records: [_record(start)],
          totals: totals,
          warnings: const [
            UsageWarning(
              providerId: 'codex-main',
              code: UsageWarningCode.providerFailure,
            ),
          ],
          refreshedAt: refreshedAt,
        ),
      );
      expect(
        const UsageProviderIdentity(id: 'codex', name: 'Codex').id,
        'codex',
      );
      expect(
        const UsageProviderIdentity(id: 'codex', name: 'Codex').name,
        'Codex',
      );
      expect(_record(start).id, 'codex-main:thread:turn');
      expect(
        const UsageQuotaResult(providerId: 'codex'),
        const UsageQuotaResult(providerId: 'codex'),
      );
      expect(
        const UsageQuotaResult(providerId: 'codex'),
        isNot(const UsageQuotaResult(providerId: 'codex', failed: true)),
      );
    });
  });

  group('UsageStatisticsRepository', () {
    late Directory temporaryDirectory;
    late File codexFile;
    late File claudeFile;
    late File grokFile;
    late _MemoryStorage storage;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('usage-repo');
      codexFile = await File(
        '${temporaryDirectory.path}${Platform.pathSeparator}codex.jsonl',
      ).writeAsString('codex');
      claudeFile = await File(
        '${temporaryDirectory.path}${Platform.pathSeparator}claude.jsonl',
      ).writeAsString('claude');
      grokFile = await File(
        '${temporaryDirectory.path}${Platform.pathSeparator}grok.jsonl',
      ).writeAsString('grok');
      storage = _MemoryStorage();
    });

    tearDown(() async => temporaryDirectory.delete(recursive: true));

    test(
      'aggregates all vendors, cache, totals, ordering, and warnings',
      () async {
        final repository = _repository(
          codex: _codexReader(
            file: codexFile,
            start: start,
            duplicateSample: true,
          ),
          claude: _claudeReader(file: claudeFile, start: start),
          grok: _grokReader(file: grokFile, start: start),
          storage: storage,
          clock: () => refreshedAt,
        );
        final report = await repository.report(
          UsageStatisticsQuery(startInclusive: start, endExclusive: end),
        );
        expect(report.records.map((record) => record.providerId), [
          'grok-main',
          'claude-main',
          'codex-main',
        ]);
        expect(report.records.first.projectPath, 'C:/grok-turn');
        expect(report.records[1].duration, const Duration(seconds: 3));
        expect(report.records[1].timeToFirstToken, const Duration(seconds: 1));
        expect(report.records[2].duration, const Duration(seconds: 2));
        expect(
          report.totals,
          const UsageTotals(
            calls: 3,
            failures: 1,
            inputTokens: 6,
            cachedInputTokens: 9,
            outputTokens: 12,
            reasoningTokens: 15,
            totalTokens: 42,
          ),
        );
        expect(report.warnings, isEmpty);
        expect(report.refreshedAt, refreshedAt);
        expect(storage.contents, isNotNull);
        expect(storage.contents, isNot(contains(codexFile.path)));
      },
    );

    test(
      'uses same-query cache and rebuilds changed or forced query',
      () async {
        var codexInput = 1;
        final repository = _repository(
          codex: _codexReader(
            file: codexFile,
            start: start,
            inputTokens: () => codexInput,
          ),
          claude: _emptyClaude(),
          grok: _emptyGrok(),
          storage: storage,
          clock: () => refreshedAt,
        );
        final query = UsageStatisticsQuery(
          startInclusive: start,
          endExclusive: end,
        );
        expect((await repository.report(query)).totals.inputTokens, 1);
        codexInput = 20;
        expect((await repository.report(query)).totals.inputTokens, 1);
        expect(
          (await repository.report(
            UsageStatisticsQuery(
              startInclusive: start.subtract(const Duration(hours: 1)),
              endExclusive: end,
            ),
          )).totals.inputTokens,
          20,
        );
        codexInput = 30;
        expect(
          (await repository.report(
            UsageStatisticsQuery(
              startInclusive: start,
              endExclusive: end,
              forceRefresh: true,
            ),
          )).totals.inputTokens,
          30,
        );
      },
    );

    test('deduplicates Codex replay samples across source files', () async {
      final fork = await File(
        '${temporaryDirectory.path}${Platform.pathSeparator}codex-fork.jsonl',
      ).writeAsString('fork');
      final repository = _repository(
        codex: CodexUsageReader(
          codexHome: 'unused',
          discoverFiles: (_) => Stream.fromIterable([codexFile, fork]),
          loadSource: (file, {isCancelled}) async => _codexLoaded(start),
          statFile: (file) => file.stat(),
        ),
        claude: _emptyClaude(),
        grok: _emptyGrok(),
        storage: storage,
        clock: () => refreshedAt,
      );

      final report = await repository.report(
        UsageStatisticsQuery(startInclusive: start, endExclusive: end),
      );

      expect(report.records, hasLength(1));
      expect(report.records.single.deduplicationKey, 'sample');
      expect(report.totals.totalTokens, 10);
    });

    test(
      'reports source and discovery problems without failing peers',
      () async {
        final badCodex = await File(
          '${temporaryDirectory.path}${Platform.pathSeparator}bad-codex.jsonl',
        ).writeAsString('bad');
        final badGrok = await File(
          '${temporaryDirectory.path}${Platform.pathSeparator}bad-grok.jsonl',
        ).writeAsString('bad');
        final repository = _repository(
          codex: CodexUsageReader(
            codexHome: 'unused',
            discoverFiles: (_) async* {
              yield codexFile;
              yield badCodex;
              throw const FileSystemException('discovery');
            },
            loadSource: (file, {isCancelled}) async =>
                file.path == codexFile.path ? _codexLoaded(start) : null,
            statFile: (file) => file.stat(),
          ),
          claude: ClaudeCodeUsageReader(
            claudeHome: 'unused',
            discoverFiles: (_) => Stream.error(StateError('provider')),
            loadSource: (_) async => null,
            statFile: (file) => file.stat(),
          ),
          grok: GrokUsageReader(
            grokHome: 'unused',
            discoverFiles: (_) => Stream.value(badGrok),
            loadSource: (_) async => null,
            statFile: (file) => file.stat(),
          ),
          storage: storage,
          clock: () => refreshedAt,
        );
        final report = await repository.report(
          UsageStatisticsQuery(startInclusive: start, endExclusive: end),
        );
        expect(report.records, hasLength(1));
        expect(
          report.warnings,
          containsAll(<UsageWarning>[
            const UsageWarning(
              providerId: 'codex-main',
              code: UsageWarningCode.unreadableSources,
            ),
            const UsageWarning(
              providerId: 'codex-main',
              code: UsageWarningCode.discoveryFailure,
            ),
            const UsageWarning(
              providerId: 'claude-main',
              code: UsageWarningCode.providerFailure,
            ),
            const UsageWarning(
              providerId: 'grok-main',
              code: UsageWarningCode.unreadableSources,
            ),
          ]),
        );
      },
    );

    test('turns cache failures into typed warnings', () async {
      storage
        ..failReads = true
        ..failWrites = true;
      final repository = _repository(
        codex: _codexReader(file: codexFile, start: start),
        claude: _emptyClaude(),
        grok: _emptyGrok(),
        storage: storage,
        clock: () => refreshedAt,
      );
      final report = await repository.report(
        UsageStatisticsQuery(startInclusive: start, endExclusive: end),
      );
      expect(report.records, hasLength(1));
      expect(
        report.warnings.map((warning) => warning.code),
        containsAll([
          UsageWarningCode.cacheReadFailure,
          UsageWarningCode.cacheWriteFailure,
        ]),
      );
    });

    test('rejects invalid ranges and translates cancellation', () async {
      final repository = _repository(
        codex: _emptyCodex(),
        claude: _emptyClaude(),
        grok: _emptyGrok(),
        storage: storage,
        clock: () => refreshedAt,
      );
      await expectLater(
        repository.report(
          UsageStatisticsQuery(startInclusive: end, endExclusive: start),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.report(
          UsageStatisticsQuery(startInclusive: start, endExclusive: end),
          isCancelled: () => true,
        ),
        throwsA(isA<UsageStatisticsCancelledException>()),
      );
      expect(
        const UsageStatisticsCancelledException().toString(),
        'UsageStatisticsCancelledException()',
      );
    });

    test('translates vendor cancellation', () async {
      final repository = _repository(
        codex: CodexUsageReader(
          codexHome: 'unused',
          discoverFiles: (_) => Stream.value(codexFile),
          loadSource: (file, {isCancelled}) async =>
              throw const CodexUsageScanCancelledException(),
          statFile: (file) => file.stat(),
        ),
        claude: _emptyClaude(),
        grok: _emptyGrok(),
        storage: storage,
        clock: () => refreshedAt,
      );
      await expectLater(
        repository.report(
          UsageStatisticsQuery(startInclusive: start, endExclusive: end),
        ),
        throwsA(isA<UsageStatisticsCancelledException>()),
      );
    });

    test('isolates unexpected Codex and Grok provider failures', () async {
      final repository = _repository(
        codex: CodexUsageReader(
          codexHome: 'unused',
          discoverFiles: (_) => Stream.error(StateError('codex')),
        ),
        claude: _emptyClaude(),
        grok: GrokUsageReader(
          grokHome: 'unused',
          discoverFiles: (_) => Stream.error(StateError('grok')),
        ),
        storage: storage,
        clock: () => refreshedAt,
      );

      final report = await repository.report(
        UsageStatisticsQuery(startInclusive: start, endExclusive: end),
      );

      expect(
        report.warnings,
        containsAll(const [
          UsageWarning(
            providerId: 'codex-main',
            code: UsageWarningCode.providerFailure,
          ),
          UsageWarning(
            providerId: 'grok-main',
            code: UsageWarningCode.providerFailure,
          ),
        ]),
      );
    });

    test('translates Grok vendor cancellation', () async {
      final repository = _repository(
        codex: _emptyCodex(),
        claude: _emptyClaude(),
        grok: GrokUsageReader(
          grokHome: 'unused',
          discoverFiles: (_) => Stream.value(grokFile),
          loadSource: (_) async =>
              throw const GrokUsageScanCancelledException(),
        ),
        storage: storage,
        clock: () => refreshedAt,
      );

      await expectLater(
        repository.report(
          UsageStatisticsQuery(startInclusive: start, endExclusive: end),
        ),
        throwsA(isA<UsageStatisticsCancelledException>()),
      );
    });

    test(
      'collects quota providers in stable order with partial failures',
      () async {
        final snapshot = AgentUsageQuotaSnapshot(
          providerId: 'b',
          providerName: 'B',
          windows: const [],
        );
        final repository = _repository(
          codex: _emptyCodex(),
          claude: _emptyClaude(),
          grok: _emptyGrok(),
          storage: storage,
          clock: () => refreshedAt,
          quotaProviders: {
            'c': _QuotaProvider(error: StateError('private')),
            'b': _QuotaProvider(snapshot: snapshot),
            'a': const _QuotaProvider(),
          },
        );
        final quotas = await repository.quotaSnapshots();
        expect(quotas.map((result) => result.providerId), ['a', 'b', 'c']);
        expect(quotas[0].snapshot, isNull);
        expect(quotas[0].failed, isFalse);
        expect(quotas[1].snapshot, same(snapshot));
        expect(quotas[2].failed, isTrue);
      },
    );
  });
}

UsageRecord _record(DateTime startedAt) => UsageRecord(
  threadId: 'thread',
  turnId: 'turn',
  providerId: 'codex-main',
  providerName: 'Codex',
  projectPath: 'C:/work',
  sourceKind: 'codex',
  startedAt: startedAt,
  status: UsageTaskStatus.completed,
  tokens: const UsageTokenBreakdown(
    inputTokens: 1,
    cachedInputTokens: 2,
    outputTokens: 3,
    reasoningTokens: 4,
  ),
);

UsageStatisticsRepository _repository({
  required CodexUsageReader codex,
  required ClaudeCodeUsageReader claude,
  required GrokUsageReader grok,
  required _MemoryStorage storage,
  required DateTime Function() clock,
  Map<String, AgentUsageQuotaProvider> quotaProviders = const {},
}) => UsageStatisticsRepository(
  codex: codex,
  claude: claude,
  grok: grok,
  cacheStore: UsagePartitionStore(storage: storage),
  codexProvider: const UsageProviderIdentity(id: 'codex-main', name: 'Codex'),
  claudeProvider: const UsageProviderIdentity(
    id: 'claude-main',
    name: 'Claude Code',
  ),
  grokProvider: const UsageProviderIdentity(id: 'grok-main', name: 'Grok'),
  quotaProviders: quotaProviders,
  clock: clock,
);

CodexUsageReader _codexReader({
  required File file,
  required DateTime start,
  bool duplicateSample = false,
  int Function()? inputTokens,
}) => CodexUsageReader(
  codexHome: 'unused',
  discoverFiles: (_) => Stream.value(file),
  loadSource: (file, {isCancelled}) async {
    final loaded = _codexLoaded(start, inputTokens: inputTokens?.call() ?? 1);
    if (!duplicateSample) return loaded;
    final turn = loaded.turns.single;
    return CodexUsageLoadedSource(
      threadId: loaded.threadId,
      projectPath: loaded.projectPath,
      sourceKind: loaded.sourceKind,
      createdAt: loaded.createdAt,
      turns: [
        CodexUsageTurnResponse(
          id: turn.id,
          status: turn.status,
          startedAt: turn.startedAt,
          completedAt: turn.completedAt,
          cwd: turn.cwd,
          model: turn.model,
          samples: [turn.samples.single, turn.samples.single],
        ),
      ],
    );
  },
  statFile: (file) => file.stat(),
);

CodexUsageLoadedSource _codexLoaded(DateTime start, {int inputTokens = 1}) =>
    CodexUsageLoadedSource(
      threadId: 'codex-thread',
      projectPath: 'C:/codex-project',
      sourceKind: 'codex_cli_rs',
      createdAt: start,
      turns: [
        CodexUsageTurnResponse(
          id: 'codex-turn',
          status: 'completed',
          startedAt: start,
          completedAt: start.add(const Duration(seconds: 3)),
          cwd: ' ',
          model: 'gpt-5',
          samples: [
            CodexUsageSampleResponse(
              deduplicationKey: 'sample',
              timestamp: start.add(const Duration(seconds: 1)),
              inputTokens: inputTokens,
              cachedInputTokens: 2,
              outputTokens: 3,
              reasoningTokens: 4,
              totalTokens: inputTokens + 9,
            ),
          ],
        ),
      ],
    );

ClaudeCodeUsageReader _claudeReader({
  required File file,
  required DateTime start,
}) => ClaudeCodeUsageReader(
  claudeHome: 'unused',
  discoverFiles: (_) => Stream.value(file),
  loadSource: (_) async => ClaudeCodeUsageLoadedSource(
    threadId: 'claude-thread',
    projectPath: 'C:/claude-project',
    turns: [
      ClaudeCodeUsageTurnResponse(
        id: 'claude-turn',
        status: 'failed',
        tokenUsageIsSessionCumulative: false,
        startedAt: start.add(const Duration(minutes: 1)),
        completedAt: start.add(const Duration(minutes: 1, seconds: 3)),
        timeToFirstToken: const Duration(seconds: 1),
        cwd: '',
        model: 'claude',
        inputTokens: 2,
        cachedInputTokens: 3,
        outputTokens: 4,
        reasoningTokens: 5,
        totalTokens: 14,
      ),
    ],
  ),
  statFile: (file) => file.stat(),
);

GrokUsageReader _grokReader({required File file, required DateTime start}) =>
    GrokUsageReader(
      grokHome: 'unused',
      discoverFiles: (_) => Stream.value(file),
      loadSource: (_) async => GrokUsageLoadedSource(
        threadId: 'grok-thread',
        projectPath: 'C:/grok-project',
        turns: [
          GrokUsageTurnResponse(
            id: 'grok-turn',
            status: 'success',
            startedAt: start.add(const Duration(minutes: 2)),
            completedAt: start.add(const Duration(minutes: 1)),
            cwd: ' C:/grok-turn ',
            model: 'grok',
            inputTokens: 3,
            cachedInputTokens: 4,
            outputTokens: 5,
            reasoningTokens: 6,
          ),
        ],
      ),
      statFile: (file) => file.stat(),
    );

CodexUsageReader _emptyCodex() => CodexUsageReader(
  codexHome: 'unused',
  discoverFiles: (_) => const Stream.empty(),
);
ClaudeCodeUsageReader _emptyClaude() => ClaudeCodeUsageReader(
  claudeHome: 'unused',
  discoverFiles: (_) => const Stream.empty(),
);
GrokUsageReader _emptyGrok() => GrokUsageReader(
  grokHome: 'unused',
  discoverFiles: (_) => const Stream.empty(),
);

final class _MemoryStorage implements UsageDocumentStorage {
  String? contents;
  bool failReads = false;
  bool failWrites = false;
  @override
  Future<String?> read() async {
    if (failReads) throw const FileSystemException('read');
    return contents;
  }

  @override
  Future<void> write(String contents) async {
    if (failWrites) throw const FileSystemException('write');
    this.contents = contents;
  }

  @override
  Future<void> close() async {}
}

final class _QuotaProvider implements AgentUsageQuotaProvider {
  const _QuotaProvider({this.snapshot, this.error});
  final AgentUsageQuotaSnapshot? snapshot;
  final Object? error;
  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    if (error case final error?) throw StateError(error.toString());
    return snapshot;
  }
}
