import 'package:zeta/src/features/agent/application/agent_provider_global_runtime.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 经 application global runtime 读取现有 bundle quota 可选端口。
///
/// bundle 只在 runtime callback 内使用；端口缺失明确返回 unsupported，异常只返回脱敏
/// unavailable，不把 Provider 协议或原始错误带入统一查询。
final class GlobalRuntimeAgentUsageQuotaSource
    implements AgentUsageQuotaSource {
  const GlobalRuntimeAgentUsageQuotaSource(
    this._globalRuntime, {
    UsageStatisticsTextCatalog? textCatalog,
  }) : _textCatalog = textCatalog ?? const FallbackUsageStatisticsTextCatalog();

  final AgentProviderGlobalRuntime _globalRuntime;
  final UsageStatisticsTextCatalog _textCatalog;

  @override
  Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> loadQuota(
    AgentProviderConfig config,
  ) async {
    try {
      return await _globalRuntime.run(config, (context) async {
        final port = context.bundle.usageQuota;
        if (port == null) {
          return const AgentUsageCapabilityResult<
            AgentUsageQuotaSnapshot
          >.unsupported();
        }
        try {
          final quota = await port.readUsageQuota();
          if (quota == null) {
            return AgentUsageCapabilityResult<
              AgentUsageQuotaSnapshot
            >.unavailable(
              AgentUsageWarning(
                code: 'quota-empty',
                message: _textCatalog.quotaUnreadable,
              ),
            );
          }
          return AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.available(
            quota,
          );
        } catch (_) {
          return AgentUsageCapabilityResult<
            AgentUsageQuotaSnapshot
          >.unavailable(
            AgentUsageWarning(
              code: 'quota-unavailable',
              message: _textCatalog.quotaUnreadable,
            ),
          );
        }
      });
    } catch (_) {
      return AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.unavailable(
        AgentUsageWarning(
          code: 'provider-unavailable',
          message: _textCatalog.agentTemporarilyUnavailable,
        ),
      );
    }
  }
}
