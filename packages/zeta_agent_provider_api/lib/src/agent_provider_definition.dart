import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'agent_provider_svg_icon.dart';

/// 单个 compile-time Provider 插件公开的静态定义。
///
/// 这里保存初始化前就能确定的白名单 metadata；协议原文、凭证和 runtime 状态均不
/// 属于 definition。配置实例可以使用自定义 id，但通过 [providerType] 路由到插件。
final class AgentProviderDefinition {
  const AgentProviderDefinition({
    required this.providerId,
    required this.providerType,
    required this.defaultConfig,
    required this.staticCapabilities,
    required this.modelCatalogSourceLabel,
    required this.metricLabel,
    this.modelCatalogFingerprintExtraKeys = const <String>{},
    this.isDefault = false,
    this.icon,
  });

  /// 内置配置的稳定 id。
  final String providerId;

  /// 插件覆盖的开放协议域。
  final AgentProviderTypeId providerType;

  /// 首次启动或损坏配置时补入的默认配置。
  final AgentProviderConfig defaultConfig;

  /// runtime 初始化前使用的保守 capability seed。
  final AgentProviderCapabilities staticCapabilities;

  /// 模型目录快照展示使用的稳定来源标签。
  final String modelCatalogSourceLabel;

  /// 该 Provider 的指标标签，编译期常量。
  ///
  /// 内置插件通过 [ZetaMetricLabel.constant] 声明；指标维度只允许规范化标签（G7），
  /// 自定义配置 id 不经过这里，由 catalog 回落不可逆短 hash（见 [metricLabelFor]）。
  final ZetaMetricLabel metricLabel;

  /// 参与模型目录安全指纹的 Provider 自有配置 key。
  ///
  /// 值只用于进程内哈希，原始 extra 不进入缓存快照；集合必须是编译期白名单。
  final Set<String> modelCatalogFingerprintExtraKeys;

  /// 插件可选的静态品牌图标；缺省时宿主显示中立图标。
  final AgentProviderSvgIcon? icon;

  /// 是否是 active 配置损坏时的默认 Provider。
  final bool isDefault;
}

/// 激活后的 Provider definition 不可变目录。
///
/// 构造时一次性校验 provider id/type 唯一以及默认项唯一，之后所有查询都是内容盲
/// 的 map lookup；未知 type 按 G4 返回 unsupported 或由执行路径显式抛错。
final class AgentProviderDefinitionCatalog {
  factory AgentProviderDefinitionCatalog(
    Iterable<AgentProviderDefinition> definitions,
  ) {
    final ordered = List<AgentProviderDefinition>.unmodifiable(definitions);
    if (ordered.isEmpty) {
      throw StateError('No Agent provider definitions were contributed');
    }

    final byProviderId = <String, AgentProviderDefinition>{};
    final byProviderType = <AgentProviderTypeId, AgentProviderDefinition>{};
    AgentProviderDefinition? defaultDefinition;
    for (final definition in ordered) {
      final providerId = definition.providerId;
      final providerType = definition.providerType.value;
      if (providerId.isEmpty || providerId != providerId.trim()) {
        throw StateError(
          'Agent provider definition has a non-canonical providerId',
        );
      }
      if (providerType.isEmpty || providerType != providerType.trim()) {
        throw StateError(
          'Agent provider definition has a non-canonical provider type',
        );
      }
      if (definition.defaultConfig.id != definition.providerId ||
          definition.defaultConfig.kind != definition.providerType) {
        throw StateError(
          'Agent provider definition/default config identity mismatch for '
          '${definition.providerId}',
        );
      }
      if (byProviderId.containsKey(definition.providerId)) {
        throw StateError(
          'Duplicate Agent provider id ${definition.providerId}',
        );
      }
      byProviderId[definition.providerId] = definition;
      if (byProviderType.containsKey(definition.providerType)) {
        throw StateError(
          'Duplicate Agent provider type ${definition.providerType.value}',
        );
      }
      byProviderType[definition.providerType] = definition;
      if (definition.isDefault) {
        if (defaultDefinition != null) {
          throw StateError('Multiple default Agent provider definitions');
        }
        defaultDefinition = definition;
      }
    }
    if (defaultDefinition == null) {
      throw StateError('No default Agent provider definition was contributed');
    }

    return AgentProviderDefinitionCatalog._(
      definitions: ordered,
      byProviderId: Map<String, AgentProviderDefinition>.unmodifiable(
        byProviderId,
      ),
      byProviderType:
          Map<AgentProviderTypeId, AgentProviderDefinition>.unmodifiable(
            byProviderType,
          ),
      defaultDefinition: defaultDefinition,
    );
  }

