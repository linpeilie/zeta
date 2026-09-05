import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

import '../../testing/usage_statistics_test_bindings.dart';

void main() {
  group('UsageStatisticsSlice', () {
    test('迟到加载只结算调用方，不覆盖最新报表', () async {
      final repository = _ControlledUsageStatisticsRepository();
      final bindings = UsageStatisticsTestBindings(
        repository: repository,
        clock: () => DateTime(2026, 8, 23, 12),
      );
      final now = DateTime(2026, 8, 23, 12);
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      final initialize = store.initialize();
      await _flushEvents();
      final refresh = store.refresh();
      await _flushEvents();

      expect(repository.requests, hasLength(2));
      expect(repository.requests.first.forceRefresh, isFalse);
      expect(repository.requests.last.forceRefresh, isTrue);

      final latest = _usageSource(refreshedAt: now);
      repository.requests.last.complete(latest);
      await refresh;
      expect(store.source, same(latest));
      expect(store.report, isNotNull);

      final stale = _usageSource(
        refreshedAt: now.subtract(const Duration(hours: 1)),
      );
      repository.requests.first.complete(stale);
      await initialize;

      expect(store.source, same(latest));
      expect(store.loading, isFalse);
      expect(store.state.initialized, isTrue);
    });

    test('扩大时间窗口时补读更早数据，已覆盖窗口不重复查询', () async {
      final repository = _ControlledUsageStatisticsRepository();
      final now = DateTime(2026, 8, 23, 12);
      final bindings = UsageStatisticsTestBindings(
        repository: repository,
        clock: () => now,
      );
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      final initialize = store.initialize();
      await _flushEvents();
      final initialEarliest = repository.requests.single.earliest;
      repository.requests.single.complete(_usageSource(refreshedAt: now));
      await initialize;

      final expand = store.selectTimePreset(UsageTimeRangePreset.last90Days);
      await _flushEvents();
      expect(repository.requests, hasLength(2));
      expect(
        repository.requests.last.earliest.isBefore(initialEarliest),
        isTrue,
      );
      repository.requests.last.complete(_usageSource(refreshedAt: now));
      await expand;

      await store.selectTimePreset(UsageTimeRangePreset.last30Days);
      expect(repository.requests, hasLength(2));
    });

    test('筛选、报表和失效选项清理保持既有语义', () async {
      final sliceRepository = _ControlledUsageStatisticsRepository();
      final now = DateTime(2026, 8, 23, 12);
      final bindings = UsageStatisticsTestBindings(
        repository: sliceRepository,
        clock: () => now,
      );
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      final sliceInitialize = store.initialize();
      await _flushEvents();
      final source = _usageSourceWithRecords(now);
      sliceRepository.requests.single.complete(source);
      await sliceInitialize;

      store
        ..selectProject('/workspace/zeta')
        ..selectProvider('codex')
        ..selectModel('gpt-5')
        ..selectRankSort(UsageRankSort.totalTokens);

      _expectEquivalentReports(
        store.report!,
        buildUsageStatisticsReport(
          source: source,
          window: store.window,
          filter: const UsageStatisticsFilter(
            projectPath: '/workspace/zeta',
            providerId: 'codex',
            model: 'gpt-5',
          ),
          trendMetric: UsageTrendMetric.totalTokens,
          rankSort: UsageRankSort.totalTokens,
        ),
      );
      expect(store.projectPath, '/workspace/zeta');
      expect(store.providerId, 'codex');
      expect(store.model, 'gpt-5');

      final sliceRefresh = store.refresh();
      await _flushEvents();
      final replacement = UsageStatisticsSourceSnapshot(
        records: <AgentUsageRecord>[
          _usageRecord(
            threadId: 'thread-grok',
            providerId: 'grok',
            providerName: 'Grok',
            projectPath: '/workspace/other',
            model: 'grok-4',
            startedAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        refreshedAt: now,
      );
      sliceRepository.requests.last.complete(replacement);
      await sliceRefresh;

      expect(store.projectPath, isNull);
      expect(store.providerId, isNull);
      expect(store.model, isNull);
      _expectEquivalentReports(
        store.report!,
        buildUsageStatisticsReport(
          source: replacement,
          window: store.window,
          filter: const UsageStatisticsFilter(),
          trendMetric: UsageTrendMetric.totalTokens,
          rankSort: UsageRankSort.totalTokens,
        ),
      );
    });

    test('关闭 store 会正常结算在途 Future，迟到结果不再回流', () async {
      final repository = _ControlledUsageStatisticsRepository();
      final bindings = UsageStatisticsTestBindings(repository: repository);
      final store = bindings.notifier;

      final initialize = store.initialize();
      await _flushEvents();
      bindings.dispose();

      await initialize;
      repository.requests.single.complete(
        _usageSource(refreshedAt: DateTime(2026, 8, 23, 12)),
      );
      await _flushEvents();

      expect(store.isClosed, isTrue);
      expect(store.source, isNull);
    });
  });

  group('AgentUsagePanelSlice', () {
    test('恢复偏好后首次只加载目标 Provider 且不重复回写', () async {
      final repository = _ControlledAgentUsagePanelRepository();
      final persistedSelections = <String?>[];
      final bindings = AgentUsagePanelTestBindings(
        repository: repository,
        onSelectionChanged: persistedSelections.add,
      );
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      store.restorePreferredProviderId(' grok ');
      final refresh = store.refresh(forceRefresh: false);
      await _flushEvents();

      expect(store.selectedProviderId, 'grok');
      expect(
        repository.providerRequests.map((request) => request.providerId),
        <String>['grok'],
      );
      expect(persistedSelections, isEmpty);

      repository.providerRequests.single.complete(_panelEntry('grok', 'Grok'));
      await refresh;
      expect(store.selectedEntry?.providerName, 'Grok');
    });

    test('快速切换按 Provider 单飞并保留各自迟到结果', () async {
      final repository = _ControlledAgentUsagePanelRepository();
      final bindings = AgentUsagePanelTestBindings(repository: repository);
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      final initialRefresh = store.refresh(forceRefresh: false);
      await _flushEvents();
      final codexRequest = repository.providerRequests.single;

      store
        ..selectProvider('grok')
        ..selectProvider('codex')
        ..selectProvider('grok');
      await _flushEvents();

      expect(
        repository.providerRequests.map((request) => request.providerId),
        <String>['codex', 'grok'],
      );
      final grokRequest = repository.providerRequests.last;
      grokRequest.complete(_panelEntry('grok', 'Grok'));
      await _flushEvents();
      expect(store.selectedProviderId, 'grok');
      expect(store.selectedEntry?.providerName, 'Grok');

      codexRequest.complete(_panelEntry('codex', 'Codex'));
      await initialRefresh;
      expect(store.entries.map((entry) => entry.providerId), <String>[
        'codex',
        'grok',
      ]);
    });

    test('在途目录刷新合并为尾随一轮，所有调用方等待最终目录', () async {
      final repository = _ControlledAgentUsagePanelRepository(
        holdDirectory: true,
      );
      final bindings = AgentUsagePanelTestBindings(repository: repository);
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      final first = store.synchronizeProviders();
      await _flushEvents();
      final second = store.synchronizeProviders();
      final third = store.synchronizeProviders();
      expect(repository.directoryRequests, hasLength(1));

      repository.directoryRequests.first.complete(_providerDirectory);
      await _flushEvents();
      expect(repository.directoryRequests, hasLength(2));

      repository.directoryRequests.last.complete(_providerDirectory);
      await _flushEvents();
      expect(repository.providerRequests, hasLength(1));
      repository.providerRequests.single.complete(
        _panelEntry('codex', 'Codex'),
      );
      await Future.wait(<Future<void>>[first, second, third]);

      expect(repository.directoryRequests, hasLength(2));
      expect(store.selectedProviderId, 'codex');
      expect(store.selectedEntry?.providerName, 'Codex');
    });

    test('目录移除 Provider 后丢弃其迟到结果', () async {
      final repository = _ControlledAgentUsagePanelRepository();
      final bindings = AgentUsagePanelTestBindings(repository: repository);
      final store = bindings.notifier;
      addTearDown(bindings.dispose);

      final staleRefresh = store.refresh(forceRefresh: false);
      await _flushEvents();
      final staleCodex = repository.providerRequests.single;

      repository.directory = const <AgentUsagePanelProvider>[
        AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
      ];
      final synchronize = store.synchronizeProviders();
      await _flushEvents();
      expect(
        store.providers.map((state) => state.provider.providerId),
        <String>['grok'],
      );
      final grokRequest = repository.providerRequests.last;

      staleCodex.complete(_panelEntry('codex', 'Stale Codex'));
      grokRequest.complete(_panelEntry('grok', 'Grok'));
      await Future.wait(<Future<void>>[staleRefresh, synchronize]);

      expect(store.providers, hasLength(1));
      expect(store.selectedEntry?.providerName, 'Grok');
    });
  });
}

const _providerDirectory = <AgentUsagePanelProvider>[
  AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
  AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
];

UsageStatisticsSourceSnapshot _usageSource({required DateTime refreshedAt}) {
  return UsageStatisticsSourceSnapshot(
    records: const <AgentUsageRecord>[],
    refreshedAt: refreshedAt,
  );
}

UsageStatisticsSourceSnapshot _usageSourceWithRecords(DateTime now) {
  return UsageStatisticsSourceSnapshot(
    records: <AgentUsageRecord>[
      _usageRecord(
        threadId: 'thread-codex',
        providerId: 'codex',
        providerName: 'Codex',
        projectPath: '/workspace/zeta',
        model: 'gpt-5',
        startedAt: now.subtract(const Duration(hours: 1)),
      ),
      _usageRecord(
        threadId: 'thread-grok',
        providerId: 'grok',
        providerName: 'Grok',
        projectPath: '/workspace/other',
        model: 'grok-4',
        startedAt: now.subtract(const Duration(days: 1)),
      ),
    ],
    refreshedAt: now,
  );
}

AgentUsageRecord _usageRecord({
  required String threadId,
  required String providerId,
  required String providerName,
  required String projectPath,
  required String model,
  required DateTime startedAt,
}) {
  return AgentUsageRecord(
    threadId: threadId,
    turnId: 'turn-$threadId',
    providerId: providerId,
    providerName: providerName,
    projectPath: projectPath,
    sourceKind: 'test',
    startedAt: startedAt,
    completedAt: startedAt.add(const Duration(minutes: 1)),
    duration: const Duration(minutes: 1),
    model: model,
    status: UsageTaskStatus.completed,
    tokens: const UsageTokenBreakdown(totalTokens: 100),
  );
}

void _expectEquivalentReports(
  UsageStatisticsReport actual,
  UsageStatisticsReport expected,
) {
  expect(
    actual.records.map((record) => record.id),
    expected.records.map((record) => record.id),
  );
  expect(actual.overview.totalCalls, expected.overview.totalCalls);
  expect(
    actual.overview.tokens.totalTokens,
    expected.overview.tokens.totalTokens,
  );
  expect(actual.projectOptions, expected.projectOptions);
  expect(actual.agentOptions, expected.agentOptions);
  expect(actual.modelOptions, expected.modelOptions);
  expect(
    actual.agentRanking.map((entry) => entry.providerId),
    expected.agentRanking.map((entry) => entry.providerId),
  );
  expect(
    actual.projectRanking.map((entry) => entry.projectPath),
    expected.projectRanking.map((entry) => entry.projectPath),
  );
}

AgentUsagePanelEntry _panelEntry(String providerId, String providerName) {
  return AgentUsagePanelEntry(
    providerId: providerId,
    providerName: providerName,
  );
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _ControlledUsageStatisticsRepository
    implements UsageStatisticsRepository {
  final List<_UsageStatisticsRequest> requests = <_UsageStatisticsRequest>[];

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) {
    final request = _UsageStatisticsRequest(
      earliest: earliest,
      forceRefresh: forceRefresh,
    );
    requests.add(request);
    return request.result.future;
  }
}

final class _UsageStatisticsRequest {
  _UsageStatisticsRequest({required this.earliest, required this.forceRefresh});

  final DateTime earliest;
  final bool forceRefresh;
  final Completer<UsageStatisticsSourceSnapshot> result =
      Completer<UsageStatisticsSourceSnapshot>();

  void complete(UsageStatisticsSourceSnapshot source) {
    result.complete(source);
  }
}

final class _ControlledAgentUsagePanelRepository
    implements AgentUsagePanelRepository {
  _ControlledAgentUsagePanelRepository({this.holdDirectory = false});

  final bool holdDirectory;
  List<AgentUsagePanelProvider> directory = _providerDirectory;
  final List<_DirectoryRequest> directoryRequests = <_DirectoryRequest>[];
  final List<_ProviderRequest> providerRequests = <_ProviderRequest>[];

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() {
    final request = _DirectoryRequest();
    directoryRequests.add(request);
    if (!holdDirectory) {
      request.complete(directory);
    }
    return request.result.future;
  }

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) {
    final request = _ProviderRequest(
      providerId: providerId,
      forceRefresh: forceRefresh,
    );
    providerRequests.add(request);
    return request.result.future;
  }
}

final class _DirectoryRequest {
  final Completer<List<AgentUsagePanelProvider>> result =
      Completer<List<AgentUsagePanelProvider>>();

  void complete(List<AgentUsagePanelProvider> providers) {
    result.complete(List<AgentUsagePanelProvider>.unmodifiable(providers));
  }
}

final class _ProviderRequest {
  _ProviderRequest({required this.providerId, required this.forceRefresh});

  final String providerId;
  final bool forceRefresh;
  final Completer<AgentUsagePanelProviderResult?> result =
      Completer<AgentUsagePanelProviderResult?>();

  void complete(AgentUsagePanelEntry entry) {
    result.complete(
      AgentUsagePanelProviderResult(
        entry: entry,
        refreshedAt: DateTime(2026, 8, 23, 12),
      ),
    );
  }
}
