import '../../testing/memory_agent_runtime_fact_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/plugins/agent_contribution_providers.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_page.dart';
import 'package:zeta/src/features/usage_statistics/data/contributed_agent_token_usage_source_registry.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../testing/agent_management_test_definitions.dart';
import '../../testing/memory_feature_stores.dart';
import '../../testing/zeta_test_app.dart';
import '../../testing/ide_test_harness.dart'
    show FakeAgentProvider, FakeAgentProviderBundleBuilder;

const _config = AgentProviderConfig(
  id: 'fourth',
  displayName: 'Fourth Agent',
  kind: AgentProviderTypeId('test.fourth'),
  command: 'fourth',
);
const _definition = AgentProviderDefinition(
  providerId: 'fourth',
  providerType: AgentProviderTypeId('test.fourth'),
  defaultConfig: _config,
  staticCapabilities: AgentProviderCapabilities.unsupported,
  modelCatalogSourceLabel: 'Fourth',
  metricLabel: ZetaMetricLabel.constant('fourth'),
);
const _managementDefinition = AgentDefinition(
  id: 'fourth',
  displayName: 'Fourth Agent',
  vendor: 'Test',
  commandName: 'fourth',
  protocol: 'test',
  transport: 'memory',
  configFormat: 'JSON',
  defaultConfigRelativePath: '',
  npmPackage: '',
);