  const AgentProviderDefinitionCatalog._({
    required this.definitions,
    required this._byProviderId,
    required this._byProviderType,
    required this.defaultDefinition,
  });

  final List<AgentProviderDefinition> definitions;
  final Map<String, AgentProviderDefinition> _byProviderId;
  final Map<AgentProviderTypeId, AgentProviderDefinition> _byProviderType;
  final AgentProviderDefinition defaultDefinition;

  /// definition 集合对应的默认 Provider 设置。
  AgentProviderSettings get defaultSettings => AgentProviderSettings(
    providers: List<AgentProviderConfig>.unmodifiable(
      definitions.map((definition) => definition.defaultConfig),
    ),
    activeProviderId: defaultDefinition.providerId,
  );

  AgentProviderDefinition? definitionForProviderId(String providerId) =>
      _byProviderId[providerId];

  AgentProviderDefinition? definitionForType(
    AgentProviderTypeId providerType,
  ) => _byProviderType[providerType];

  /// 自定义配置 id 可复用任一已注册 type；内置保留 id 不允许冒充另一插件。
  bool acceptsConfigIdentity(
    String providerId,
    AgentProviderTypeId providerType,
  ) {
    final reserved = _byProviderId[providerId];
    return reserved == null || reserved.providerType == providerType;
  }

  /// 只接受已激活插件声明的持久化 type；未知值不猜协议。
  AgentProviderTypeId? decodeProviderType(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final candidate = AgentProviderTypeId(normalized);
    return _byProviderType.containsKey(candidate) ? candidate : null;
  }

  /// 内置稳定 id 使用插件声明的 canonical name；自定义 id 保持用户值。
  String normalizeDisplayName(String providerId, String displayName) =>
      _byProviderId[providerId]?.defaultConfig.displayName ?? displayName;

  /// 缺失的内置 Provider 按插件注册顺序补回，已有自定义配置保持原顺序。
  List<AgentProviderConfig> ensureDefaultProviders(
    Iterable<AgentProviderConfig> providers,
  ) {
    final result = List<AgentProviderConfig>.of(providers);
    final ids = result.map((provider) => provider.id).toSet();
    for (final definition in definitions) {
      if (ids.add(definition.providerId)) {
        if (definition.isDefault) {
          result.insert(0, definition.defaultConfig);
        } else {
          result.add(definition.defaultConfig);
        }
      }
    }
    return List<AgentProviderConfig>.unmodifiable(result);
  }

  AgentProviderCapabilities staticCapabilitiesFor(
    AgentProviderTypeId providerType,
  ) =>
      _byProviderType[providerType]?.staticCapabilities ??
      AgentProviderCapabilities.unsupported;

  /// 指标标签查询：内置 id 用插件声明的常量，未知/自定义 id 回落不可逆短 hash。
  ///
  /// 语义与退役的厂商身份分支逐分支一致。
  ZetaMetricLabel metricLabelFor(String providerId) =>
      _byProviderId[providerId]?.metricLabel ??
      ZetaMetricLabel.hashed(providerId);

  String modelCatalogSourceFor(AgentProviderConfig config) =>
      _byProviderType[config.kind]?.modelCatalogSourceLabel ??
      config.displayName;

  Iterable<String> modelCatalogFingerprintExtraKeysFor(
    AgentProviderConfig config,
  ) =>
      _byProviderType[config.kind]?.modelCatalogFingerprintExtraKeys ??
      const <String>{};
}
