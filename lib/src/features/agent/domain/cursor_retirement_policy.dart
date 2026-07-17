import 'package:zeta/src/features/agent/domain/agent_provider_models.dart';

/// Cursor 软下线后的运行时选择结果。
///
/// [effectiveProvider] 只用于当前进程，不会写回持久化设置；因此旧 Cursor
/// 配置及其最后选择值可以保持原样。
final class CursorRetirementResolution {
  const CursorRetirementResolution({
    required this.effectiveProvider,
    required this.hasRuntimeProvider,
    this.unavailableReason,
  });

  final AgentProviderConfig effectiveProvider;
  final bool hasRuntimeProvider;
  final String? unavailableReason;
}

/// Cursor Phase 3A 软下线策略。
///
/// 该策略只处理产品目录和旧配置选择，不读取或修改任何 Cursor 会话数据。
abstract final class CursorRetirementPolicy {
  static const String unavailableMessage =
      'Cursor Agent 已软下线，当前版本不再支持启动或恢复 Cursor 会话。';

  /// 配置是否属于已经退役的 Cursor 运行时。
  static bool isRetiredProvider(AgentProviderConfig config) {
    return isRetiredProviderId(config.id) ||
        config.kind == AgentProviderKind.cursorAcp;
  }

  /// Provider id 是否是旧 Cursor 内置 id。
  static bool isRetiredProviderId(String providerId) {
    return providerId.trim() == cursorAgentProviderId;
  }

  /// 返回仍可出现在产品目录中的 Provider，保留原有顺序。
  static List<AgentProviderConfig> supportedProviders(
    Iterable<AgentProviderConfig> providers,
  ) {
    return List<AgentProviderConfig>.unmodifiable(
      providers.where((provider) => !isRetiredProvider(provider)),
    );
  }

  /// 返回已启用且仍可进入运行时的 Provider。
  static List<AgentProviderConfig> enabledRuntimeProviders(
    Iterable<AgentProviderConfig> providers,
  ) {
    return List<AgentProviderConfig>.unmodifiable(
      providers.where(
        (provider) => provider.enabled && !isRetiredProvider(provider),
      ),
    );
  }

  /// 解析当前进程应使用的 Provider，但不修改或保存 [settings]。
  static CursorRetirementResolution resolve(AgentProviderSettings settings) {
    final selected = _providerById(
      settings.providers,
      settings.activeProviderId,
    );
    final selectedIsRetired =
        isRetiredProviderId(settings.activeProviderId) ||
        (selected != null && isRetiredProvider(selected));
    if (!selectedIsRetired) {
      return CursorRetirementResolution(
        effectiveProvider: selected ?? settings.activeProvider,
        hasRuntimeProvider: true,
      );
    }

    final enabled = enabledRuntimeProviders(settings.providers);
    final fallback = enabled.isEmpty ? null : enabled.first;
    final supported = supportedProviders(settings.providers);
    final safeDisplayProvider =
        fallback ??
        (supported.isEmpty
            ? AgentProviderConfig.defaultCodex.copyWith(enabled: false)
            : supported.first);
    final reason = fallback == null
        ? '$unavailableMessage 当前没有已启用的可用 Provider；旧 Cursor 配置保持原样。'
        : '$unavailableMessage 已临时回退到 ${fallback.displayName}；旧 Cursor 配置保持原样。';
    return CursorRetirementResolution(
      effectiveProvider: safeDisplayProvider,
      hasRuntimeProvider: fallback != null,
      unavailableReason: reason,
    );
  }

  /// 返回某个旧 Provider 无法进入运行时的用户可读原因。
  static String? unavailableReasonFor({
    required String providerId,
    AgentProviderConfig? config,
  }) {
    if (isRetiredProviderId(providerId) ||
        (config != null && isRetiredProvider(config))) {
      return '$unavailableMessage 旧 Cursor 配置和会话数据保持原样。';
    }
    return null;
  }
}

AgentProviderConfig? _providerById(
  Iterable<AgentProviderConfig> providers,
  String providerId,
) {
  for (final provider in providers) {
    if (provider.id == providerId) {
      return provider;
    }
  }
  return null;
}
