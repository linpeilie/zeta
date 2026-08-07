import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/provider_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// 用量面板是「会话之前的全局信息」的典型消费者：它借用共享 Provider 读套餐，
/// 用完必须还回租约且**不得**关闭共享实例。会话级实例改造会改变它拿到的是哪个
/// 实例，但「借了要还、还了不关」这条不变量必须一直成立。
void main() {
  group('ProviderAgentUsagePanelRepository 的租约借还', () {
    test('成功路径：租约被释放，共享实例不被关闭', () async {
      final harness = _Harness(<AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
      ]);
      addTearDown(harness.dispose);

      final events = await harness.repository.load().toList();

      expect(harness.registry.debugLeaseCount, 0);
      expect(harness.factory.providers.single.disposeCount, 0);
      expect(harness.factory.providers.single.quotaReads, 1);
      final loaded = events.whereType<AgentUsagePanelProviderLoaded>().single;
      expect(loaded.entry.providerId, defaultAgentProviderId);
      expect(loaded.entry.quota, isNotNull);
    });

    test('读取套餐抛错时仍然释放租约，并按无套餐继续返回', () async {
      final harness = _Harness(<AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
      ], quotaThrows: true);
      addTearDown(harness.dispose);

      final events = await harness.repository.load().toList();

      expect(harness.registry.debugLeaseCount, 0);
      expect(harness.factory.providers.single.disposeCount, 0);
      final loaded = events.whereType<AgentUsagePanelProviderLoaded>().single;
      expect(loaded.entry.quota, isNull);
    });

    test('多个已启用 Provider 各借各还，结束后没有租约残留', () async {
      final harness = _Harness(<AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
        AgentProviderConfig.defaultGrok,
      ]);
      addTearDown(harness.dispose);

      await harness.repository.load().toList();

      expect(harness.factory.providers, hasLength(2));
      expect(harness.registry.debugLeaseCount, 0);
      expect(harness.registry.debugProviderCount, 2);
      for (final provider in harness.factory.providers) {
        expect(provider.disposeCount, 0);
        expect(provider.quotaReads, 1);
      }
    });
  });
}

final class _Harness {
  _Harness(this.configs, {bool quotaThrows = false})
    : factory = _UsageProviderFactory(quotaThrows: quotaThrows) {
    registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    repository = ProviderAgentUsagePanelRepository(
      enabledProviderLoader: () async => configs,
      providerLeaseLoader: registry.acquire,
      seedIndexStore: MemoryUsageStatisticsIndexStore(),
      scanner: const _EmptyCodexUsageLogScanner(),
      grokScanner: const _EmptyGrokUsageLogScanner(),
      clock: () => DateTime.utc(2026, 8, 7, 12),
    );
  }

  final List<AgentProviderConfig> configs;
  final _UsageProviderFactory factory;
  late final AgentProviderRuntimeRegistry registry;
  late final ProviderAgentUsagePanelRepository repository;

  Future<void> dispose() => registry.close();
}

final class _UsageProviderFactory implements AgentProviderFactory {
  _UsageProviderFactory({required this.quotaThrows});

  final bool quotaThrows;
  final List<_UsageFakeProvider> providers = <_UsageFakeProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _UsageFakeProvider(config, quotaThrows: quotaThrows);
    providers.add(provider);
    return provider;
  }
}

final class _UsageFakeProvider extends Fake
    implements AgentProvider, AgentUsageQuotaProvider {
  _UsageFakeProvider(this.config, {required this.quotaThrows});

  @override
  final AgentProviderConfig config;

  final bool quotaThrows;

  int disposeCount = 0;
  int quotaReads = 0;

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    quotaReads += 1;
    if (quotaThrows) {
      throw StateError('quota unavailable');
    }
    return AgentUsageQuotaSnapshot(
      providerId: config.id,
      providerName: config.displayName,
      windows: const <AgentUsageWindow>[],
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _EmptyCodexUsageLogScanner implements CodexUsageLogScanner {
  const _EmptyCodexUsageLogScanner();

  @override
  Future<CodexUsageScanResult> scan({
    required String codexHome,
    required Map<String, CodexUsageSessionSnapshot> cachedSessions,
    bool forceRefresh = false,
  }) async {
    return const CodexUsageScanResult(
      sessions: <String, CodexUsageSessionSnapshot>{},
      warnings: <String>[],
    );
  }
}

final class _EmptyGrokUsageLogScanner implements GrokUsageLogScanner {
  const _EmptyGrokUsageLogScanner();

  @override
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    bool forceRefresh = false,
  }) async {
    return GrokUsageScanResult(
      sessions: const <GrokUsageSessionSnapshot>[],
      warnings: const <String>[],
    );
  }
}
