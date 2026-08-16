import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_token_aggregation.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 将统一用量查询事件投影为现有侧栏面板仓储契约。
final class QueryAgentUsagePanelRepository
    implements AgentUsagePanelRepository {
  QueryAgentUsagePanelRepository(
    this._queryService, {
    DateTime Function()? clock,
    UsageStatisticsTextCatalog? textCatalog,
  }) : _clock = clock ?? DateTime.now,
       _textCatalog = textCatalog ?? const FallbackUsageStatisticsTextCatalog();

  final AgentUsageQueryService _queryService;
  final DateTime Function() _clock;
  final UsageStatisticsTextCatalog _textCatalog;

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async {
    final providers = await _queryService.discoverProviders();
    return List<AgentUsagePanelProvider>.unmodifiable(
      providers.map(
        (provider) => AgentUsagePanelProvider(
          providerId: provider.providerId,
          providerName: provider.providerName,
        ),
      ),
    );
  }

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    final now = _clock();
    final earliest = DateTime(now.year, now.month, now.day);
    final snapshot = await _queryService.loadProvider(
      providerId,
      AgentUsageQuery(earliest: earliest, forceRefresh: forceRefresh),
    );
    if (snapshot == null) {
      return null;
    }
    return AgentUsagePanelProviderResult(
      entry: _panelEntry(snapshot, now: now),
      refreshedAt: _clock(),
    );
  }

  AgentUsagePanelEntry _panelEntry(
    AgentUsageProviderSnapshot snapshot, {
    required DateTime now,
  }) {
    UsageTokenBreakdown? todayTokens;
    String? message;
    switch (snapshot.tokenHistory.status) {
      case AgentUsageCapabilityStatus.available:
        final history = snapshot.tokenHistory.value;
        if (history != null) {
          if (history.historyPresence == AgentTokenHistoryPresence.absent) {
            message = _textCatalog.noTokenHistory;
          } else {
            todayTokens = sumAgentUsageTokens(
              history.records.where((record) => !record.startedAt.isAfter(now)),
            );
          }
        }
      case AgentUsageCapabilityStatus.unavailable:
        message = _textCatalog.todayTokensUnreadable;
      case AgentUsageCapabilityStatus.unsupported:
        break;
    }

    return AgentUsagePanelEntry(
      providerId: snapshot.provider.providerId,
      providerName: snapshot.provider.providerName,
      todayTokens: todayTokens,
      quota: snapshot.quota.isAvailable ? snapshot.quota.value : null,
      message: message,
    );
  }
}