void main() {
  testWidgets('第四个插件经激活、管理检测及用量查询接入，无厂商注册分支', (tester) async {
    final fourth = _HostPlugin();
    final catalog = ZetaPluginCatalog.forTesting(
      factories: [...zetaAgentProviderPluginFactories(), fourth],
    );
    final container = ProviderContainer(
      overrides: [zetaPluginCatalogProvider.overrideWithValue(catalog)],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      catalog.close();
    });
    final definitions = container.read(agentProviderDefinitionCatalogProvider);
    expect(definitions.definitionForProviderId('fourth'), same(_definition));
    final management = container.read(agentManagementContributionsProvider);
    final usage = container.read(agentUsageContributionsProvider);
    expect(management.map((c) => c.providerId), [
      'codex',
      'grok',
      'claude_code',
      'fourth',
    ]);
    expect(usage, hasLength(4));

    // 三个真实插件的声明保持原样，仅在测试接缝替换其 IO 工厂，避免扫描本机。
    final safeManagement = [
      for (final contribution in management)
        if (contribution.providerId == 'fourth')
          contribution
        else
          AgentManagementContribution(
            providerId: contribution.providerId,
            definition: contribution.definition,
            createRepository: (_) => _Repository(
              contribution.definition,
              definitions
                  .definitionForProviderId(contribution.providerId)!
                  .defaultConfig,
            ),
          ),
    ];
    final safeApp = zetaTestComposition(
      overrides: [
        agentProviderBundleFactoryProvider.overrideWithValue(_BundleFactory()),
        agentProviderDefinitionCatalogProvider.overrideWithValue(definitions),
        agentManagementContributionsProvider.overrideWithValue(safeManagement),
        agentUsageContributionsProvider.overrideWithValue(usage),
      ],
    );
    final workbench = safeApp.createWorkbenchComposition(
      runtimeFactSource: MemoryAgentRuntimeFactSource(),
    );
    addTearDown(workbench.dispose);
    final store = workbench.agentManagementComposition.store;
    await store.initialize();
    await store.detect();
    expect(fourth.repository.detectCalls, 1);
    expect(store.agents, hasLength(4));
    expect(store.agents.last.installed, isTrue);

    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final theme = buildIdeThemeData(
      brightness: Brightness.light,
      codeFontFamily: 'JetBrainsMono',
    );
    await tester.pumpWidget(
      IdeThemeScope(
        themeMode: ThemeMode.light,
        lightTheme: theme,
        darkTheme: buildIdeThemeData(
          brightness: Brightness.dark,
          codeFontFamily: 'JetBrainsMono',
        ),
        child: ProviderScope(
          child: sf.ShadcnApp(
            locale: ZetaLocalization.simplifiedChinese,
            supportedLocales: ZetaLocalization.supportedLocales,
            localizationsDelegates: ZetaLocalization.delegates,
            theme: buildShadcnTheme(theme),
            builder: (context, child) => IdeMaterialLayer(
              theme: buildMaterialTheme(theme),
              child: child,
            ),
            home: sf.Scaffold(
              child: AgentManagementPage(sliceStore: store, autoDetect: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Fourth Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final registry = ContributedAgentTokenUsageSourceRegistry(
      usage,
      services: AgentUsageHostServices(
        partitionPort: MemoryUsageStatisticsPartitionStore(),
      ),
    );
    final query = AgentUsageQuery(earliest: DateTime.utc(2026, 9, 1));
    final source = registry.createFor(_config)!;
    final result = await source.load(query);
    expect(result.providerId, 'fourth');
    expect(fourth.source.queries, [query]);
    expect(
      registry.createFor(
        _config.copyWith(kind: const AgentProviderTypeId('unknown')),
      ),
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await catalog.close();
    await tester.pump();
  });

  test('未激活、关闭、essential 失败及缺项均拒绝宿主贡献', () async {
    final catalog = ZetaPluginCatalog.forTesting(
      factories: [...zetaAgentProviderPluginFactories(), _HostPlugin()],
    );
    expect(catalog.resolveAgentHostContributions, throwsStateError);
    catalog.activate();
    final snapshot = catalog.resolveAgentHostContributions();
    expect(() => snapshot.management.clear(), throwsUnsupportedError);
    expect(() => snapshot.usage.clear(), throwsUnsupportedError);
    await catalog.close();
    expect(catalog.resolveAgentHostContributions, throwsStateError);
    for (final plugin in [
      _HostPlugin(fail: true),
      _HostPlugin(omitUsage: true),
      _HostPlugin(duplicateManagement: true),
      _HostPlugin(mismatchUsage: true),
    ]) {
      final invalid = ZetaPluginCatalog.forTesting(
        factories: [...zetaAgentProviderPluginFactories(), plugin],
      )..activate();
      expect(invalid.resolveAgentHostContributions, throwsStateError);
      await invalid.close();
    }
  });

  test('管理接缝空集、重复和错误身份拒绝，能力键保持原字节', () {
    expect(
      testClaudeManagementCapabilities.accountDataEnrichmentExtraKey,
      testAccountDataEnrichmentKey,
    );
    final contribution = testAgentManagementContributions.first;
    for (final contributions in <List<AgentManagementContribution>>[
      [],
      [contribution, contribution],
      [
        AgentManagementContribution(
          providerId: 'wrong',
          definition: _managementDefinition,
          createRepository: (_) => _Repository(_managementDefinition, _config),
        ),
      ],
    ]) {
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(
            _BundleFactory(),
          ),
          agentManagementContributionsProvider.overrideWithValue(contributions),
        ],
      );
      expect(
        () => app.createWorkbenchComposition(
          runtimeFactSource: MemoryAgentRuntimeFactSource(),
        ),
        throwsStateError,
      );
      expect(app.container.exists(zetaPluginCatalogProvider), isFalse);
    }
  });

  test('用量接缝的空集和重复类型拒绝，未知类型才是 unsupported', () {
    final services = AgentUsageHostServices(
      partitionPort: MemoryUsageStatisticsPartitionStore(),
    );
    expect(
      () => ContributedAgentTokenUsageSourceRegistry([], services: services),
      throwsStateError,
    );
    final contribution = testAgentUsageContributions.first;
    expect(
      () => ContributedAgentTokenUsageSourceRegistry([
        contribution,
        contribution,
      ], services: services),
      throwsStateError,
    );
  });

  test('覆盖 bundle 及两个贡献接缝不创建插件目录', () {
    final container = ProviderContainer(
      overrides: [
        agentProviderBundleFactoryProvider.overrideWithValue(_BundleFactory()),
        agentManagementContributionsProvider.overrideWithValue(
          testAgentManagementContributions,
        ),
        agentUsageContributionsProvider.overrideWithValue(
          testAgentUsageContributions,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(agentProviderBundleFactoryProvider);
    expect(container.read(agentManagementContributionsProvider), hasLength(3));
    expect(container.read(agentUsageContributionsProvider), hasLength(3));
    expect(container.exists(zetaPluginCatalogProvider), isFalse);
    expect(container.exists(resolvedAgentProviderPluginsProvider), isFalse);
  });
}

final class _HostPlugin implements ZetaSynchronousPluginFactory {
  _HostPlugin({
    this.fail = false,
    this.omitUsage = false,
    this.duplicateManagement = false,
    this.mismatchUsage = false,
  });
  final bool fail, omitUsage, duplicateManagement, mismatchUsage;
  final repository = _Repository(_managementDefinition, _config);
  final source = _Source();
  @override
  final descriptor = ZetaPluginDescriptor(
    id: 'test.fourth',
    apiVersion: ZetaPluginApiVersion.current,
    essential: true,
  );
  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);
  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) {
    if (fail) throw StateError('fixture activation failure');
    final management = AgentManagementContribution(
      providerId: 'fourth',
      definition: _managementDefinition,
      createRepository: (_) => repository,
    );
    return _Handle([
      AgentProviderPluginContribution(
        definition: _definition,
        bundleFactory: _BundleFactory(),
      ),
      management,
      if (duplicateManagement) management,
      if (!omitUsage)
        AgentUsageContribution(
          providerType: mismatchUsage
              ? const AgentProviderTypeId('other')
              : _config.kind,
          createSource: (_, _) => source,
        ),
    ]);
  }
}

final class _Handle implements ZetaPluginHandle {
  _Handle(this.contributions);
  @override
  final List<ZetaPluginContribution> contributions;
  @override
  Future<void> close() async {}
}

final class _BundleFactory implements AgentProviderBundleFactory {
  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) =>
      FakeAgentProviderBundleBuilder.fromFake(
        FakeAgentProvider(
          config: config,
          declaredCapabilities: AgentProviderCapabilities.unsupported,
        ),
      ).createBundle(config);
}

final class _Repository
    implements AgentCliManagementRepository, AgentCliManagementDescriptor {
  _Repository(this.definition, this.defaultProviderConfig);
  final AgentDefinition definition;
  int detectCalls = 0;
  @override
  final AgentProviderConfig defaultProviderConfig;
  @override
  String get agentId => definition.id;
  @override
  String get configPath => '';
  @override
  AgentCliManagementCapabilities get managementCapabilities =>
      AgentCliManagementCapabilities.none;
  @override
  bool acceptsExecutablePath(String path) => true;
  @override
  String get connectionModelSourceLabel => 'test';
  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    detectCalls++;
    return ManagedAgent.forDefinition(
      definition: definition,
      enabled: enabled,
    ).copyWith(
      installationState: AgentInstallationState.installed,
      accountState: AgentAccountState.notRequired,
      runtimeState: AgentRuntimeState.idle,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Source implements AgentTokenUsageSource {
  final List<AgentUsageQuery> queries = [];
  @override
  String get providerId => 'fourth';
  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) async {
    queries.add(query);
    return AgentTokenUsageSourceSnapshot(
      providerId: providerId,
      providerName: 'Fourth Agent',
      historyPresence: AgentTokenHistoryPresence.absent,
      records: [],
      refreshedAt: query.earliest,
    );
  }
}
