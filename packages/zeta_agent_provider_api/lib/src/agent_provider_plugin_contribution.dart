import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'agent_provider_definition.dart';

/// Agent Provider 插件贡献：向宿主提供一个中立的 [AgentProviderBundleFactory]。
///
/// 这是首期唯一的贡献类型。它定义在宿主侧契约包
/// `zeta_agent_provider_api`：内核不认识 Agent 语义，也不 import Provider 契约。
final class AgentProviderPluginContribution extends ZetaPluginContribution {
  const AgentProviderPluginContribution({
    required this.definition,
    required this.bundleFactory,
  });

  /// 该插件覆盖的 Provider identity、type 与静态 capability。
  final AgentProviderDefinition definition;

  /// 由该插件提供的 bundle 工厂。
  ///
  /// 工厂只被 `AgentProviderRuntimeRegistry` 调用；调用方仍必须显式传 scope。
  final AgentProviderBundleFactory bundleFactory;

  @override
  String get contributionKind => 'zeta.agent.provider-bundle-factory';
}

/// 三个显式 Provider contribution 解析后的目标态目录。
final class ResolvedAgentProviderPlugins {
  ResolvedAgentProviderPlugins(
    Iterable<AgentProviderPluginContribution> contributions,
  ) : this._(List<AgentProviderPluginContribution>.unmodifiable(contributions));

  ResolvedAgentProviderPlugins._(this.contributions)
    : definitions = AgentProviderDefinitionCatalog(
        contributions.map((contribution) => contribution.definition),
      ),
      bundleFactory = AgentProviderPluginBundleFactory(contributions);

  final List<AgentProviderPluginContribution> contributions;
  final AgentProviderDefinitionCatalog definitions;
  final AgentProviderBundleFactory bundleFactory;
}

/// 按开放 Provider type 路由的聚合 bundle factory。
///
/// 重复 type 在 definition catalog 构造时已经 fail-closed；运行时未知 type 直接抛
/// [UnsupportedError]，绝不回落到某个内置 Provider。
final class AgentProviderPluginBundleFactory
    implements AgentProviderBundleFactory {
  factory AgentProviderPluginBundleFactory(
    Iterable<AgentProviderPluginContribution> contributions,
  ) {
    final snapshot = List<AgentProviderPluginContribution>.unmodifiable(
      contributions,
    );
    return AgentProviderPluginBundleFactory._(
      _indexFactories(snapshot),
      _indexReservedProviderTypes(snapshot),
    );
  }

  AgentProviderPluginBundleFactory._(
    this._factories,
    this._reservedProviderTypes,
  );

  final Map<AgentProviderTypeId, AgentProviderBundleFactory> _factories;
  final Map<String, AgentProviderTypeId> _reservedProviderTypes;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    final reservedType = _reservedProviderTypes[config.id];
    if (reservedType != null && reservedType != config.kind) {
      throw UnsupportedError(
        'Agent provider configuration ${config.id} does not match its plugin',
      );
    }
    final factory = _factories[config.kind];
    if (factory == null) {
      throw UnsupportedError(
        'No active Agent provider plugin covers configuration ${config.id}',
      );
    }
    return factory.createBundle(config);
  }

  static Map<AgentProviderTypeId, AgentProviderBundleFactory> _indexFactories(
    Iterable<AgentProviderPluginContribution> contributions,
  ) {
    final factories = <AgentProviderTypeId, AgentProviderBundleFactory>{};
    for (final contribution in contributions) {
      final providerType = contribution.definition.providerType;
      if (factories.containsKey(providerType)) {
        throw StateError('Duplicate Agent provider type ${providerType.value}');
      }
      factories[providerType] = contribution.bundleFactory;
    }
    return Map<AgentProviderTypeId, AgentProviderBundleFactory>.unmodifiable(
      factories,
    );
  }

  static Map<String, AgentProviderTypeId> _indexReservedProviderTypes(
    Iterable<AgentProviderPluginContribution> contributions,
  ) {
    final providerTypes = <String, AgentProviderTypeId>{};
    for (final contribution in contributions) {
      final definition = contribution.definition;
      if (providerTypes.containsKey(definition.providerId)) {
        throw StateError(
          'Duplicate Agent provider id ${definition.providerId}',
        );
      }
      providerTypes[definition.providerId] = definition.providerType;
    }
    return Map<String, AgentProviderTypeId>.unmodifiable(providerTypes);
  }
}
