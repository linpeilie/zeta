import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import '../../testing/agent_management_test_definitions.dart';

void main() {
  test('manifest 与激活目录双向、同序一致；settings、默认项与贡献所有者匹配', () async {
    final catalog = ZetaPluginCatalog.builtIn(
      factories: zetaAgentProviderPluginFactories(),
    );
    addTearDown(catalog.close);
    catalog.activate();
    final resolved = catalog.resolveAgentProviders();
    final host = catalog.resolveAgentHostContributions();
    expect(
      _identity(zetaAgentProviderDefinitions),
      _identity(resolved.definitions.definitions),
    );
    expect(
      zetaAgentProviderDefinitionCatalog.definitions,
      zetaAgentProviderDefinitions,
    );
    expect(
      resolved.definitions.defaultSettings.toJson(),
      zetaBuiltInAgentProviderSettings.toJson(),
    );
    expect(
      zetaAgentProviderDefinitions.where((d) => d.isDefault),
      hasLength(1),
    );
    expect(
      zetaAgentProviderDefinitionCatalog.defaultDefinition.providerId,
      zetaDefaultAgentProviderId,
    );
    expect(
      host.management.map((c) => c.providerId),
      zetaAgentProviderDefinitions.map((d) => d.providerId),
    );
    expect(
      host.usage.map((c) => c.providerType),
      zetaAgentProviderDefinitions.map((d) => d.providerType),
    );
    for (final state in catalog.registry.states.where(
      (s) => s.status == ZetaPluginStatus.active,
    )) {
      final providers = catalog.registry
          .contributionsOf<AgentProviderPluginContribution>(
            state.descriptor.id,
          );
      final management = catalog.registry
          .contributionsOf<AgentManagementContribution>(state.descriptor.id);
      final usage = catalog.registry.contributionsOf<AgentUsageContribution>(
        state.descriptor.id,
      );
      expect(providers, hasLength(1));
      expect(management, hasLength(1));
      expect(usage, hasLength(1));
      expect(
        management.single.providerId,
        providers.single.definition.providerId,
      );
      expect(
        management.single.definition.id,
        providers.single.definition.providerId,
      );
      expect(
        usage.single.providerType,
        providers.single.definition.providerType,
      );
      // 测试定义直接复用插件对象；禁止再引入逐字段副本。
      expect(
        identical(
          testAgentManagementDefinitions[management.single.providerId],
          management.single.definition,
        ),
        isTrue,
      );
    }
  });

  test('D7 内置身份、类型与增强键逐字节冻结，允许追加未来插件', () {
    expect(_frozenIdentityViolations(zetaAgentProviderDefinitions), isEmpty);
    expect(AgentProviderSettings.currentVersion, 2);
    expect(usageStatisticsPartitionIndexVersion, 4);
    expect(
      testClaudeManagementCapabilities.accountDataEnrichmentExtraKey,
      'claudeCode.accountDataEnrichment',
    );
    expect(
      testClaudeManagementCapabilities.requiresConnectionTestConfirmation,
      isTrue,
    );
  });

  test('反例：manifest 遗漏、增加或重新排序均不等于激活目录', () {
    final baseline = _identity(zetaAgentProviderDefinitions);
    for (final changed in [
      zetaAgentProviderDefinitions.skip(1),
      zetaAgentProviderDefinitions.reversed,
      [...zetaAgentProviderDefinitions, zetaAgentProviderDefinitions.first],
    ]) {
      expect(_identity(changed), isNot(equals(baseline)));
    }
  });
  test('反例：持久化类型改变或内置项消失均违反冻结样本', () {
    expect(
      _frozenIdentityViolations(zetaAgentProviderDefinitions.skip(1)),
      isNotEmpty,
    );
    final original = zetaAgentProviderDefinitions.first;
    final changed = AgentProviderDefinition(
      providerId: original.providerId,
      providerType: const AgentProviderTypeId('changed'),
      defaultConfig: original.defaultConfig,
      staticCapabilities: original.staticCapabilities,
      modelCatalogSourceLabel: original.modelCatalogSourceLabel,
      metricLabel: original.metricLabel,
    );
    expect(
      _frozenIdentityViolations([
        changed,
        ...zetaAgentProviderDefinitions.skip(1),
      ]),
      isNotEmpty,
    );
  });
  test('反例：空目录、重复身份及缺默认项必须拒绝构造', () {
    for (final definitions in <List<AgentProviderDefinition>>[
      [],
      [...zetaAgentProviderDefinitions, zetaAgentProviderDefinitions.first],
      zetaAgentProviderDefinitions.where((d) => !d.isDefault).toList(),
    ]) {
      expect(
        () => AgentProviderDefinitionCatalog(definitions),
        throwsStateError,
      );
    }
  });
}

List<(String, String)> _identity(
  Iterable<AgentProviderDefinition> definitions,
) => definitions.map((d) => (d.providerId, d.providerType.value)).toList();

List<String> _frozenIdentityViolations(
  Iterable<AgentProviderDefinition> definitions,
) {
  const frozen = {
    'codex': 'codexAppServer',
    'grok': 'acp',
    'claude_code': 'claudeCode',
  };
  final byId = {
    for (final d in definitions) d.providerId: d.providerType.value,
  };
  return [
    for (final e in frozen.entries)
      if (byId[e.key] != e.value) e.key,
  ];
}
