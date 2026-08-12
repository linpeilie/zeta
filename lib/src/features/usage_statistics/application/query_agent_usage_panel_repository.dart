import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_token_aggregation.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// 将统一用量查询事件投影为现有侧栏面板仓储契约。
final class QueryAgentUsagePanelRepository
    implements AgentUsagePanelRepository {
  QueryAgentUsagePanelRepository(
    this._queryService, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AgentUsageQueryService _queryService;
  final DateTime Function() _clock;

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    final now = _clock();
    final earliest = DateTime(now.year, now.month, now.day);
    await for (final event in _queryService.load(
      AgentUsageQuery(earliest: earliest, forceRefresh: forceRefresh),
    )) {
      switch (event) {
        case AgentUsageProvidersDiscovered():
          yield AgentUsagePanelProvidersDiscovered(
            providers: <AgentUsagePanelProvider>[
              for (final provider in event.providers)
                AgentUsagePanelProvider(
                  providerId: provider.providerId,
                  providerName: provider.providerName,
                ),
            ],
          );
        case AgentUsageProviderResolved():
          yield AgentUsagePanelProviderLoaded(
            _panelEntry(event.snapshot, now: now),
          );
        case AgentUsageQueryCompleted():
          yield AgentUsagePanelLoadCompleted(event.refreshedAt);
      }
    }
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
          todayTokens = sumAgentUsageTokens(
            history.records.where((record) => !record.startedAt.isAfter(now)),
          );
        }
      case AgentUsageCapabilityStatus.unavailable:
        message = '今日 Token 暂时无法读取';
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
