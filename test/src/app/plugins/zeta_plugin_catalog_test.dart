import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

void main() {
  group('ZetaPluginCatalog built-in Provider plugins', () {
    test('同步激活三个显式插件并解析唯一目标态目录', () {
      final catalog = ZetaPluginCatalog.builtIn();

      final report = catalog.activate();
      final resolved = catalog.resolveAgentProviders();

      expect(report.isDegraded, isFalse);
      expect(report.activeIds, <String>[
        CodexAgentProviderPlugin.pluginId,
        GrokAgentProviderPlugin.pluginId,
        ClaudeCodeAgentProviderPlugin.pluginId,
      ]);
      expect(
        resolved.definitions.definitions.map(
          (definition) => definition.providerType,
        ),
        <AgentProviderTypeId>[
          codexAgentProviderType,
          grokAgentProviderType,
          claudeCodeAgentProviderType,
        ],
      );
      expect(
        resolved.definitions.defaultSettings.toJson(),
        builtInAgentProviderSettings.toJson(),
      );
    });

    test('未激活时解析 fail-closed', () {
      final catalog = ZetaPluginCatalog.builtIn();

      expect(catalog.resolveAgentProviders, throwsStateError);
      expect(catalog.report, isNull);
    });

    test('关闭后三个插件均 stopped，且从未创建 runtime', () async {
      final catalog = ZetaPluginCatalog.builtIn()..activate();

      await catalog.close();

      for (final pluginId in <String>[
        CodexAgentProviderPlugin.pluginId,
        GrokAgentProviderPlugin.pluginId,
        ClaudeCodeAgentProviderPlugin.pluginId,
      ]) {
        expect(
          catalog.registry.stateOf(pluginId)!.status,
          ZetaPluginStatus.stopped,
        );
      }
      expect(catalog.resolveAgentProviders, throwsStateError);
    });

    test('三个插件分别写入激活指标', () {
      final metrics = InMemoryZetaMetricsPort();

      ZetaPluginCatalog.builtIn(metrics: metrics).activate();

      expect(metrics.totalOf(ZetaMetric.pluginActivated), 3);
      expect(metrics.lastValueOf(ZetaMetric.pluginActiveCount), 3);
    });
  });

  group('Provider contribution fail-closed', () {
    test('重复 Provider type 在 resolve 阶段拒绝', () {
      final catalog = ZetaPluginCatalog.forTesting(
        factories: <ZetaPluginFactory>[
          _ContributionPlugin(
            id: 'test.provider.first',
            contribution: const AgentProviderPluginContribution(
              definition: codexAgentProviderDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
          ),
          _ContributionPlugin(
            id: 'test.provider.duplicate',
            contribution: const AgentProviderPluginContribution(
              definition: codexAgentProviderDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
          ),
        ],
      )..activate();

      expect(catalog.resolveAgentProviders, throwsStateError);
    });

    test('重复 Provider 保留 id 在 resolve 阶段拒绝', () {
      const futureType = AgentProviderTypeId('future.protocol');
      const duplicateIdDefinition = AgentProviderDefinition(
        providerId: defaultAgentProviderId,
        providerType: futureType,
        defaultConfig: AgentProviderConfig(
          id: defaultAgentProviderId,
          displayName: 'Future',
          kind: futureType,
          command: 'future',
        ),
        staticCapabilities: AgentProviderCapabilities.unsupported,
        modelCatalogSourceLabel: 'Future',
      );
      final catalog = ZetaPluginCatalog.forTesting(
        factories: <ZetaPluginFactory>[
          _ContributionPlugin(
            id: 'test.provider.codex',
            contribution: const AgentProviderPluginContribution(
              definition: codexAgentProviderDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
          ),
          _ContributionPlugin(
            id: 'test.provider.duplicate-id',
            contribution: const AgentProviderPluginContribution(
              definition: duplicateIdDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
          ),
        ],
      )..activate();

      expect(catalog.resolveAgentProviders, throwsStateError);
    });

    test('essential 插件激活失败时拒绝部分目录', () {
      final catalog = ZetaPluginCatalog.forTesting(
        factories: <ZetaPluginFactory>[
          _ContributionPlugin(
            id: 'test.provider.codex',
            contribution: const AgentProviderPluginContribution(
              definition: codexAgentProviderDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
          ),
          _ThrowingPlugin('test.provider.failed'),
        ],
      );

      final report = catalog.activate();

      expect(report.isDegraded, isTrue);
      expect(catalog.resolveAgentProviders, throwsStateError);
    });

    test('启动解析失败会关闭已经激活的插件 handle', () async {
      var closeCount = 0;
      final catalog = ZetaPluginCatalog.forTesting(
        factories: <ZetaPluginFactory>[
          _ContributionPlugin(
            id: 'test.provider.active-before-failure',
            contribution: const AgentProviderPluginContribution(
              definition: codexAgentProviderDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
            onClose: () => closeCount += 1,
          ),
          _ThrowingPlugin('test.provider.failed'),
        ],
      );

      expect(catalog.activateAndResolveAgentProviders, throwsStateError);
      await pumpEventQueue();

      expect(closeCount, 1);
      expect(
        catalog.registry.stateOf('test.provider.active-before-failure')!.status,
        ZetaPluginStatus.stopped,
      );
    });

    test('essential 插件零 Provider 贡献时拒绝部分目录并关闭 handle', () async {
      var healthyCloseCount = 0;
      final catalog = ZetaPluginCatalog.forTesting(
        factories: <ZetaPluginFactory>[
          _ContributionPlugin(
            id: 'test.provider.healthy',
            contribution: const AgentProviderPluginContribution(
              definition: codexAgentProviderDefinition,
              bundleFactory: _ConstStubBundleFactory(),
            ),
            onClose: () => healthyCloseCount += 1,
          ),
          _EmptyPlugin('test.provider.empty-essential', essential: true),
        ],
      );

      expect(catalog.activateAndResolveAgentProviders, throwsStateError);
      await pumpEventQueue();

      expect(healthyCloseCount, 1);
      expect(
        catalog.registry.stateOf('test.provider.healthy')!.status,
        ZetaPluginStatus.stopped,
      );
      expect(
        catalog.registry.stateOf('test.provider.empty-essential')!.status,
        ZetaPluginStatus.stopped,
      );
    });

    test('definition id 与 type 必须是可稳定持久化的 canonical 值', () {
      AgentProviderDefinition definition({
        required String providerId,
        required String providerType,
      }) {
        final type = AgentProviderTypeId(providerType);
        return AgentProviderDefinition(
          providerId: providerId,
          providerType: type,
          defaultConfig: AgentProviderConfig(
            id: providerId,
            displayName: 'Fixture',
            kind: type,
            command: 'fixture',
          ),
          staticCapabilities: AgentProviderCapabilities.unsupported,
          modelCatalogSourceLabel: 'Fixture',
          isDefault: true,
        );
      }

      for (final fixture in <({String providerId, String providerType})>[
        (providerId: '', providerType: 'future'),
        (providerId: ' future ', providerType: 'future'),
        (providerId: 'future', providerType: ''),
        (providerId: 'future', providerType: ' future '),
      ]) {
        expect(
          () => AgentProviderDefinitionCatalog(<AgentProviderDefinition>[
            definition(
              providerId: fixture.providerId,
              providerType: fixture.providerType,
            ),
          ]),
          throwsStateError,
        );
      }
    });

    test('零 Provider contribution 时拒绝启动', () {
      final catalog = ZetaPluginCatalog.forTesting(
        factories: <ZetaPluginFactory>[_EmptyPlugin('test.empty')],
      )..activate();

      expect(catalog.resolveAgentProviders, throwsStateError);
    });

    test('贡献类型保留稳定 kind 标签', () {
      const contribution = AgentProviderPluginContribution(
        definition: codexAgentProviderDefinition,
        bundleFactory: _ConstStubBundleFactory(),
      );

      expect(
        contribution.contributionKind,
        'zeta.agent.provider-bundle-factory',
      );
    });
  });

  test('兼容插件、默认工厂和闭集 kind 已从生产源码删除', () {
    final sources = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('packages')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    final combined = sources.map((file) => file.readAsStringSync()).join('\n');

    expect(combined, isNot(contains('CompatibilityAgentProviderPlugin')));
    expect(combined, isNot(contains('DefaultAgentProviderFactory')));
    expect(combined, isNot(contains('AgentProviderKind')));
  });
}

final class _ContributionPlugin implements ZetaSynchronousPluginFactory {
  _ContributionPlugin({
    required String id,
    required this.contribution,
    this.onClose,
  }) : descriptor = ZetaPluginDescriptor(
         id: id,
         apiVersion: ZetaPluginApiVersion.current,
         essential: true,
       );

  final AgentProviderPluginContribution contribution;
  final void Function()? onClose;

  @override
  final ZetaPluginDescriptor descriptor;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) =>
      _ContributionsHandle(<ZetaPluginContribution>[
        contribution,
      ], onClose: onClose);
}

final class _ThrowingPlugin implements ZetaSynchronousPluginFactory {
  _ThrowingPlugin(String id)
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
        essential: true,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) {
    throw StateError('fixture activation failure');
  }
}

final class _EmptyPlugin implements ZetaSynchronousPluginFactory {
  _EmptyPlugin(String id, {bool essential = false})
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
        essential: essential,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) =>
      _ContributionsHandle(const <ZetaPluginContribution>[]);
}

final class _ContributionsHandle implements ZetaPluginHandle {
  const _ContributionsHandle(this.contributions, {this.onClose});

  @override
  final List<ZetaPluginContribution> contributions;

  final void Function()? onClose;

  @override
  Future<void> close() async => onClose?.call();
}

final class _ConstStubBundleFactory implements AgentProviderBundleFactory {
  const _ConstStubBundleFactory();

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    throw UnsupportedError('测试不应触发 bundle 创建');
  }
}
