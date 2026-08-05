import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 按稳定优先级构造一次请求独占的权限快照。
///
/// application 只比较中立 selection 是否存在，不解析 optionId 的 Provider 语义。
final class AgentPermissionRequestResolver {
  const AgentPermissionRequestResolver._();

  /// 按 thread effective → provider default → catalog default 解析。
  static AgentPermissionRequestSnapshot resolve({
    AgentPermissionSelection? threadEffective,
    AgentPermissionSelection? providerDefault,
    AgentPermissionSelection? catalogDefault,
  }) {
    if (threadEffective != null) {
      return AgentPermissionRequestSnapshot.resolved(
        selection: threadEffective,
        source: AgentPermissionRequestSource.threadEffective,
      );
    }
    if (providerDefault != null) {
      return AgentPermissionRequestSnapshot.resolved(
        selection: providerDefault,
        source: AgentPermissionRequestSource.providerDefault,
      );
    }
    if (catalogDefault != null) {
      return AgentPermissionRequestSnapshot.resolved(
        selection: catalogDefault,
        source: AgentPermissionRequestSource.catalogDefault,
      );
    }
    return const AgentPermissionRequestSnapshot.providerFallback();
  }
}
