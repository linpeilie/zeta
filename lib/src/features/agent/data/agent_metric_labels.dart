import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Agent Provider 的指标标签映射。
///
/// 放在 data 层而不是中立内核：它**按 Provider 身份分支**，属于 Provider 语义
/// （G1/G4 同款判定——静态能力表也在 data 层）。内核只接受注入的解析函数。
///
/// `AgentProviderConfig.id` 是从 `~/.zeta/config` 的 JSON 自由解码出来的（见
/// `agent_provider_config_codec.dart`），**不能当作可信标识直接进指标**。这里把
/// 内置 Provider 映射到编译期常量，其余一律走会话内不可逆短 hash：
///
/// - 内置：`codex` / `grok` / `claude_code` → 原样，指标可读；
/// - 其它（手工改配置、将来的自定义 Provider）→ `h.xxxxxxxx`，可聚合但不可读。
abstract final class AgentMetricLabels {
  static const ZetaMetricLabel codex = ZetaMetricLabel.constant('codex');
  static const ZetaMetricLabel grok = ZetaMetricLabel.constant('grok');
  static const ZetaMetricLabel claudeCode = ZetaMetricLabel.constant(
    'claude_code',
  );

  /// 把 Provider ID 映射成指标标签。
  static ZetaMetricLabel forProviderId(String providerId) {
    return switch (providerId) {
      defaultAgentProviderId => codex,
      grokAgentProviderId => grok,
      defaultClaudeCodeProviderId => claudeCode,
      _ => ZetaMetricLabel.hashed(providerId),
    };
  }
}
