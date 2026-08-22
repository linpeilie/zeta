import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

void main() {
  group('ZetaPluginCatalog', () {
    test('同步激活后立即可取到唯一的 Provider 工厂', () {
      final factory = _StubBundleFactory();
      final catalog = ZetaPluginCatalog.compatibility(bundleFactory: factory);

      final report = catalog.activate();

      expect(report.isDegraded, isFalse);
      expect(report.activeIds, <String>[
        CompatibilityAgentProviderPlugin.pluginId,
      ]);
      expect(
        catalog.resolveAgentProviderBundleFactory(),
        same(factory),
        reason: '兼容插件必须原样交出宿主构造的工厂，不得包一层新语义',
      );
    });

    test('未激活时取工厂 fail-closed，不静默返回默认实现', () {
      final catalog = ZetaPluginCatalog.compatibility(
        bundleFactory: _StubBundleFactory(),
      );

      expect(catalog.resolveAgentProviderBundleFactory, throwsStateError);
      expect(catalog.report, isNull);
    });

    test('关闭后插件进入 stopped，且不触碰 runtime 进程所有权', () async {
      final factory = _StubBundleFactory();
      final catalog = ZetaPluginCatalog.compatibility(bundleFactory: factory)
        ..activate();

      await catalog.close();

      expect(
        catalog.registry
            .stateOf(CompatibilityAgentProviderPlugin.pluginId)!
            .status,
        ZetaPluginStatus.stopped,
      );
      expect(
        factory.createdBundles,
        0,
        reason: '插件生命周期不得创建或关闭任何 Provider runtime',
      );
    });

    test('激活写入插件指标', () {
      final metrics = InMemoryZetaMetricsPort();
      ZetaPluginCatalog.compatibility(
        bundleFactory: _StubBundleFactory(),
        metrics: metrics,
      ).activate();

      expect(metrics.totalOf(ZetaMetric.pluginActivated), 1);
      expect(metrics.lastValueOf(ZetaMetric.pluginActiveCount), 1);
    });
  });

  group('兼容层账本', () {
    test('兼容插件是唯一的 Agent Provider 贡献者，且只有一个使用点', () {
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) =>
                !file.path.endsWith('compatibility_agent_provider_plugin.dart'),
          )
          .toList(growable: false);

      final constructionSites = sources
          .where(
            (file) => file.readAsStringSync().contains(
              'CompatibilityAgentProviderPlugin(',
            ),
          )
          .map((file) => file.path.replaceAll(r'\', '/'))
          .toList(growable: false);

      expect(
        constructionSites,
        <String>['lib/src/app/plugins/zeta_plugin_catalog.dart'],
        reason:
            '兼容插件只允许由编译期目录构造一次。Phase 3 第 6 批把三个 Provider '
            '拆成显式插件后，本文件与该构造点一起删除。',
      );
    });

    test('贡献类型只声明一个稳定 kind 标签', () {
      const contribution = AgentProviderPluginContribution(
        bundleFactory: _ConstStubBundleFactory(),
      );

      expect(
        contribution.contributionKind,
        'zeta.agent.provider-bundle-factory',
      );
    });
  });
}

final class _StubBundleFactory implements AgentProviderBundleFactory {
  int createdBundles = 0;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    createdBundles += 1;
    throw UnsupportedError('测试不应触发 bundle 创建');
  }
}

final class _ConstStubBundleFactory implements AgentProviderBundleFactory {
  const _ConstStubBundleFactory();

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    throw UnsupportedError('测试不应触发 bundle 创建');
  }
}
