import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/codex_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

typedef EnabledAgentProviderLoader =
    Future<List<AgentProviderConfig>> Function();
typedef AgentProviderInstanceLoader =
    Future<AgentProvider> Function(AgentProviderConfig config);
typedef SharedAgentProviderPredicate = bool Function(AgentProvider provider);

/// 按已启用 Provider 配置实例汇总套餐和全局今日 Token。
class ProviderAgentUsagePanelRepository implements AgentUsagePanelRepository {
  ProviderAgentUsagePanelRepository({
    required this.enabledProviderLoader,
    required this.providerLoader,
    required this.isSharedProvider,
    required this.seedIndexStore,
    this.scanner = const FileSystemCodexUsageLogScanner(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final EnabledAgentProviderLoader enabledProviderLoader;
  final AgentProviderInstanceLoader providerLoader;
  final SharedAgentProviderPredicate isSharedProvider;
  final UsageStatisticsIndexStore seedIndexStore;
  final CodexUsageLogScanner scanner;
  final DateTime Function() _clock;

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    final seedFuture = _loadSeed();
    final configs = await enabledProviderLoader();
    final providers = <AgentUsagePanelProvider>[
      for (final config in configs) _providerSummary(config),
    ];

    // 在发布目录前创建全部 Future，确保 UI 收到 Tabs 时各 Provider 已并行加载。
    final providerLoads = <Future<AgentUsagePanelLoadEvent>>[
      for (final config in configs)
        _loadProvider(
          config,
          seedFuture: seedFuture,
          forceRefresh: forceRefresh,
        ),
    ];

    yield AgentUsagePanelProvidersDiscovered(providers: providers);
    if (providerLoads.isNotEmpty) {
      yield* Stream<AgentUsagePanelLoadEvent>.fromFutures(providerLoads);
    }
    yield AgentUsagePanelLoadCompleted(_clock());
  }

  Future<UsageStatisticsIndexSnapshot> _loadSeed() async {
    try {
      return await seedIndexStore.load();
    } catch (_) {
      return const UsageStatisticsIndexSnapshot();
    }
  }

  Future<AgentUsagePanelLoadEvent> _loadProvider(
    AgentProviderConfig config, {
    required Future<UsageStatisticsIndexSnapshot> seedFuture,
    required bool forceRefresh,
  }) async {
    AgentProvider? provider;
    try {
      provider = await providerLoader(config);
      final quota = await _readQuota(provider);
      if (config.kind != AgentProviderKind.codexAppServer) {
        return AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(
            providerId: config.id,
            providerName: config.displayName,
            quota: quota,
          ),
        );
      }

      UsageTokenBreakdown? todayTokens;
      String? message;
      try {
        final seed = await seedFuture;
        final memoryIndex = MemoryUsageStatisticsIndexStore()..snapshot = seed;
        final now = _clock();
        final source =
            await CodexUsageStatisticsRepository(
              providerLoader: () async => provider!,
              indexStore: memoryIndex,
              scanner: scanner,
              includeQuota: false,
              clock: _clock,
            ).load(
              earliest: DateTime(now.year, now.month, now.day),
              forceRefresh: forceRefresh,
            );
        todayTokens = _sumTokens(
          source.records
              .where((record) => !record.startedAt.isAfter(now))
              .toList(),
        );
      } catch (_) {
        message = '今日 Token 暂时无法读取';
      }
      return AgentUsagePanelProviderLoaded(
        AgentUsagePanelEntry(
          providerId: config.id,
          providerName: config.displayName,
          todayTokens: todayTokens,
          quota: quota,
          message: message,
        ),
      );
    } catch (_) {
      return AgentUsagePanelProviderFailed(
        provider: _providerSummary(config),
        message: '当前 Agent 暂时无法连接',
      );
    } finally {
      if (provider != null && !isSharedProvider(provider)) {
        try {
          await provider.dispose();
        } catch (_) {
          // 临时 Provider 清理失败不应覆盖已读取的统计结果。
        }
      }
    }
  }

  AgentUsagePanelProvider _providerSummary(AgentProviderConfig config) {
    return AgentUsagePanelProvider(
      providerId: config.id,
      providerName: config.displayName,
    );
  }

  Future<AgentUsageQuotaSnapshot?> _readQuota(AgentProvider provider) async {
    if (provider case final AgentUsageQuotaProvider quotaProvider) {
      try {
        return await quotaProvider.readUsageQuota();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  UsageTokenBreakdown _sumTokens(List<AgentUsageRecord> records) {
    var input = 0;
    var cached = 0;
    var output = 0;
    var reasoning = 0;
    var total = 0;
    for (final record in records) {
      input += record.tokens.inputTokens ?? 0;
      cached += record.tokens.cachedInputTokens ?? 0;
      output += record.tokens.outputTokens ?? 0;
      reasoning += record.tokens.reasoningTokens ?? 0;
      total += record.tokens.effectiveTotal ?? 0;
    }
    return UsageTokenBreakdown(
      inputTokens: input,
      cachedInputTokens: cached,
      outputTokens: output,
      reasoningTokens: reasoning,
      totalTokens: total,
    );
  }
}
