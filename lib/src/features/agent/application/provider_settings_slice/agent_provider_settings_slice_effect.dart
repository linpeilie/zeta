import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

sealed class AgentProviderSettingsSliceEffect {
  const AgentProviderSettingsSliceEffect();
}

final class ProviderSettingsLoadEffect
    extends AgentProviderSettingsSliceEffect {
  const ProviderSettingsLoadEffect(this.operationId);

  final OperationId operationId;
}

/// 持久化完整 Provider settings，并按配置变化失效相关外部资源。
///
/// [previousConfig]/[updatedConfig] 仅在 Provider config 发生变化时携带；runner
/// 据此计算安全指纹和环境值变化。模型选择、权限或 active id 更新不误清目录。
final class ProviderSettingsPersistEffect
    extends AgentProviderSettingsSliceEffect {
  const ProviderSettingsPersistEffect({
    required this.operationId,
    required this.settings,
    this.previousConfig,
    this.updatedConfig,
    this.restartProvider = false,
  });

  final OperationId operationId;
  final AgentProviderSettings settings;
  final AgentProviderConfig? previousConfig;
  final AgentProviderConfig? updatedConfig;
  final bool restartProvider;
}
